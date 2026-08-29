#!/bin/bash
# Omarchy dotfiles restore â€” run after tailscale up + .env.keys restored
set -e

DOTFILES_DIR="${1:-$HOME/dotfiles-checkout}"

if [ ! -d "$DOTFILES_DIR" ]; then
    echo "Cloning dotfiles..."
    git clone https://github.com/lincolnqjunior/dotfiles.git "$DOTFILES_DIR"
fi

# Load .env.keys
if [ ! -f "$HOME/.config/opencode/.env.keys" ]; then
    echo "ERROR: ~/.config/opencode/.env.keys missing."
    echo "Restore from VPS: scp lincoln@hermes-agent:~/infra/9router/.env ~/.config/opencode/.env.keys"
    echo "Or restore from BW vault (preferred)."
    exit 1
fi

set -a; source "$HOME/.config/opencode/.env.keys"; set +a

# Symlink dotfiles to home
link_file() {
    local src="$1" dst="$2"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        mv "$dst" "$dst.bak-$(date +%s)"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst"
}

[ -f "$DOTFILES_DIR/home/.config/opencode/opencode.jsonc" ] && link_file "$DOTFILES_DIR/home/.config/opencode/opencode.jsonc" "$HOME/.config/opencode/opencode.jsonc"
[ -d "$DOTFILES_DIR/home/.config/opencode/agents" ] && link_file "$DOTFILES_DIR/home/.config/opencode/agents" "$HOME/.config/opencode/agents"
[ -d "$DOTFILES_DIR/home/.config/opencode/prompts" ] && link_file "$DOTFILES_DIR/home/.config/opencode/prompts" "$HOME/.config/opencode/prompts"
[ -d "$DOTFILES_DIR/home/.agents/skills" ] && link_file "$DOTFILES_DIR/home/.agents/skills" "$HOME/.agents/skills"
[ -f "$DOTFILES_DIR/home/.ssh/config" ] && link_file "$DOTFILES_DIR/home/.ssh/config" "$HOME/.ssh/config"
[ -f "$DOTFILES_DIR/home/.honcho/config.json.example" ] && cp "$DOTFILES_DIR/home/.honcho/config.json.example" "$HOME/.honcho/config.json" 2>/dev/null || true

chmod 600 "$HOME/.ssh/config" 2>/dev/null
chmod 700 "$HOME/.ssh" 2>/dev/null

echo "âœ“ Dotfiles restore complete. Run: opencode --version"
