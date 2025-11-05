#!/bin/bash
# ============================================
# Backup Config Selector (No Confirmation)
# ============================================

set -e

# --- Colors ---
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"

# --- Ensure dialog exists ---
if ! command -v dialog &>/dev/null; then
  echo -e "${YELLOW}Installing 'dialog'...${RESET}"
  sudo apt-get update -y
  sudo apt-get install -y dialog
fi

# --- Quietly install minimal dependencies ---
sudo apt-get install -y pv tree rsync tar >/dev/null 2>&1 || true

# --- Folder browser (directories only) ---
browse_folder() {
    local start_dir="$1"
    local title="$2"
    local backtitle="$3"
    local current_dir="$start_dir"
    local choice

    while true; do
        local items=()
        for entry in "$current_dir"/*; do
            [ -d "$entry" ] || continue
            name=$(basename "$entry")
            items+=("$entry" "📁 $name")
        done
        items+=(".." "⬆️ Go up")
        items+=("SELECT_THIS" "✅ Use this folder")

        choice=$(dialog --clear \
            --title "$title" \
            --backtitle "$backtitle" \
            --menu "Current: $current_dir" 20 70 15 \
            "${items[@]}" \
            2>&1 >/dev/tty)

        clear
        [ $? -ne 0 ] && echo "" && return

        case "$choice" in
            "..")
                current_dir=$(dirname "$current_dir")
                ;;
            "SELECT_THIS")
                realpath "$current_dir"
                return
                ;;
            *)
                current_dir="$choice"
                ;;
        esac
    done
}

# --- Function to sanitize escape characters ---
clean_path() {
    echo -n "$1" | sed 's/\x1B\[[0-9;]*[A-Za-z]//g' | tr -d '\r'
}

# --- Begin selections ---
clear
echo -e "${BLUE}Starting interactive folder selection...${RESET}"

COMPOSE_DIR=$(browse_folder "$PWD" "Select Immich docker-compose Folder" "Example: /mnt/st/central-immich/compose")
COMPOSE_DIR=$(clean_path "$COMPOSE_DIR")
[ -z "$COMPOSE_DIR" ] && { echo -e "${RED}No compose dir selected.${RESET}"; exit 1; }

STACKS_DIR=$(browse_folder "$PWD" "Select Dockge Stacks Folder" "Example: /opt/stacks")
STACKS_DIR=$(clean_path "$STACKS_DIR")
[ -z "$STACKS_DIR" ] && { echo -e "${RED}No stacks dir selected.${RESET}"; exit 1; }

BACKUP_LOCATION=$(browse_folder "$PWD" "Select Main Backup Destination Folder" "Where backups will be stored")
BACKUP_LOCATION=$(clean_path "$BACKUP_LOCATION")
[ -z "$BACKUP_LOCATION" ] && { echo -e "${RED}No backup destination selected.${RESET}"; exit 1; }

CONTAINERS_VAR_NAME=$(dialog --inputbox "Enter Dockge .env variable name for containers root:" 10 60 "CONTAINERS_ROOT" 2>&1 >/dev/tty)
clear
[ -z "$CONTAINERS_VAR_NAME" ] && CONTAINERS_VAR_NAME="CONTAINERS_ROOT"

# --- Auto detect container path ---
FIRST_ENV_FILE=$(find "$STACKS_DIR" -type f -name ".env" -exec grep -l "$CONTAINERS_VAR_NAME=" {} + | head -n 1 2>/dev/null || true)

if [ -z "$FIRST_ENV_FILE" ]; then
    echo -e "${RED}❌ No .env file found with $CONTAINERS_VAR_NAME inside $STACKS_DIR${RESET}"
    echo -e "${YELLOW}Tip:${RESET} Make sure your .env file actually defines that variable."
    exit 1
fi

LINE=$(grep -m 1 "$CONTAINERS_VAR_NAME=" "$FIRST_ENV_FILE")
CONTAINERS_PATH=$(echo "$LINE" | sed 's/^[^=]*=//; s/"//g; s/'"'"'//g')

if [ ! -d "$CONTAINERS_PATH" ]; then
    echo -e "${RED}❌ Container path not found:${RESET} $CONTAINERS_PATH"
    exit 1
fi

# --- Save configuration directly ---
CONFIG_FILE="backup_config.env"

cat > "$CONFIG_FILE" <<EOF
# ============================================
# Backup Configuration (Generated $(date))
# ============================================

COMPOSE_DIR="$COMPOSE_DIR"
STACKS_DIR="$STACKS_DIR"
CONTAINERS_VAR_NAME="$CONTAINERS_VAR_NAME"
CONTAINERS_PATH="$CONTAINERS_PATH"
BACKUP_LOCATION="$BACKUP_LOCATION"
EOF

# --- Display summary ---
clear
echo -e "${GREEN}✅ Configuration saved successfully.${RESET}"
echo -e "File: ${YELLOW}$CONFIG_FILE${RESET}\n"
echo -e "You can import it later with:"
echo -e "  source $CONFIG_FILE\n"
echo -e "${GREEN}Saved values:${RESET}"
echo "COMPOSE_DIR=$COMPOSE_DIR"
echo "STACKS_DIR=$STACKS_DIR"
echo "CONTAINERS_VAR_NAME=$CONTAINERS_VAR_NAME"
echo "CONTAINERS_PATH=$CONTAINERS_PATH"
echo "BACKUP_LOCATION=$BACKUP_LOCATION"
