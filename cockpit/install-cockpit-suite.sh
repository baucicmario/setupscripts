#!/bin/bash
# =============================================================
# 🧰 Cockpit Suite Installer (modular version)
# =============================================================

set -e
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[36m"; RESET="\e[0m"; BOLD="\e[1m"
line() { echo -e "${BLUE}------------------------------------------------------------${RESET}"; }

TMP_DIR=$(mktemp -d /tmp/cockpit-suite.XXXX)
trap "rm -rf $TMP_DIR" EXIT

echo -e "${BOLD}${GREEN}🧰 Cockpit Suite Installation Script${RESET}"
line

# 🧩 Require sudo
if ! sudo -v >/dev/null 2>&1; then
  echo -e "${RED}❌ This script needs sudo.${RESET}"
  exit 1
fi

# 🧠 Detect OS
. /etc/os-release
CODENAME=$VERSION_CODENAME
echo -e "${BLUE}Detected OS:${RESET} ${YELLOW}${PRETTY_NAME}${RESET}"
line

# 🧩 Get selected modules from arguments
if [ $# -eq 0 ]; then
  echo -e "${YELLOW}Usage: $0 [module1 module2 ...]${RESET}"
  echo -e "${YELLOW}Please run select-modules.sh first and pass the selected modules as arguments.${RESET}"
  exit 1
fi
SELECTED="$@"

# 🧱 Install Cockpit core & Dependencies
echo -e "${BLUE}📦 Installing Cockpit core & script dependencies (jq)...${RESET}"
sudo apt update -y
# Install jq (for parsing GitHub API) AND cockpit
sudo apt install -y -t ${CODENAME}-backports cockpit jq
echo -e "${GREEN}✅ Cockpit core and dependencies installed.${RESET}"
line


# 🧩 45Drives fallback installer
install_45drives_deb() {
  local repo="$1"
  local pattern="$2"
  local name="$3"

  echo -e "${BLUE}🔍 Checking latest release for ${repo}...${RESET}"
  local url=$(curl -s "https://api.github.com/repos/45Drives/${repo}/releases/latest" \
              | jq -r '.assets[]?.browser_download_url' | grep -E "$pattern" | head -n1)

  if [[ -z "$url" ]]; then
    url=$(curl -s "https://api.github.com/repos/45Drives/${repo}/releases" \
          | jq -r '.[0].assets[]?.browser_download_url' | grep -E 'bookworm.*\.deb' | head -n1)
  fi

  if [[ -z "$url" ]]; then
    echo -e "${RED}❌ No .deb found for ${repo}.${RESET}"
    return
  fi

  echo -e "${BLUE}⬇️ Installing ${name} from ${repo}...${RESET}"
  curl -L -o "${TMP_DIR}/${repo}.deb" "$url"
  sudo dpkg -i "${TMP_DIR}/${repo}.deb" || sudo apt install -yf
  echo -e "${GREEN}✅ Installed ${name}.${RESET}"
}

# 🧩 Install selected modules
if [ -z "$SELECTED" ]; then
  echo -e "${YELLOW}⏩ No optional modules selected.${RESET}"
else
  echo -e "${BLUE}📦 Installing selected modules individually...${RESET}"
  echo -e "${BLUE}🔄 Updating package lists (once)...${RESET}"
  sudo apt update -y

  for pkg in $SELECTED; do
    pkg_clean=$(echo "$pkg" | tr -d '"')
    echo -e "${BLUE}➡️  Processing module:${RESET} ${pkg_clean}"

    # Check if package exists in apt
    if apt-cache show "$pkg_clean" >/dev/null 2>&1; then
      echo -e "${BLUE}⬇️ Installing ${pkg_clean} from apt...${RESET}"
      if sudo apt install -y "$pkg_clean"; then
        echo -e "${GREEN}✅ Installed ${pkg_clean}.${RESET}"
      else
        echo -e "${RED}❌ Failed to install ${pkg_clean} via apt.${RESET}"
      fi
    else
      echo -e "${YELLOW}⚠️ ${pkg_clean} not available in apt — checking for fallback method...${RESET}"

      case "$pkg_clean" in
        cockpit-navigator)
          echo -e "${BLUE}⬇️ Installing Cockpit Navigator (direct download)...${RESET}"
          NAV_URL="https://github.com/45Drives/cockpit-navigator/releases/download/v0.5.10/cockpit-navigator_0.5.10-1focal_all.deb"
          curl -L -o "${TMP_DIR}/cockpit-navigator.deb" "$NAV_URL"
          sudo apt install -y "${TMP_DIR}/cockpit-navigator.deb" || sudo apt install -yf
          echo -e "${GREEN}✅ Cockpit Navigator installed.${RESET}"
          ;;
        cockpit-file-sharing)
          install_45drives_deb "cockpit-file-sharing" "(_all\.deb|_amd64\.deb)" "File Sharing"
          ;;
        cockpit-identities)
          install_45drives_deb "cockpit-identities" "(_all\.deb|_amd64\.deb)" "Identities"
          ;;
        *)
          echo -e "${RED}❌ No installation method available for ${pkg_clean}.${RESET}"
          ;;
      esac
    fi
  done
fi

line

# ✅ Enable Cockpit
echo -e "${BLUE}⚙️ Enabling Cockpit service...${RESET}"
sudo systemctl enable --now cockpit.socket

IP=$(hostname -I | awk '{print $1}')
line
echo -e "${GREEN}${BOLD}🎉 Cockpit Suite is ready!${RESET}"
echo -e "🌐 Access: ${YELLOW}https://${IP}:9090${RESET}"
echo -e "💡 Login with your normal system credentials."
line

# Summary
echo -e "${BOLD}${BLUE}📋 Installed Modules Summary:${RESET}"
for pkg in $SELECTED; do
  if dpkg -l | grep -q "$pkg"; then
    echo -e "   ${GREEN}✔ ${pkg}${RESET}"
  else
    echo -e "   ${RED}✖ ${pkg}${RESET}"
  fi
done
line
