#!/bin/bash
# first-boot.sh — Omarchy 4.0.1 bring-up via Tailscale -> VPS pull
# Author: TARS, 2026-08-29
# Run on first Omarchy login as your user (will prompt for sudo).
set -euo pipefail

TS_AUTHKEY="tskey-auth-krZeM8sG7G11CNTRL-zCTdFjzRKXE7DgZtVPvDXED3JViRpB4j"
VPS="lincoln@hermes-agent"
BW_PASS="Bolodebanana11*"

echo "=== Omarchy bootstrap v2026-08-29 ==="
echo "  user : $USER@$(hostname)"
echo "  date : $(date)"
echo ""

# -- 1. System packages (pacman defaults; AUR packages deferred) -----------
echo "[1/8] Installing system packages..."
sudo pacman -Sy --noconfirm --needed \
    tailscale curl wget git openssh p7zip jq unzip base-devel openssh

# -- 2. Start tailscaled ---------------------------------------------------
echo "[2/8] Starting tailscaled..."
sudo systemctl enable --now tailscaled
sleep 3

# -- 3. Tailscale auth -----------------------------------------------------
echo "[3/8] Authenticating Tailscale..."
sudo tailscale up --auth-key="$TS_AUTHKEY" --hostname="omarchy-desktop"

echo "  Waiting for Tailscale Online..."
for i in {1..30}; do
    if sudo tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
        TS_IP=$(sudo tailscale ip -4)
        echo "  Tailscale up: $TS_IP"
        break
    fi
    sleep 2
done

# -- 4. Pull SSH keys bundle from VPS ------------------------------------
echo "[4/8] Pulling SSH keys from VPS..."
mkdir -p ~/bootstrap && cd ~/bootstrap
scp -o StrictHostKeyChecking=accept-new "$VPS:/home/lincoln/backups/ssh-keys-"*.7z ./
SSH_BUNDLE=$(ls ssh-keys-*.7z | head -1)
7z x "$SSH_BUNDLE" -p"$BW_PASS" >/dev/null
mkdir -p ~/.ssh
chmod 700 ~/.ssh
[ -d ssh-keys-* ] && cp -r ssh-keys-*/. ~/.ssh/ 2>/dev/null || \
    cp ssh-keys-*/* ~/.ssh/ 2>/dev/null || true
chmod 600 ~/.ssh/id_* ~/.ssh/gha_key ~/.ssh/config ~/.ssh/known_hosts 2>/dev/null || true
chmod 644 ~/.ssh/*.pub 2>/dev/null || true
cd ~

# -- 5. Pull opencode .env.keys from VPS ----------------------------------
echo "[5/8] Pulling opencode secrets from VPS..."
mkdir -p ~/.config/opencode
scp -o StrictHostKeyChecking=accept-new "$VPS:/home/lincoln/backups/env-keys-template.txt" ~/.config/opencode/.env.keys
chmod 600 ~/.config/opencode/.env.keys
set -a; source ~/.config/opencode/.env.keys; set +a

# -- 6. Restore dotfiles via restore.sh ----------------------------------
echo "[6/8] Restoring dotfiles..."
git clone https://github.com/lincolnqjunior/dotfiles.git ~/dotfiles-checkout
bash ~/dotfiles-checkout/restore.sh ~/dotfiles-checkout

# -- 7. Install opencode CLI ----------------------------------------------
echo "[7/8] Installing opencode CLI..."
curl -fsSL https://opencode.ai/install | bash
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# -- 8. Smoke test --------------------------------------------------------
echo ""
echo "[8/8] Smoke test ==="
echo "  Tailscale : $(sudo tailscale status --json 2>/dev/null | jq -r .BackendState)"
echo "  VPS ssh   : $(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new $VPS 'echo OK' 2>&1 | head -1)"
echo "  Honcho    : $(curl -s --max-time 5 http://100.99.168.33:8000/health)"
echo "  9router   : $(curl -s --max-time 5 http://100.99.168.33:20128/api/health)"
echo "  opencode  : $(~/.local/bin/opencode --version 2>&1 || echo MISSING)"

echo ""
echo "=== Bootstrap complete ==="
echo "  Next steps:"
echo "    1. bw login"
echo "    2. export BW_SESSION=\$(bw unlock --raw)"
echo "    3. source ~/.config/opencode/.env.keys"
echo "    4. opencode   (verify config loads)"
echo "    5. @escriba resume"
