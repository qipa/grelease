#!/bin/bash
##################云鸟发布控制系统v3
### 发布系统主要工作流程: 
### dev-->push to stash-->stash hooks trigger auto release|manual release-->view|reload|restart|git pull|change branch|rollback branch-->grunt-->rsync-->reload-->smoke test-->log-->email
### 新特性：更加友好的支持多服务器发布环境、保证grunt结果的唯一性、按需grunt、node reload/restart、强制发布、冒烟测试等特性，特开发v3版本，v1和v2、v3核心功能一致
### coding by laijingli@weiboyi.com
### @20150420

####全局变量定义
repo=beeper
wwwuser=www
wwwpass=123
release_root_dir=/backup/autoshell
log_dir=${release_root_dir}/log/
tmp_dir=${release_root_dir}/tmp/
entrance_menu=${tmp_dir}.entrance_menu_v3.tmp
candidate_version=${tmp_dir}.candidate_version_v3.tmp
candidate_version_rollback=${tmp_dir}.candidate_version_rollback_v3.tmp
ssh_user_source_ip=`echo $SSH_CLIENT|awk '{print $1}'`
release_server_ip=`/sbin/ifconfig eth0|grep "net addr"|cut -d: -f2|cut -d" " -f1`
opration_log=${log_dir}opration.log
email_log=${log_dir}email_body_v3.log
receipt_user=362560701@qq.com
today=$(date +%Y%m%d)
email_tittle="【发布报告】_${repo}_by_www_from_${ssh_user_source_ip}_${today}"


######项目的配置文件，用于确定项目-服务器ip-wwwroot的对应关系
config_file=${release_root_dir}/yunniao_release_v3.conf
######stash hooks传递参数来保证自动发布
stash_hook_pass_arg_name=$1
#echo stash_hook_pass_arg_name:$stash_hook_pass_arg_name


