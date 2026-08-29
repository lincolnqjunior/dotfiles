#!/bin/bash
# first-boot.sh - Omarchy bring-up via Tailscale and VPS restore.
# Run as the desktop user. The script requests sudo only when needed.
set -euo pipefail

if (( EUID == 0 )); then
  echo "Run this script as your desktop user, without 'sudo bash'." >&2
  exit 1
fi

VPS=${VPS:-lincoln@hermes-agent}
TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME:-omarchy-desktop}

if [[ -r $HOME/.config/opencode/.env.keys ]]; then
  sed -i '1s/^\xEF\xBB\xBF//' "$HOME/.config/opencode/.env.keys"
  set -a
  source "$HOME/.config/opencode/.env.keys"
  set +a
fi

echo "=== Omarchy bootstrap v2026-08-29 ==="
echo "  user : $USER@$(hostname)"
echo "  date : $(date)"
echo

echo "[1/8] Installing system packages..."
sudo pacman -S --noconfirm --needed \
  tailscale curl wget git openssh p7zip jq unzip base-devel uv

echo "[2/8] Starting tailscaled..."
sudo systemctl enable --now tailscaled.service

echo "[3/8] Authenticating Tailscale..."
if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; then
  echo "  Tailscale is already online."
else
  tailscale_args=(up "--hostname=$TAILSCALE_HOSTNAME")
  if [[ -n ${TS_AUTHKEY:-} ]]; then
    tailscale_args+=("--auth-key=$TS_AUTHKEY")
  fi
  sudo tailscale "${tailscale_args[@]}"
fi

echo "  Waiting for Tailscale Online..."
for _ in {1..30}; do
  if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; then
    echo "  Tailscale up: $(tailscale ip -4)"
    break
  fi
  sleep 2
done

if ! tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; then
  echo "Tailscale did not become ready." >&2
  exit 1
fi

echo "[4/8] Pulling SSH keys from VPS..."
bootstrap_dir="$HOME/bootstrap"
mkdir -p "$bootstrap_dir"
scp -o StrictHostKeyChecking=accept-new \
  "$VPS:/home/lincoln/backups/ssh-keys-*.7z" "$bootstrap_dir/"

bundles=("$bootstrap_dir"/ssh-keys-*.7z)
if [[ ! -f ${bundles[0]} ]]; then
  echo "No SSH key bundle was downloaded." >&2
  exit 1
fi
ssh_bundle=${bundles[-1]}
chmod 600 "$ssh_bundle"

bundle_password=${SSH_BUNDLE_PASSWORD:-}
if [[ -z $bundle_password ]]; then
  read -rsp "SSH bundle password: " bundle_password </dev/tty
  printf '\n' >/dev/tty
fi

extract_dir=$(mktemp -d "$bootstrap_dir/extracted.XXXXXX")
trap 'rm -rf "$extract_dir"' EXIT
7z x "$ssh_bundle" "-p$bundle_password" "-o$extract_dir" -y >/dev/null
unset bundle_password

if [[ -d $HOME/.ssh ]]; then
  cp -a "$HOME/.ssh" "$HOME/.ssh.pre-bootstrap-$(date +%Y%m%d-%H%M%S)"
fi
install -d -m 700 "$HOME/.ssh"
[[ -f $extract_dir/config ]] && install -m 600 "$extract_dir/config" "$HOME/.ssh/config"
for key in id_ed25519 id_sddc gh_ed25519 gha_key; do
  if [[ -f $extract_dir/$key && -f $extract_dir/$key.pub ]]; then
    install -m 600 "$extract_dir/$key" "$HOME/.ssh/$key"
    install -m 644 "$extract_dir/$key.pub" "$HOME/.ssh/$key.pub"
  fi
done

echo "[5/8] Pulling application secrets from VPS..."
mkdir -p "$HOME/.config/opencode" "$HOME/.honcho"
scp -o StrictHostKeyChecking=accept-new \
  "$VPS:/home/lincoln/backups/env-keys-template.txt" \
  "$HOME/.config/opencode/.env.keys"
sed -i '1s/^\xEF\xBB\xBF//' "$HOME/.config/opencode/.env.keys"
chmod 600 "$HOME/.config/opencode/.env.keys"

if scp -o StrictHostKeyChecking=accept-new \
  "$VPS:/home/lincoln/.honcho/config.json" "$HOME/.honcho/config.json"; then
  chmod 600 "$HOME/.honcho/config.json"
else
  echo "  WARNING: Honcho config could not be restored."
fi

set -a
source "$HOME/.config/opencode/.env.keys"
set +a
unset TS_AUTHKEY

if ! grep -Fq '.config/opencode/.env.keys' "$HOME/.bashrc"; then
  cat >>"$HOME/.bashrc" <<'EOF'

if [[ -r "$HOME/.config/opencode/.env.keys" ]]; then
  set -a
  source "$HOME/.config/opencode/.env.keys"
  set +a
  unset TS_AUTHKEY
fi
EOF
fi

if ! grep -Fq '.memorygraph/neo4j.env' "$HOME/.bashrc"; then
  cat >>"$HOME/.bashrc" <<'EOF'

if [[ -r "$HOME/.memorygraph/neo4j.env" ]]; then
  export MEMORY_BACKEND=memgraph
  set -a
  source "$HOME/.memorygraph/neo4j.env"
  set +a
fi
EOF
fi

if ! grep -Fq 'CONTEXT_MODE_DATA_DIR=' "$HOME/.bashrc"; then
  cat >>"$HOME/.bashrc" <<'EOF'

export CONTEXT_MODE_DATA_DIR="$HOME/.local/share/opencode"
export CONTEXT_MODE_DIR="$CONTEXT_MODE_DATA_DIR/context-mode"
EOF
fi

if ! grep -Fq '.config/opencode/bin:$PATH' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/.config/opencode/bin:$PATH"' >>"$HOME/.bashrc"
fi

echo "[6/8] Restoring dotfiles..."
if [[ -d $HOME/dotfiles-checkout/.git ]]; then
  git -C "$HOME/dotfiles-checkout" pull --ff-only
else
  git clone https://github.com/lincolnqjunior/dotfiles.git "$HOME/dotfiles-checkout"
fi
bash "$HOME/dotfiles-checkout/restore.sh" "$HOME/dotfiles-checkout"

echo "[7/8] Installing OpenCode CLI..."
if ! command -v opencode >/dev/null; then
  curl -fsSL https://opencode.ai/install | bash
fi
export PATH="$HOME/.local/bin:$PATH"
if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$HOME/.bashrc"
fi

echo
echo "[8/8] Smoke test ==="
echo "  Tailscale : $(tailscale status --json 2>/dev/null | jq -r .BackendState)"
echo "  VPS ssh   : $(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$VPS" 'echo OK' 2>&1 | head -1)"
echo "  Honcho    : $(curl -s --max-time 5 http://100.99.168.33:8000/health)"
echo "  9router   : $(curl -s --max-time 5 http://100.99.168.33:20128/api/health)"
echo "  opencode  : $(opencode --version 2>&1 || echo MISSING)"

echo
echo "=== Bootstrap complete ==="
echo "Restart OpenCode to load the restored configuration."
