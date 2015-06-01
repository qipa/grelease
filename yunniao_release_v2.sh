#!/bin/bash
##################云鸟内网发布控制系统v2
### 为更加友好的支持多服务器发布环境、保证grunt结果的唯一性特开放v2版本，v1和v2核心功能一致
### coding by laijingli@weiboyi.com
### @20150420

repo=beeper
wwwuser=www
wwwpass=123
log_dir=/backup/autoshell/log/
tmp_dir=/backup/autoshell/tmp/
entrance_menu=${tmp_dir}.entrance_menu_v2.tmp
candidate_version=${tmp_dir}.candidate_version.tmp
candidate_version_rollback=${tmp_dir}.candidate_version_rollback_v2.tmp
email_log=${log_dir}email_body_v2.log
release_server_ip=`/sbin/ifconfig eth0|grep "net addr"|cut -d: -f2|cut -d" " -f1`

######项目的配置文件，用于确定项目-服务器ip-wwwroot的对应关系
config_file=/backup/autoshell/yunniao_release_v2.conf
######stash hooks传递参数来保证自动发布
stash_hook_pass_arg_name=$1
#echo stash_hook_pass_arg_name:$stash_hook_pass_arg_name


################################### 发布机函数定义开始
function_entrance_menu (){
#####入口菜单
	echo
	echo "********************* 欢迎使用云鸟发布控制系统v2 *********************"
	echo 发布时间:`date`
	#echo 发布用户:`whoami`
	echo 发布用户:`cat /tmp/.whoami`
	/bin/rm /tmp/.whoami
	echo 发布结果log地址: http://192.168.1.121/stash_hooks_auto_publish_log
	echo "*********************"

	###case语句用于判断是stash服务器hooks触发的自动发布还是手工发布
	case $stash_hook_pass_arg_name in
	master99)
	echo -e "\033[32m\033[01m本次发布由stash hooks触发的master branch自动发布\033[0m"
	git_local_source_dir=/var/www/beeper_99/beeper/
	server_ip=192.168.100.99
	server_www_root=/var/www/beeper_v2
	stash_hook_trigger_auto_publish=master99;;

	release92)
	echo -e "\033[32m\033[01m本次发布由stash hooks触发的release branch自动发布\033[0m"	
	git_local_source_dir=/var/www/beeper_92/beeper/
	server_ip=192.168.100.92
	server_www_root=/var/www/beeper_v2
	stash_hook_trigger_auto_publish=release92;;

	release217)
	echo -e "\033[32m\033[01m本次发布由stash hooks触发的release branch自动发布\033[0m"
	git_local_source_dir=/var/www/beeper_217/beeper/
	server_ip=192.168.100.217
	server_www_root=/var/www/beeper_v2
	stash_hook_trigger_auto_publish=release217;;

	*)
	#####如果没有stash hooks传递过来的参数，则进入手工发布流程
	echo "---------------------------------------"
	echo "---    请选择要发布的目标服务器    ----"
	echo "---------------------------------------"
	####使用配置文件的实现方式入口菜单
	cat $config_file|grep -v ^#|awk '{print FNR " --> "$3" "$4" "$5}' > $entrance_menu
	cat $entrance_menu
	entrance_menu_line_num=`cat $entrance_menu|wc -l`
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
		echo 1秒后退出发布系统...;sleep 1;exit
	else
		####变量赋值，用于将本地变量传递到远程
		git_local_source_dir=$(cat $entrance_menu|awk 'NR==line_num_awk{print $3}' line_num_awk=$input_num)
		server_ip=$(cat $entrance_menu|awk 'NR==line_num_awk{print $4}' line_num_awk=$input_num)
		server_www_root=$(cat $entrance_menu|awk 'NR==line_num_awk{print $5}' line_num_awk=$input_num)
		stash_hook_trigger_auto_publish=no
		#echo git_local_source_dir:$git_local_source_dir
		#echo server_ip:$server_ip
		#echo server_www_root:$server_www_root
	fi;;
esac
}


#function_git_email_notify (){
###发布结果邮件通知
#}


function_git_local_status (){
	echo ---------------------------------------
	echo "发布机($release_server_ip:`pwd`)当前git status:"
	git status -uno
	echo ---------------------------------------
	echo "发布机($release_server_ip:`pwd`)当前发布branch版本(*表示)、上一个发布版本(可回滚版本)、下一个版本(如果有回滚过会出现,master分支除外):"
	git branch|grep -B 1  -A 1 ^* > $candidate_version_rollback
	cat $candidate_version_rollback
	#candidate_version_first_rollback=`cat $candidate_version_rollback|cut -d/ -f2|head -n1`
	###取可回滚版本并删除航首的空格
	candidate_version_first_rollback=`cat $candidate_version_rollback|head -n1|sed 's/^[ \t]*//g'`
	echo 
}


