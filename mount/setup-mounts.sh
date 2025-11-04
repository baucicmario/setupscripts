#!/bin/bash
# Interactively find and add unmounted drives to /etc/fstab using whiptail.
# This script will automatically request sudo privileges if not run as root.

# --- Colors (for terminal fallback/logs) ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# --- Sudo-Launcher ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}ℹ️ This script needs administrative privileges.${RESET}"
  echo -e "${BLUE}Attempting to re-run with sudo...${RESET}"
  sudo bash "$0" "$@"
  exit $?
fi

# --- If we reach this point, we are running as root ---

# --- Backup fstab ---
if [ ! -f /etc/fstab.bak ]; then
  cp /etc/fstab /etc/fstab.bak
  whiptail --title "Backup" --msgbox "Created /etc/fstab.bak as a safety backup." 8 78
fi

whiptail --title "Auto-Mount Setup" --msgbox "Welcome! This script will help you find and auto-mount new drives.\n\nIt will scan for partitions that are not in /etc/fstab or currently mounted." 10 78

# --- Find eligible partitions ---
declare -A DRIVE_DETAILS
WHIPTAIL_OPTIONS=()
PART_COUNT=0

while read -r part_line; do
  read -r NAME FSTYPE UUID LABEL SIZE <<<"$part_line"

  if grep -q "UUID=$UUID" /etc/fstab; then
    continue
  fi

  if findmnt -n "$NAME" > /dev/null; then
    continue
  fi

  PART_COUNT=$((PART_COUNT + 1))
  DRIVE_DETAILS[$NAME]="$UUID|$FSTYPE|$LABEL"
  DRIVE_INFO="${LABEL:-<no label>} ($SIZE, $FSTYPE)"
  WHIPTAIL_OPTIONS+=("$NAME" "$DRIVE_INFO" "OFF")

done < <(lsblk -fpo NAME,FSTYPE,UUID,LABEL,SIZE | awk 'NR>1 && $2!="" && $2!="swap" && $3!=""')

if [ $PART_COUNT -eq 0 ]; then
  whiptail --title "No Drives Found" --msgbox "No new, unmounted, or unconfigured drives were found." 8 78
  exit 0
fi

# --- Show Checklist ---
SELECTED_DRIVES_STR=$(whiptail --title "Select Partitions to Mount" --checklist \
  "Use SPACE to select drives you wish to auto-mount:" 20 78 10 \
  "${WHIPTAIL_OPTIONS[@]}" 3>&1 1>&2 2>&3)

if [ $? -ne 0 ]; then
  whiptail --title "Cancelled" --msgbox "No changes were made." 8 78
  exit 0
fi

eval "SELECTED_DRIVES=($SELECTED_DRIVES_STR)"

# --- Process Selections ---
FINAL_REPORT="Mounting process complete.\n\nSummary:\n"

for DEVICE in "${SELECTED_DRIVES[@]}"; do
  IFS='|' read -r UUID FSTYPE LABEL <<< "${DRIVE_DETAILS[$DEVICE]}"
  
  SUGGESTED_NAME=$(basename "$DEVICE")
  DEFAULT_MNT="/mnt/${LABEL:-$SUGGESTED_NAME}"

  MNT_PATH=$(whiptail --title "Mount Point for $DEVICE" --inputbox \
    "Where do you want to mount this drive?" 10 78 "$DEFAULT_MNT" \
    3>&1 1>&2 2>&3)

  if [ -z "$MNT_PATH" ]; then
    FINAL_REPORT+="  - $DEVICE: Skipped (no mount path provided)\n"
    continue
  fi
  
  if [[ "$MNT_PATH" != "/mnt/"* && "$MNT_PATH" != "/media/"* ]]; then
    whiptail --title "Error" --msgbox "Invalid path: $MNT_PATH\n\nMount point must start with /mnt/ or /media/.\nSkipping this drive." 10 78
    FINAL_REPORT+="  - $DEVICE: Failed (Invalid path)\n"
    continue
  fi

  OPTIONS="defaults"
  FSTYPE_FINAL=$FSTYPE
  if [ "$FSTYPE" == "ntfs" ]; then
    FSTYPE_FINAL="ntfs-3g"
  fi
  
  whiptail --title "Configuring $DEVICE" --infobox "Configuring $MNT_PATH..." 8 78
  sleep 1

  # --- Start: THIS IS THE FIXED BLOCK ---
  
  # 1. Create directory
  if ! mkdir -p "$MNT_PATH"; then
    whiptail --title "Error" --msgbox "Failed to create directory: $MNT_PATH" 8 78
    FINAL_REPORT+="  - $DEVICE: FAILED (mkdir error)\n"
    continue # Skip to next drive
  fi
  
  # 2. Add to fstab
  FSTAB_LINE="UUID=$UUID $MNT_PATH $FSTYPE_FINAL $OPTIONS 0 2"
  if ! echo "$FSTAB_LINE" >> /etc/fstab; then
    whiptail --title "Error" --msgbox "Failed to write to /etc/fstab." 8 78
    FINAL_REPORT+="  - $DEVICE: FAILED (fstab write error)\n"
    continue # Skip to next drive
  fi

  # 3. Mount it now
  if ! mount "$MNT_PATH"; then
    whiptail --title "Error" --msgbox "❌ Mount Failed! $DEVICE was added to /etc/fstab, but could not be mounted.\n\nPlease check your fstab entry." 10 78
    FINAL_REPORT+="  - $DEVICE: FAILED to mount ($MNT_PATH)\n"
  
  # 4. Double-Check Verification (only if mount *succeeded*)
  elif findmnt -n "$MNT_PATH" > /dev/null; then
    whiptail --title "Success" --msgbox "✅ Successfully mounted $DEVICE to $MNT_PATH." 8 78
    FINAL_REPORT+="  - $DEVICE: OK ($MNT_PATH)\n"
  else
    # This case is unlikely if 'mount' returned 0, but good to have
    whiptail --title "Error" --msgbox "❌ Mount reported success, but verification failed." 10 78
    FINAL_REPORT+="  - $DEVICE: FAILED (verification error)\n"
  fi
  # --- End: THIS IS THE FIXED BLOCK ---
  
done

# --- Final Report ---
whiptail --title "All Done!" --msgbox "$FINAL_REPORT" 20 78