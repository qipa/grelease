#!/bin/bash
######nodejs recluster controll script coding by laijingli@weiboyi.com
######20150522

node_server_env="testing"
#node_server_env="production"
runuser=www
app_root_dir=/var/www/beeper_v2
#app_root_dir=/var/www/beeper_testonly/beeper
node_recluster_cmd="/usr/local/bin/node recluster.js"
#node_recluster_cmd="/root/node-v0.12.3-linux-x64/bin/node recluster.js"
node_recluster_reload_cmd="$app_root_dir/bin/restart_recluster.sh"
default_node_services="admin.js api.js kue.js customer.js customer_api.js mosca.js"


function_help () {
operation="start|stop|reload|restart"
cat <<EOF
Useage:
$0 {$operation}      --->{$operation} all node service in {$default_node_services}
$0 {$operation} one  --->{$operation} one node service in {$default_node_services}
EOF
}

###根据用户输入的第二个参数确定是重启所有服务还是一个服务
if   [[ -z $1 ]] && [[ -z $2 ]];then
	function_help
	exit
elif [[ $1 ]]    && [[ -z $2 ]];then
	echo operation on all services in {$default_node_services}:
	echo
	node_services=$default_node_services
elif [[ `echo $default_node_services|awk '{for (i=1;i<=NF;i++) print $i}'|grep ^$2$` ]];then
	node_services=$2
else
	echo syntax error,please check ...
	function_help
fi


function_get_node_process_info () {
	echo -------------------------------------------------------------------------
	echo process info for $node_service service:
	ps aux|grep  " $node_service$"|grep -vE "grep|restart_node_recluster.sh"
	echo
}

function_start_node_service  (){
	lock_file="/var/lock/subsys/$node_service.v2.lock"
	if [ ! -f "$lock_file" ] ; then
		echo -ne "\033[32m\033[01m Starting service $node_service: \033[0m"
		/sbin/runuser -l "$runuser" -c "cd $app_root_dir;NODE_ENV=$node_server_env $node_recluster_cmd $node_service >> /tmp/$node_service.log 2>&1 &" && echo 成功 || echo 失败
		return_reslut=$?
		[ $return_reslut -eq 0 ] && touch $lock_file
		sleep 1
		function_get_node_process_info
	else
		echo "lock_file $lock_file exists."
		echo "node_service $node_service is locked."
		return_reslut=1
	fi

}

function_stop_node_service (){
	lock_file="/var/lock/subsys/$node_service.v2.lock"
	echo  -ne "\033[32m\033[01m Stopping service $node_service: \033[0m"
	ps aux|grep  "$node_recluster_cmd $node_service"|grep -v grep|awk '{print $2}'|xargs kill -9 > /dev/null 2>&1 && echo 成功 || echo 失败
	return_reslut=$?
	[ $return_reslut -eq 0 ] && /bin/rm -f $lock_file
}

function_reload_node_service (){
	#function_get_node_process_info
	echo  -ne "\033[32m\033[01m Reloading service $node_service: \033[0m"
	/sbin/runuser -l "$runuser" -c "$node_recluster_reload_cmd  $node_service" && echo 成功 || echo 失败
	sleep 1
	#function_get_node_process_info
}


loop_start   (){ for node_service in $node_services ;do function_start_node_service;echo;done }
loop_stop    (){ for node_service in $node_services ;do function_stop_node_service;echo;done }
loop_reload  (){ for node_service in $node_services ;do function_reload_node_service;echo;done }
loop_restart (){ for node_service in $node_services ;do function_stop_node_service;function_start_node_service;echo;done }

case "$1" in
	start)
		loop_start
		;;
	stop)
		loop_stop
		;;
	reload)
		loop_reload
		;;
	restart)
		loop_restart
		;;
	*)
		function_help
		return_reslut=1
esac
exit $return_reslut