function_git_show_remote_release_branchs (){
	echo ---------------------------------------
	####服务器当前发布branch版本
	current_local_release_version=`git branch|grep ^* |cut -d" " -f2`
	echo "列出stash远程服务器上比当前发布版本高的、可发布的(最多列出10个即将发布版本)release branch:"
	git branch -a|grep "remotes/origin/release/"|grep -A 10 remotes/origin/$current_local_release_version$  \
		     |grep -v remotes/origin/$current_local_release_version$ > $candidate_version
	###如果当前远程stash服务器上没有可发布的版本,则提示后直接退出
	if [ -s $candidate_version ];then
		echo 远程服务器上有可发布的版本	
		candidate_version_ok=yes
	else
		echo 
		echo 当前远程stash服务器上没有可发布的版本,自动退出...
		exit
	fi
	cat $candidate_version
	candidate_version_first=`cat $candidate_version|cut -d/ -f4|head -n1`
	candidate_version_last=`cat  $candidate_version|cut -d/ -f4|tail -n1`
	echo
}


function_last_commit (){
	echo ---------------------------------------
	echo "发布机($release_server_ip:`pwd`)当前branch最后一次commit信息:"
	git log --pretty=oneline  -1
	#git log --color --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset"  \
	#		--abbrev-commit -1|head -n 1
}


function_git_process_conflic_detect (){
	###在git发布前检测是否有git进程存在，以免冲突导致发布错误或失败
	ps aux|grep git|grep -v grep
	git_process_conflic_or_not=$?
	#echo git_process_conflic_or_not:$git_process_conflic_or_not
	if [ $git_process_conflic_or_not != 0 ];then
		echo no git process run now,and you can release.
	else
		echo "发布机($release_server_ip:`pwd`)当前有git进程正在运行，以免因进程冲突导致发布错误，请等待50秒后返回主菜单后重试"
		echo 等待50秒... ; sleep 50
		#exit
	fi
}


function_git_grunt (){
####压缩css等文件
	grunt_cmd="grunt  build_web_css build_web_js"
	echo "[2/3]---------------------------------------"
	cd $git_local_source_dir
	echo "发布机($release_server_ip:`pwd`)开始$grunt_cmd ..."
	echo
	$grunt_cmd
	git_grunt_result=$?
	echo
	if [[ $git_grunt_result = 0 ]];then
		echo grunt成功,开始rsync代码到目标服务器
		rsync_code_or_not=yes
	else
		echo grunt失败，请检查...
	fi
}

#function_git_restart_node_service (){
#echo 发布完成，系统自动重启nodejs,请稍等...
#sudo ./bin/restart_recluster.sh admin.js    && echo admin.js 重启成功
#sudo ./bin/restart_recluster.sh customer.js && echo customer.js 重启成功
#sudo ./bin/restart_recluster.sh api.js      && echo api.js 重启成功
#}


function_git_update_current_branch (){
	function_git_process_conflic_detect
	function_last_commit
	echo
	echo "[1/3]---------------------------------------"
	echo "发布机($release_server_ip:`pwd`)发布执行结果(git pull):"
	git reset --hard
	git pull
	git_pull_result=$?
	if [[ $git_pull_result = 0 ]];then 
		echo
		echo 发布机代码更新成功,开始运行grunt压缩css文件	
		function_git_grunt
		function_git_local_status
		function_last_commit
	else
		echo 发布机代码更新失败，请检查...
	fi
}	


