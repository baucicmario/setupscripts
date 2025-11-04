#!/bin/bash
set -e
SCRIPT_PATH="$(realpath "$0")"
MARKER_FILE="$HOME/variables.conf"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Color definitions
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Detect OS ---
. /etc/os-release
CODENAME=$VERSION_CODENAME
echo -e "${BLUE}Detected OS:${RESET} ${YELLOW}${PRETTY_NAME}${RESET}"
echo "--------------------------------------------------"

# --- Always Install Dependencies in a Single Command ---
PACKAGES_TO_INSTALL=("whiptail" "samba" "jq" "curl" "rsync" "pv" "tar" "tree" "samba")

echo -e "${YELLOW}⚙️ Attempting to install core dependencies using a single command...${RESET}"
sudo apt update -y

# Combine the standard packages with the backported package:
# - Packages without a target (whiptail, samba, jq) are pulled from the default repo.
# - Packages listed after '-t ${CODENAME}-backports' (cockpit) are pulled from backports.
sudo apt install -y \
  "${PACKAGES_TO_INSTALL[@]}" \
  -t "${CODENAME}-backports" \
  cockpit

echo -e "${GREEN}✅ All core and script dependencies installed/verified.${RESET}"
echo "--------------------------------------------------"