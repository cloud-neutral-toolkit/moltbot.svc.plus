#!/usr/bin/env bash
# Multi-distribution installer for clawdbot.svc.plus
# Supports: Debian/Ubuntu, RHEL/CentOS/Rocky, Fedora, Arch Linux, openSUSE, macOS
set -euo pipefail

PROXY="${PROXY:-caddy}"
INSTALL_METHOD="${INSTALL_METHOD:-npm}"
GIT_REPO="${GIT_REPO:-https://github.com/cloud-neutral-toolkit/openclawbot.svc.plus.git}"
SOURCE_REPO="${SOURCE_REPO:-https://github.com/cloud-neutral-toolkit/openclawbot.svc.plus.git}"
CLAWDBOT_VERSION="${CLAWDBOT_VERSION:-latest}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
PUBLIC_SCHEME="https"
OS_FAMILY="linux"
OS_NAME="$(uname -s 2>/dev/null || true)"
PACKAGE_MANAGER=""
UPDATE_CMD=""
INSTALL_CMD=""

usage() {
  cat <<'EOF'
Usage:
  init_vhost.sh [domain]

Supported Distributions:
  - Debian/Ubuntu/Kali/Pop!_OS/Linux Mint (apt)
  - RHEL/CentOS/Rocky Linux/AlmaLinux/Oracle Linux (dnf/yum)
  - Fedora (dnf)
  - Arch Linux/Manjaro (pacman)
  - openSUSE/SUSE (zypper)
  - macOS (Homebrew)

Installation Modes:
  1. npm (default) - Install from npm registry: npm install -g clawdbot@latest
  2. git (source)  - Install from source: git clone and build from repository
  3. npm-alt       - Alternative npm package: npm install -g openclaw@latest

Defaults:
  - domain: current hostname (hostname -f, then hostname)
  - install mode: npm (set INSTALL_METHOD=git for source installation)
  - clawdbot version: "latest" (override with CLAWDBOT_VERSION env var)
  - proxy: Caddy with automatic TLS (set PROXY=nginx to use nginx+Certbot)
  - customize Certbot email via CERTBOT_EMAIL

Environment Variables:
  PROXY=caddy|nginx           - Web proxy selection
  INSTALL_METHOD=npm|git|npm-alt - Installation method
  CLAWDBOT_VERSION=latest     - Specific version to install
  CERTBOT_EMAIL=email         - Let's Encrypt email for certificates
  SOURCE_REPO=repo-url        - Source repository URL (for git mode)

Examples:
  # Install with defaults (npm mode + Caddy + auto TLS)
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/init_vhost.sh | bash

  # Install from source (git mode) with specific domain
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/init_vhost.sh | bash -s openclawbot.svc.plus INSTALL_METHOD=git

  # Install alternative npm package (openclaw)
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/init_vhost.sh | bash -s openclawbot.svc.plus INSTALL_METHOD=npm-alt

  # Install with nginx proxy
  curl -fsSL https://raw.githubusercontent.com/cloud-neutral-toolkit/openclawbot.svc.plus/main/scripts/init_vhost.sh | bash -s openclawbot.svc.plus PROXY=nginx

  # Install from custom repository
  SOURCE_REPO=https://github.com/your-org/openclawbot.svc.plus.git bash init_vhost.sh openclawbot.svc.plus INSTALL_METHOD=git

  # Install with specific version and email
  CLAWDBOT_VERSION=v1.2.3 CERTBOT_EMAIL=admin@example.com bash init_vhost.sh openclawbot.svc.plus

Source Installation Mode Details (INSTALL_METHOD=git):
  This mode will:
  - Clone the repository to /opt/openclawbot-svc-plus
  - Install dependencies with pnpm
  - Build the UI components (pnpm ui:build)
  - Build the application (pnpm build)
  - Install the built application globally
  - Set up the daemon service
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DOMAIN="${1:-}"
if [[ -z "$DOMAIN" ]]; then
  DOMAIN="$(hostname -f 2>/dev/null || true)"
  if [[ -z "$DOMAIN" ]]; then
    DOMAIN="$(hostname 2>/dev/null || true)"
  fi
fi

if [[ -z "$DOMAIN" ]]; then
  echo "Failed to determine domain (hostname). Pass one explicitly."
  exit 1
fi

PROXY="$(tr '[:upper:]' '[:lower:]' <<< "$PROXY")"
if [[ "$PROXY" != "caddy" && "$PROXY" != "nginx" ]]; then
  echo "Unsupported proxy mode '$PROXY'. Use 'caddy' or 'nginx'."
  exit 1
fi

INSTALL_METHOD="$(tr '[:upper:]' '[:lower:]' <<< "$INSTALL_METHOD")"
if [[ "$INSTALL_METHOD" != "npm" && "$INSTALL_METHOD" != "git" && "$INSTALL_METHOD" != "npm-alt" ]]; then
  echo "Unsupported install method '$INSTALL_METHOD'. Use 'npm', 'git', or 'npm-alt'."
  echo "  npm:    Install from npm registry (clawdbot@latest)"
  echo "  git:    Install from source code (git clone and build)"
  echo "  npm-alt: Install alternative npm package (openclaw@latest)"
  exit 1
fi

case "$OS_NAME" in
  Darwin)
    OS_FAMILY="darwin"
    ;;
  Linux)
    OS_FAMILY="linux"
    ;;
  *)
    echo "Unsupported OS: ${OS_NAME:-unknown}"
    exit 1
    ;;
