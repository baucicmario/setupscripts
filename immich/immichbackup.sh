#!/bin/bash
set -e

# ============================================
# Immich Backup Script
# Sequential Gauges + Timing + No Compression
# ============================================

auto_install_dependencies() {
    local deps=(whiptail docker pv tree)
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then return; fi

    echo "⏳ Installing missing dependencies: ${missing[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y >/dev/null 2>&1 && sudo apt-get install -y "${missing[@]}" >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y "${missing[@]}" >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        sudo apk add "${missing[@]}" >/dev/null 2>&1
    else
        echo "❌ No supported package manager found."
        exit 1
    fi
}
auto_install_dependencies

# --- Accept arguments only ---
if [ $# -ge 2 ]; then
    COMPOSE_DIR="$1"
    BACKUP_BASE="$2"
else
    echo "Usage: $0 <compose_dir> <backup_base>"
    exit 1
fi

# --- Show selected locations ---
echo "📦 Using COMPOSE_DIR: $COMPOSE_DIR"
echo "📦 Using BACKUP_BASE: $BACKUP_BASE"

# --- Validate compose directory ---
if [ ! -f "$COMPOSE_DIR/.env" ]; then
    echo "❌ Missing .env in $COMPOSE_DIR"
    exit 1
fi

# --- Load .env ---
set -a
source "$COMPOSE_DIR/.env"
set +a

BACKUP_DEST="$BACKUP_BASE/system-backup-$(date +%F)/immich"

# --- Safe directory creation ---
create_dir_safe() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" 2>/dev/null || {
            echo "⚠️  Permission denied for $dir — creating with sudo..."
            sudo mkdir -p "$dir"
            sudo chown -R "$USER:$USER" "$dir"
        }
    fi
}
create_dir_safe "$BACKUP_DEST"

# --- Verify database container ---
# --- Verify database container and start if needed ---
mkdir -p "$BACKUP_DEST"

echo "🔎 Checking for 'immich_postgres' container..."
DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^immich_postgres$' || true)

if [ -z "$DB_CONTAINER" ]; then
    echo "⚠️  Container 'immich_postgres' is not running. Attempting to start the stack..."
    
    # Determine which compose command to use
    COMPOSE_CMD=""
    if command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        echo "❌ Cannot find 'docker-compose' (v1) or 'docker compose' (v2) command."
        echo "   Please ensure Docker Compose is installed and available in your PATH."
        exit 1
    fi

    echo "🚀 Running '$COMPOSE_CMD up -d' in $COMPOSE_DIR..."
    
    # Run the compose command from the correct directory
    # Redirect output to /dev/null to avoid cluttering script output
    (cd "$COMPOSE_DIR" && $COMPOSE_CMD up -d) >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo "❌ 'docker compose up' command failed. Check for errors in $COMPOSE_DIR."
        exit 1
    fi
    
    echo "⏳ Waiting 15 seconds for the database to initialize..."
    sleep 15
    
    # Re-check for the container
    echo "🔎 Re-checking for 'immich_postgres' container..."
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep -E '^immich_postgres$' || true)
    
    if [ -z "$DB_CONTAINER" ]; then
        echo "❌ Failed to start 'immich_postgres' container after 'up' command. Aborting backup."
        exit 1
    fi
    
    echo "✅ Container 'immich_postgres' is now running."
else
    echo "✅ 'immich_postgres' container is already running."
fi

# --- Timing + Logging ---
declare -A STEP_TIMES
START_TOTAL=$(date +%s)

# --- Helper: run command with progress gauge and timing ---
run_gauge() {
    local title="$1"
    local message="$2"
    local cmd="$3"
    local key="$4"

    local start=$(date +%s)
    whiptail --title "$title" --gauge "$message" 10 70 0 < <( eval "$cmd" )
    local end=$(date +%s)
    STEP_TIMES["$key"]=$((end - start))
}

# --- Step 1: Database backup ---
run_gauge "Immich Backup" "Backing up PostgreSQL database..." '
    docker exec -t "$DB_CONTAINER" pg_dumpall --clean --if-exists --username="$DB_USERNAME" \
        | gzip > "$BACKUP_DEST/immich_db_$(date +%F).sql.gz" &
    pid=$!
    for i in $(seq 0 100); do
        echo $i
        sleep 0.5
        if ! kill -0 $pid 2>/dev/null; then break; fi
    done
    wait $pid
    echo 100
