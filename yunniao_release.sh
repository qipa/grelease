#!/bin/bash
##################云鸟内网发布控制系统
### coding by laijingli@weiboyi.com
### @20150420

repo=beeper
wwwuser=www
wwwpass=123
log_dir=/backup/autoshell/log/
tmp_dir=/backup/autoshell/tmp/
email_log=${log_dir}email_body.log

######项目的配置文件，用于确定项目-服务器ip-wwwroot的对应关系
config_file=/backup/autoshell/yunniao_release.conf
######stash hooks传递参数来保证自动发布
stash_hook_pass_arg_name=$1
#echo stash_hook_pass_arg_name:$stash_hook_pass_arg_name


#########发布机命令
function_entrance_menu (){
	#####入口菜单
	echo
	echo "********************* 欢迎使用云鸟发布控制系统 *********************"
	echo 发布时间:`date`
	echo 发布用户:`whoami`
	echo 发布结果log地址: http://192.168.1.121/stash_hooks_auto_publish_log
	echo "*********************"

	###case语句用于判断是stash服务器hooks触发的自动发布还是手工发布
	case $stash_hook_pass_arg_name in
	master99)
	echo -e "\033[32m\033[01m本次发布由stash hooks触发的master branch自动发布\033[0m"
	server_ip=192.168.100.99
	server_www_root=/var/www/beeper_v2
	stash_hook_trigger_auto_publish=master99;;

	release92)
	echo -e "\033[32m\033[01m本次发布由stash hooks触发的release branch自动发布\033[0m"	
	server_ip=192.168.100.92
	server_www_root=/var/www/beeper_v2
	stash_hook_trigger_auto_publish=release92;;

	release217)
	echo -e "\033[32m\033[01m本次发布由stash hooks触发的release branch自动发布\033[0m"
	server_ip=192.168.100.217
	server_www_root=/var/www/beeper_v2
	stash_hook_trigger_auto_publish=release217;;

	*)
	#####如果没有stash hooks传递过来的参数，则进入手工发布流程
	echo "---------------------------------------"
	echo "---    请选择要发布的目标服务器    ----"
	echo "---------------------------------------"
	####使用配置文件的实现方式入口菜单
	cat $config_file|grep -v ^#|awk '{print FNR " --> "$3" "$4" "$5}' > ${tmp_dir}.entrance_menu.tmp
	cat ${tmp_dir}.entrance_menu.tmp
	entrance_menu_line_num=`cat ${tmp_dir}.entrance_menu.tmp|wc -l`
	#echo entrance_menu_line_num:$entrance_menu_line_num


	####每次清空input_num，以便重复发布
	input_num=""
	function_input_num () {
		echo -en "\033[31m\033[01m请输入要发布目标服务器编号(输入exit退出系统):\033[0m"
		read input_num
		####根据用户的输入替换掉数字后为空串则说明用户输入为纯数字
		is_num=`echo $input_num | sed 's/[0-9]//g'`
	}
	###判断输入是否合法,直到用户输入为非空且全是数字且大于等于1且小于等于entrance_menu_line_num或者输入exit时退出循环         
	#function_input_num
	until  	[ "$input_num" != "" ] && \
		[ "$is_num" = "" ] && \
		[ "$input_num" -ge 1 ] && \
		[ "$input_num" -le $entrance_menu_line_num ] || \
		[ "$input_num" = "exit" ];do
		function_input_num
	done 

	if [ "$input_num" = "exit" ];then
		###返回值用于保证输入一次exit即可彻底退出系统
		return 100
		echo 1秒后退出发布系统...;sleep 1;exit
	else
		####变量赋值，用于将本地变量传递到远程
		#echo input_wwwserver:$input_num
		#server_ip=${wwwserver[$input_num]}
		server_ip=$(cat ${tmp_dir}.entrance_menu.tmp|awk 'NR==line_num_awk{print $3}' line_num_awk=$input_num)
		#server_www_root=${wwwroot[$input_num]}
		server_www_root=$(cat ${tmp_dir}.entrance_menu.tmp|awk 'NR==line_num_awk{print $4}' line_num_awk=$input_num)
		stash_hook_trigger_auto_publish=no
		#echo ssh www@$server_ip
		#echo server_www_root:$server_www_root
	fi;;
