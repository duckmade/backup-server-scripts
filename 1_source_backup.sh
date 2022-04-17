#!/bin/bash
umask 0000

source_ip=""              # ip address of the source
source_mac=""             # macaddress of source
destination_ip=""         # ip address of the destination
destination_mac=""        # macaddress of destination

poweroff="source"         # should shutdown server after sync: "none" "both" "source" "backup"?
sync_primary="yes"        # should primary data be synced?
sync_secondary="yes"      # should secondary data be synced?

failover="yes"            # should the destination server take over running of docker stacks?
sync_primary_back="no"    # should the primary data be synced back if failover="yes"?
sync_secondary_back="yes" # should the secondary data be synced back if failover="yes"?

# docker stacks to shutdown and restart ("stack 1" "stack 2")
declare -a stacks=("" "")

# primary directories to backup on source server ("source 1" "destination 1" "source 2" "destination 2")
declare -a primary=("" "" "" "")

# secondary directories to backup on source server ("source 1" "destination 1" "source 2" "destination 2")
declare -a secondary=("" "" "" "")

CONFI="/mnt/user/appdata/backups/config.cfg"
loglocation="/mnt/user/appdata/backups/logs/"
logname="$loglocation""$(date +'%Y-%m-%d--%H:%M')""--source_to_destination.txt"

# functions ####################################################################
 
pingdestination () {
  ping "$destination_ip" -c3 > /dev/null 2>&1 ; yes=$? ; # ping backup server 3 times to check for reply
  if [ ! $yes == 0 ] ; then
    destinationstatus="off"
  else
    destinationstatus="on"
  fi
}

shallicontinue () {
  pingdestination
  if [ "$destinationstatus" == "on"  ] ; then
    echo "Backup server already running. So Sync must be manually run from backup server"
    echo "Exiting"
    exit
  else
    echo "Backup server is off....continuing"
  fi
}

setup () {
  # set flag to shutdown backup or source server after sync
  if [ "$poweroff" == "backup"  ] ; then
    echo "Backup server has been set to turn off after sync"
    failover="no" #set failover to no as backup server will shutdown
  elif [ "$poweroff" == "source"  ] ; then
    echo "Source server has been set to turn off after sync"
    failover="yes" #set failover to yes as source server will shutdown
  else
    echo "Neither Source nor Backup server is set to be turned off"
  fi
  if [ "$failover" == "yes"  ] ; then
    sync_secondary="yes" # sync_secondary set to yes as server duties set to switch
    poweroff="source" # make sure source server is set to shutdown
    echo "Stacks are set to start on Backup server after sync completed"
  else
    echo "No stacks on Backup server are set to start after sync had completed"
  fi
  # make flag file to tell backup server when it starts to start backup process
  touch /mnt/user/appdata/backups/start
  echo "Making flag in appdata to tell backupserver job has been requested"
}

wakeonlan () {
  etherwake -b $destination_mac
}

writeconfig () {
  echo "Writing config file" 
  echo
  echo "primary=(${primary[@]})"  | sudo tee  --append $CONFI
  echo "secondary=(${secondary[@]})"  | sudo tee  --append $CONFI
  echo "source_ip=\"$source_ip\"" | sudo tee  --append $CONFI
  echo "source_mac=\"$source_mac\"" | sudo tee  --append $CONFI
  echo "destination_ip=\"$destination_ip\"" | sudo tee  --append $CONFI
  echo "destination_mac=\"$destination_mac\"" | sudo tee  --append $CONFI
  echo "poweroff=\"$poweroff\"" | sudo tee  --append $CONFI
  echo "sync_primary=\"$sync_primary\"" | sudo tee  --append $CONFI
  echo "sync_secondary=\"$sync_secondary\"" | sudo tee  --append $CONFI
  echo "failover=\"$failover\"" | sudo tee  --append $CONFI
  echo "sync_primary_back=\"$sync_primary_back\"" | sudo tee  --append $CONFI
  echo "sync_secondary_back=\"$sync_secondary_back\"" | sudo tee  --append $CONFI
  echo "stacks=(${stacks[@]})"  | sudo tee  --append $CONFI
  echo "loglocation=\"$loglocation\"" | sudo tee  --append $CONFI
  echo "logname=\"$logname\"" | sudo tee  --append $CONFI
  echo
}

destinationstatus () {
  # check if backup server has started up yet
  checkbackup=1
  while [ "$destinationstatus" == "off" ] ; do
    pingdestination
    echo ".............................Checking backup server attempt...""$checkbackup"
    echo "Backup server not started yet"
    echo "Waiting 30 seconds to check again"
    ((checkbackup=checkbackup+1))
    sleep 30  # wait 30 seconds before rechecking
  done
  echo "Okay server is now on, taking" "$((checkbackup * 30))" "seconds to boot. Backup process should start from the backup server side"
}

mainfunction () {
  shallicontinue
  setup
  wakeonlan
  writeconfig
  destinationstatus
}

# start process ################################################################

mkdir -p "$loglocation" && touch "$logname"
mainfunction 2>&1 | tee -a "$logname"
exit
