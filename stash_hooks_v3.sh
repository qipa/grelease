#!/bin/bash

######stash hooks脚本，用于当用户提交后触发异步发布过程

####全局log文件
LOGFILE=/usr/local/atlassian-stash/external-hooks/log/post-receive-v3-`date +%Y%m%d`.log
####供用户查看的发布log
git_beeper_master_branch_auto_publish_log_99=/var/log/stash_hooks_log/beeper_master_auto_publish_to_99.log
git_beeper_release_branch_auto_publish_log_92=/var/log/stash_hooks_log/beeper_release_auto_publish_to_92.log
git_beeper_release_branch_auto_publish_log_217=/var/log/stash_hooks_log/beeper_release_auto_publish_to_217.log
####ssh remote execute command
#ssh_publish_server="sshpass -pstash-hooks123 ssh stash-hooks-auto-publish@192.168.100.119 "
ssh_publish_server="sshpass -p123 ssh www@192.168.100.119 "
stash_web_hook_arg_id=$1

function_auto_pushlish_and_log (){
	###传递参数给发布机，确定是发布master还是release
	pass_branch_name=$1
	echo -----------------发布beeper $pass_branch_name
	echo 最新commit信息:
	echo "$(git log -1)"
	echo 
	echo 最新commit详情:
	echo http://192.168.1.121:7990/projects/BEEPER/repos/beeper/commits/$newrev
	echo
	echo "oldrev:$oldrev --> newrev:$newrev  ref:$ref"
	$ssh_publish_server "/backup/autoshell/yunniao_release_v3.sh $pass_branch_name" 
}

function_stash_hooks_trigger(){
echo
echo
echo ------------------$(date) stash hooks trigger start------------------
echo trigger: $stash_web_hook_arg_id
while read oldrev newrev ref 
do
	####ref定义测试用途
	#ref=refs/heads/release/4.3
	#ref=refs/heads/master
	echo "所有---: oldrev:$oldrev --> newrev:$newrev  ref:$ref"
	####如果是master分支更新，则触发99上的发布脚本
	if [[ $ref =~ .*/master$ ]]; then
		###sleep 3
		sleep 3
		mv $git_beeper_master_branch_auto_publish_log_99.last $git_beeper_master_branch_auto_publish_log_99.last.last
		mv $git_beeper_master_branch_auto_publish_log_99      $git_beeper_master_branch_auto_publish_log_99.last
		function_auto_pushlish_and_log master99 | tee $git_beeper_master_branch_auto_publish_log_99
	fi

	if [[ $ref =~ .*/release/* ]];then
		###发布到92
		mv $git_beeper_release_branch_auto_publish_log_92.last $git_beeper_release_branch_auto_publish_log_92.last.last
                mv $git_beeper_release_branch_auto_publish_log_92      $git_beeper_release_branch_auto_publish_log_92.last
                function_auto_pushlish_and_log release92 | tee $git_beeper_release_branch_auto_publish_log_92
	
		###sleep 3s
		sleep 3	
		###发布到217
		mv $git_beeper_release_branch_auto_publish_log_217.last $git_beeper_release_branch_auto_publish_log_217.last.last
                mv $git_beeper_release_branch_auto_publish_log_217      $git_beeper_release_branch_auto_publish_log_217.last
                function_auto_pushlish_and_log release217 | tee $git_beeper_release_branch_auto_publish_log_217
        fi

done
echo 本次stash trigger完成。
}

function_stash_hooks_trigger >>$LOGFILE


