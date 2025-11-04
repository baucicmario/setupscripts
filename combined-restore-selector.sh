#!/bin/bash
set -e

# Marker file to know if we're resuming after reboot
MARKER_FILE="$HOME/variables.conf"

# Determine the full path to this script
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

if [ ! -f "$MARKER_FILE" ]; then
    ######################
    # Phase 1: Pre-Reboot
    ######################
    echo "=== Phase 1: Running before reboot ==="

    # Run setup scripts
    sudo bash "$SCRIPT_DIR/mount/setup-mounts.sh"
    bash "$SCRIPT_DIR/smb/select-smb-shares.sh"
    bash "$SCRIPT_DIR/cockpit/select-modules.sh"
    bash "$SCRIPT_DIR/docker/docker-setup.sh"

    # -----------------------------------------------------------------
    # Prompt user inputs
    # -----------------------------------------------------------------

    # Dockge --- Prompt for backup directory ---
    BACKUP_LOCATION=$(whiptail --inputbox "Enter the backup directory:" 10 70 "/mnt/st/system-backup-$(date +%F)" 3>&1 1>&2 2>&3)
    if [ -z "$BACKUP_LOCATION" ]; then
        echo "❌ No backup parent directory entered. Exiting."
        exit 1
    fi

    # Dockge --- Prompt for containers variable name ---
    CONTAINERS_VAR_NAME=$(whiptail --inputbox "Enter the .env files containers variable name (default: CONTAINERS_ROOT):" 10 70 "CONTAINERS_ROOT" 3>&1 1>&2 2>&3)
    if [ -z "$CONTAINERS_VAR_NAME" ]; then
        CONTAINERS_VAR_NAME="CONTAINERS_ROOT"
    fi

    # IMMICH --- Prompt for restore directory ---
    RESTORE_DIR=$(whiptail --inputbox "Enter directory to restore Immich files to:" 10 70 "/mnt/st/immich_restored" 3>&1 1>&2 2>&3)
    if [ -z "$RESTORE_DIR" ]; then
        echo "❌ No restore directory entered. Exiting."
        exit 1
    fi

    CONTAINERS_DIR="$RESTORE_DIR/containers"
    STACKS_DIR="/opt/stacks"

    # -----------------------------------------------------------------
    # Save variables to marker file
    # -----------------------------------------------------------------
    {
        echo "BACKUP_LOCATION=\"$BACKUP_LOCATION\""
        echo "CONTAINERS_VAR_NAME=\"$CONTAINERS_VAR_NAME\""
        echo "STACKS_DIR=\"$STACKS_DIR\""
        echo "RESTORE_DIR=\"$RESTORE_DIR\""
        echo "CONTAINERS_DIR=\"$CONTAINERS_DIR\""
    } > "$MARKER_FILE"

    # -----------------------------------------------------------------
    # Schedule continuation after reboot
    # -----------------------------------------------------------------
    echo "Scheduling continuation after reboot..."
    sudo bash -c "echo '@reboot root \"$SCRIPT_PATH\"' > /etc/cron.d/self_resume"
    echo "Rebooting system..."
    sudo reboot

else
    ######################
    # Phase 2: Post-Reboot
    ######################
    echo "=== Phase 2: Resuming after reboot ==="

    echo "Sourcing variables from $MARKER_FILE ..."
    source "$MARKER_FILE"

    # Ensure we’re in the script directory
    cd "$SCRIPT_DIR"

    # Run post-reboot tasks
    bash "$SCRIPT_DIR/dockge/dockge-base-setup.sh"

    # Call restore scripts with stored variables
    bash "$SCRIPT_DIR/dockge/restore-dockge-containers.sh" "$STACKS_DIR" "$BACKUP_LOCATION" "$CONTAINERS_VAR_NAME"
    bash "$SCRIPT_DIR/immich/restoreimmich.sh" "$BACKUP_LOCATION" "$RESTORE_DIR" "$CONTAINERS_DIR"

    # -----------------------------------------------------------------
    # Start all containers
    # -----------------------------------------------------------------
    echo "Attempting to start all Docker containers..."
    docker ps -aq | xargs -r docker start
    echo "Container startup command executed."

    # -----------------------------------------------------------------
    # Cleanup marker and cron
    # -----------------------------------------------------------------
    echo "Cleaning up..."
    sudo rm -f "$MARKER_FILE"
    sudo rm -f /etc/cron.d/self_resume

    echo "✅ All done!"
fi
