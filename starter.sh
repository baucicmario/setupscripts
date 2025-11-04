#!/bin/bash
set -e

echo "launching startup script...yohohoho"


# --- Ensure dependencies ---
DEPS=(whiptail docker pv tree rsync tar)
MISSING=()
for dep in "${DEPS[@]}"; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    MISSING+=("$dep")
  fi
done

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
