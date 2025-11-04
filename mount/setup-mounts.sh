#!/bin/bash
# =============================================================
# 🧩 SMB Share Selector (for non-interactive smb-setup)
# =============================================================
# This script provides a 'whiptail' TUI to select drives and
# set a password. It then calls 'smb-setup.sh' with that info.
set -e

# --- Colors ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
RESET="\e[0m"
BOLD="\e[1m"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Ensure dependencies ---
PACKAGES_TO_INSTALL=()

# Check for whiptail
if ! command -v whiptail >/dev/null 2>&1; then
  PACKAGES_TO_INSTALL+=("whiptail")
fi

# Check for Samba commands
if ! command -v smbd >/dev/null 2>&1 || ! command -v smbpasswd >/dev/null 2>&1; then
  PACKAGES_TO_INSTALL+=("samba")
fi

# Remove duplicates (in case we add 'samba' twice, etc.)
UNIQUE_PACKAGES=($(echo "${PACKAGES_TO_INSTALL[@]}" | tr ' ' '\n' | sort -u))

if [ ${#UNIQUE_PACKAGES[@]} -ne 0 ]; then
  echo -e "${YELLOW}⚙️ Installing missing dependencies: ${UNIQUE_PACKAGES[*]}...${RESET}"
  # Ensure we have sudo/root privileges for this
  if [ "$EUID" -ne 0 ]; then
    sudo apt update -y
    sudo apt install -y "${UNIQUE_PACKAGES[@]}"
  else
    apt update -y
    apt install -y "${UNIQUE_PACKAGES[@]}"
  fi
  echo -e "${GREEN}✅ Dependencies installed.${RESET}"
fi

# --- List available drives correctly ---
# We look for 'disk' or 'nvme' types
DRIVES_RAW=$(lsblk -dn -o NAME,SIZE,TYPE | grep -E "disk|nvme")
OPTIONS=()

while read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    label="$name ($size)"
    # Format for whiptail: "TAG" "DESCRIPTION" "ON/OFF"
    OPTIONS+=("$name" "$label" "OFF")
done <<< "$DRIVES_RAW"

if [ ${#OPTIONS[@]} -eq 0 ]; then
    echo -e "${RED}❌ No physical drives (disk/nvme) found. Exiting.${RESET}"
    exit 1
fi

# --- Whiptail drive selection ---
SELECTED=$(whiptail --title "Select Drives to Share" --checklist \
"Select the drives you want to share (SPACE = select, ENTER = confirm)" 20 80 10 \
"${OPTIONS[@]}" 3>&1 1>&2 2>&3)

# Exit if user pressed Cancel
if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Cancelled. Exiting.${RESET}"
  exit 1
fi

SELECTED=$(echo $SELECTED | tr -d '"')

if [ -z "$SELECTED" ]; then
    echo -e "${RED}❌ No drives selected. Exiting.${RESET}"
    exit 1
fi

# --- Collect top-level mount points (parent folders) ---
MNT_FOLDERS=()
for drive in $SELECTED; do
    # Find all mountpoints for partitions on the selected drive
    # e.g., /dev/sdb -> /dev/sdb1 -> /mnt/storage
    while read -r part mount; do
        [ -z "$mount" ] && continue
        [ -d "$mount" ] && MNT_FOLDERS+=("$mount")
    done < <(lsblk -ln -o NAME,MOUNTPOINT "/dev/$drive")
done

# Ensure mount points are unique
MNT_FOLDERS=($(echo "${MNT_FOLDERS[@]}" | tr ' ' '\n' | sort -u))

if [ ${#MNT_FOLDERS[@]} -eq 0 ]; then
  echo -e "${RED}❌ No mounted folders found on selected drives.${RESET}"
  echo -e "${YELLOW}Please mount the partitions first (you can use 'setup-mounts.sh'). Exiting.${RESET}"
  exit 0
fi

# --- Prompt for SMB password ---
SMB_PASSWORD=$(whiptail --title "Samba Password" --passwordbox "Enter a password for your Samba user (will be set/updated):" 10 60 3>&1 1>&2 2>&3)

if [ $? -ne 0 ] || [ -z "$SMB_PASSWORD" ]; then
  echo -e "${RED}❌ No password entered or Cancelled. Exiting.${RESET}"
  exit 1
fi

echo -e "${GREEN}✅ Information collected. Calling setup script...${RESET}"
echo -e "${BLUE}------------------------------------------------------------${RESET}"

# --- Call the setup script ---
SETUP_SCRIPT="$SCRIPT_DIR/smb-setup.sh"

if [ ! -f "$SETUP_SCRIPT" ]; then
    echo -e "${RED}❌ Error: '$SETUP_SCRIPT' not found!${RESET}"
    echo -e "${YELLOW}Please make sure both scripts are in the same directory.${RESET}"
    exit 1
fi

# Call the setup script with the password and selected mount points as arguments
"$SETUP_SCRIPT" "$SMB_PASSWORD" "${MNT_FOLDERS[@]}"