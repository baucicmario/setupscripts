#!/bin/bash
# ============================================
# Dockge Restore Selector (for non-interactive restore-dockge-containers.sh)
# ============================================
set -e
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check for docker
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
BACKUP_LOCATION=$(whiptail --inputbox "Enter the backup parent directory:" 10 70 "/mnt/st" 3>&1 1>&2 2>&3)
if [ -z "$BACKUP_LOCATION" ]; then
  echo -e "${RED}❌ No backup parent directory entered. Exiting.${RESET}"
  exit 1
fi

# --- Prompt for containers variable name ---
BACKUP_LOCATION=$(whiptail --inputbox "Enter the backup directory:" 10 70 "/mnt/st/system-backup-$(date +%F)" 3>&1 1>&2 2>&3)
if [ -z "$BACKUP_LOCATION" ]; then
  echo -e "${RED}❌ No backup parent directory entered. Exiting.${RESET}"
  exit 1
fi

# Call the restore script with the selected arguments
"$SCRIPT_DIR/restore-dockge-containers.sh" "$STACKS_DIR" "$BACKUP_LOCATION" "$CONTAINERS_VAR_NAME"
