#!/bin/bash
set -e
SCRIPT_PATH="$(realpath "$0")"
MARKER_FILE="$HOME/variables.conf"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Color definitions
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

bash "$SCRIPT_DIR/dependencies.sh"


if groups $USER | grep -q '\bdocker\b'; then

    source "$MARKER_FILE"
    cd "$SCRIPT_DIR"
    bash "$SCRIPT_DIR/dockge/dockge-base-setup.sh"
    bash "$SCRIPT_DIR/dockge/restore-dockge-containers.sh" "$STACKS_DIR" "$BACKUP_LOCATION" "$CONTAINERS_VAR_NAME"
    bash "$SCRIPT_DIR/immich/restoreimmich.sh" "$BACKUP_LOCATION" "$RESTORE_DIR" "$CONTAINERS_DIR"
    docker ps -aq | xargs -r docker start
    sudo rm -f "$MARKER_FILE"

else

    sudo bash "$SCRIPT_DIR/mount/setup-mounts.sh"
    bash "$SCRIPT_DIR/smb/select-smb-shares.sh"
    bash "$SCRIPT_DIR/cockpit/select-modules.sh" #
    bash "$SCRIPT_DIR/docker/docker-setup.sh" #

    BACKUP_LOCATION=$(whiptail --inputbox "Enter the backup directory:" 10 70 "/mnt/st/system-backup-$(date +%F)" 3>&1 1>&2 2>&3)
        if [ -z "$BACKUP_LOCATION" ]; then
            echo "❌ No backup parent directory entered. Exiting."
            exit 1
        fi
    
    if whiptail --title "Custom Restore Variables" --yesno "Do you want to set custom restore variables? (Selecting 'No' will use default locations)" 8 60; then

        CONTAINERS_VAR_NAME=$(whiptail --inputbox "Enter the .env files containers variable name (default: CONTAINERS_ROOT):" 10 70 "CONTAINERS_ROOT" 3>&1 1>&2 2>&3)
        if [ -z "$CONTAINERS_VAR_NAME" ]; then
            CONTAINERS_VAR_NAME="CONTAINERS_ROOT"
        fi
        RESTORE_DIR=$(whiptail --inputbox "Enter directory to restore Immich files to:" 10 70 "/mnt/st/immich_restored" 3>&1 1>&2 2>&3)
        if [ -z "$RESTORE_DIR" ]; then
            echo "❌ No restore directory entered. Exiting."
            exit 1
        fi
    else
        if [ -f "$BACKUP_LOCATION/default_values.conf" ]; then
            source "$BACKUP_LOCATION/default_values.conf"
        else
            echo "❌ Default values file not found. Exiting."
            exit 1
        fi
    fi

    CONTAINERS_DIR="$RESTORE_DIR/containers"
    STACKS_DIR="/opt/stacks"

    {
        echo "BACKUP_LOCATION=\"$BACKUP_LOCATION\""
        echo "CONTAINERS_VAR_NAME=\"$CONTAINERS_VAR_NAME\""
        echo "STACKS_DIR=\"$STACKS_DIR\""
        echo "RESTORE_DIR=\"$RESTORE_DIR\""
        echo "CONTAINERS_DIR=\"$CONTAINERS_DIR\""
    } > "$MARKER_FILE"

    exec sg docker -c "$SCRIPT_PATH"
fi