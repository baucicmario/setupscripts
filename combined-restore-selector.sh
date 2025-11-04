#!/bin/bash
set -e

# Marker file to know if we're resuming after reboot
MARKER_FILE="/tmp/self_resume_marker"

# Determine the full path to this script
SCRIPT_PATH="$(realpath "$0")"

if [ ! -f "$MARKER_FILE" ]; then
    ######################
    # Phase 1: Pre-Reboot
    ######################
    echo "=== Phase 1: Running before reboot ==="

    # Your pre-reboot commands here
    bash ./cockpit/select-modules.sh
    bash ./docker/docker-setup.sh
    bash ./smb/smb-setup.sh

# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#Dockge --- Prompt for backup directory ---
BACKUP_LOCATION=$(whiptail --inputbox "Enter the backup directory:" 10 70 "/mnt/st/system-backup-$(date +%F)" 3>&1 1>&2 2>&3)
if [ -z "$BACKUP_LOCATION" ]; then
  echo -e "${RED}❌ No backup parent directory entered. Exiting.${RESET}"
  exit 1
fi

#Dockge --- Prompt for containers variable name ---
CONTAINERS_VAR_NAME=$(whiptail --inputbox "Enter the .env files containers variable name (default: CONTAINERS_ROOT):" 10 70 "CONTAINERS_ROOT" 3>&1 1>&2 2>&3)
if [ -z "$CONTAINERS_VAR_NAME" ]; then
  CONTAINERS_VAR_NAME="CONTAINERS_ROOT"
fi

# IMMICH --- Prompt for restore directory ---
RESTORE_DIR=$(whiptail --inputbox "Enter directory to restore Immich files to:" 10 70 "/mnt/st/immich_restored" 3>&1 1>&2 2>&3)
if [ -z "$RESTORE_DIR" ]; then
  echo -e "${RED}❌ No restore directory entered. Exiting.${RESET}"
  exit 1
fi

# IMMICH--- Prompt for containers directory ---
CONTAINERS_DIR="$RESTORE_DIR/containers"

# Dockge --- Prompt for stacks directory ---
STACKS_DIR="/opt/stacks"


# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

    #saving to variables.conf
    {
        echo "BACKUP_LOCATION=\"$BACKUP_LOCATION\""
        echo "CONTAINERS_VAR_NAME=\"$CONTAINERS_VAR_NAME\""
        echo "STACKS_DIR=\"$STACKS_DIR\""
        echo "RESTORE_DIR=\"$RESTORE_DIR\""
        echo "CONTAINERS_DIR=\"$CONTAINERS_DIR\""
    } > ./variables.conf

    #----------------------------------------------------------------------------------------------------------------------------------------------
    # Create marker to indicate post-reboot continuation
    touch "$MARKER_FILE"
    # Schedule this script to run at reboot
    echo "Scheduling continuation after reboot..."
    sudo bash -c "echo '@reboot root \"$SCRIPT_PATH\"' > /etc/cron.d/self_resume"
    echo "Rebooting system..."
    sudo reboot
else
    ######################
    # Phase 2: Post-Reboot
    ######################
    echo "=== Phase 2: Resuming after reboot ==="

    echo "Sourcing variables from variables.conf..."
    source ./variables.conf


    # Your post-reboot commands here
    bash ./dockge/dockge-setup.sh
    
    
    # Call the restore script with the selected arguments
    "$SCRIPT_DIR/dockge/restore-dockge-containers.sh" "$STACKS_DIR" "$BACKUP_LOCATION" "$CONTAINERS_VAR_NAME"

    "$SCRIPT_DIR/immich/restoreimmich.sh" "$BACKUP_LOCATION" "$RESTORE_DIR" "$CONTAINERS_DIR"

    bash ./immich/restoreimmich.sh
    bash ./dockge/restore-containers.sh

    #----------------------------------------------------------------------------------------------------------------------------------------------
    # Cleanup: remove marker and cron job
    echo "Cleaning up..."
    sudo rm -f "$MARKER_FILE"
    sudo rm -f /etc/cron.d/self_resume

    echo "All done!"
fi
