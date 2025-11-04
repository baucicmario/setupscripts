#!/bin/bash
# =============================================================
# 🐳 Docker Installer & User Setup
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

echo -e "${BOLD}${GREEN}🐳 Docker Installer & Setup${RESET}"
line

CURRENT_USER=$(whoami)

# --- Download Docker install script ---
echo -e "${BLUE}⬇️  Downloading Docker installation script...${RESET}"
curl -fsSL https://get.docker.com -o get-docker.sh

# --- Run Docker install script ---
echo -e "${BLUE}⚙️ Installing Docker...${RESET}"
sudo sh get-docker.sh
line

# --- Add current user to Docker group ---
if groups $CURRENT_USER | grep -q "\bdocker\b"; then
    echo -e "${GREEN}✅ User '$CURRENT_USER' is already in the docker group.${RESET}"
else
    echo -e "${BLUE}👤 Adding user '$CURRENT_USER' to 'docker' group...${RESET}"
    sudo usermod -aG docker "$CURRENT_USER"
    echo -e "${GREEN}✅ User '$CURRENT_USER' added to 'docker' group.${RESET}"
fi
line

# --- Activate docker group without logout ---
echo -e "${BLUE}🔄 Activating Docker group for current session...${RESET}"
if command -v newgrp >/dev/null 2>&1; then
    newgrp docker <<'EONG'
echo -e "\e[32m✅ Docker group activated for current session!\e[0m"
EONG
else
    echo -e "${YELLOW}⚠️  Please log out and log back in to use Docker without sudo.${RESET}"
fi
line

# --- Verify Docker installation ---
echo -e "${BLUE}🐳 Verifying Docker installation...${RESET}"
docker_version=$(docker --version 2>/dev/null || echo "Not found")
if [[ "$docker_version" != "Not found" ]]; then
    echo -e "${GREEN}${BOLD}✅ Docker installed successfully: ${docker_version}${RESET}"
    echo -e "${BOLD}💡 You can now run 'docker run hello-world' to test Docker.${RESET}"
else
    echo -e "${RED}❌ Docker installation failed.${RESET}"
fi
line

# --- Cleanup ---
rm -f get-docker.sh
echo -e "${GREEN}✨ Done! Happy Dockering!${RESET}"
echo -e "${BLUE}🐳 Testing Docker for current session...${RESET}"
sg docker -c "docker run hello-world"

