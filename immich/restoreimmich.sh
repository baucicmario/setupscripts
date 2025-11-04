#!/bin/bash
set -e

# ============================================
# Immich Restore Script (Non-interactive)
# ============================================

auto_install_dependencies() {
    local deps=(pv docker)
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then return; fi

    echo "Installing missing packages: ${missing[*]}"
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

declare -A STEP_TIMES
START_TOTAL=$(date +%s)

run_gauge() {
    local title="$1"
    local message="$2"
    local cmd="$3"
    local key="$4"
    local start=$(date +%s)
    echo "$message"
    eval "$cmd"
    local end=$(date +%s)
    STEP_TIMES["$key"]=$((end - start))
}

# --- Accept arguments only ---
if [ $# -ne 3 ]; then
    echo "Usage: $0 <BACKUP_ROOT> <RESTORE_DIR> <CONTAINERS_DIR>"
    exit 1
fi
BACKUP_ROOT="$1"
RESTORE_DIR="$2"
CONTAINERS_DIR="$3"

# --- Validate backup root ---
if [ ! -d "$BACKUP_ROOT" ]; then
    echo "❌ Backup root folder not found: $BACKUP_ROOT"
    exit 1
fi

# Automatically detect Immich backup folder
BACKUP_SRC=$(find "$BACKUP_ROOT" -type d -name "immich" | sort | tail -n 1)
if [ -z "$BACKUP_SRC" ]; then
    echo "❌ No 'immich' backup directory found under $BACKUP_ROOT"
    exit 1
fi

# --- Safe create directories with permission handling ---
create_dir_safe() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" 2>/dev/null || {
            echo "⚠️  Permission denied for $dir — creating with sudo..."
            sudo mkdir -p "$dir"
            sudo chown -R "$USER":"$USER" "$dir"
        }
    fi
}

create_dir_safe "$RESTORE_DIR"
create_dir_safe "$RESTORE_DIR/backups"
create_dir_safe "$RESTORE_DIR/UploadLocation"
create_dir_safe "$RESTORE_DIR/CustomUploadLocation"
create_dir_safe "$RESTORE_DIR/compose"
create_dir_safe "$CONTAINERS_DIR"

# --- Step 4: Restore compose and env files ---
run_gauge "Immich Restore" "Restoring compose and .env files..." '
    cp "$BACKUP_SRC/.env" "$RESTORE_DIR/compose/.env" 2>/dev/null || true
    if [ -f "$BACKUP_SRC/docker-compose.yml" ]; then
        cp "$BACKUP_SRC/docker-compose.yml" "$RESTORE_DIR/compose/"
    elif [ -f "$BACKUP_SRC/compose.yaml" ]; then
        cp "$BACKUP_SRC/compose.yaml" "$RESTORE_DIR/compose/"
    fi
' "Restore Compose Files"

# --- Step 5: Update .env paths ---
run_gauge "Immich Restore" "Updating environment paths..." '
    ENV_FILE="$RESTORE_DIR/compose/.env"
    if [ -f "$ENV_FILE" ]; then
        sed -i "s|^CONTAINERS_ROOT=.*|CONTAINERS_ROOT=$CONTAINERS_DIR|" "$ENV_FILE"
        sed -i "s|^UPLOAD_LOCATION=.*|UPLOAD_LOCATION=$RESTORE_DIR/UploadLocation|" "$ENV_FILE"
        sed -i "s|^CUSTOMUPLOAD_LOCATION=.*|CUSTOMUPLOAD_LOCATION=$RESTORE_DIR/CustomUploadLocation|" "$ENV_FILE"
    fi
' "Update Env File"