' "Database Backup"

# --- Step 2: Creating manifests ---
run_gauge "Immich Backup" "Creating file manifests..." '
    if command -v tree >/dev/null 2>&1; then
        tree -o "$BACKUP_DEST/library_manifest_$(date +%F).txt" "$UPLOAD_LOCATION" >/dev/null 2>&1
        tree -o "$BACKUP_DEST/custom_upload_manifest_$(date +%F).txt" "$CUSTOMUPLOAD_LOCATION" >/dev/null 2>&1
    fi
' "File Manifests"

# --- Step 3: Saving config files ---
run_gauge "Immich Backup" "Copying environment and compose files..." '
    cp "$COMPOSE_DIR/.env" "$BACKUP_DEST/"
    if [ -f "$COMPOSE_DIR/docker-compose.yml" ]; then
        cp "$COMPOSE_DIR/docker-compose.yml" "$BACKUP_DEST/"
    elif [ -f "$COMPOSE_DIR/compose.yaml" ]; then
        cp "$COMPOSE_DIR/compose.yaml" "$BACKUP_DEST/"
    fi
' "Config Copy"

# --- Step 4: Archiving upload directory (no compression, fixed progress) ---
run_gauge "Immich Backup" "Archiving upload location (no compression)..." '
    ARCHIVE1="$BACKUP_DEST/UPLOAD_LOCATION_$(date +%F).tar"
    size1=$(du -sb "$UPLOAD_LOCATION" | awk "{print \$1}")
    (tar -C "$UPLOAD_LOCATION" -cf - . | pv -n -s "$size1" > "$ARCHIVE1") 2>&1 | while read -r p; do
        echo "$p"
    done
' "Upload Archive"

# --- Step 5: Archiving custom upload directory (no compression, fixed progress) ---
run_gauge "Immich Backup" "Archiving custom upload location (no compression)..." '
    ARCHIVE2="$BACKUP_DEST/CUSTOMUPLOAD_LOCATION_$(date +%F).tar"
    size2=$(du -sb "$CUSTOMUPLOAD_LOCATION" | awk "{print \$1}")
    (tar -C "$CUSTOMUPLOAD_LOCATION" -cf - . | pv -n -s "$size2" > "$ARCHIVE2") 2>&1 | while read -r p; do
        echo "$p"
    done
' "Custom Upload Archive"

# --- Step 6: Writing summary ---
run_gauge "Immich Backup" "Writing backup information..." '
    INFO_FILE="$BACKUP_DEST/backup_info.txt"
    {
        echo "===== Immich Backup Information ====="
        echo "Timestamp: $(date "+%Y-%m-%d %H:%M:%S")"
        echo "Compose Directory: $COMPOSE_DIR"
        echo "Backup Destination: $BACKUP_DEST"
        echo ""
        echo "UPLOAD_LOCATION=$UPLOAD_LOCATION"
        echo "CUSTOMUPLOAD_LOCATION=$CUSTOMUPLOAD_LOCATION"
        echo "DB_USERNAME=$DB_USERNAME"
        echo "DB_DATABASE_NAME=$DB_DATABASE_NAME"
    } > "$INFO_FILE"
' "Write Info"

# --- Compute total time ---
END_TOTAL=$(date +%s)
TOTAL_TIME=$((END_TOTAL - START_TOTAL))

# --- Build timing summary ---
SUMMARY="✅ Immich Backup Completed Successfully!\n\nBackup saved to:\n$BACKUP_DEST\n\n--- Step Timings ---\n"
for key in "${!STEP_TIMES[@]}"; do
    mins=$((STEP_TIMES[$key] / 60))
    secs=$((STEP_TIMES[$key] % 60))
    SUMMARY+="• $key: ${mins}m ${secs}s\n"
done
SUMMARY+="------------------------\nTotal: $((TOTAL_TIME / 60))m $((TOTAL_TIME % 60))s\n"

# --- Final message ---
echo -e "$SUMMARY"