esac
}


#function_git_email_notify (){
###发布结果邮件通知
#}


######远程目标服务器发布命令，注意单引号
cmds='
#pwd
local_ip=`/sbin/ifconfig eth0|grep "net addr"|cut -d: -f2|cut -d" " -f1`
echo
echo "远程目标服务器($local_ip:`pwd`)发布命令start:"

function_git_local_status (){
	echo ---------------------------------------
	echo 服务器当前git status:
	git status -uno
	echo
	echo "服务器当前发布branch版本(*表示)、上一个发布版本(可回滚版本)、下一个版本(如果有回滚过会出现,master分支除外):"
	git branch|grep -B 1  -A 1 ^* > /tmp/.candidate_version_rollback.tmp
	cat /tmp/.candidate_version_rollback.tmp
	#candidate_version_first_rollback=`cat /tmp/.candidate_version_rollback.tmp|cut -d/ -f2|head -n1`
	candidate_version_first_rollback=`cat /tmp/.candidate_version_rollback.tmp|head -n1`
	echo 
}


function_git_show_remote_release_branchs (){
	echo ---------------------------------------
	####服务器当前发布branch版本
	current_local_release_version=`git branch|grep ^* |cut -d" " -f2`
	echo "列出stash远程服务器上比当前发布版本高的、可发布的(最多列出10个即将发布版本)release branch:"
	git branch -a|grep "remotes/origin/release/"|grep -A 10 remotes/origin/$current_local_release_version$|grep -v remotes/origin/$current_local_release_version$ > /tmp/.candidate_version.tmp
	###如果当前远程stash服务器上没有可发布的版本,则提示后直接退出
	if [ -s /tmp/.candidate_version.tmp ];then
		echo 远程服务器上有可发布的版本	
	else
		echo 
		echo 当前远程stash服务器上没有可发布的版本,自动退出...
		exit
	fi
	cat /tmp/.candidate_version.tmp
	candidate_version_first=`cat /tmp/.candidate_version.tmp|cut -d/ -f4|head -n1`
	candidate_version_last=`cat  /tmp/.candidate_version.tmp|cut -d/ -f4|tail -n1`
	echo
}

function_last_commit (){
	echo ---------------------------------------
	echo 服务器当前branch最后一次commit信息:
	#git log --pretty=oneline  -1
	git log --color --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset" --abbrev-commit -1|head -n 1
}

function_git_process_conflic_detect (){
###在git发布前检测是否有git进程存在，以免冲突导致发布错误或失败
ps aux|grep git|grep -v grep
git_process_conflic_or_not=$?
#echo git_process_conflic_or_not:$git_process_conflic_or_not
if [ $git_process_conflic_or_not != 0 ];then
	echo no git process run now,and you can release.
else
	echo "服务器($local_ip)当前有git进程正在运行，以免因进程冲突导致发布错误，请等待50秒后返回主菜单后重试"
	echo 等待50秒... ; sleep 50
	#exit
fi
}


function_git_grunt (){
####压缩css等文件
echo
#echo 开始grunt  sass build_web_js ...
#grunt  sass build_web_js
#git_grunt_result=$?
echo
#if [[ $git_grunt_result = 0 ]];then
#	echo grunt成功
#else
#	echo grunt失败，请检查...
#fi
}

function_git_restart_node_service (){
echo 发布完成，系统自动重启nodejs,请稍等...
sudo ./bin/restart_recluster.sh admin.js    && echo admin.js 重启成功
sudo ./bin/restart_recluster.sh customer.js && echo customer.js 重启成功
sudo ./bin/restart_recluster.sh api.js      && echo api.js 重启成功
}