# --- Step 6: Restore DB + manifests ---
run_gauge "Immich Restore" "Copying database dumps and manifests..." '
    cp "$BACKUP_SRC"/immich_db_*.sql.gz "$RESTORE_DIR/backups/" 2>/dev/null || true
    cp "$BACKUP_SRC"/*manifest_*.txt "$RESTORE_DIR/backups/" 2>/dev/null || true
' "Copy Backups"

# --- Load environment variables ---
COMPOSE_DIR="$RESTORE_DIR/compose"
BACKUP_DIR="$RESTORE_DIR/backups"
UPLOAD_LOCATION="$RESTORE_DIR/UploadLocation"
CUSTOMUPLOAD_LOCATION="$RESTORE_DIR/CustomUploadLocation"

# --- Step 7: Extract upload archives ---
echo "==============================="
echo "📦 Step 7: Extracting upload archives..."
echo "==============================="

UPLOAD_TAR=$(find "$BACKUP_SRC" -maxdepth 1 -type f -name "UPLOAD_LOCATION_*.tar" | sort | tail -n 1)
CUSTOMUPLOAD_TAR=$(find "$BACKUP_SRC" -maxdepth 1 -type f -name "CUSTOMUPLOAD_LOCATION_*.tar" | sort | tail -n 1)

if [ -z "$UPLOAD_TAR" ] && [ -z "$CUSTOMUPLOAD_TAR" ]; then
    echo "⚠️  No upload archive files found in: $BACKUP_SRC"
else
    if [ -n "$UPLOAD_TAR" ]; then
        echo "📁 Extracting upload archive: $UPLOAD_TAR"
        mkdir -p "$UPLOAD_LOCATION"
        if command -v pv >/dev/null 2>&1; then
            UPLOAD_SIZE=$(stat -c%s "$UPLOAD_TAR" 2>/dev/null || stat -f%z "$UPLOAD_TAR")
            echo "   → $(numfmt --to=iec --suffix=B $UPLOAD_SIZE)"
            pv -p -t -e -r -s "$UPLOAD_SIZE" "$UPLOAD_TAR" | tar -xf - -C "$UPLOAD_LOCATION"
        else
            echo "   (No pv found — extracting without progress bar)"
            tar -xf "$UPLOAD_TAR" -C "$UPLOAD_LOCATION"
        fi
    else
        echo "⚠️  No UPLOAD_LOCATION_*.tar file found."
    fi

    if [ -n "$CUSTOMUPLOAD_TAR" ]; then
        echo "📁 Extracting custom upload archive: $CUSTOMUPLOAD_TAR"
        mkdir -p "$CUSTOMUPLOAD_LOCATION"
        if command -v pv >/dev/null 2>&1; then
            CUSTOMUPLOAD_SIZE=$(stat -c%s "$CUSTOMUPLOAD_TAR" 2>/dev/null || stat -f%z "$CUSTOMUPLOAD_TAR")
            echo "   → $(numfmt --to=iec --suffix=B $CUSTOMUPLOAD_SIZE)"
            pv -p -t -e -r -s "$CUSTOMUPLOAD_SIZE" "$CUSTOMUPLOAD_TAR" | tar -xf - -C "$CUSTOMUPLOAD_LOCATION"
        else
            echo "   (No pv found — extracting without progress bar)"
            tar -xf "$CUSTOMUPLOAD_TAR" -C "$CUSTOMUPLOAD_LOCATION"
        fi
    else
        echo "⚠️  No CUSTOMUPLOAD_LOCATION_*.tar file found."
    fi
fi

echo "✅ Extraction complete."
echo "==============================="

set -a
source "$COMPOSE_DIR/.env"
set +a

BACKUP_FILE=$(ls -t "$BACKUP_DIR"/immich_db_*.sql.gz 2>/dev/null | head -n1)
if [ -z "$BACKUP_FILE" ]; then
    echo "❌ Database backup not found."
    exit 1
fi

# --- Step 9: Manifest and sanity checks ---
echo "Performing pre-flight checks..."
sleep 1

if [ -z "$(ls -A "$UPLOAD_LOCATION" 2>/dev/null)" ] || [ -z "$(ls -A "$CUSTOMUPLOAD_LOCATION" 2>/dev/null)" ]; then
    echo "❌ Upload directories appear empty or missing.\n\nPlease verify your backup contents."
    exit 1
fi

LATEST_LIB_MANIFEST=$(ls -t "$BACKUP_DIR"/library_manifest_*.txt 2>/dev/null | head -n1)
LATEST_CUSTOM_MANIFEST=$(ls -t "$BACKUP_DIR"/custom_upload_manifest_*.txt 2>/dev/null | head -n1)

# --- Step 10: Run Docker restore sequence (terminal mode) ---
echo "==============================="
echo "🔧 Step 10: Restoring Docker containers and database..."
echo "==============================="

cd "$COMPOSE_DIR" || {
    echo "❌ ERROR: Could not enter compose directory: $COMPOSE_DIR"
    exit 1
}

echo "🧹 Stopping and removing old containers..."
docker compose down -v

echo "📦 Pulling latest container images..."
docker compose pull

echo "⚙️  Creating new containers (without starting all)..."
docker compose create

echo "🐘 Starting PostgreSQL container..."
docker start immich_postgres

echo "⏳ Waiting 25 seconds for PostgreSQL to initialize..."
sleep 25

echo "💾 Restoring database from backup: $BACKUP_FILE"
if [ -z "$DB_USERNAME" ]; then
    echo "⚠️  DB_USERNAME is not set. Trying default: 'postgres'"
    DB_USERNAME="postgres"
fi

gunzip --stdout "$BACKUP_FILE" | \
  sed "s/SELECT pg_catalog.set_config('search_path', ''.*);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" | \
  docker exec -i immich_postgres psql --dbname=postgres --username="$DB_USERNAME"

echo "🚀 Starting all Immich containers..."
docker compose up -d

echo "✅ Immich restore process completed."
echo "==============================="
