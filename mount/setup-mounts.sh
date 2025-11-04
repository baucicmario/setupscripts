#!/bin/bash
# Interactively find and add unmounted drives to /etc/fstab.
# This script will automatically request sudo privileges if not run as root.

set -e

# --- Colors ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

line() { echo -e "${BLUE}------------------------------------------------------------${RESET}"; }

# --- Sudo-Launcher ---
# If not running as root, re-launch this script with sudo
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}ℹ️ This script needs administrative privileges.${RESET}"
  echo -e "${BLUE}Attempting to re-run with sudo...${RESET}"
  
  # Re-execute this script with sudo, passing all original arguments
  # Using "sudo bash" is a robust way to ensure it's executed by bash
  sudo bash "$0" "$@"
  
  # Exit the original, non-privileged script
  exit $?
fi

# --- If we reach this point, we are running as root ---

echo -e "${BOLD}${GREEN}🔧 Interactive Auto-Mount Setup${RESET}"
echo -e "${GREEN}✅ Running with administrative privileges.${RESET}"
line

# --- Backup fstab ---
if [ ! -f /etc/fstab.bak ]; then
  echo -e "${BLUE}💾 Backing up /etc/fstab -> /etc/fstab.bak${RESET}"
  cp /etc/fstab /etc/fstab.bak
else
  echo -e "${GREEN}✅ /etc/fstab.bak already exists.${RESET}"
fi
line

# --- Find eligible partitions ---
# Read partitions into an array
readarray -t PARTITIONS < <(lsblk -fpo NAME,FSTYPE,UUID,LABEL,SIZE | awk 'NR>1 && $2!="" && $2!="swap" && $3!=""')

if [ ${#PARTITIONS[@]} -eq 0 ]; then
  echo -e "${GREEN}✅ No new partitions found that need configuration.${RESET}"
  exit 0
fi

FOUND_NEW=0

# --- Loop over partitions ---
for part_line in "${PARTITIONS[@]}"; do
  # Parse the line
  read -r NAME FSTYPE UUID LABEL SIZE <<<"$part_line"

  # 1. Check if already in fstab by UUID
  if grep -q "UUID=$UUID" /etc/fstab; then
    echo -e "${GREEN}ℹ️ Skipping $NAME (${LABEL:-no label}): Already in /etc/fstab.${RESET}"
    continue
  fi

  # 2. Check if mounted (even if not in fstab)
  if findmnt -n "$NAME" > /dev/null; then
    echo -e "${GREEN}ℹ️ Skipping $NAME (${LABEL:-no label}): Already mounted.${RESET}"
    continue
  fi

  # --- We found a drive that needs setup! ---
  FOUND_NEW=1
  line
  echo -e "${BOLD}Found new partition:${RESET}"
  echo -e "  Device: ${YELLOW}$NAME${RESET}"
  echo -e "  Label:  ${YELLOW}${LABEL:-<none>}${RESET}"
  echo -e "  Size:   ${YELLOW}$SIZE${RESET}"
  echo -e "  Type:   ${YELLOW}$FSTYPE${RESET}"
  echo -e "  UUID:   ${YELLOW}$UUID${RESET}"
  echo ""

  # Ask user to mount
  read -p "Do you want to automatically mount this partition? (y/n) " -n 1 -r REPLY
  echo # for new line

  if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    # --- Get Mount Point ---
    SUGGESTED_NAME=$(basename "$NAME")
    DEFAULT_MNT="/mnt/${LABEL:-$SUGGESTED_NAME}"

    read -p "Enter mount point (default: ${BOLD}$DEFAULT_MNT${RESET}): " MNT_PATH
    MNT_PATH="${MNT_PATH:-$DEFAULT_MNT}" # Use default if input is empty

    # Validate path
    if [[ "$MNT_PATH" != "/mnt/"* && "$MNT_PATH" != "/media/"* ]]; then
      echo -e "${RED}❌ Invalid path. Mount point must start with /mnt/ or /media/. Skipping.${RESET}"
      continue
    fi

    # --- Get Options ---
    OPTIONS="defaults"
    read -p "Mount as read-only? (y/n) " -n 1 -r RO_REPLY
    echo
    if [[ "$RO_REPLY" =~ ^[Yy]$ ]]; then
      OPTIONS="ro,defaults"
    fi

    # Handle 'ntfs' -> 'ntfs-3g' for robust fstab entry
    if [ "$FSTYPE" == "ntfs" ]; then
      echo -e "${BLUE}ℹ️ Converted 'ntfs' type to 'ntfs-3g' for fstab.${RESET}"
      FSTYPE="ntfs-3g"
    fi

    # --- Perform Actions ---
    echo -e "${BLUE}⚙️ Configuring auto-mount...${RESET}"
    
    # 1. Create directory
    echo "  -> Creating directory: $MNT_PATH"
    if ! mkdir -p "$MNT_PATH"; then
        echo -e "${RED}❌ Failed to create directory. Skipping.${RESET}"
        continue
    fi

    # 2. Add to fstab
    echo "  -> Adding to /etc/fstab"
    FSTAB_LINE="UUID=$UUID $MNT_PATH $FSTYPE $OPTIONS 0 2"
    
    # Use tee -a to append as root. This is safer than 'echo ... >>'
    if ! echo "$FSTAB_LINE" | tee -a /etc/fstab > /dev/null; then
        echo -e "${RED}❌ Failed to write to /etc/fstab. Skipping.${RESET}"
        continue
    fi

    # 3. Mount it now
    echo "  -> Attempting to mount..."
    if ! mount "$MNT_PATH"; then
        echo -e "${RED}❌ Mount failed!${RESET}"
        echo -e "${YELLOW}Please check /etc/fstab for the new line and manually debug.${RESET}"
        echo -e "${YELLOW}The entry '$FSTAB_LINE' may be incorrect.${RESET}"
    else
        echo -e "${GREEN}✅ Successfully mounted $NAME to $MNT_PATH.${RESET}"
    fi
  else
    echo -e "${YELLOW}Skipping $NAME.${RESET}"
  fi
done

line
if [ $FOUND_NEW -eq 0 ]; then
  echo -e "${GREEN}✨ All partitions are already configured.${RESET}"
else
  echo -e "${GREEN}✨ All new partitions processed!${RESET}"
fi