function_git_update_current_branch (){
	function_git_process_conflic_detect
	echo ---------------------------------------
	function_last_commit
	echo
	echo "发布执行结果(git pull):"
	git pull
	git_pull_result=$?
	echo
	if [[ $git_pull_result = 0 ]];then 
		echo 发布成功	
	else
		echo 发布失败，请检查...
	fi
	function_git_grunt
	function_git_local_status
	function_last_commit
}	


function_input_release_version () {
	function_git_local_status
	function_git_show_remote_release_branchs
	echo -en "\033[31m\033[01m从上述列表选择要切换的远程branch名字，仅数字版本号(比如1.0),退出请输入exit:\033[0m"
	read input_release_version
	###判断输入是否合法,即用户输入的版本号是否存在于远程库
	if [ "$input_release_version" = "exit" ];then 
		echo bye... ;exit
	else
		grep remotes/origin/release/${input_release_version}$  /tmp/.candidate_version.tmp	
		#git branch -a|grep  remotes/origin/release/${input_release_version}$
		input_hit=$?
	fi
}

function_change_branch () {
	function_git_process_conflic_detect
	function_input_release_version
	until [ "$input_hit" = "0" ] || [ "$input_hit" = "exit" ];do
		function_input_release_version
	done
	#echo 输入正确:$input_release_version

	##获取用户切换branch确认
	function_last_commit
	echo -en "\033[31m\033[01m是否要切换到release/$input_release_version分支(yes/no):\033[0m"
	read input_change_branch_or_not
	##判断输入是否合法
	until [ "$input_change_branch_or_not" = "yes" ] || [ "$input_change_branch_or_not" = "no" ] ;do
		echo -en "\033[31m\033[01m请输入yes或者no返回发布主菜单:\033[0m"
		read input_change_branch_or_not
	done

	if [ "$input_change_branch_or_not" = "yes" ];then
       		##绿色提示
		echo -e "\033[32m\033[01m你要发布\033[0m"
		echo git pull执行结果:
		git checkout     release/$input_release_version  && \
		git merge origin/release/$input_release_version
		git_change_branch_result=$?
		echo
		if [[ $git_change_branch_result = 0 ]];then
			echo 发布成功
		else
			echo 发布失败，请检查...
		fi
		#git pull
		echo
		function_git_grunt
		git status
		function_last_commit
	fi
}



function_rollback_branch (){
	function_git_process_conflic_detect
	function_git_local_status
	#echo candidate_version_first_rollback:$candidate_version_first_rollback

	#####只有release分支才有回滚操作，master等其他分支没有回滚操作
	echo $candidate_version_first_rollback|grep release >/dev/null
	rollback_release_or_not=$?
	if [ $rollback_release_or_not = 0 ];then	
	##获取用户回滚branch确认
	function_last_commit
	echo -en "\033[31m\033[01m是否要回滚到$candidate_version_first_rollback分支(yes回滚/no返回发布主菜单):\033[0m"
	read input_rollback_branch_or_not
	##判断输入是否合法
	until [ "$input_rollback_branch_or_not" = "yes" ] || [ "$input_rollback_branch_or_not" = "no" ] ;do
		echo -en "\033[31m\033[01m是否要回滚到$candidate_version_first_rollback分支(yes回滚/no返回发布主菜单):\033[0m"
		read input_rollback_branch_or_not
	done

	if [ "$input_rollback_branch_or_not" = "yes" ];then
       		##绿色提示
		echo -e "\033[32m\033[01m你要回滚\033[0m"
		echo git pull执行结果:
		git checkout     $candidate_version_first_rollback  && \
		git merge origin/$candidate_version_first_rollback
		git_rollback_result=$?
		echo
		if [[ $git_rollback_result = 0 ]];then
			echo 发布成功
		else
			echo 发布失败，请检查...
		fi
		#git pull
		echo
		function_git_grunt
		git status
		function_last_commit
	fi
	else
		echo 只有release分支才有回滚操作，master等其他分支没有回滚操作
	fi
}



