#!/bin/bash
set -e

# =========================================
# Two-phase reboot script with systemd resume
# =========================================

# Define key paths
SCRIPT_PATH="$(realpath "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
MARKER_FILE="$SCRIPT_DIR/variables.conf"
SERVICE_FILE="/etc/systemd/system/self_resume.service"

# Ensure proper PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cd "$SCRIPT_DIR"

# -------------------------------------------------------
if [ ! -f "$MARKER_FILE" ]; then
    ##############################
    # Phase 1: Before Reboot
    ##############################
    echo "=== Phase 1: Running before reboot ==="

    # -------------------------------------------------------------------
    # User input
    BACKUP_LOCATION=$(whiptail --inputbox "Enter the backup directory:" 10 70 "/mnt/st/system-backup-$(date +%F)" 3>&1 1>&2 2>&3)
    if [ -z "$BACKUP_LOCATION" ]; then
        echo "❌ No backup directory entered. Exiting."
        exit 1
    fi

    CONTAINERS_VAR_NAME=$(whiptail --inputbox "Enter the .env files containers variable name (default: CONTAINERS_ROOT):" 10 70 "CONTAINERS_ROOT" 3>&1 1>&2 2>&3)
    if [ -z "$CONTAINERS_VAR_NAME" ]; then
        CONTAINERS_VAR_NAME="CONTAINERS_ROOT"
    fi

    RESTORE_DIR=$(whiptail --inputbox "Enter directory to restore Immich files to:" 10 70 "/mnt/st/immich_restored" 3>&1 1>&2 2>&3)
    if [ -z "$RESTORE_DIR" ]; then
        echo "❌ No restore directory entered. Exiting."
        exit 1
    fi

    CONTAINERS_DIR="$RESTORE_DIR/containers"
    STACKS_DIR="/opt/stacks"


    # Pre-reboot setup scripts
    bash "$SCRIPT_DIR/cockpit/select-modules.sh"
    bash "$SCRIPT_DIR/docker/docker-setup.sh"
    bash "$SCRIPT_DIR/smb/select-smb-shares.sh"

    # Save variables for phase 2
    {
        echo "BACKUP_LOCATION=\"$BACKUP_LOCATION\""
        echo "CONTAINERS_VAR_NAME=\"$CONTAINERS_VAR_NAME\""
        echo "STACKS_DIR=\"$STACKS_DIR\""
        echo "RESTORE_DIR=\"$RESTORE_DIR\""
        echo "CONTAINERS_DIR=\"$CONTAINERS_DIR\""
    } > "$MARKER_FILE"

    # Create systemd service for resuming after reboot
    echo "Creating systemd resume service..."
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Resume script after reboot
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_PATH
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable self_resume.service

    echo "Rebooting system..."
    sudo reboot

# -------------------------------------------------------
else
    ##############################
    # Phase 2: After Reboot
    ##############################
    echo "=== Phase 2: Resuming after reboot ==="
    echo "Sourcing variables from variables.conf..."
    source "$MARKER_FILE"

    # Post-reboot setup
    bash "$SCRIPT_DIR/dockge/dockge-base-setup.sh"

    # Run restore steps
    bash "$SCRIPT_DIR/dockge/restore-dockge-containers.sh" "$STACKS_DIR" "$BACKUP_LOCATION" "$CONTAINERS_VAR_NAME"
    bash "$SCRIPT_DIR/immich/restoreimmich.sh" "$BACKUP_LOCATION" "$RESTORE_DIR" "$CONTAINERS_DIR"

    # -------------------------------------------------------------------
    # Cleanup
    echo "Cleaning up..."
    sudo rm -f "$MARKER_FILE"
    sudo systemctl disable self_resume.service --now || true
    sudo rm -f "$SERVICE_FILE"
    sudo systemctl daemon-reload

    echo "✅ All done!"
fi
