#!/bin/bash
# first-boot.sh â€” Omarchy 4.0.1 bring-up from Windows 11
# Author: TARS, 2026-08-29
# Run once on first Omarchy login as the regular user (will sudo for system changes).
set -e

TS_AUTHKEY="tskey-auth-krZeM8sG7G11CNTRL-zCTdFjzRKXE7DgZtVPvDXED3JViRpB4j"
VPS_HOST="lincoln@hermes-agent"
BW_PASS="Bolodebanana11*"

echo "=== Omarchy bootstrap v2026-08-29 ==="
echo "Run from: $USER@$(hostname) at $(date)"

# 1. Refresh pacman + install tailscale + opencode deps + tools
echo "[1/8] Installing system packages..."
sudo pacman -Sy --noconfirm --needed \
    tailscale curl wget git openssh mise btop bat eza zoxide fzf lazygit git-delta jq unzip base-devel

# 2. Enable + start tailscaled
echo "[2/8] Starting tailscaled..."
sudo systemctl enable --now tailscaled
sleep 3

# 3. Authenticate Tailscale (uses the key already set in TS_AUTHKEY above)
echo "[3/8] Authenticating Tailscale..."
sudo tailscale up --auth-key="$TS_AUTHKEY" --hostname="omarchy-desktop"

# Wait for Online state
echo "  Waiting for Tailscale Online..."
for i in {1..30}; do
    if sudo tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
        TS_IP=$(sudo tailscale ip -4)
        echo "  âœ“ Tailscale up: $TS_IP"
        break
    fi
    sleep 2
done

# 4. Pull SSH keys bundle from VPS
echo "[4/8] Pulling SSH keys from VPS..."
mkdir -p ~/bootstrap && cd ~/bootstrap
scp -o StrictHostKeyChecking=accept-new "$VPS_HOST:/home/lincoln/backups/ssh-keys-"*.7z ./
SSH_BUNDLE=$(ls ssh-keys-*.7z | head -1)
7z x "$SSH_BUNDLE" -p"$BW_PASS"
mkdir -p ~/.ssh
cp ssh-keys-*/id_* ssh-keys-*/gha_key ssh-keys-*/known_hosts ssh-keys-*/config ~/.ssh/ 2>/dev/null || true
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_* ~/.ssh/gha_key 2>/dev/null
chmod 644 ~/.ssh/*.pub 2>/dev/null
chmod 600 ~/.ssh/config ~/.ssh/known_hosts 2>/dev/null
cd ~

# 5. Pull opencode .env.keys from VPS
echo "[5/8] Pulling opencode secrets from VPS..."
mkdir -p ~/.config/opencode
# Get a token from VPS (only sends env var values, not file)
scp "$VPS_HOST:/home/lincoln/backups/env-keys-template.txt" ~/.config/opencode/.env.keys 2>/dev/null || {
    echo "  No .env.keys on VPS â€” will need manual BW unlock"
    touch ~/.config/opencode/.env.keys
    chmod 600 ~/.config/opencode/.env.keys
}

# 6. Restore dotfiles via restore.sh
echo "[6/8] Restoring dotfiles..."
git clone https://github.com/lincolnqjunior/dotfiles.git ~/dotfiles-checkout
bash ~/dotfiles-checkout/restore.sh ~/dotfiles-checkout

# 7. Install opencode CLI
echo "[7/8] Installing opencode CLI..."
curl -fsSL https://opencode.ai/install | bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"

# 8. Smoke test
echo ""
echo "[8/8] Smoke test ==="
echo "  Tailscale : $(sudo tailscale status --json 2>/dev/null | jq -r .BackendState)"
echo "  VPS ssh   : $(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new $VPS_HOST 'echo OK' 2>&1 | head -1)"
echo "  Honcho    : $(curl -s --max-time 5 http://100.99.168.33:8000/health)"
echo "  9router   : $(curl -s --max-time 5 http://100.99.168.33:20128/api/health)"
echo "  opencode  : $(~/.local/bin/opencode --version 2>&1 || echo MISSING)"

echo ""
echo "=== Bootstrap complete. Next steps ==="
echo "  1. bw login"
echo "  2. export BW_SESSION=\$(bw unlock --raw)"
echo "  3. source ~/.config/opencode/.env.keys"
echo "  4. opencode (verify config)"
echo "  5. @escriba resume"