################################### 发布机函数定义开始
function_entrance_menu (){
	#####入口菜单
	echo
	echo "********************* 欢迎使用云鸟发布控制系统v3 **********************"
	echo 发布时间: `date`
	echo 发布用户: `whoami` from $ssh_user_source_ip
	echo "***********************************************************************"
	echo 发布过程请不要强行终止，如遇发布异常，重试几次后仍不成功，请联系ops.

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
	cat $config_file|grep -v ^#|awk '{print FNR " --> "$3" "$4" "$5" "$6}'|column  -t > $entrance_menu
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

###git操作相关函数定义
function_git_local_status (){
	echo
	echo "发布机($release_server_ip:`pwd`)当前git status:"
	git status -uno
	echo
	echo "发布机($release_server_ip:`pwd`)当前发布branch版本(*表示)、上一个发布版本(可回滚版本)、下一个版本(如果有回滚过会出现,master分支除外):"
	git branch|grep -B 1  -A 1 ^* > $candidate_version_rollback
	cat $candidate_version_rollback
	#candidate_version_first_rollback=`cat $candidate_version_rollback|cut -d/ -f2|head -n1`
	###取可回滚版本并删除航首的空格
	candidate_version_first_rollback=`cat $candidate_version_rollback|head -n1|sed 's/^[ \t]*//g'`
}

function_git_show_remote_release_branchs (){
	####show服务器当前发布branch版本
	current_local_release_version=`git branch|grep ^* |cut -d" " -f2`
	echo "列出stash远程服务器上比当前发布版本高的、可发布的(最多列出10个即将发布版本)release branch:"
	#git branch -a|grep "remotes/origin/release/"|grep -A 10 remotes/origin/$current_local_release_version$  \
	#	     |grep -v remotes/origin/$current_local_release_version$ > $candidate_version
	###解决带小数位版本号的排序问题
	git branch -a|grep remotes/origin/release|awk -F / '{print $4}'|sort -t . -k1,1n -k2,2n|awk '{print "remotes/origin/release/" $1}' \
		     |grep -A 10 remotes/origin/$current_local_release_version$|grep -v remotes/origin/$current_local_release_version$ > $candidate_version
	###如果当前远程stash服务器上没有可发布的版本,则提示后直接退出
	if [ -s $candidate_version ];then
		echo 远程服务器上有可发布的版本	
		candidate_version_ok=yes
	else
		echo 
		echo 当前远程stash服务器上没有可发布的版本,自动返回发布主菜单...
		#exit
		break 3
	fi
	cat $candidate_version
	candidate_version_first=`cat $candidate_version|cut -d/ -f4|head -n1`
	candidate_version_last=`cat  $candidate_version|cut -d/ -f4|tail -n1`
	echo
}

function_git_last_commit (){
	echo
	echo "发布机($release_server_ip:`pwd`)当前branch最后一次commit信息:"
	git log --pretty=oneline  -1
	#git log --color --graph --pretty=format:"%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset"  \
	#	--abbrev-commit -1|head -n 1
}

function_git_process_conflic_detect (){
	###在git发布前检测是否有git进程存在，以免冲突导致发布错误或失败
	ps aux|grep git|grep -v grep
	git_process_conflic_or_not=$?
	#echo git_process_conflic_or_not:$git_process_conflic_or_not
	if [ $git_process_conflic_or_not != 0 ];then
		echo no git process run now,and you can release.
	else
		echo "发布机($release_server_ip:`pwd`)当前有git进程正在运行，以免因进程冲突导致发布错误，请等待10秒后返回主菜单后重试"
		echo 等待10秒... ; sleep 10
		#exit
	fi
}

function_git_update_current_branch (){
	function_git_process_conflic_detect
	function_git_local_status
	function_git_last_commit
	last_commit_num=`function_git_last_commit|tail -n 1|awk '{print $1}'`
	#echo last_commit_num:$last_commit_num
	echo
	echo  -e "\033[32m\033[01m-------------[1/5]---------------------------------------\033[0m"
	echo "发布机($release_server_ip:`pwd`)发布执行结果(git pull):"
	git reset --hard && \
	git pull
	git_pull_result=$?
	echo
	#function_git_local_status
	function_git_last_commit
	current_commit_num=`function_git_last_commit|tail -n 1|awk '{print $1}'`
	#echo current_commit_num:$current_commit_num
	echo
	if [[ $git_pull_result = 0 ]];then
		if [[ $force_release_code = yes ]];then
			echo
			echo 发布机代码更新成功,手动强制grunt压缩css文件
			grunt_or_not=yes
			function_git_grunt
		else
			if [[ $last_commit_num = $current_commit_num ]];then
				echo
				echo "Already up-to-date,无代码更新,不需要运行grunt压缩css文件"
				grunt_or_not=no
				function_git_grunt
			else
				###如果有代码更新，判断static目录本次和上次发布commit代码是否有变化，有变化则按需grunt，无变化则不grunt
				git diff --name-only $last_commit_num $current_commit_num|grep ^static/ 2>&1 >/dev/null
				git_diff_result=$?
				if [[ $git_diff_result = 0 ]];then 
					echo
					echo 发布机代码更新成功,且static目录有更新,开始运行grunt压缩css文件	
					grunt_or_not=yes
					function_git_grunt
				else
					echo 发布机代码更新成功,且static目录没有变化,不需要运行grunt,但需要运行rsync
					rsync_code_or_not=yes
				fi
			fi
		fi
	else
		echo 发布机代码更新失败，请检查...
	fi
}	

function_git_input_release_version () {
	function_git_local_status
	function_git_show_remote_release_branchs
	if [ $candidate_version_ok = yes ] ;then
		echo -en "\033[31m\033[01m从上述列表选择要切换的远程branch名字，仅数字版本号,比如3.5(exit退出发布系统,back返回发布主菜单):\033[0m"
		read input_release_version
		###判断输入是否合法,即用户输入的版本号是否存在于远程库
		if   [ "$input_release_version" = "exit" ];then 
			echo bye... ;exit
		elif [ "$input_release_version" = "back" ];then
			echo 返回发布主菜单...
			break 2 
		else
			grep remotes/origin/release/${input_release_version}$  $candidate_version	
			#git branch -a|grep  remotes/origin/release/${input_release_version}$
			input_hit=$?
		fi
	else
		exit
	fi
}

function_git_change_branch () {
	function_git_process_conflic_detect
	function_git_input_release_version
	until [ "$input_hit" = "0" ] || [ "$input_hit" = "exit" ] || [ "$input_release_version" = "back" ];do
		function_git_input_release_version
	done
	#echo 输入正确:$input_release_version

	##获取用户切换branch确认
	function_git_last_commit
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
		echo -e "\033[32m\033[01m-------------[1/5]---------------------------------------\033[0m"
		echo "发布机($release_server_ip:`pwd`)git pull执行结果:"
		git reset --hard
		git checkout     release/$input_release_version  && \
		git merge origin/release/$input_release_version
		git_change_branch_result=$?
		echo
		if [[ $git_change_branch_result = 0 ]];then
			echo 发布机代码change branch成功,开始运行grunt压缩css文件
			grunt_or_not=yes
			function_git_grunt
			function_git_last_commit
		else
			echo 发布机代码更新失败，请检查...
		fi
	else
		echo 你已取消change branch操作，不做任何操作，返回发布主菜单...
		break
	fi
}

function_git_rollback_branch (){
	function_git_process_conflic_detect
	function_git_local_status
	#echo candidate_version_first_rollback:$candidate_version_first_rollback

	#####只有release分支才有回滚操作，master等其他分支没有回滚操作
	echo $candidate_version_first_rollback|grep release >/dev/null
	rollback_release_or_not=$?
	if [ $rollback_release_or_not = 0 ];then	
	##获取用户回滚branch确认
	function_git_last_commit
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
		echo -e "\033[32m\033[01m-------------[1/5]---------------------------------------\033[0m"
		echo "发布机($release_server_ip:`pwd`)git pull执行结果:"
		echo candidate_version_first_rollback:$candidate_version_first_rollback
		git reset --hard
		git checkout     $candidate_version_first_rollback  && \
		git merge origin/$candidate_version_first_rollback
		git_rollback_result=$?
		echo
			if [[ $git_rollback_result = 0 ]];then
				echo 发布机代码rollback成功,开始运行grunt压缩css文件
				grunt_or_not=yes
				function_git_grunt
				function_git_last_commit
			else
				echo 发布机代码rollback失败，不运行grunt,请检查...
			fi
		else
			echo 你已取消回滚操作，不做任何操作，返回发布主菜单...
			break 
		fi
	else
		echo
		echo 只有release分支才有回滚操作，master等其他分支没有回滚操作,不做任何操作，返回发布主菜单...
		#exit
		break 
	fi
}

function_git_grunt (){
	####压缩css等文件
	echo
	echo -e "\033[32m\033[01m-------------[2/5]---------------------------------------\033[0m"
	if [[ $grunt_or_not = yes ]];then
		grunt_cmd="grunt  build_web_css build_web_js"
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
	else
		echo 不需要运行grunt...
	fi
}

function_rsync_process_conflic_detect (){
	###在rsync代码前检测是否有rsync进程存在，以免冲突导致rsync错误或失败
	#echo --------------------------------------------
	ps aux|grep rsync|grep $server_ip|grep -v grep
	rsync_process_conflic_or_not=$?
	#echo rsync_process_conflic_or_not:$rsync_process_conflic_or_not
	if [ $rsync_process_conflic_or_not != 0 ];then
		echo no rsync process run now,and you can rsync code to destination web server.
	else
		echo "发布机($release_server_ip:`pwd`)当前有rsync进程正在运行，以免因进程冲突导致发布错误，请等待30秒后返回主菜单后重试"
		echo 等待30秒... ; sleep 30
		#exit
	fi
}

function_rsync_code (){
	###只有存在可回滚版本时才真正rsync代码
	echo
	echo -e "\033[32m\033[01m-------------[3/5]---------------------------------------\033[0m"
	if [[ $force_release_code = yes ]];then rsync_code_or_not=yes;fi
	if [ $rsync_code_or_not = yes ];then
		###如果需要同步代码，则需发送邮件报告
		email_notify_or_not=yes
		function_rsync_process_conflic_detect
		echo
		echo rsync code from release server to web server
		rsync_cmd="sshpass -p $wwwpass rsync -vzrtopg "
		###开始真正同步发布机git代码到web服务器,并隐藏同步的git信息
		echo "rsync -vzrtopg --exclude "node_modules"  --exclude "tmp"  $git_local_source_dir  $wwwuser@$server_ip:$server_www_root"
		echo
		$rsync_cmd  -e "ssh -o StrictHostKeyChecking=no" --exclude "node_modules"  --exclude "tmp"  \
		$git_local_source_dir  $wwwuser@$server_ip:$server_www_root | grep -v ^.git
		#$git_local_source_dir  $wwwuser@$server_ip:$server_www_root | grep -v ^.git
		rsync_code_result=$?
		echo
		if [[ $rsync_code_result = 0 ]];then
			echo rsync成功,开始reload node service
			reload_node_or_not=yes
		else
			echo rsync失败，请检查...
		fi
	else
		echo 不需要运行rsync,没有代码需要同步...
	fi
}

function_show_node_service_info_on_web_server (){
	remote_opration="echo 当前node监听端口信息:; \
			ps aux|grep node|grep -v grep|sort -k12 ; \
			echo ; \
			echo 当前node监听端口信息:; \
			sudo netstat -anp|grep LIST|grep node; \
			sleep 1"	
	ssh_remote_cmd="sshpass -p $wwwpass ssh -tt -o StrictHostKeyChecking=no "
	$ssh_remote_cmd $wwwuser@$server_ip "$remote_opration"
}

function_reload_node_service_on_web_server (){
	echo
	echo -e "\033[32m\033[01m-------------[4/5]---------------------------------------\033[0m"
	if [[ $force_release_code = yes ]];then reload_node_or_not=yes;fi
	if [ $reload_node_or_not = yes ];then
		echo 系统自动reload nodejs,请稍等...
		remote_opration="sudo /etc/init.d/restart_node_recluster.sh reload; \
				sleep 1s; \
				echo reload后node监听端口信息:; \
				sudo netstat -anp|grep LIST|grep node"
		ssh_remote_cmd="sshpass -p $wwwpass ssh -tt -o StrictHostKeyChecking=no "
		#echo ssh $wwwuser@$server_ip "$remote_opration"
		echo
		$ssh_remote_cmd $wwwuser@$server_ip "$remote_opration"
	else
		echo reload node service自动取消，因为没有代码rsync到$server_ip服务器...
	fi
}

function_restart_node_service_on_web_server (){
	if [[ $force_release_code = yes ]];then restart_node_or_not=yes;fi
	if [ $restart_node_or_not = yes ];then
		echo 系统自动restart nodejs,请稍等...
		remote_opration="sudo /etc/init.d/restart_node_recluster.sh restart"
		ssh_remote_cmd="sshpass -p $wwwpass ssh -tt -o StrictHostKeyChecking=no "
		echo ssh $wwwuser@$server_ip "$remote_opration"
		echo
		$ssh_remote_cmd $wwwuser@$server_ip "$remote_opration"
	else
		echo restart node service取消
	fi
}

function_smoke_test (){
	###注意smoke_test_name和smoke_test_url的一一对应关系
	smoke_test_name=(
	A_3500
	B_8500
	S_5500)
	smoke_test_url=(
	http://$server_ip:3500/login/reg
	http://$server_ip:8500/public/home
	http://$server_ip:5500/api/v2/check_update)
	smoke_test_num=${#smoke_test_url[@]}
	echo
	echo -e "\033[32m\033[01m-------------[5/5]---------------------------------------\033[0m"	
	echo auto run basic smoke test: 
	for ((i=0;i<$smoke_test_num;i++));do
		test_name=${smoke_test_name[$i]}
		test_url=${smoke_test_url[$i]}
		echo -n "smoke test for $test_name by test url $test_url "
		http_return_code=`curl -o /dev/null -s -w %{http_code} $test_url`
		if [[ $http_return_code = 200 ]];then
			echo http_return_code=$http_return_code,smoke test 成功
		else
			echo http_return_code=$http_return_code,smoke test 失败
		fi
	done
}

function_email_notify (){
	echo
	echo email_notify_or_not=$email_notify_or_not
	echo manual_release_or_not=$manual_release_or_not 
	###如果是手工发布，且需要rynsc代码的话则需要发送email通知，用于线上发布
	if [[ $email_notify_or_not = yes ]] && [[ $manual_release_or_not = yes ]];then
		cat $email_log |mutt -a $email_log -s $email_tittle $receipt_user
		echo  发布报告邮件已发送到$receipt_user
	fi
}

####为什么写的那么冗余，涉及到在有管道的时候函数的返回值无法返回给父进程，email时需要用到管道接受屏幕输出到文件
####参考http://blog.csdn.net/ithomer/article/details/7954577
####参考http://www.linuxidc.com/Linux/2013-11/93331.htm

###将rsync、reload、smoke test、email模块集成到一个事务函数中
function_transcation_update_rsync_reload_smoke_email (){
	function_git_update_current_branch	
	function_rsync_code
	function_reload_node_service_on_web_server
	function_smoke_test
	function_email_notify
}

function_transcation_change_rsync_reload_smoke_email (){
	function_git_change_branch
	function_rsync_code
	function_reload_node_service_on_web_server
	function_smoke_test
	function_email_notify
}

function_transcation_rollback_rsync_reload_smoke_email (){
	function_git_rollback_branch
	function_rsync_code
	function_reload_node_service_on_web_server
	function_smoke_test
	function_email_notify
}



function_release_menu (){
	##全局默认
	candidate_version_ok=no
	force_release_code=no
	grunt_or_not=no
	rsync_code_or_not=no
	reload_node_or_not=no
	restart_node_or_not=no
	email_notify_or_not=no
	manual_release_or_not=no
	####默认不返回发布主菜单
	auto_return_entrance_menu=no


	#####根据stash hooks触发自动发布
	auto_publish=$stash_hook_trigger_auto_publish
	case $auto_publish in 
	master99|release92|release217)
	echo -e "\033[32m\033[01m根据stash hooks触发master branch自动发布\033[0m"
	input_user_type=6
	auto_return_entrance_menu=yes;;


	*)
	manual_release_or_not=yes
	####远程目标服务器发布选项菜单
	echo "---------------------------------------"
	echo "------  请选择发布操作类型选项  -------"
	echo "          on $server_ip                "
	echo "---------------------------------------"
	echo "1 --> run basic smoke test"
	echo "2 --> 查看web服务器当前发布代码版本信息"
	echo "3 --> 查看服务器当前node进程及监听端口信息"
	echo "4 --> 手动强制reload  node服务 (包括admin.js api.js kue.js customer.js customer_api.js mosca.js)"
	echo "5 --> 手动强制restart node服务 (包括admin.js api.js kue.js customer.js customer_api.js mosca.js)"
	echo "6 --> 手动or自动发布代码(在当前branch上git pull更新代码,自动按需grunt、rsync、reload)"
	echo "7 --> 手动强制发布代码  (在当前branch上git pull更新代码,自动强制grunt、rsync、reload)"
	echo "8 --> 手动发布新branch  (升级release branch版本号,包括版本号正常升级及线上bugfix)"
	echo "9 --> 手动回滚旧branch  (降级release branch版本号)"

	###输入
	echo -en "\033[31m\033[01m请选择发布选项编号(exit退出发布系统,back返回发布主菜单):\033[0m"
	read  input_user_type
	##判断输入是否合法
	until   [ "$input_user_type" = "1" ] || [ "$input_user_type" = "2" ] || [ "$input_user_type" = "3" ] || \
		[ "$input_user_type" = "4" ] || [ "$input_user_type" = "5" ] || [ "$input_user_type" = "6" ] || \
		[ "$input_user_type" = "7" ] || [ "$input_user_type" = "8" ] || [ "$input_user_type" = "9" ] || \
		[ "$input_user_type" = "exit" ] || [ "$input_user_type" = "back" ] ;do
		echo -en "\033[31m\033[01m请选择发布选项编号(exit退出发布系统,back返回发布主菜单):\033[0m"
		read input_user_type
	done;;
	
	esac

	###执行用户输入的操作
	if      [ "$input_user_type" = "1" ];then
		echo run basic smoke test
		function_smoke_test	
	elif    [ "$input_user_type" = "2" ];then
		echo 查看web服务器当前发布代码版本信息
		function_git_local_status
		function_git_last_commit
	elif  [ "$input_user_type" = "3" ];then
		echo 查看服务器当前node进程及监听端口信息
		function_show_node_service_info_on_web_server
	elif  [ "$input_user_type" = "4" ];then	
		echo "手动reload node服务 on $server_ip"
		reload_node_or_not=yes
		function_reload_node_service_on_web_server
		function_smoke_test
	elif  [ "$input_user_type" = "5" ];then
		echo "手动强制restart node服务 on $server_ip"
		restart_node_or_not=yes
		function_restart_node_service_on_web_server
		function_smoke_test
	elif  [ "$input_user_type" = "6" ];then
		echo 手动or自动发布代码 |tee  $email_log
		function_transcation_update_rsync_reload_smoke_email |tee  -a $email_log
	elif  [ "$input_user_type" = "7" ];then
		echo 手动强制发布代码 |tee  $email_log
		force_release_code=yes
		function_transcation_update_rsync_reload_smoke_email |tee  -a $email_log
	elif  [ "$input_user_type" = "8" ];then
		echo 手动发布新branch |tee  $email_log
		function_transcation_change_rsync_reload_smoke_email |tee  -a $email_log
	elif  [ "$input_user_type" = "9" ];then
		echo 手动回滚旧branch |tee  $email_log
		function_transcation_rollback_rsync_reload_smoke_email |tee  -a $email_log
	elif  [ "$input_user_type" = "back" ];then
		echo 返回发布主菜单
		auto_return_entrance_menu=yes
	else 
		echo 1秒后退出发布系统...;sleep 1;exit	
	fi
}


################################## main workflow starts ########################################
function_main (){
	function_entrance_menu
	####在发布机更新代码前进入相应目录
	cd $git_local_source_dir
	echo pwd:`pwd`
	###循环显示release_menu，直到用户主动返回发布主菜单
	while true;do
		function_release_menu
		echo
		###如果用户主动选择返回发布主菜单或者是自动发布则直接返回发布主菜单
		if [[ $auto_return_entrance_menu = yes ]];then
			break 
		fi
	done
}

function_loop_publish_workflow () {
	##归档发布log
	if [[ -f $opration_log.last ]];then mv $opration_log.last $opration_log.last.last;fi
	if [[ -f $opration_log ]]     ;then mv $opration_log      $opration_log.last;fi
	###开始进入发布流程
	while true;do
		function_main
		####如果是stash hook触发则自动发布完成后自动退出
		#echo stash_hook_trigger_auto_publish----$stash_hook_trigger_auto_publish
		case $stash_hook_trigger_auto_publish in
			master99|release92|release217) 
			echo -e "\033[32m\033[01m本次发布由stash hooks触发的自动发布,发布完成自动退出...\033[0m"
			echo 发布结束时间:`date`
			exit;;
		esac
	done
}

function_loop_publish_workflow |tee  $opration_log


