#!/bin/bash
umask 0000

destination_ip="" # ip address of the destination
destination_mac="" # macaddress of destination

loglocation="/mnt/user/appdata/backups/logs/"
logname="$loglocation""$(date +'%Y-%m-%d')"--1_source_start_destination.txt

# functions ####################################################################
 
pingdestination () {
  ping "$destination_ip" -c3 > /dev/null 2>&1 ; yes=$? ;
  if [ ! $yes == 0 ] ; then
    destinationstatus="off"
  else
    destinationstatus="on"
  fi
}

shallicontinue () {
  pingdestination
  if [ "$destinationstatus" == "on"  ] ; then
    echo "Backup server already running. Sync must be manually run from backup server ... exiting"
    exit
  fi
  echo "Backup server is off"
  echo "Creating flag to tell backupserver that job has been requested"
  touch /mnt/user/appdata/backups/start
}

wakeonlan () {
  etherwake -b "$destination_mac"
}

destinationstatus () {
  checkbackup=1
  while [ "$destinationstatus" == "off" ] ; do
    pingdestination
    echo "...Checking backup server attempt...""$checkbackup"
    echo "Backup server not started yet. Waiting 30 seconds to retry ..."
    ((checkbackup=checkbackup+1))
    sleep 30
  done
  echo "Server is on, taking" "$((checkbackup * 30))" "seconds to boot. Backup process should start from the backup server ... exiting"
}

mainfunction () {
  shallicontinue
  wakeonlan
  destinationstatus
}

# start process ################################################################

mkdir -p "$loglocation" && touch "$logname"
mainfunction 2>&1 | tee -a "$logname"
exit
