#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Check prerequisites
command -v borg >/dev/null 2>&1 || {
  echo >&2 "Borg is not installed. Please install it first."
  exit 1
}
[[ -d /mnt/backups/borgbackup ]] || {
  echo >&2 "Backup directory does not exist."
  exit 1
}

export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes

borg_home_repo='/mnt/backups/borgbackup/home-repo'

echo "Starting backup for home"

# --show-rc: if return 0 code, then it's successful
if ! sudo borg create --list --filter=AME --progress --stats --exclude-caches --show-rc \
  --exclude /home/*/Documents/backup-for-cloud/ \
  --exclude /home/*/.cache/ \
  --exclude /home/*Downloads/ \
  --exclude /**.snapshots/ \
  --exclude /home/*/Trash/ \
  --exclude /home/*thumbnails/ \
  --exclude /home/*mozilla/firefox/*.default-release/storage/default/* \
  --exclude /home/*/venv/ \
  --exclude /home/*/.npm/_cacache/ \
  --exclude /home/*/node_modules/ \
  --exclude /home/*/bower_components/ \
  --exclude /home/*/.config/Code/CachedData/ \
  --exclude /home/*/.tox/ \
  --exclude /home/*/.venv/ \
  --exclude /home/*/.backups/ \
  --compression zstd,15 $borg_home_repo::'{now:home-developer-%d-%m-%Y}' \
  /home/developer/; then
  echo "Backup of home directory failed" >&2
  exit 1
fi

echo "Backup of home directory complete"

if ! sudo borg prune -v $borg_home_repo --list --stats --show-rc \
  --keep-daily=7 \
  --keep-weekly=4 \
  --keep-monthly=2; then
  echo "Pruning of home backups failed" >&2
  exit 1
fi

echo "Pruning of home backups complete"

if ! sudo borg check $borg_home_repo; then
  echo "Check of home backups failed" >&2
  exit 1
fi
echo "borg check completed successfully"

if ! sudo borg compact $borg_home_repo; then
  echo "Compaction of home backups failed" >&2
  exit 1
fi

echo "Compaction complete"

# Being paronoid here
sync

echo "Borg backup completed successfully"
