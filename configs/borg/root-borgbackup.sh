#!/bin/bash -e
# Extract command
#sudo borg extract --progress --list /mnt/backups/borgbackup/root-repo::root-27-02-2024

export BORG_UKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes

REPOSITORY_root='/mnt/backups/borgbackup/root-repo'

sudo borg create --list --filter=AME --progress --stats --exclude-caches --show-rc --one-file-system \
  --exclude /run/ \
  --exclude /proc/ \
  --exclude /sys/ \
  --exclude /tmp/ \
  --exclude /dev/ \
  --exclude /mnt/ \
  --exclude /media/ \
  --exclude /lost+found/ \
  --exclude /home/ \
 --compression zstd,15 $REPOSITORY_root::root-{now:%d-%m-%Y} \
  / /boot

echo "Backup of root directory complete"

echo "Pruning old root backups"

sudo borg prune -v $REPOSITORY_root --list --stats --show-rc \
    --keep-daily=7 \
    --keep-weekly=4 \
    --keep-monthly=2 

sudo borg check $REPOSITORY_root

echo "Check complete"

sudo borg compact $REPOSITORY_root

echo "Compaction complete"
# make sure to sync
sync

# if return = 'rc 0' then it's successful
if [ $? -eq 0 ]; then
  echo "Backup and prune complete!"
else
  echo "Backup and prune failed!"
fi

