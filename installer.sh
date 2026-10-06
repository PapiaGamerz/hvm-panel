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

BIN_FILE="${INSTALL_DIR}/hvm.bin"
LOG_FILE="/var/log/hvm.log"
CRED_FILE="${INSTALL_DIR}/admin_credentials.txt"

# Zip ফাইল সাধারণত 2MB মতো, তাই ১MB মিনিমাম থ্রেশহোল্ড রাখা হলো
MIN_FILE_SIZE_MB=1

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

       HVM PANEL V9 ULTRA INSTALLER
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

info "Installing required system dependencies..."

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
# PREPARE INSTALL DIRECTORY
# =========================================================

info "Preparing installation directory at ${INSTALL_DIR}..."

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

ok "Directory created and set."

line

# =========================================================
# ZIP DOWNLOAD, UNZIP & INTEGRITY CHECK
# =========================================================

info "Downloading HVM Core Archive (.zip)..."

rm -f hvm.zip hvm.bin

curl -L \
    --fail \
    --retry 5 \
    --retry-delay 3 \
    --progress-bar \
    -o hvm.zip "${HVM_URL}"

echo

if [[ ! -f hvm.zip ]] || [[ ! -s hvm.zip ]]; then
    error "Download failed or downloaded zip file is empty."
    exit 1
fi

FILE_SIZE_MB=$(du -m hvm.zip | cut -f1)

info "Downloaded Zip Size: ${FILE_SIZE_MB} MB"

if [[ "${FILE_SIZE_MB}" -lt "${MIN_FILE_SIZE_MB}" ]]; then
    error "Archive validation failed: File size is smaller than expected (${MIN_FILE_SIZE_MB}MB)."
    file hvm.zip || true
    exit 1
fi

info "Extracting Zip Archive..."
unzip -o hvm.zip -d "${INSTALL_DIR}" >/dev/null

# যদি Unzip করার পর hvm.bin সরাসরি না আসে তবে প্রাপ্ত বাইনারি ফাইলের নাম hvm.bin দেওয়া
if [[ ! -f "${BIN_FILE}" ]]; then
    EXTRACTED_BIN=$(find "${INSTALL_DIR}" -type f ! -name "hvm.zip" ! -name "*.txt" | head -n 1)
    if [[ -n "${EXTRACTED_BIN}" ]]; then
        mv "${EXTRACTED_BIN}" "${BIN_FILE}"
    else
        error "No executable binary found inside the zip package."
        exit 1
    fi
fi

chmod +x "${BIN_FILE}"
rm -f hvm.zip

ok "Package downloaded, extracted, and verified successfully."

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
# SYSTEMD SERVICE CONFIGURATION
# =========================================================

if command -v systemctl >/dev/null 2>&1; then

    info "Setting up Systemd Service..."

cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=HVM Panel V9 Ultra Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_FILE} --port ${PANEL_PORT}
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
        ok "HVM Systemd service successfully started."
    else
        error "Failed to start HVM service."
        echo
        systemctl status ${SERVICE_NAME} --no-pager
        echo
        exit 1
    fi

else
    warn "Systemd not detected. Executing background job with nohup..."
    nohup ${BIN_FILE} --port ${PANEL_PORT} >> ${LOG_FILE} 2>&1 &
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
║               HVM PANEL V9 ULTRA INSTALLED               ║
╚══════════════════════════════════════════════════════════╝

 STATUS            : ${PANEL_STATUS}
 PANEL URL         : http://${PUBLIC_IP}:${PANEL_PORT}

 ADMIN USERNAME    : ${ADMIN_USER}
 ADMIN PASSWORD    : ${ADMIN_PASS}

 INSTALL DIR       : ${INSTALL_DIR}
 BINARY FILE       : ${BIN_FILE}
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
