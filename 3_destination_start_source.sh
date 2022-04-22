#!/bin/bash
umask 0000

# ip address of the source
source_ip=""

# macaddress of source
source_mac=""

# location where docker related data is stored on source server (without trailing slash!)
docker_location_source="/mnt/user/appdata"

# location of backup directory for both source and destination (without trailing slash!)
backup_location="/mnt/user/system/backups"

# optional variables ###########################################################

# location where docker related data is stored on destination server (without trailing slash!)
# if set, docker data is synced to destination server and stacks are shutdown!
docker_location_destination=""

# fixed variables ##############################################################

log_location="$backup_location"/logs
log_name="$log_location"/"$(date +'%Y-%m-%d')"--3_destination_start_source.txt

HOST="root@""$source_ip"

# functions ####################################################################

pingsource () {
  ping "$source_ip" -c10 > /dev/null 2>&1 ; yes=$? ;
  if [ ! $yes == 0 ] ; then
    sourcestatus="off"
  else
    sourcestatus="on"
  fi
}

shallicontinue () {
  if [ -f "$backup_location"/i_shutdown_source ] ; then
    rm "$backup_location"/i_shutdown_source
    pingsource
    if [ "$sourcestatus" == "on"  ] ; then
      echo "Source server already running"
      cleanup
      exit
    fi
    echo "Source server is off. Attempting to start source server"
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
  while ssh "$HOST" [ ! -d "$backup_location"/ ] ; do
    echo "...Checking source server attempt..." "$checkarray"
    echo "Waiting for source server array to become available. Waiting 10 seconds to retry ..."
    ((checkarray=checkarray+1))
    sleep 10
  done
  echo "Source server array now started, taking" "$((checkarray * 10))" "seconds to start. I will wait 60 seconds to be sure docker service has started"
  sleep 60
}

shutdownstacks () {
  for i in $(find /boot/config/plugins/compose.manager/projects/ -mindepth 1 -maxdepth 1 -type d) ; do
    echo "Shutting down stacks on destination server ..."
    docker-compose -f "$i"/compose.yml down
  done
  sleep 10
  for i in $(ssh "$HOST" find /boot/config/plugins/compose.manager/projects/ -mindepth 1 -maxdepth 1 -type d) ; do
    echo "Shutting down specified stacks on source server ..."
    ssh "$HOST" docker-compose -f "$i"/compose.yml down
  done
  sleep 10
}

startupstacks () {
  for i in $(ssh "$HOST" find /boot/config/plugins/compose.manager/projects/ -mindepth 1 -maxdepth 1 -type d) ; do
    echo "Starting stacks on source server ....." 
    ssh "$HOST" docker-compose -f "$i"/compose.yml up -d
  done
}

cleanup () {
  rsync -avhsP --delete "$backup_location"/ "$HOST":"$backup_location" >/dev/null
  echo "Shutting down backup server ... exiting"
  poweroff
}

mainfunction () {
  shallicontinue
  wakeonlan
  sourcestatus
  checkarraystarted
  if [ -n "$docker_location_destination"] ; then
    echo "Syncing docker data back to source server ..."
    shutdownstacks
    rsync -avhsP --delete "$docker_location_destination"/ "$HOST":"$docker_location_source"
    startupstacks
  fi
  cleanup
}

# start process ################################################################

mkdir -p "$log_location" && touch "$log_name"
mainfunction 2>&1 | tee -a "$log_name"
exit