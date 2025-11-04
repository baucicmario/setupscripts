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
    # autorun.conf creation for immichbackup.sh by asking for inputs BACKUP_ROOT="/mnt/st/system-backup-2025-11-01" RESTORE_DIR="/mnt/st/immich_restored" CONTAINERS_DIR="/mnt/st/immich_restored/containers"
    echo "Creating autorun.conf for immichrestore.sh..."
    BACKUP_ROOT=$(whiptail --inputbox "Enter the root folder containing Immich backups:" 10 70 "/mnt/st/system-backup-$(date +%F)" 3>&1 1>&2 2>&3) || {
        whiptail --msgbox "❌ Setup canceled." 8 50
        exit 1
    }
    RESTORE_DIR=$(whiptail --inputbox "Enter directory to restore Immich files to:" 10 70 "/mnt/st/immich_restored" 3>&1 1>&2 2>&3) || {
        whiptail --msgbox "❌ Setup canceled." 8 50
        exit 1
    }
    CONTAINERS_DIR=$(whiptail --inputbox "Enter directory to hold Docker containers during restore:" 10 70 "/mnt/st/immich_restored/containers" 3>&1 1>&2 2>&3) || {
        whiptail --msgbox "❌ Setup canceled." 8 50
        exit 1
    }
    #saving to autorun.conf
    {
        echo "BACKUP_ROOT=\"$BACKUP_ROOT\""
        echo "RESTORE_DIR=\"$RESTORE_DIR\""
        echo "CONTAINERS_DIR=\"$CONTAINERS_DIR\""
    } > ./immich/autorun.conf

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



    # Your post-reboot commands here
    bash ./dockge/dockge-setup.sh
    bash ./immich/restoreimmich.sh
    bash ./dockge/restore-containers.sh

    #----------------------------------------------------------------------------------------------------------------------------------------------
    # Cleanup: remove marker and cron job
    echo "Cleaning up..."
    sudo rm -f "$MARKER_FILE"
    sudo rm -f /etc/cron.d/self_resume

    echo "All done!"
fi
