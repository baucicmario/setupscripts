#!/bin/bash
# dockge-backup.sh - System backup with dependency check, container stop, permission fix, and live progress bar

# --- Accept arguments only ---
if [ $# -ne 3 ]; then
    echo "Usage: $0 <STACKS_DIR> <BACKUP_PARENT_DIR> <CONTAINERS_VAR_NAME>"
    exit 1
fi
STACKS_DIR="$1"
BACKUP_PARENT_DIR="$2"
CONTAINERS_VAR_NAME="$3"

# --- Global setup ---
CURRENT_DATE=$(date +"%Y-%m-%d")
BASE_BACKUP_PATH="$BACKUP_PARENT_DIR/system-backup-$CURRENT_DATE"
STACKS_BACKUP_DEST="$BASE_BACKUP_PATH/dockge/stacks"
CONTAINERS_BACKUP_DEST_DIR="$BASE_BACKUP_PATH/containers"
CONTAINERS_ARCHIVE_FILE="$CONTAINERS_BACKUP_DEST_DIR/containers.tar.gz"
LOG_FILE="$BASE_BACKUP_PATH/backup.log"

mkdir -p "$BASE_BACKUP_PATH"

# Log setup: send stdout to both terminal and log, keep pv progress live
exec > >(tee -a "$LOG_FILE")
exec 2>&1

START_TIME=$(date +%s)

echo "==============================="
echo " Dockge System Backup Utility"
echo " Date: $CURRENT_DATE"
echo " Log: $LOG_FILE"
echo "==============================="

# ----------------------------------------
# Step 0: Dependency check and install
# ----------------------------------------
echo "Checking for required dependencies..."

PKG_MANAGER=""
if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt-get"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
fi

if [ -n "$PKG_MANAGER" ]; then
    echo "Installing missing packages (sudo $PKG_MANAGER install -y rsync pv tar)..."
    if [ "$PKG_MANAGER" = "apk" ]; then
        sudo "$PKG_MANAGER" add rsync pv tar
    else
        sudo "$PKG_MANAGER" install -y rsync pv tar
    fi
else
    echo "⚠️ No supported package manager found. Please ensure 'rsync', 'pv', and 'tar' are installed."
fi

echo "✅ Dependency check complete."
echo "---"

# ----------------------------------------
# Step 1: Stop all running containers
# ----------------------------------------
echo "Stopping all running containers..."
if command -v docker >/dev/null 2>&1; then
    RUNNING=$(docker ps -q)
    if [ -n "$RUNNING" ]; then
        echo "Stopping Docker containers..."
        sudo docker stop $(docker ps -q)
    else
        echo "No Docker containers running."
    fi
fi

if command -v podman >/dev/null 2>&1; then
    RUNNING=$(podman ps -q)
    if [ -n "$RUNNING" ]; then
        echo "Stopping Podman containers..."
        sudo podman stop $(podman ps -q)
    else
        echo "No Podman containers running."
    fi
fi

echo "✅ All containers stopped."
echo "---"

# ----------------------------------------
# Step 2: Mirror Dockge stacks
# ----------------------------------------
echo "Part 1: Mirroring Dockge stacks..."
mkdir -p "$STACKS_BACKUP_DEST"

if rsync -av --delete "$STACKS_DIR/" "$STACKS_BACKUP_DEST/"; then
    echo "✅ Part 1: Stacks mirror successful!"
else
    echo "❌ Error (Part 1): rsync failed. Check logs above."
fi

echo "---"

# ----------------------------------------
# Step 3: Archive container volumes
# ----------------------------------------
echo "Part 2: Archiving container volumes..."
FIRST_ENV_FILE=$(find "$STACKS_DIR" -type f -name .env -exec grep -l "$CONTAINERS_VAR_NAME=" {} + | head -n 1)

if [ -z "$FIRST_ENV_FILE" ]; then
    echo "❌ No .env file found with $CONTAINERS_VAR_NAME."
    exit 1
fi

LINE=$(grep -m 1 "$CONTAINERS_VAR_NAME=" "$FIRST_ENV_FILE")
CONTAINERS_PATH=$(echo "$LINE" | sed 's/^[^=]*=//; s/"//g; s/'"'"'//g')

if [ ! -d "$CONTAINERS_PATH" ]; then
    echo "❌ Container path not found: $CONTAINERS_PATH"
    exit 1
fi

echo "Source path: $CONTAINERS_PATH"
echo "Destination archive: $CONTAINERS_ARCHIVE_FILE"

mkdir -p "$CONTAINERS_BACKUP_DEST_DIR"

# Fix permissions
echo "Adjusting file permissions (sudo chmod -R +r)..."
sudo chmod -R +r "$CONTAINERS_PATH" 2>/dev/null || echo "⚠️ Some permissions could not be changed."

# Create archive with live progress
SOURCE_PARENT=$(dirname "$CONTAINERS_PATH")
SOURCE_BASENAME=$(basename "$CONTAINERS_PATH")

if command -v pv >/dev/null 2>&1; then
    SIZE=$(sudo du -sb "$CONTAINERS_PATH" | awk '{print $1}')
    echo "Creating archive with progress bar..."
    (cd "$SOURCE_PARENT" && \
        sudo tar -cf - "$SOURCE_BASENAME" | pv -s "$SIZE" 2> >(tee -a "$LOG_FILE" >&2) | gzip > "$CONTAINERS_ARCHIVE_FILE")
else
    echo "Creating archive (no progress bar - install 'pv' for visual progress)..."
    sudo tar -czvf "$CONTAINERS_ARCHIVE_FILE" -C "$SOURCE_PARENT" "$SOURCE_BASENAME"
fi

if [ $? -eq 0 ]; then
    echo "✅ Part 2: Container volumes backup successful!"
else
    echo "❌ Error (Part 2): tar command failed. See $LOG_FILE for details."
    exit 1
fi

# ----------------------------------------
# Step 4: Summary and timing
# ----------------------------------------
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ARCHIVE_SIZE=$(du -h "$CONTAINERS_ARCHIVE_FILE" | awk '{print $1}')

echo "---"
echo "✅ Master backup complete!"
echo "Backup stored at: $BASE_BACKUP_PATH"
echo "Archive size: $ARCHIVE_SIZE"
echo "Elapsed time: ${ELAPSED}s"
echo "==============================="
exit 0
