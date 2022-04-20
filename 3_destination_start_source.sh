#!/bin/bash
umask 0000

source_ip="" # ip address of the source
source_mac="" # macaddress of source

# secondary directories to sync back to source ("source 1" "source 2") (optional)
declare -a source_secondary=("" "")
declare -a destination_secondary=("" "")

loglocation="/mnt/user/appdata/backups/logs/"
logname="$loglocation""$(date +'%Y-%m-%d')"--3_destination_start_source.txt

HOST="root@""$source_ip"

# functions ####################################################################

pingsource () {
  ping "$source_ip" -c3 > /dev/null 2>&1 ; yes=$? ;
  if [ ! $yes == 0 ] ; then
    sourcestatus="off"
  else
    sourcestatus="on"
  fi
}

shallicontinue () {
  if [ -f /mnt/user/appdata/backups/shutdown ] ; then
    rm /mnt/user/appdata/backups/shutdown
    pingsource
    if [ "$sourcestatus" == "on"  ] ; then
      echo "Source server already running. Shutting down backup server ... exiting"
      poweroff
      exit
    else
      echo "Source server is off. Attempting to start source server"
    fi
  else
    echo "I didn't shutdown the source server so i will not start it up ... exiting"
    exit
  fi
}

wakeonlan () {
  etherwake -b "$source_mac"
}

sourcestatus () {
  checksource=1
  while [ "$sourcestatus" == "off" ] ; do
    pingsource
    echo "...Checking source server attempt..." "$checksource"
    echo "Source server not started yet. Waiting 30 seconds to retry ..."
    ((checksource=checksource+1))
    sleep 30
  done
  echo "Server is on, taking" "$((checksource * 30))" "seconds to boot"
}

checkarraystarted () {
  checkarray=1
  while ssh "$HOST" [ ! -d "/mnt/user/appdata/backups/" ] ; do
    echo "...Checking source server attempt..." "$checkarray"
    echo "Waiting for source server array to become available. Waiting 10 seconds to retry ..."
    ((checkarray=checkarray+1))
    sleep 10
  done
  echo "Source server array now started, taking" "$((checkarray * 10))" "seconds to start. I will wait 60 seconds to be sure docker service has started"
  sleep 60
}

shutdownstacks () {
  for i in $(echo /boot/config/plugins/compose.manager/projects/*/compose.yml) ; do
    echo "Shutting down stacks on backup ..."
    docker-compose -f "$i" down
  done
  sleep 10
}

startupstacks () {
  for i in $(ssh "$HOST" echo /boot/config/plugins/compose.manager/projects/*/compose.yml) ; do
    echo "Restarting stacks on source server ....." 
    ssh "$HOST" docker-compose -f "$i" up -d
  done
}

syncdata () {
  if [ ${#source_secondary[@]} -ne 0 ] ; then
    echo "Syncing secondary data back to source server ..."
    shutdownstacks
    for j in `seq 0 ${#source_secondary[@]}` ; do
      rsync -avhsP --delete "${destination_secondary[$j]}" "$HOST":"${source_secondary[$j]}"
    done
    startupstacks
  fi
}

cleanup () {
  echo "Shutting down backup server ... exiting"
  rsync -avhsP  "$logname" "$HOST":"$logname" >/dev/null
  rm "$logname"
  poweroff
}

mainfunction () {
  shallicontinue
  wakeonlan
  sourcestatus
  checkarraystarted
  syncdata
  cleanup
}

# start process ################################################################

mkdir -p "$loglocation" && touch "$logname"
mainfunction 2>&1 | tee -a "$logname"
exit