#!/bin/bash
# Interactively find and add unmounted drives to /etc/fstab for auto-mounting.

set -e

# --- Colors ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

line() { echo -e "${BLUE}------------------------------------------------------------${RESET}"; }

echo -e "${BOLD}${GREEN}🔧 Interactive Auto-Mount Setup${RESET}"
line

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ This script must be run as root (or with sudo).${RESET}"
  exit 1
fi

# --- Backup fstab ---
if [ ! -f /etc/fstab.bak ]; then
  echo -e "${BLUE}💾 Backing up /etc/fstab -> /etc/fstab.bak${RESET}"
  cp /etc/fstab /etc/fstab.bak
else
  echo -e "${GREEN}✅ /etc/fstab.bak already exists.${RESET}"
fi
line

# --- Find eligible partitions ---
# We look for partitions that have a UUID and a Filesystem, but are not 'swap'.
# We read this into an array to avoid subshell issues with 'while read'.
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
  # This avoids trying to mount a drive that's already mounted manually.
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
    # Suggest a default mount point, e.g., /mnt/Storage or /mnt/sdb1
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
    try
      # 1. Create directory
      echo "  -> Creating directory: $MNT_PATH"
      mkdir -p "$MNT_PATH"

      # 2. Add to fstab
      echo "  -> Adding to /etc/fstab"
      FSTAB_LINE="UUID=$UUID $MNT_PATH $FSTYPE $OPTIONS 0 2"
      echo "$FSTAB_LINE" >> /etc/fstab

      # 3. Mount it now
      echo "  -> Attempting to mount..."
      mount "$MNT_PATH"

      echo -e "${GREEN}✅ Successfully mounted $NAME to $MNT_PATH.${RESET}"

    catch
      echo -e "${RED}❌ An error occurred. Failed to configure $MNT_PATH.${RESET}"
      echo -e "${YELLOW}Check /etc/fstab for the last line and remove it if necessary.${RESET}"
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