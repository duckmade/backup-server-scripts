#!/bin/bash
umask 0000

# ip address of the source
source_ip=""

# should the destination server take over running docker stacks (default: no)?
failover="no"

# data directories to backup ("source 1" "source 2") (without trailing slash!)
declare -a source=("/mnt/user/data" "/mnt/user/timemachine")
declare -a destination=("/mnt/user/data" "/mnt/user/timemachine")

# location where docker related data is stored on source server (without trailing slash!)
docker_location_source="/mnt/user/appdata"

# location of backup directory for both source and destination (without trailing slash!)
backup_location="/mnt/user/system/backups"

# optional variables ###########################################################

# location where docker related data is stored on destination server (without trailing slash!)
# if set, docker data is synced to destination server and stacks are shutdown!
docker_location_destination="/mnt/user/appdata"

# fixed variables (DONT CHANGE) ################################################

log_location="$backup_location"/logs
log_name="$log_location"/"$(date +'%Y-%m-%d--%H:%M')"--2_destination_backup.txt

HOST="root@""$source_ip"

# functions ####################################################################

shutdownstacks () {
  for i in $(find /boot/config/plugins/compose.manager/projects/ -mindepth 1 -maxdepth 1 -type d) ; do
    echo "Shutting down specified stacks on destination server ..."
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
  if [ "$failover" == "yes" ] ; then
    for i in $(find /boot/config/plugins/compose.manager/projects/ -mindepth 1 -maxdepth 1 -type d) ; do
      echo "Starting stacks on backup server ..."
      docker-compose -f "$i"/compose.yml up -d
    done
  else
    for i in $(ssh "$HOST" find /boot/config/plugins/compose.manager/projects/ -mindepth 1 -maxdepth 1 -type d) ; do
      echo "Starting stacks on source server ..."
      ssh "$HOST" docker-compose -f "$i"/compose.yml up -d
    done
  fi
}

mainfunction () {
  if [ -f "$backup_location"/i_shutdown_source ] ; then
    rm "$backup_location"/i_shutdown_source
  fi
  ssh "$HOST" [[ -f "$backup_location"/start ]] && start="yes" || start="no";
  if [ "$start" == "yes" ] ; then
    ssh "$HOST" rm "$backup_location"/start
    rsync -avhsP "$HOST":"$backup_location"/ "$backup_location" >/dev/null
    echo "Source server initiated sync"
    echo "Syncing data to backup server ..."
    for i in `seq 1 ${#source[@]}` ; do
      rsync -avhsP --delete "$HOST":"${source[$i -1]}"/ "${destination[$i -1]}"
    done
    if [ -n "$docker_location_destination" ] ; then
      echo "Syncing docker data to backup server ..."
      shutdownstacks
      rsync -avhsP --delete "$HOST":"$docker_location_source"/ "$docker_location_destination"
      startupstacks
    fi
    if [ "$failover" == "yes" ] ; then
      echo "Source server will shut off shortly ... exiting"
      touch "$backup_location"/i_shutdown_source
    else
      echo "Shutting down backup server ... exiting"
    fi
  else
    echo "Source server didn't request sync job. Normal start of backup server ... exiting"
  fi
}

# start process ################################################################

mkdir -p "$log_location" && touch "$log_name"
mainfunction 2>&1 | tee -a "$log_name"
rsync -avhsP "$log_name" "$HOST":"$log_name" >/dev/null
if [ "$failover" == "yes" ] ; then
  ssh "$HOST" poweroff
else
  poweroff
fi
exit