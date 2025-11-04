#!/bin/bash
# =============================================================
# 🧩 SMB Share Selector (for non-interactive smb-setup)
# =============================================================
set -e
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"


#echo -e "${YELLOW}⚙️ Attempting to install samba...${RESET}"
#sudo apt update -y
#sudo apt install -y samba

# --- List available drives correctly ---
DRIVES_RAW=$(lsblk -dn -o NAME,SIZE,TYPE | grep -E "disk|nvme")
OPTIONS=()
while read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    label="$name ($size)"
    OPTIONS+=("$name" "$label" "OFF")
done <<< "$DRIVES_RAW"

# --- Whiptail drive selection ---
SELECTED=$(whiptail --title "Select Drives to Share" --checklist \
"Select the drives you want to share (SPACE = select, ENTER = confirm)" 20 80 10 \
"${OPTIONS[@]}" 3>&1 1>&2 2>&3)

SELECTED=$(echo $SELECTED | tr -d '"')

if [ -z "$SELECTED" ]; then
    echo -e "${RED}❌ No drives selected. Exiting.${RESET}"
    exit 1
fi

# --- Collect top-level mount points (parent folders) ---
MNT_FOLDERS=()
for drive in $SELECTED; do
    while read -r part mount; do
        [ -z "$mount" ] && continue
        [ -d "$mount" ] && MNT_FOLDERS+=("$mount")
    done < <(lsblk -ln -o NAME,MOUNTPOINT "/dev/$drive")
done

MNT_FOLDERS=($(echo "${MNT_FOLDERS[@]}" | tr ' ' '\n' | sort -u))

if [ ${#MNT_FOLDERS[@]} -eq 0 ]; then
  echo -e "${RED}❌ No mounted folders found on selected drives. Exiting.${RESET}"
  exit 0
fi

# --- Prompt for SMB password ---
SMB_PASSWORD=$(whiptail --title "Samba Password" --passwordbox "Enter a password for your Samba user (will be set/updated):" 10 60 3>&1 1>&2 2>&3)
if [ -z "$SMB_PASSWORD" ]; then
  echo -e "${RED}❌ No password entered. Exiting.${RESET}"
  exit 1
fi

# Call the setup script with the password and selected mount points as arguments
"$SCRIPT_DIR/smb-setup.sh" "$SMB_PASSWORD" "${MNT_FOLDERS[@]}"
