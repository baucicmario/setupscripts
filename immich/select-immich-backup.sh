#!/bin/bash
# ============================================
# Immich Backup Selector (for non-interactive immichbackup.sh)
# ============================================
set -e
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Ensure dependencies ---
if ! command -v docker >/dev/null 2>&1; then
  echo -e "${YELLOW}⚙️ Installing missing dependency: docker...${RESET}"
  sudo apt update -y
  sudo apt install -y docker 
fi

# --- Prompt for docker-compose directory ---
COMPOSE_DIR=$(whiptail --inputbox "Enter Immich docker-compose folder:" 10 70 "/mnt/st/central-immich/compose" 3>&1 1>&2 2>&3)
if [ -z "$COMPOSE_DIR" ]; then
  echo -e "${RED}❌ No compose directory entered. Exiting.${RESET}"
  exit 1
fi

# --- Prompt for backup destination ---
BACKUP_BASE=$(whiptail --inputbox "Enter backup destination folder:" 10 70 "/mnt/st" 3>&1 1>&2 2>&3)
if [ -z "$BACKUP_BASE" ]; then
  echo -e "${RED}❌ No backup destination entered. Exiting.${RESET}"
  exit 1
fi

# Call the backup script with the selected arguments
"$SCRIPT_DIR/immichbackup.sh" "$COMPOSE_DIR" "$BACKUP_BASE"
