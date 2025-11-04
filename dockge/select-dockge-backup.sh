#!/bin/bash
# ============================================
# Dockge Backup Selector (for non-interactive dockge-backup.sh)
# ============================================
set -e
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Ensure dependencies ---# Check for docker
if ! command -v docker >/dev/null 2>&1; then
  echo -e "${YELLOW}⚙️ Installing missing dependency: docker...${RESET}"
  sudo apt update -y
  sudo apt install -y docker 
fi

# --- Prompt for stacks directory ---
STACKS_DIR=$(whiptail --inputbox "Enter the Dockge stacks directory:" 10 70 "/opt/stacks" 3>&1 1>&2 2>&3)
if [ -z "$STACKS_DIR" ]; then
  echo -e "${RED}❌ No stacks directory entered. Exiting.${RESET}"
  exit 1
fi

# --- Prompt for backup parent directory ---
BACKUP_PARENT_DIR=$(whiptail --inputbox "Enter the backup directory where the backup folder will be made:" 10 70 "/mnt/st" 3>&1 1>&2 2>&3)
if [ -z "$BACKUP_PARENT_DIR" ]; then
  echo -e "${RED}❌ No backup parent directory entered. Exiting.${RESET}"
  exit 1
fi

# --- Prompt for containers variable name ---
CONTAINERS_VAR_NAME=$(whiptail --inputbox "Enter the .env files containers variable name (default: CONTAINERS_ROOT):" 10 70 "CONTAINERS_ROOT" 3>&1 1>&2 2>&3)
if [ -z "$CONTAINERS_VAR_NAME" ]; then
  CONTAINERS_VAR_NAME="CONTAINERS_ROOT"
fi

# Call the backup script with the selected arguments
"$SCRIPT_DIR/dockge-backup.sh" "$STACKS_DIR" "$BACKUP_PARENT_DIR" "$CONTAINERS_VAR_NAME"
