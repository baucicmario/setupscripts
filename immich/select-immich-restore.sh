#!/bin/bash
# ============================================
# Immich Restore Selector (for non-interactive restoreimmich.sh)
# ============================================
set -e
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Ensure dependencies ---
MISSING=()
for dep in whiptail pv docker; do
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

# --- Prompt for backup root folder ---
BACKUP_LOCATION=$(whiptail --inputbox "Enter the root folder containing Immich backups:" 10 70 "/mnt/st/system-backup-$(date +%F)" 3>&1 1>&2 2>&3)
if [ -z "$BACKUP_LOCATION" ]; then
  echo -e "${RED}❌ No backup root entered. Exiting.${RESET}"
  exit 1
fi

# --- Prompt for restore directory ---
RESTORE_DIR=$(whiptail --inputbox "Enter directory to restore Immich files to:" 10 70 "/mnt/st/immich_restored" 3>&1 1>&2 2>&3)
if [ -z "$RESTORE_DIR" ]; then
  echo -e "${RED}❌ No restore directory entered. Exiting.${RESET}"
  exit 1
fi

# --- Prompt for containers directory ---
CONTAINERS_DIR=$(whiptail --inputbox "Enter path for Docker containers:" 10 70 "$RESTORE_DIR/containers" 3>&1 1>&2 2>&3)
if [ -z "$CONTAINERS_DIR" ]; then
  echo -e "${RED}❌ No containers directory entered. Exiting.${RESET}"
  exit 1
fi

# Call the restore script with the selected arguments
"$SCRIPT_DIR/restoreimmich.sh" "$BACKUP_LOCATION" "$RESTORE_DIR" "$CONTAINERS_DIR"