function_input_release_version () {
	function_git_local_status
	function_git_show_remote_release_branchs
	if [ $candidate_version_ok = yes ] ;then
		echo -en "\033[31m\033[01m从上述列表选择要切换的远程branch名字，仅数字版本号(比如1.0),退出请输入exit:\033[0m"
		read input_release_version
		###判断输入是否合法,即用户输入的版本号是否存在于远程库
		if [ "$input_release_version" = "exit" ];then 
			echo bye... ;exit
		else
			grep remotes/origin/release/${input_release_version}$  $candidate_version	
			#git branch -a|grep  remotes/origin/release/${input_release_version}$
			input_hit=$?
		fi
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
		echo
		echo "[1/3]---------------------------------------"
		echo "发布机($release_server_ip:`pwd`)git pull执行结果:"
		git reset --hard
		git checkout     release/$input_release_version  && \
		git merge origin/release/$input_release_version
		git_change_branch_result=$?
		echo
		if [[ $git_change_branch_result = 0 ]];then
			echo 发布机代码change branch成功,开始运行grunt压缩css文件
			function_git_grunt
			git status
			function_last_commit
		else
			echo 发布机代码更新失败，请检查...
		fi
	else
		echo 你已取消change branch操作，不rsync代码，返回发布主菜单
		rsync_code_or_not=no
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
		echo
		echo "[1/3]---------------------------------------"
		echo "发布机($release_server_ip:`pwd`)git pull执行结果:"
		echo candidate_version_first_rollback:$candidate_version_first_rollback
		git reset --hard
		git checkout     $candidate_version_first_rollback  && \
		git merge origin/$candidate_version_first_rollback
		git_rollback_result=$?
		echo
			if [[ $git_rollback_result = 0 ]];then
				echo 发布机代码rollback成功,开始运行grunt压缩css文件
				function_git_grunt
				git status
				function_last_commit
			else
				echo 发布机代码rollback失败，请检查...
			fi
		else
			echo 你已取消回滚操作，不rsync代码，返回发布主菜单
			rsync_code_or_not=no
		fi
	else
		echo 只有release分支才有回滚操作，master等其他分支没有回滚操作,且不需要同步代码
		rsync_code_or_not=no
	fi
}


function_rsync_process_conflic_detect (){
	###在rsync代码前检测是否有rsync进程存在，以免冲突导致rsync错误或失败
	echo --------------------------------------------
	ps aux|grep rsync|grep -v grep
	rsync_process_conflic_or_not=$?
	#echo rsync_process_conflic_or_not:$rsync_process_conflic_or_not
	if [ $rsync_process_conflic_or_not != 0 ];then
		echo no rsync process run now,and you can rsync code to destination web server.
	else
		echo "发布机($release_server_ip:`pwd`)当前有rsync进程正在运行，以免因进程冲突导致发布错误，请等待50秒后返回主菜单后重试"
		echo 等待50秒... ; sleep 50
		#exit
	fi
}


function_rsync_code (){
	###只有存在可回滚版本时才真正rsync代码
	if [ $rsync_code_or_not = yes ];then
		function_rsync_process_conflic_detect
		echo
		echo "[3/3]---------------------------------------"		
		echo rsync code from release server to web server
		rsync_cmd="sshpass -p $wwwpass rsync -vzrtopg "
		###开始真正同步发布机git代码到web服务器,并隐藏同步的git信息
		#echo "rsync -vzrtopg --exclude "node_modules"  --exclude "tmp" $git_local_source_dir  $wwwuser@$server_ip:$server_www_root"
		echo "rsync  -vzrtopg --exclude "node_modules"  --exclude "tmp" $git_local_source_dir  $wwwuser@$server_ip:$server_www_root"
		echo
		$rsync_cmd  -e "ssh -o StrictHostKeyChecking=no" --exclude "node_modules"  --exclude "tmp"   \
		$git_local_source_dir  $wwwuser@$server_ip:$server_www_root | grep -v ^.git
		#$git_local_source_dir  $wwwuser@$server_ip:$server_www_root | grep -v ^.git
		rsync_code_result=$?
		echo
		if [[ $rsync_code_result = 0 ]];then
			echo rsync成功,发布完成
		else
			echo rsync失败，请检查...
		fi
	else
		echo rsync取消，因为只有存在可回滚版本时才真正rsync代码...
	fi
}


function_release_menu (){
	#####根据stash hooks触发自动发布
	auto_publish=$stash_hook_trigger_auto_publish
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
		function_rsync_code
	elif  [ "$input_user_type" = "2" ];then
		#echo 2
		function_change_branch	
		function_rsync_code
	elif  [ "$input_user_type" = "3" ];then
		#echo backuping
		function_rollback_branch
		function_rsync_code
	else
		echo 返回发布主菜单
		#exit
	fi
}



################################## main workflow starts ########################################
function_main (){
	function_entrance_menu
	####在发布机更新代码前进入相应目录
	cd $git_local_source_dir
	echo pwd:`pwd`
	function_release_menu
}


function_loop_publish_workflow () {
	###开始进入发布流程
	function_main
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


function_loop_publish_workflow |tee  $email_log


