#!/bin/bash
# ============================================
# Combined Backup Selector (v5 - Shared Backup Dest)
# Asks for a single backup destination, then for each service.
# ============================================

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Setup ---
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Define Script Paths ---
IMMICH_SCRIPT="$SCRIPT_DIR/immich/immichbackup.sh"
DOCKGE_SCRIPT="$SCRIPT_DIR/dockge/dockge-backup.sh"

# --- Pre-run Sanity Checks ---
echo -e "${BLUE}Checking backup script locations...${RESET}"
ERRORS=0
if [ ! -f "$IMMICH_SCRIPT" ]; then
  echo -e "${RED}❌ Error: Immich backup script not found at:${RESET}"
  echo -e "   $IMMICH_SCRIPT"
  ERRORS=1
elif [ ! -x "$IMMICH_SCRIPT" ]; then
   echo -e "${YELLOW}⚠️ Warning: Immich script is not executable. Attempting to fix...${RESET}"
   chmod +x "$IMMICH_SCRIPT" || { echo -e "${RED}Failed to set permissions.${RESET}"; ERRORS=1; }
fi

if [ ! -f "$DOCKGE_SCRIPT" ]; then
  echo -e "${RED}❌ Error: Dockge backup script not found at:${RESET}"
  echo -e "   $DOCKGE_SCRIPT"
  ERRORS=1
elif [ ! -x "$DOCKGE_SCRIPT" ]; then
   echo -e "${YELLOW}⚠️ Warning: Dockge script is not executable. Attempting to fix...${RESET}"
   chmod +x "$DOCKGE_SCRIPT" || { echo -e "${RED}Failed to set permissions.${RESET}"; ERRORS=1; }
fi

if [ $ERRORS -ne 0 ]; then
  echo -e "\n${RED}Please fix the errors above and re-run the script. Exiting.${RESET}"
  exit 1
fi
echo -e "${GREEN}✅ All backup scripts found and executable.${RESET}"

# --- Ensure dependencies ---
DEPS=(whiptail docker pv tree rsync tar)
MISSING=()
for dep in "${DEPS[@]}"; do
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

# --- Prompt for ALL variables one-by-one ---
echo -e "${BLUE}Gathering backup configuration...${RESET}"

# -- 1. Get Main Backup Destination --
MAIN_BACKUP_DEST=$(whiptail --title "Main Backup Config (1/3)" --inputbox "Enter the main backup destination folder:" 10 70 "/mnt/st" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$MAIN_BACKUP_DEST" ]; then
  echo -e "${RED}❌ No backup destination provided. Exiting.${RESET}"
  exit 1
fi

# -- 2. Get Immich Config --
COMPOSE_DIR=$(whiptail --title "Immich Config (2/3)" --inputbox "Enter Immich docker-compose folder:\n(Leave blank to skip Immich backup)" 10 70 "/mnt/st/central-immich/compose" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Backup configuration cancelled. Exiting.${RESET}"
  exit 1
fi
# Set Immich backup base *only* if COMPOSE_DIR was given
[ -n "$COMPOSE_DIR" ] && BACKUP_BASE="$MAIN_BACKUP_DEST"


# -- 3. Get Dockge Config --
STACKS_DIR=$(whiptail --title "Dockge Config (3/3)" --inputbox "Enter the Dockge stacks directory:\n(Leave blank to skip Dockge backup)" 10 70 "/opt/stacks" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Backup configuration cancelled. Exiting.${RESET}"
  exit 1
fi

if [ -n "$STACKS_DIR" ]; then
  # Set Dockge backup parent *only* if STACKS_DIR was given
  BACKUP_PARENT_DIR="$MAIN_BACKUP_DEST"
  
  CONTAINERS_VAR_NAME=$(whiptail --title "Dockge Config (3/3)" --inputbox "Enter the .env files containers variable name (default: CONTAINERS_ROOT):" 10 70 "CONTAINERS_ROOT" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Backup configuration cancelled. Exiting.${RESET}"
    exit 1
  fi
  
  # Handle default for Dockge .env var
  if [ -z "$CONTAINERS_VAR_NAME" ]; then
    CONTAINERS_VAR_NAME="CONTAINERS_ROOT"
  fi
else
  # Ensure vars are empty if user skipped
  BACKUP_PARENT_DIR=""
  CONTAINERS_VAR_NAME=""
fi

# --- Execute Backups ---
RAN_IMMICH=0
RAN_DOCKGE=0

echo -e "\n${BLUE}Starting backup process...${RESET}"

# --- Run Immich Backup ---
if [ -n "$COMPOSE_DIR" ]; then
  echo -e "\n${BLUE}🚀 Launching Immich Backup...${RESET}"
  echo -e "   Compose Dir: ${YELLOW}$COMPOSE_DIR${RESET}"
  echo -e "   Backup Dest: ${YELLOW}$BACKUP_BASE${RESET}"
  
  "$IMMICH_SCRIPT" "$COMPOSE_DIR" "$BACKUP_BASE"
  
  echo -e "${GREEN}✅ Immich Backup Finished.${RESET}"
  RAN_IMMICH=1
else
  echo -e "\n${YELLOW}ℹ️ Skipping Immich backup (paths not provided).${RESET}"
fi

# --- Run Dockge Backup ---
if [ -n "$STACKS_DIR" ]; then
  echo -e "\n${BLUE}🚀 Launching Dockge Backup...${RESET}"
  echo -e "   Stacks Dir:  ${YELLOW}$STACKS_DIR${RESET}"
  echo -e "   Backup Dest: ${YELLOW}$BACKUP_PARENT_DIR${RESET}"
  echo -e "   .env Var:    ${YELLOW}$CONTAINERS_VAR_NAME${RESET}"

  "$DOCKGE_SCRIPT" "$STACKS_DIR" "$BACKUP_PARENT_DIR" "$CONTAINERS_VAR_NAME"
  
  echo -e "${GREEN}✅ Dockge Backup Finished.${RESET}"
  RAN_DOCKGE=1
else
  echo -e "\n${YELLOW}ℹ️ Skipping Dockge backup (paths not provided).${RESET}"
fi

# --- Final Summary ---
echo -e "\n---"
if [ $RAN_IMMICH -eq 0 ] && [ $RAN_DOCKGE -eq 0 ]; then
  echo -e "${YELLOW}⏹️ No backups were configured to run.${RESET}"
else
  echo -e "${GREEN}🎉 All selected backups are complete.${RESET}"
fi