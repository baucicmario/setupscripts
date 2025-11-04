#!/bin/bash
# ============================================
# Dockge Restore Selector (for non-interactive restore-dockge-containers.sh)
# ============================================
set -e
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Ensure dependencies ---
MISSING=()
for dep in whiptail rsync pv tar docker; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    MISSING+=("$dep")
  fi
done
if [ ${#MISSING[@]} -ne 0 ]; then
  echo -e "${YELLOW}⚙️ Installing missing dependencies: ${MISSING[*]}...${RESET}"
  sudo apt update -y
  for dep in "${MISSING[@]}"; do
    sudo apt install -y "$dep"
  done
fi

# --- Prompt for stacks directory ---
STACKS_DIR=$(whiptail --inputbox "Enter the Dockge stacks directory:" 10 70 "/opt/stacks" 3>&1 1>&2 2>&3)
if [ -z "$STACKS_DIR" ]; then
  echo -e "${RED}❌ No stacks directory entered. Exiting.${RESET}"
  exit 1
fi

# --- Prompt for backup parent directory ---
BACKUP_PARENT_DIR=$(whiptail --inputbox "Enter the backup parent directory:" 10 70 "/mnt/st" 3>&1 1>&2 2>&3)
if [ -z "$BACKUP_PARENT_DIR" ]; then
  echo -e "${RED}❌ No backup parent directory entered. Exiting.${RESET}"
  exit 1
fi

# --- Prompt for containers variable name ---
CONTAINERS_VAR_NAME=$(whiptail --inputbox "Enter the .env files containers variable name (default: CONTAINERS_ROOT):" 10 70 "CONTAINERS_ROOT" 3>&1 1>&2 2>&3)
if [ -z "$CONTAINERS_VAR_NAME" ]; then
  CONTAINERS_VAR_NAME="CONTAINERS_ROOT"
fi

# Call the restore script with the selected arguments
"$SCRIPT_DIR/restore-dockge-containers.sh" "$STACKS_DIR" "$BACKUP_PARENT_DIR" "$CONTAINERS_VAR_NAME"
