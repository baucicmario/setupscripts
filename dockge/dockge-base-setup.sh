#!/bin/bash
# =============================================================
# 🐳 Dockge Installer & Setup
# =============================================================
set -e

# --- Colors ---
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

line() { echo -e "${BLUE}------------------------------------------------------------${RESET}"; }

echo -e "${BOLD}${GREEN}🐳 Dockge Installer & Setup${RESET}"
line

# --- Ensure Docker is installed ---
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${YELLOW}⚙️ Docker not found. Installing...${RESET}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm -f get-docker.sh
else
    echo -e "${GREEN}✅ Docker is already installed.${RESET}"
fi
line

# --- Ensure Docker Compose plugin is available ---
if ! docker compose version >/dev/null 2>&1; then
    echo -e "${YELLOW}⚙️ Docker Compose plugin not found. Installing...${RESET}"
    sudo apt update && sudo apt install -y docker-compose-plugin
else
    echo -e "${GREEN}✅ Docker Compose plugin is available.${RESET}"
fi
line

# --- Create Dockge directory ---
DOCKGE_DIR="/opt/dockge"
sudo mkdir -p "$DOCKGE_DIR"
sudo chown "$USER":"$USER" "$DOCKGE_DIR"
cd "$DOCKGE_DIR"

# --- Download compose.yaml ---
echo -e "${BLUE}⬇️  Downloading Dockge compose.yaml...${RESET}"
curl -fsSL https://raw.githubusercontent.com/louislam/dockge/master/compose.yaml -o compose.yaml
line

# --- Start Dockge ---
echo -e "${BLUE}⚙️ Starting Dockge using Docker Compose...${RESET}"
sg docker -c "docker compose up -d"
line

# --- Detect IP and print access link ---
IP_ADDR=$(hostname -I | awk '{print $1}')
DOCKGE_PORT=5001  # default Dockge port
echo -e "${GREEN}${BOLD}✅ Dockge installed and running successfully!${RESET}"
echo -e "${BOLD}💡 You can access Dockge at:${RESET} ${YELLOW}http://${IP_ADDR}:${DOCKGE_PORT}${RESET}"
echo -e "${BOLD}💡 You can manage Dockge with 'docker compose' commands in ${DOCKGE_DIR}${RESET}"
line
