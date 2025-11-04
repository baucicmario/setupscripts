#!/bin/bash
set -e

echo "launching startup script...yohohoho"

sudo apt-get install whiptail -y

# Show whiptail menu for backup or restore
CHOICE=$(whiptail --title "Backup or Restore" --menu "Choose an action:" 15 60 2 \
    "backup" "Run combined-backup-selector.sh" \
    "restore" "Run combined-restore-selector.sh" \
    3>&1 1>&2 2>&3)

exitstatus=$?
if [ $exitstatus = 0 ]; then
    if [ "$CHOICE" = "backup" ]; then
        bash ./combined-backup-selector.sh
    elif [ "$CHOICE" = "restore" ]; then
        bash ./combined-restore-selector.sh
    fi
else
    echo "Cancelled."
    exit 1
fi