esac

if [[ "$OS_FAMILY" == "linux" ]]; then
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
  else
    echo "Unsupported Linux (missing /etc/os-release)."
    exit 1
  fi
fi

# Determine package manager and validate supported distributions
if [[ "$OS_FAMILY" == "linux" ]]; then
  case "${ID:-}" in
    debian|ubuntu|kali|pop|linuxmint)
      PACKAGE_MANAGER="apt"
      UPDATE_CMD="apt-get update"
      INSTALL_CMD="apt-get install -y"
      ;;
    rhel|centos|fedora|rocky|almalinux|ol)
      PACKAGE_MANAGER="dnf"
      UPDATE_CMD="dnf check-update || true"
      INSTALL_CMD="dnf install -y"
      # For older RHEL/CentOS versions, fallback to yum
      if ! command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
        UPDATE_CMD="yum check-update || true"
        INSTALL_CMD="yum install -y"
      fi
      ;;
    arch|manjaro)
      PACKAGE_MANAGER="pacman"
      UPDATE_CMD="pacman -Sy"
      INSTALL_CMD="pacman -S --noconfirm"
      ;;
    opensuse*|suse*)
      PACKAGE_MANAGER="zypper"
      UPDATE_CMD="zypper refresh"
      INSTALL_CMD="zypper install -y"
      ;;
    *)
      echo "Unsupported Linux distribution: ${ID:-unknown}"
      echo "This installer supports: Debian/Ubuntu, RHEL/CentOS/Rocky, Fedora, Arch, openSUSE"
      exit 1
      ;;
  esac
fi

as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    # Allow callers to pass sudo-style flags without breaking root execution.
    if [[ "${1:-}" == "-E" ]]; then
      shift
    fi
    "$@"
  else
    sudo "$@"
  fi
}

run_as_user() {
  local user="${SUDO_USER:-$USER}"
  if [[ "$user" == "root" ]]; then
    echo "Run this installer as a non-root user (with sudo available)."
    exit 1
  fi
  sudo -u "$user" -H "$@"
}

