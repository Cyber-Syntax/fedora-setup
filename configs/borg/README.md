# Send it bash script to root partition
- Because that script need to be start as a root. I fixed by sending below location and giving root permission via adding sudoers nopasswd for this script.

/opt/borg/home-borgbackup.sh