function_release_menu (){
	#####根据stash hooks触发自动发布
	case $auto_publish in 
	master99)
	echo -e "\033[32m\033[01m根据stash hooks触发master branch自动发布\033[0m"
	input_user_type=1;;

	release92|release217)
	echo -e "\033[32m\033[01m根据stash hooks触发release branch自动发布\033[0m"
	input_user_type=1;;

	*)
	####远程目标服务器发布选项菜单
	echo "---------------------------------------"
	echo "--------  请选择发布类型选项  ---------"
	echo "---------------------------------------"
	echo "1 --> 手动更新代码 (在当前master/release branch上git pull更新代码)"
	echo "2 --> 发布新branch (手工升级release branch版本号,包括版本号正常升级及线上bugfix)"
	echo "3 --> 回滚旧branch (手工降级release branch版本号)"

	###输入
	echo -en "\033[31m\033[01m请选择发布选项编号(exit返回发布主菜单):\033[0m"
	read  input_user_type
	##判断输入是否合法
	until [ "$input_user_type" = "1" ] || [ "$input_user_type" = "2" ] || [ "$input_user_type" = "3" ] || [ "$input_user_type" = "exit" ];do
		echo -en "\033[31m\033[01m请选择发布选项编号(exit返回发布主菜单):\033[0m"
		read input_user_type
	done;;
esac


	if    [ "$input_user_type" = "1" ];then
		#echo 1
		function_git_update_current_branch
	elif  [ "$input_user_type" = "2" ];then
		#echo 2
		function_change_branch	
	elif  [ "$input_user_type" = "3" ];then
		#echo backuping
		function_rollback_branch
	else
		echo 返回发布主菜单
	fi
}

function_release_menu


'


#echo $cmds
############### main workflow starts
function_main (){
function_entrance_menu
return_function_entrance_menu=$?
#echo return_function_entrance_menu:$return_function_entrance_menu
if [ $return_function_entrance_menu = 100 ];then 
	return 200
fi
#echo repo $repo on $wwwserver in $wwwroot release branch is: 
###为保证本地变量传递到远程，需要将本地变量和远程变量分开,sudo因为保证exec能够执行本脚本
sudo sshpass -p $wwwpass  ssh -o ConnectTimeout=5 $wwwuser@$server_ip \
	"auto_publish=$stash_hook_trigger_auto_publish;cd $server_www_root;$cmds" |tee $email_log
}

function_loop_publish_workflow () {
###开始进入发布流程
function_main
return_function_main=$?
#echo return_function_main:$return_function_main
if [ $return_function_main = 200 ] ;then 
echo 1秒后退出发布系统...;sleep 1;exit
fi

####如果是stash hook触发则自动发布完成后自动退出
#echo stash_hook_trigger_auto_publish----$stash_hook_trigger_auto_publish
case $stash_hook_trigger_auto_publish in
	master99) 
	echo -e "\033[32m\033[01m本次发布由stash hooks触发的自动发布,发布完成自动退出...\033[0m"
	echo 发布结束时间:`date`
	exit;;
	release92|release217)
	echo -e "\033[32m\033[01m本次发布由stash hooks触发的自动发布,发布完成自动退出...\033[0m"
	echo 发布结束时间:`date`
	exit;;
	*)
	##用户是否返回发布主菜单继续发布
	while true;do
	echo -en "\033[31m\033[01m输入yes返回发布主菜单继续发布,no退出发布系统:\033[0m"
	read input_continue_or_not
	##判断输入是否合法
	until [ "$input_continue_or_not" = "yes" ] || [ "$input_continue_or_not" = "no" ] ;do
		echo -en "\033[31m\033[01m输入yes返回发布主菜单继续发布,no退出发布系统:\033[0m"
		read input_continue_or_not
	done

	if [ "$input_continue_or_not" = "yes" ];then
		function_main |tee -a $log
	else
		echo 1秒后退出发布系统...;sleep 1;exit
	fi
	done;;
esac
}

function_loop_publish_workflow |tee -a $email_log



