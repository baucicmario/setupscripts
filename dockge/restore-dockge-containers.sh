#!/bin/bash
# dockge-backup.sh - Clean version with live progress bar (no log file)

# --- Accept arguments only ---
if [ $# -ne 3 ]; then
    echo "Usage: $0 <STACKS_DIR> <BACKUP_LOCATION> <CONTAINERS_VAR_NAME>"
    exit 1
fi
STACKS_DIR="$1"
BACKUP_LOCATION="$2"
CONTAINERS_VAR_NAME="$3"

echo "==============================="
echo " Dockge System Restore Utility"
echo "==============================="

# --- Step 0: Find latest backup ---
echo "backup at: $BACKUP_LOCATION"

STACKS_BACKUP_SRC="$BACKUP_LOCATION/dockge/stacks"
CONTAINERS_ARCHIVE_FILE="$BACKUP_LOCATION/containers/containers.tar.gz"

if [ ! -d "$STACKS_BACKUP_SRC" ]; then
    echo "❌ Missing stacks backup directory: $STACKS_BACKUP_SRC"
    exit 1
fi

if [ ! -f "$CONTAINERS_ARCHIVE_FILE" ]; then
    echo "❌ Missing container archive: $CONTAINERS_ARCHIVE_FILE"
    exit 1
fi

# --- Step 1: Stop all running containers ---
echo "---"
echo "Stopping all running containers..."
if command -v docker >/dev/null 2>&1; then
    RUNNING=$(docker ps -q)
    if [ -n "$RUNNING" ]; then
        sudo docker stop $(docker ps -q)
    else
        echo "No Docker containers running."
    fi
fi

if command -v podman >/dev/null 2>&1; then
    RUNNING=$(podman ps -q)
    if [ -n "$RUNNING" ]; then
        sudo podman stop $(podman ps -q)
    else
        echo "No Podman containers running."
    fi
fi

echo "✅ All containers stopped."

# --- Step 2: Restore stacks ---
echo "---"
echo "Restoring Dockge stacks to $STACKS_DIR..."
sudo mkdir -p "$STACKS_DIR"
sudo rsync -av --delete "$STACKS_BACKUP_SRC/" "$STACKS_DIR/"

if [ $? -eq 0 ]; then
    echo "✅ Stacks restored successfully."
else
    echo "❌ Error restoring stacks."
    exit 1
fi

# --- Step 3: Determine container path ---
echo "---"
echo "Locating container root path..."
FIRST_ENV_FILE=$(find "$STACKS_DIR" -type f -name .env -exec grep -l "$CONTAINERS_VAR_NAME=" {} + | head -n 1)

if [ -z "$FIRST_ENV_FILE" ]; then
    echo "❌ Could not find any .env file with $CONTAINERS_VAR_NAME."
    exit 1
fi

LINE=$(grep -m 1 "$CONTAINERS_VAR_NAME=" "$FIRST_ENV_FILE")
CONTAINERS_PATH=$(echo "$LINE" | sed 's/^[^=]*=//; s/"//g; s/'"'"'//g')

if [ -z "$CONTAINERS_PATH" ]; then
    echo "❌ $CONTAINERS_VAR_NAME is empty in .env file."
    exit 1
fi

echo "Container volumes target path: $CONTAINERS_PATH"

# ... (Previous script content)

# --- Step 4: Restore containers archive (with progress bar) ---
sudo mkdir -p "$CONTAINERS_PATH"
SOURCE_PARENT=$(dirname "$CONTAINERS_PATH")

echo "---"
echo "Restoring container volumes from archive..."

# Check if pv is installed before attempting to use it
if command -v pv >/dev/null 2>&1; then
    # Use sudo to get the file size
    ARCHIVE_SIZE=$(sudo stat -c %s "$CONTAINERS_ARCHIVE_FILE")
    
    echo "Starting extraction..."
    
    # Use a single sudo block for the entire operation.
    # The 'sh -c' string will FIRST change directory, THEN run the pipe.
    sudo sh -c "cd '$SOURCE_PARENT' && cat '$CONTAINERS_ARCHIVE_FILE' | pv -s '$ARCHIVE_SIZE' -p | tar -xzf -"
    
    # Get the exit code from the 'sh -c' command
    TAR_EXIT_CODE=$?
else
    echo "⚠️ 'pv' not found. Falling back to simple tar extraction..."
    
    # Fallback: Change directory in the current shell, then run sudo tar
    # This (your original logic) is correct.
    cd "$SOURCE_PARENT" || exit 1
    sudo tar -xzvf "$CONTAINERS_ARCHIVE_FILE"
    TAR_EXIT_CODE=$?
fi

# Check the exit code after the extraction attempt
if [ $TAR_EXIT_CODE -eq 0 ]; then
    echo -e "\n✅ Container volumes restored successfully."
else
    echo -e "\n❌ Error extracting container archive (Exit Code: $TAR_EXIT_CODE)."
    exit 1
fi

# ... (Rest of the script)

# --- Step 5: Fix permissions ---
echo "---"
echo "Fixing file permissions..."
sudo chmod -R +r "$STACKS_DIR"
sudo chmod -R +r "$CONTAINERS_PATH"

# --- Step 6: Restart containers ---
echo "---"
echo "Restarting containers..."
if [ -f "$STACKS_DIR/docker-compose.yaml" ] || [ -f "$STACKS_DIR/compose.yaml" ]; then
    cd "$STACKS_DIR" && sudo docker compose up -d || echo "⚠️ Could not auto-start containers."
else
    echo "No compose file found; please start your Dockge stacks manually."
fi

echo "---"
echo "✅ Restore complete!"
echo "Stacks directory: $STACKS_DIR"
echo "Containers directory: $CONTAINERS_PATH"
echo "==============================="
exit 0
