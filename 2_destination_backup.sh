#!/bin/bash
umask 0000

source_ip="192.168.1.100" # ip address of the source
forcestart="no"           # should request be forced to source?

CONFI="/mnt/user/appdata/backups/config.cfg"

# functions ####################################################################

readconfig () {
  # read config file written by source server and set other variables
  mkdir -p /mnt/user/appdata/backups/
  HOST="root@""$source_ip"
  rsync -avhsP  "$HOST":"$CONFI" "$CONFI" 
  source "$CONFI"
  ssh "$HOST" [[ -f /mnt/user/appdata/backups/start ]] && start="yes" ||  start="no";
}

syncmaindata () {
  # sync data from source server to backup server
  if [ "$sync_primary" == "yes"  ] ; then
    for i in `seq 0 2 ${#primary[@]}` ; do
      rsync -avhsP --delete "$HOST":"${primary[$i]}" "${primary[$i + 1]}"
    done
  fi
}

shutdownstacks () {
  for contval in "${stacks[@]}" ; do
    echo "Shutting down specified stacks on host and backup server ....." 
    ssh "$HOST" docker-compose -f /boot/config/plugins/compose.manager/projects/"$contval"/compose.yml down
    docker-compose -f /boot/config/plugins/compose.manager/projects/"$contval"/compose.yml down
    echo 
  done
  sleep 10
}

startupstacks () {
  if [ "$failover" == "yes"  ] ; then
    for contval in "${stacks[@]}" ; do
      echo "Starting specified stacks on backup server ....." 
      docker-compose -f /boot/config/plugins/compose.manager/projects/"$contval"/compose.yml up
      echo 
    done
  fi
  if [ "$failover" == "no"  ] ; then
    for contval in "${stacks[@]}" ; do
      echo "Starting specified stacks on source server  ....." 
      ssh "$HOST" docker-compose -f /boot/config/plugins/compose.manager/projects/"$contval"/compose.yml up
      echo 
    done
  fi
}

syncappdata () {
  if [ "$sync_secondary" == "yes"  ] ; then
    shutdownstacks
    for j in `seq 0 2 ${#secondary[@]}` ; do
      rsync -avhsP --delete "$HOST":"${secondary[$j]}" "${secondary[$j + 1]}"
    done
    startupstacks
  fi
}

endandshutdown () {
  # this function cleans up and exits script shutting down server if that has been set
  if [ "$poweroff" == "backup"  ] ; then
    echo "Shutting down backup server"
    poweroff # shutdown backup server
  elif [ "$poweroff" == "source"  ] ; then
    ssh "$HOST" 'poweroff' # shutdown source server to shutdown
    echo "source server will shut off shortly"
    touch /mnt/user/appdata/backups/i_shutdown_source
  else
    echo "Neither Source nor backup server set to turn off"
  fi
  ssh "$HOST" 'rm /mnt/user/appdata/backups/start' 
}

mainfunction () {
  # check if main server started process by making start flag file, then start sync
  if [ "$start" == "yes" ] ; then
    syncmaindata
    syncappdata
    endandshutdown
  elif  [ "$forcestart" == "yes"  ] ; then
    syncmaindata
    syncappdata
    endandshutdown
  else
    echo "Source server didn't request sync job"
    echo "Normal start of backup server so exiting script"
    exit
  fi
}

# start process ################################################################

readconfig
mainfunction 2>&1 | ssh "$HOST" -T tee -a "$logname"
exit