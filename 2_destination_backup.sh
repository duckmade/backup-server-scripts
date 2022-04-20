#!/bin/bash
umask 0000

source_ip="" # ip address of the source
failover="no" # should the destination server take over running of docker stacks or turn off after sync (default: no)?

# primary directories to backup ("source 1" "source 2")
declare -a source_primary=("" "")
declare -a destination_primary=("" "")

# secondary directories to backup ("source 1" "source 2") (optional)
declare -a source_secondary=("" "")
declare -a destination_secondary=("" "")

loglocation="/mnt/user/appdata/backups/logs/"
logname="$loglocation""$(date +'%Y-%m-%d')"--2_destination_backup.txt

HOST="root@""$source_ip"

# functions ####################################################################

shallicontinue () {
  ssh "$HOST" [[ -f /mnt/user/appdata/backups/start ]] && start="yes" || start="no";
  if [ "$start" == "no" ] ; then
    echo "Source server didn't request sync job. Normal start of backup server ... exiting"
    exit
  fi
  echo "Source server initiated sync"
}

shutdownstacks () {
  for i in $(echo /boot/config/plugins/compose.manager/projects/*/compose.yml) ; do
    echo "Shutting down specified stacks on host server ..."
    docker-compose -f "$i" down
  done
  sleep 10
  for i in $(ssh "$HOST" echo /boot/config/plugins/compose.manager/projects/*/compose.yml) ; do
    echo "Shutting down specified stacks on backup server ..."
    ssh "$HOST" docker-compose -f "$i" down
  done
  sleep 10
}

startupstacks () {
  if [ "$failover" == "yes"  ] ; then
    for i in $(echo /boot/config/plugins/compose.manager/projects/*/compose.yml) ; do
      echo "Starting stacks on backup server ..."
      docker-compose -f "$i" up -d
    done
  else
    for i in $(ssh "$HOST" echo /boot/config/plugins/compose.manager/projects/*/compose.yml) ; do
      echo "Starting stacks on source server ..."
      ssh "$HOST" docker-compose -f "$i" up -d
    done
  fi
}

syncdata () {
  echo "Syncing primary data to backup server ..."
  for i in `seq 0 ${#source_primary[@]}` ; do
    rsync -avhsP --delete "$HOST":"${source_primary[$i]}" "${destination_primary[$i]}"
  done
  if [ ${#source_secondary[@]} -ne 0 ] ; then
    echo "Syncing secondary data to backup server ..."
    shutdownstacks
    for j in `seq 0 ${#source_secondary[@]}` ; do
      rsync -avhsP --delete "$HOST":"${source_secondary[$j]}" "${destination_secondary[$j]}"
    done
    startupstacks
  else
    echo "No secondary data to sync ... exiting"
  fi
}

cleanup () {
  ssh "$HOST" 'rm /mnt/user/appdata/backups/start'
  if [ "$failover" == "yes"  ] ; then
    echo "Source server will shut off shortly ... exiting"
    rsync -avhsP  "$logname" "$HOST":"$logname" >/dev/null
    rm "$logname"
    ssh "$HOST" 'poweroff'
    touch /mnt/user/appdata/backups/shutdown
  else
    echo "Shutting down backup server ... exiting"
    rsync -avhsP  "$logname" "$HOST":"$logname" >/dev/null
    rm "$logname"
    poweroff
  fi
}

mainfunction () {
  shallicontinue
  syncdata
  cleanup
}

# start process ################################################################

mkdir -p "$loglocation" && touch "$logname"
mainfunction 2>&1 | tee -a "$logname"
exit