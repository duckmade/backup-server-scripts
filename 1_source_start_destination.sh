#!/bin/bash
umask 0000

# ip address of the destination
destination_ip=""

# macaddress of destination
destination_mac=""

# location of backup directory for both source and destination (without trailing slash!)
backup_location="/mnt/user/system/backups"

# fixed variables (DONT CHANGE) ################################################

log_location="$backup_location"/logs
log_name="$log_location"/"$(date +'%Y-%m-%d--%H:%M')"--1_source_start_destination.txt

# functions ####################################################################
 
pingdestination () {
  ping "$destination_ip" -c10 > /dev/null 2>&1 ; yes=$? ;
  if [ ! $yes == 0 ] ; then
    destinationstatus="off"
  else
    destinationstatus="on"
  fi
}

wakeonlan () {
  etherwake -b "$destination_mac"
}

destinationstatus () {
  checkbackup=1
  while [ "$destinationstatus" == "off" ] ; do
    pingdestination
    echo "...Checking backup server attempt..." "$checkbackup"
    echo "Backup server not started yet. Waiting 30 seconds to retry ..."
    ((checkbackup=checkbackup+1))
    sleep 30
  done
  echo "Server is on, taking" "$((checkbackup * 30))" "seconds to boot"
}

mainfunction () {
  if [ -f "$backup_location"/start ] ; then
    rm "$backup_location"/start
  fi
  pingdestination
  if [ "$destinationstatus" == "on" ] ; then
    echo "Backup server already running"
  else
    echo "Backup server is off. Attempting to start destination server"
    touch "$backup_location"/start
    wakeonlan
    destinationstatus
  fi
  echo "Sync must initiate from backup server ... exiting"
}

# start process ################################################################

mkdir -p "$log_location" && touch "$log_name"
mainfunction 2>&1 | tee -a "$log_name"
exit