ensure_node24() {
  local need_install=1
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "${major:-0}" -ge 24 ]]; then
      need_install=0
    fi
  fi
  if [[ "$need_install" -eq 1 ]]; then
    # Install base dependencies
    case "$PACKAGE_MANAGER" in
      apt)
        as_root $UPDATE_CMD
        as_root $INSTALL_CMD curl ca-certificates
        if [[ $(id -u) -eq 0 ]]; then
          curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
        else
          curl -fsSL https://deb.nodesource.com/setup_24.x | as_root -E bash -
        fi
        as_root $INSTALL_CMD nodejs
        ;;
      dnf|yum)
        as_root $UPDATE_CMD
        as_root $INSTALL_CMD curl ca-certificates
        # Install NodeSource repository
        curl -fsSL https://rpm.nodesource.com/setup_24.x | as_root bash -
        as_root $INSTALL_CMD nodejs
        ;;
      pacman)
        as_root $UPDATE_CMD
        as_root $INSTALL_CMD curl ca-certificates
        as_root $INSTALL_CMD nodejs npm
        ;;
      zypper)
        as_root $UPDATE_CMD
        as_root $INSTALL_CMD curl ca-certificates nodejs npm
        ;;
    esac
  fi
}

ensure_node24_darwin() {
  local need_install=1
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    if [[ "${major:-0}" -ge 24 ]]; then
      need_install=0
    fi
  fi
  if [[ "$need_install" -eq 1 ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew install node@24 || brew install node
      if brew list node@24 >/dev/null 2>&1; then
        brew link --overwrite --force node@24
      fi
    else
      local arch pkg_name pkg_url pkg_path
      arch="$(uname -m)"
      case "$arch" in
        arm64) arch="arm64" ;;
        x86_64) arch="x64" ;;
        *)
          echo "Unsupported macOS architecture: ${arch}"
          exit 1
          ;;
      esac
      pkg_name="$(curl -fsSL https://nodejs.org/dist/latest-v24.x/ \
        | awk -F\" -v arch="$arch" '/node-v24.*-darwin-/{if ($2 ~ ("-darwin-" arch "\\.pkg$")) {print $2; exit}}')"
      if [[ -z "$pkg_name" ]]; then
        echo "Failed to find a Node.js v24 macOS installer."
        exit 1
      fi
      pkg_url="https://nodejs.org/dist/latest-v24.x/${pkg_name}"
      pkg_path="/tmp/${pkg_name}"
      curl -fsSL "$pkg_url" -o "$pkg_path"
      as_root installer -pkg "$pkg_path" -target /
    fi
  fi
}

ensure_packages() {
  local packages=(git curl ca-certificates)
  # Add firewall based on package manager
  case "$PACKAGE_MANAGER" in
    apt) packages+=(ufw) ;;
    dnf|yum) packages+=(firewalld) ;;
    pacman) packages+=(iptables) ;;
    zypper) packages+=(firewalld) ;;
  esac

  # Add proxy packages
  if [[ "$PROXY" == "nginx" ]]; then
    case "$PACKAGE_MANAGER" in
      apt) packages+=(nginx certbot python3-certbot-nginx) ;;
      dnf|yum) packages+=(nginx certbot python3-certbot-nginx) ;;
      pacman) packages+=(nginx certbot) ;;
      zypper) packages+=(nginx certbot) ;;
    esac
  else
    case "$PACKAGE_MANAGER" in
      apt) packages+=(caddy) ;;
      dnf|yum) packages+=(caddy) ;;
      pacman) packages+=(caddy) ;;
      zypper) packages+=(caddy) ;;
    esac
  fi

  as_root $UPDATE_CMD
  as_root $INSTALL_CMD "${packages[@]}"
}

ensure_packages_darwin() {
  if [[ "$PROXY" == "nginx" ]]; then
    echo "nginx + Certbot is not supported on macOS in this installer. Use PROXY=caddy."
    exit 1
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required on macOS. Install it from https://brew.sh and re-run."
    exit 1
  fi
  brew install git caddy curl
}

ensure_pnpm() {
  run_as_user corepack enable
  run_as_user corepack prepare pnpm@latest --activate
}

