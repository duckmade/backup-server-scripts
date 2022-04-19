# backup-server-scripts

Contains backup script files for DUCKMADE's servers

The scripts on 2 Unraid servers. One being the source the other being the destination (where the backup is made). When combined together, both machines automatically backup the selected data from the source to the destination. The destination server is automatically powered on and started from the script running on the source. Once the destination server has started it will sync the user selected data from the source to itself. Upon sync completion, various actions can be made:

1. **Backup only**: The destination can automatically shut down after the sync has completed. This is useful if you want to have a backup server only running when needed for the backup job, saving both electricity and wear and tear on the destination's hard disks.

2. **Failover server**: The source can be shutdown after the sync has completed leaving only the destination running. The data (including Docker stacks) is synced from the source to the destination. Selected stacks are started on the destination, taking over the duties of the source. This is useful if you want your Docker applications to remain running, while you might perform maintainance on the source.

3. **Switch back**: The source can be automatically started at a later time. The data can be synced back from the destination to the source. The destination is then shutdown while the Docker applications are resumed on the source.

There are 3 scripts to make this process work:

1. `1_source_start_destination.sh`: (runs on source) All variables are set in this script for both source and destination and shared as file via SSH. This script can be set to run on a cron schedule, which will start the destination automatically.

2. `2_destination_backup.sh`: (runs on destination) Being set to autorun on the start of the destination. However it will only execute if the destination was started by script 1 on the source. Manual powering of the destination will not run the backup. When the script executes it will sync the data from the variables in the source. Only one variable needs setting in this script: the source ip address.

3. `3_destination_start_source.sh`: (runs on destination) This script is also run on the destination and should be set to run at the time you want the source to autostart. It will automatically start source and re-sync the data back to the source.

*Notes:*

1. *These scripts should be run using Unraid's User Scripts plugin.*

2. *For these scripts to work you must create SSH keys on the destination and import them to the source in order for the destination to be able to establish and SSH connection to the source.*