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

# --- Ensure whiptail (optional, not needed here) ---
# --- Check arguments ---
if [ $# -lt 2 ]; then
    echo -e "${YELLOW}Usage: $0 <smb_password> <mount_point1> <mount_point2> ...${RESET}"
    echo -e "${YELLOW}Please run select-smb-shares.sh to select drives and provide the password first.${RESET}"
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

# --- Restart Samba ---
echo -e "${BLUE}🔄 Restarting Samba service...${RESET}"
sudo systemctl restart smbd
line

# --- Summary ---
IP_ADDR=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}${BOLD}✅ Selected drives are now shared!${RESET}"
echo ""
echo -e "${BOLD}💡 Access them from another device using:${RESET}"
echo -e "   \\\\${YELLOW}${IP_ADDR}${RESET}\\\\<foldername>"
echo ""
echo -e "${BOLD}Example shares:${RESET}"
for dir in "${MNT_FOLDERS[@]}"; do
  sharename=$(basename "$dir")
  echo -e "   📂 \\${IP_ADDR}\\${YELLOW}${sharename}${RESET}"
done
echo ""
line
echo -e "${GREEN}✨ Done! Happy sharing!${RESET}"
