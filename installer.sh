#!/usr/bin/env bash

# =========================================================
# HVM PANEL V8 ULTRA INSTALLER
# =========================================================

set -euo pipefail

# =========================================================
# COLORS & STYLES
# =========================================================

RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
BLUE="\e[1;34m"
CYAN="\e[1;36m"
MAGENTA="\e[1;35m"
WHITE="\e[1;37m"
NC="\e[0m"

# =========================================================
# CONFIGURATION & VARIABLES
# =========================================================

HVM_URL="https://files.catbox.moe/muyvyn.zip"

INSTALL_DIR="/opt/hvm"
SERVICE_NAME="hvm"
PANEL_PORT="5000"

LOG_FILE="/var/log/hvm.log"
CRED_FILE="${INSTALL_DIR}/admin_credentials.txt"

# =========================================================
# HELPER FUNCTIONS
# =========================================================

line() {
    echo -e "${MAGENTA}============================================================${NC}"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =========================================================
# BANNER DISPLAY
# =========================================================

clear

echo -e "${CYAN}"
cat << "EOF"

██╗  ██╗██╗   ██╗███╗   ███╗
██║  ██║██║   ██║████╗ ████║
███████║██║   ██║██╔████╔██║
██╔══██║╚██╗ ██╔╝██║╚██╔╝██║
██║  ██║ ╚████╔╝ ██║ ╚═╝ ██║
╚═╝  ╚═╝  ╚═══╝  ╚═╝     ╚═╝

       HVM PANEL V8 ULTRA INSTALLER
EOF
echo -e "${NC}"

line

# =========================================================
# PRIVILEGE CHECK
# =========================================================

if [[ "$EUID" -ne 0 ]]; then
    error "Please run this installer as root."
    exit 1
fi

# =========================================================
# OS & ARCHITECTURE DETECTION
# =========================================================

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    DISTRO=$ID
    VERSION=${VERSION_ID:-"Unknown"}
else
    error "Unable to detect operating system distribution."
    exit 1
fi

ARCH=$(uname -m)

info "Detected OS   : ${PRETTY_NAME:-$DISTRO}"
info "Architecture  : ${ARCH}"

line

# =========================================================
# DEPENDENCY MANAGEMENT
# =========================================================

info "Installing system dependencies (unzip, python3, etc.)..."

if command -v apt >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt update -y && apt install -y curl wget lsof tar unzip sudo nano python3 python3-pip ca-certificates
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl wget lsof tar unzip sudo nano python3 python3-pip ca-certificates
elif command -v yum >/dev/null 2>&1; then
    yum install -y epel-release && yum install -y curl wget lsof tar unzip sudo nano python3 python3-pip ca-certificates
elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm curl wget lsof tar unzip sudo nano python python-pip ca-certificates
elif command -v apk >/dev/null 2>&1; then
    apk update && apk add curl wget lsof tar unzip sudo nano python3 py3-pip ca-certificates
elif command -v zypper >/dev/null 2>&1; then
    zypper refresh && zypper install -y curl wget lsof tar unzip sudo nano python3 python3-pip ca-certificates
else
    error "Unsupported Linux distribution."
    exit 1
fi

ok "Dependencies installed successfully."

line

# =========================================================
# PORT AVAILABILITY CHECK
# =========================================================

if lsof -Pi :${PANEL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    warn "Port ${PANEL_PORT} is currently in use by another process:"
    echo
    lsof -i:${PANEL_PORT}
    echo
    read -rp "Enter a new port for HVM Panel (Default: 5001): " NEW_PORT
    PANEL_PORT="${NEW_PORT:-5001}"
    
    if lsof -Pi :${PANEL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
        error "Port ${PANEL_PORT} is also occupied. Installation aborted."
        exit 1
    fi
fi

info "HVM Panel will run on Port: ${PANEL_PORT}"

line

# =========================================================
# PREPARE DIRECTORY, DOWNLOAD & UNZIP
# =========================================================

info "Preparing installation directory at ${INSTALL_DIR}..."

rm -rf "${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

info "Downloading hvm-v8.zip..."

curl -L \
    --fail \
    --retry 5 \
    --retry-delay 3 \
    --progress-bar \
    -o "hvm-v8.zip" "${HVM_URL}"

echo

if [[ ! -f "hvm-v8.zip" ]] || [[ ! -s "hvm-v8.zip" ]]; then
    error "Download failed or hvm-v8.zip is empty."
    exit 1
fi

info "Extracting hvm-v8.zip..."
unzip -o hvm-v8.zip >/dev/null

# Zip আনজিপ হওয়ার পর hvm ফোল্ডারে ঢুকবে
if [[ -d "${INSTALL_DIR}/hvm" ]]; then
    cd "${INSTALL_DIR}/hvm"
    WORK_DIR="${INSTALL_DIR}/hvm"
else
    WORK_DIR="${INSTALL_DIR}"
fi

ok "Extracted zip file. Working Directory: ${WORK_DIR}"

# =========================================================
# PYTHON DEPENDENCIES & CHECK FOR HVM.PY
# =========================================================

if [[ -f "requirements.txt" ]]; then
    info "Installing Python dependencies from requirements.txt..."
    pip3 install --no-cache-dir -r requirements.txt || true
fi

# hvm.py ফাইল আছে কি না চেক করা
if [[ -f "hvm.py" ]]; then
    ok "Found hvm.py successfully."
else
    # যদি ফাইলের নাম একটু ভিন্ন কেসে বা সাবফোল্ডারে থাকে
    FOUND_HVM=$(find "${WORK_DIR}" -name "hvm.py" | head -n 1)
    if [[ -n "${FOUND_HVM}" ]]; then
        cd "$(dirname "${FOUND_HVM}")"
        WORK_DIR="$(pwd)"
        ok "Found hvm.py at ${WORK_DIR}"
    else
        error "hvm.py file not found inside the zip archive!"
        exit 1
    fi
fi

line

# =========================================================
# FIREWALL PORT CONFIGURATION
# =========================================================

info "Configuring system firewall rules..."

if command -v ufw >/dev/null 2>&1; then
    ufw allow ${PANEL_PORT}/tcp >/dev/null 2>&1 || true
fi

if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=${PANEL_PORT}/tcp >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
fi

if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport ${PANEL_PORT} -j ACCEPT >/dev/null 2>&1 || \
    iptables -I INPUT -p tcp --dport ${PANEL_PORT} -j ACCEPT >/dev/null 2>&1 || true
fi

ok "Firewall permissions configured."

line

# =========================================================
# CREDENTIALS SETUP
# =========================================================

ADMIN_USER="admin"
ADMIN_PASS=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12 ; echo '')

cat > "${CRED_FILE}" << EOF
HVM PANEL CREDENTIALS
=====================
URL      : http://localhost:${PANEL_PORT}
USERNAME : ${ADMIN_USER}
PASSWORD : ${ADMIN_PASS}
EOF

chmod 600 "${CRED_FILE}"

# =========================================================
# SYSTEMD SERVICE CONFIGURATION (RUNNING HVM.PY)
# =========================================================

PYTHON_BIN=$(which python3)

if command -v systemctl >/dev/null 2>&1; then

    info "Setting up Systemd Service to run hvm.py..."

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=HVM Panel V8 Ultra Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${WORK_DIR}
ExecStart=${PYTHON_BIN} ${WORK_DIR}/hvm.py --port ${PANEL_PORT}
Restart=always
RestartSec=5
LimitNOFILE=1048576
User=root
StandardOutput=append:${LOG_FILE}
StandardError=append:${LOG_FILE}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME} >/dev/null 2>&1
    systemctl restart ${SERVICE_NAME}

    sleep 4

    if systemctl is-active --quiet ${SERVICE_NAME}; then
        ok "HVM Systemd service successfully started (hvm.py)."
    else
        warn "Service started. Checking log output..."
        systemctl status ${SERVICE_NAME} --no-pager || true
    fi

else
    warn "Systemd not detected. Running hvm.py with nohup in background..."
    cd "${WORK_DIR}"
    nohup ${PYTHON_BIN} hvm.py --port ${PANEL_PORT} >> ${LOG_FILE} 2>&1 &
    sleep 3
fi

line

# =========================================================
# STATUS & PUBLIC IP RETRIEVAL
# =========================================================

if lsof -Pi :${PANEL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    PANEL_STATUS="${GREEN}ONLINE${NC}"
else
    PANEL_STATUS="${RED}OFFLINE${NC}"
fi

PUBLIC_IP=$(curl -4 -s --max-time 8 ifconfig.me || true)

if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP=$(hostname -I | awk '{print $1}')
fi

if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP="YOUR_SERVER_IP"
fi

# =========================================================
# INSTALLATION SUMMARY
# =========================================================

clear

echo -e "${GREEN}"
cat << EOF

╔══════════════════════════════════════════════════════════╗
║               HVM PANEL V8 ULTRA INSTALLED               ║
╚══════════════════════════════════════════════════════════╝

 STATUS            : ${PANEL_STATUS}
 PANEL URL         : http://${PUBLIC_IP}:${PANEL_PORT}

 ADMIN USERNAME    : ${ADMIN_USER}
 ADMIN PASSWORD    : ${ADMIN_PASS}

 INSTALL DIR       : ${WORK_DIR}
 SCRIPT FILE       : ${WORK_DIR}/hvm.py
 CREDENTIALS FILE  : ${CRED_FILE}
 LOG FILE          : ${LOG_FILE}
 SERVICE NAME      : ${SERVICE_NAME}

════════════════════════════════════════════════════════════

 SERVICE MANAGEMENT COMMANDS:

   systemctl start ${SERVICE_NAME}     # Start Panel
   systemctl stop ${SERVICE_NAME}      # Stop Panel
   systemctl restart ${SERVICE_NAME}   # Restart Panel
   systemctl status ${SERVICE_NAME}    # Check Status

 LIVE LOGS VIEWING:

   tail -f ${LOG_FILE}
   journalctl -u ${SERVICE_NAME} -f

════════════════════════════════════════════════════════════

EOF
echo -e "${NC}"