configure_firewall() {
  local ports=(22/tcp 80/tcp 443/tcp 18789/tcp)
  for port in "${ports[@]}"; do
    as_root ufw allow "${port}" >/dev/null
  done
  as_root ufw default allow outgoing >/dev/null
  as_root ufw default deny incoming >/dev/null
  if as_root ufw status | grep -q "Status: inactive"; then
    as_root ufw --force enable >/dev/null
  fi
}

configure_firewall_darwin() {
  # macOS uses application-level firewall; leave port management to the operator.
  return 0
}

install_clawdbot_npm() {
  as_root npm install -g "clawdbot@${CLAWDBOT_VERSION}"
}

install_clawdbot_npm_alt() {
  as_root npm install -g "openclaw@${CLAWDBOT_VERSION}"
}

install_clawdbot_git() {
  local install_dir="/opt/openclawbot-svc-plus"
  if [[ ! -d "$install_dir" ]]; then
    run_as_user mkdir -p "$install_dir"
    run_as_user git clone "$SOURCE_REPO" "$install_dir"
  else
    run_as_user git -C "$install_dir" fetch --all --prune
    run_as_user git -C "$install_dir" checkout main
    run_as_user git -C "$install_dir" reset --hard origin/main
  fi
  run_as_user bash -c "cd $install_dir && pnpm install && pnpm ui:build && pnpm build"
  run_as_user npm install -g "$install_dir"
}

install_clawdbot() {
  case "$INSTALL_METHOD" in
    git)
      install_clawdbot_git
      ;;
    npm-alt)
      install_clawdbot_npm_alt
      ;;
    npm|*)
      install_clawdbot_npm
      ;;
  esac
}

configure_clawdbot() {
  run_as_user clawdbot onboard --install-daemon
  run_as_user clawdbot config set gateway.trustedProxies.0 127.0.0.1
}

