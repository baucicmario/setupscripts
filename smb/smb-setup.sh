#!/bin/bash
# Automatically share provided mount points as SMB shares (non-interactive).
set -e

# --- Colors ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

line() { echo -e "${BLUE}------------------------------------------------------------${RESET}"; }

echo -e "${BOLD}${GREEN}🔧 Auto SMB Share Setup (Non-Interactive)${RESET}"
line

CURRENT_USER=$(whoami)

# --- Check arguments ---
if [ $# -lt 2 ]; then
    echo -e "${YELLOW}Usage: $0 <smb_password> <mount_point1> <mount_point2> ...${RESET}"
    echo -e "${YELLOW}Please provide the Samba password and at least one mount point.${RESET}"
    exit 1
fi
SMB_PASSWORD="$1"
shift
MNT_FOLDERS=("$@")

# --- Check Samba installation ---
if ! command -v smbd >/dev/null 2>&1; then
  echo -e "${YELLOW}📦 Samba not found. Installing...${RESET}"
  sudo apt update && sudo apt install -y samba
  echo -e "${GREEN}✅ Samba installed successfully.${RESET}"
else
  echo -e "${GREEN}✅ Samba is already installed.${RESET}"
fi
line

# --- Set up Samba user ---
echo -e "${BOLD}${BLUE}👤 Setting up Samba user for ${YELLOW}$CURRENT_USER${RESET}"
if ! sudo pdbedit -L | grep -q "^$CURRENT_USER:"; then
  echo -e "${YELLOW}Setting Samba password for user '$CURRENT_USER' (non-interactive)${RESET}"
  echo -e "$SMB_PASSWORD\n$SMB_PASSWORD" | sudo smbpasswd -a -s "$CURRENT_USER"
  echo -e "${GREEN}✅ Samba user '$CURRENT_USER' added.${RESET}"
else
  echo -e "${YELLOW}Updating Samba password for user '$CURRENT_USER' (non-interactive)${RESET}"
  echo -e "$SMB_PASSWORD\n$SMB_PASSWORD" | sudo smbpasswd -s "$CURRENT_USER"
  echo -e "${GREEN}✅ Samba user '$CURRENT_USER' password updated.${RESET}"
fi
line

# --- Backup smb.conf ---
if [ ! -f /etc/samba/smb.conf.bak ]; then
  echo -e "${BLUE}💾 Backing up smb.conf -> smb.conf.bak${RESET}"
  sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
else
  echo -e "${GREEN}✅ Backup already exists.${RESET}"
fi
line

if [ ${#MNT_FOLDERS[@]} -eq 0 ]; then
  echo -e "${RED}❌ No mounted folders provided. Exiting.${RESET}"
  exit 0
fi

echo -e "${BLUE}📁 Will share the following top-level folders:${RESET}"
for d in "${MNT_FOLDERS[@]}"; do
  echo -e "   - ${YELLOW}$d${RESET}"
done
line

# --- Remove old auto-generated section ---
sudo sed -i '/# BEGIN-AUTO-SMB/,/# END-AUTO-SMB/d' /etc/samba/smb.conf

# --- Append new shares ---
echo -e "${BLUE}⚙️  Updating Samba configuration...${RESET}"
sudo tee -a /etc/samba/smb.conf > /dev/null <<EOF

# BEGIN-AUTO-SMB
# Automatically generated SMB shares for selected drives
EOF

for dir in "${MNT_FOLDERS[@]}"; do
  sharename=$(basename "$dir")
  sudo tee -a /etc/samba/smb.conf > /dev/null <<EOF
[$sharename]
    path = $dir
    valid users = $CURRENT_USER
    read only = no
    browseable = yes
    writable = yes

EOF
done

sudo tee -a /etc/samba/smb.conf > /dev/null <<EOF
# END-AUTO-SMB
EOF
line

# --- ⭐ START: FIXED VALIDATE AND RESTART BLOCK ⭐ ---
echo -e "${BLUE}⚙️ Validating Samba configuration...${RESET}"

# Use 'testparm' to check for syntax errors
if ! sudo testparm -s; then
    echo -e "${RED}❌ Samba configuration is invalid! Service not restarted.${RESET}"
    echo -e "${YELLOW}Please run 'sudo testparm' to see the full error.${RESET}"
    exit 1
fi
echo -e "${GREEN}✅ Samba configuration is valid.${RESET}"
line

echo -e "${BLUE}🔄 Restarting Samba service...${RESET}"
if ! sudo systemctl restart smbd; then
    echo -e "${RED}❌ Failed to issue restart command to Samba.${RESET}"
    exit 1
fi

# Give the service a second to start
sleep 1

# --- This is the new, critical check ---
if sudo systemctl is-active --quiet smbd; then
    echo -e "${GREEN}✅ Samba service is active and running.${RESET}"
else
    echo -e "${RED}❌ Samba service FAILED to start.${RESET}"
    echo -e "${YELLOW}Check status with: sudo systemctl status smbd${RESET}"
    echo -e "${YELLOW}Check logs with: sudo journalctl -u smbd -n 50${RESET}"
    exit 1
fi
line
# --- ⭐ END: FIXED VALIDATE AND RESTART BLOCK ⭐ ---


# --- Summary ---
IP_ADDR=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}${BOLD}✅ Selected drives are now shared!${RESET}"
echo ""
echo -e "${BOLD}💡 Access them from another device using:${RESET}"
echo -e "   \\\\${YELLOW}${IP_ADDR}${RESET}\\\\<foldername>"
echo ""

# --- ⭐ START: FINAL FIXED EXAMPLE SHARES LOOP ⭐ ---
echo -e "${BOLD}Example shares:${RESET}"
for dir in "${MNT_FOLDERS[@]}"; do
  sharename=$(basename "$dir")
  # Print the static parts first, then the colored part
  echo -en "   📂 \\\\${IP_ADDR}\\"
  echo -e "${YELLOW}${sharename}${RESET}"
done
# --- ⭐ END: FINAL FIXED EXAMPLE SHARES LOOP ⭐ ---

echo ""
line
echo -e "${GREEN}✨ Done! Happy sharing!${RESET}"