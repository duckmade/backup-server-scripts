#!/bin/bash
umask 0000

CONFI="/mnt/user/appdata/backups/config.cfg"

# functions ####################################################################

readconfig () { 
  source "$CONFI"
  HOST="root@""$source_ip" 
  mkdir -p "$loglocation"
  logname="$loglocation""$(date +'%Y-%m-%d--%H:%M')""--destination_to_source.txt"
  touch "$logname"
}

pingsource () {
  ping "$source_ip" -c3 > /dev/null 2>&1 ; yes=$? ; # ping source server 3 times to check for reply
  if [ ! $yes == 0 ] ; then
    sourcestatus="off"
  else
    sourcestatus="on"
  fi
}

shallicontinue () {
  if [ -f /mnt/user/appdata/backups/i_shutdown_source ] ; then
    rm /mnt/user/appdata/backups/i_shutdown_source
    pingsource
    if [ "$sourcestatus" == "on"  ] ; then
      echo "Source server already running."
      echo "Shutting down backup server"
      poweroff
      exit
    else
      echo "Source server is off...continuing"
      echo "Attempting to start source server"
    fi
  else
    echo "I didnt shutdown the source server so i will not start it up ....exiting"
    exit
  fi
}

wakeonlan () {
  etherwake -b "$source_mac"
}

sourcestatus () {
  sourcecheck=1
  #check if source server has started up yet
  while [ "$sourcestatus" == "off" ] ; do
    pingsource
    echo "..........Checking source server attempt..." "$sourcecheck"
    echo "Source server not started yet"
    echo "Waiting 30 seconds to retry ......"
    ((sourcecheck=sourcecheck+1))
    sleep 30  # wait 30 seconds before rechecking
  done
  echo "..........Checking source server attempt..." "$sourcecheck"
  echo "Source server is now up"
}

checkarraystarted () {
  arraycheck=1
  while ssh "$HOST" [ ! -d "/mnt/user/appdata/backups/" ] ; do
    echo "Attempt" "$arraycheck" "waiting for source server array to become available"
    echo "Waiting 10 seconds to retry...."
    ((arraycheck=arraycheck+1))
    sleep 10
  done
  echo "Attempt" "$arraycheck" "Ok. Source server array now started...."
  echo "I will wait 30 seconds to be sure docker service has started"
  sleep 30
}

syncmaindata () {
  # sync data from destination server to source server
  if [ "$sync_primary_back" == "yes"  ] ; then
    echo "Main data will be synced back to source server"
    for i in `seq 0 2 ${#primary[@]}` ; do
      rsync -avhsP --delete "${primary[$i + 1]}" "$HOST":"${primary[$i]}"
    done
  fi
}

shutdownstacks () {
  for contval in "${stacks[@]}" ; do
    echo "Shutting down specified stacks on source server before sync ....." 
    ssh "$HOST" docker-compose -f /boot/config/plugins/compose.manager/projects/"$contval"/compose.yml down
    echo 
  done
  sleep 10
}

startupstacks () {
  for contval in "${stacks[@]}" ; do
    echo "Restarting specified stacks on source server now appdata is synced ....." 
    ssh "$HOST" docker-compose -f /boot/config/plugins/compose.manager/projects/"$contval"/compose.yml up
    echo 
  done
}

syncappdata () {
  if [ "$sync_secondary_back" == "yes"  ] ; then
    echo "Appdata will be synced back to source server"
    shutdownstacks
    for j in `seq 0 2 ${#secondary[@]}` ; do
      rsync -avhsP --delete "${secondary[$j + 1]}" "$HOST":"${secondary[$j]}"
    done
    startupstacks # Restart the shutdown stacks on source now appdata has been synced
  fi
}

sync2source () {
  syncmaindata
  syncappdata 
}

# start process ################################################################

readconfig
shallicontinue
wakeonlan
sleep 5
sourcestatus 
checkarraystarted 
sync2source 2>&1 | tee -a "$logname"
rsync -avhsP  "$logname" "$HOST":"$logname" >/dev/null
rm "$logname"
poweroff # shutdown server
exit