configure_nginx() {
  local vhost="/etc/nginx/sites-available/clawdbot-${DOMAIN}.conf"
  if [[ ! -f "$vhost" ]]; then
    cat <<EOF | as_root tee "$vhost" >/dev/null
server {
  listen 80;
  server_name ${DOMAIN};

  location / {
    proxy_pass http://127.0.0.1:18789;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
EOF
  fi
  as_root ln -sf "$vhost" "/etc/nginx/sites-enabled/$(basename "$vhost")"
  as_root nginx -t
  as_root systemctl enable --now nginx
  as_root systemctl reload nginx
}

configure_nginx_rhel() {
  local vhost="/etc/nginx/conf.d/clawdbot-${DOMAIN}.conf"
  if [[ ! -f "$vhost" ]]; then
    cat <<EOF | as_root tee "$vhost" >/dev/null
server {
  listen 80;
  server_name ${DOMAIN};

  location / {
    proxy_pass http://127.0.0.1:18789;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
EOF
  fi
  as_root nginx -t
  as_root systemctl enable --now nginx
  as_root systemctl reload nginx
}

configure_caddy() {
  local service="/etc/caddy/Caddyfile"
  if [[ "$OS_FAMILY" == "darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      service="$(brew --prefix)/etc/Caddyfile"
    fi
  fi
  cat <<EOF | as_root tee "$service" >/dev/null
${DOMAIN} {
  reverse_proxy 127.0.0.1:18789
}
EOF
  if [[ "$OS_FAMILY" == "darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew services start caddy || brew services restart caddy
    else
      as_root caddy start --config "$service"
    fi
  else
    as_root systemctl enable --now caddy
    as_root systemctl reload caddy
  fi
}

configure_nginx_distro() {
  case "$PACKAGE_MANAGER" in
    apt|zypper)
      configure_nginx
      ;;
    dnf|yum|pacman)
      configure_nginx_rhel
      ;;
  esac
}

configure_firewall() {
  case "$PACKAGE_MANAGER" in
    apt)
      local ports=(22/tcp 80/tcp 443/tcp 18789/tcp)
      for port in "${ports[@]}"; do
        as_root ufw allow "${port}" >/dev/null
      done
      as_root ufw default allow outgoing >/dev/null
      as_root ufw default deny incoming >/dev/null
      if as_root ufw status | grep -q "Status: inactive"; then
        as_root ufw --force enable >/dev/null
      fi
      ;;
    dnf|yum|zypper)
      as_root systemctl enable --now firewalld
      as_root firewall-cmd --permanent --add-port=22/tcp
      as_root firewall-cmd --permanent --add-port=80/tcp
      as_root firewall-cmd --permanent --add-port=443/tcp
      as_root firewall-cmd --permanent --add-port=18789/tcp
      as_root firewall-cmd --reload
      ;;
    pacman)
      as_root systemctl enable --now iptables
      as_root iptables -A INPUT -p tcp --dport 22 -j ACCEPT
      as_root iptables -A INPUT -p tcp --dport 80 -j ACCEPT
      as_root iptables -A INPUT -p tcp --dport 443 -j ACCEPT
      as_root iptables -A INPUT -p tcp --dport 18789 -j ACCEPT
      as_root iptables-save > /etc/iptables/iptables.rules
      ;;
  esac
}

configure_certbot() {
  local email_args=("--register-unsafely-without-email")
  if [[ -n "$CERTBOT_EMAIL" ]]; then
    email_args=("--email" "$CERTBOT_EMAIL" "--agree-tos" "--no-eff-email")
  fi
  as_root certbot --nginx "${email_args[@]}" --redirect -d "$DOMAIN" || true
}

configure_caddy() {
  local service="/etc/caddy/Caddyfile"
  if [[ "$OS_FAMILY" == "darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      service="$(brew --prefix)/etc/Caddyfile"
    fi
  fi
  cat <<EOF | as_root tee "$service" >/dev/null
${DOMAIN} {
  reverse_proxy 127.0.0.1:18789
}
EOF
  if [[ "$OS_FAMILY" == "darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew services start caddy || brew services restart caddy
    else
      as_root caddy start --config "$service"
    fi
  else
    as_root systemctl enable --now caddy
    as_root systemctl reload caddy
  fi
}

configure_proxy() {
  if [[ "$PROXY" == "nginx" ]]; then
    configure_nginx_distro
    configure_certbot
  else
    configure_caddy
  fi
}

health_check_url() {
  local url="$1"
  for i in $(seq 1 5); do
    if curl -fsS --max-time 5 --retry 3 --retry-delay 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

run_health_checks() {
  if ! health_check_url http://127.0.0.1:18789; then
    echo "Warning: local gateway health check failed."
  fi
  local target="${PUBLIC_SCHEME}://${DOMAIN}"
  if ! health_check_url "${target}"; then
    echo "Warning: public health check failed for ${target}. TLS might not be active yet."
  fi
}

echo "==> Domain: ${DOMAIN}"
if [[ "$OS_FAMILY" == "darwin" ]]; then
  ensure_packages_darwin
  ensure_node24_darwin
else
  ensure_packages
  ensure_node24
fi
ensure_pnpm
if [[ "$OS_FAMILY" == "darwin" ]]; then
  configure_firewall_darwin
else
  configure_firewall
fi
install_clawdbot
configure_clawdbot
configure_proxy
run_health_checks

cat <<EOF

Done.
Gateway is listening on http://127.0.0.1:18789 and proxied via ${PUBLIC_SCHEME}://${DOMAIN}.
Access control and TLS are handled by ${PROXY^^}.

If you need to tweak config later:
  - \`clawdbot config get gateway.trustedProxies\`
EOF

if [[ "$OS_FAMILY" == "darwin" ]]; then
  cat <<'EOF'
  - `tail -f /tmp/clawdbot/clawdbot-gateway.log`
EOF
else
  cat <<'EOF'
  - `journalctl --user -u clawdbot-gateway --no-pager`
EOF
fi
