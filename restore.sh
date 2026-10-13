#!/bin/bash
# Omarchy dotfiles restore - run after Tailscale and .env.keys are restored.
set -euo pipefail

DOTFILES_DIR="${1:-$HOME/dotfiles-checkout}"

if [[ ! -d $DOTFILES_DIR ]]; then
  echo "Cloning dotfiles..."
  git clone https://github.com/lincolnqjunior/dotfiles.git "$DOTFILES_DIR"
fi

if [[ ! -f $HOME/.config/opencode/.env.keys ]]; then
  echo "ERROR: ~/.config/opencode/.env.keys missing."
  echo "Restore it from the VPS or the Bitwarden vault."
  exit 1
fi

set -a
source "$HOME/.config/opencode/.env.keys"
set +a

backup_suffix="bak-$(date +%Y%m%d-%H%M%S)"

link_file() {
  local src=$1 dst=$2
  if [[ ( -e $dst || -L $dst ) && ! -L $dst ]]; then
    mv "$dst" "$dst.$backup_suffix"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
}

link_entries() {
  local src_dir=$1 dst_dir=$2 entry
  [[ -d $src_dir ]] || return 0
  mkdir -p "$dst_dir"
  for entry in "$src_dir"/*; do
    [[ -e $entry ]] || continue
    link_file "$entry" "$dst_dir/$(basename "$entry")"
  done
}

config_src="$DOTFILES_DIR/home/.config/opencode/opencode.jsonc"
[[ -f $config_src ]] && link_file "$config_src" "$HOME/.config/opencode/opencode.json"
link_entries "$DOTFILES_DIR/home/.config/opencode/agents" "$HOME/.config/opencode/agents"
link_entries "$DOTFILES_DIR/home/.config/opencode/prompts" "$HOME/.config/opencode/prompts"
link_entries "$DOTFILES_DIR/home/.config/opencode/plugins" "$HOME/.config/opencode/plugins"
# QL5 (#228): o plugin do statusline tem imports BARE (solid-js, @opentui/*) e,
# symlinkado, resolve pelo realpath — ou seja, a partir de dentro do checkout.
# Sem este link, `node_modules` fica fora da árvore e o plugin morre com
# ERR_MODULE_NOT_FOUND, em silêncio (mesma classe do 9a1de0e, que era para
# import relativo; aqui é para import bare). node_modules é gitignored, então o
# link precisa ser refeito a cada restore.
ln -sfn "$HOME/.config/opencode/plugins/node_modules" "$DOTFILES_DIR/home/.config/opencode/plugins/node_modules"
link_entries "$DOTFILES_DIR/home/.config/opencode/skills" "$HOME/.config/opencode/skills"
link_entries "$DOTFILES_DIR/home/.agents/skills" "$HOME/.agents/skills"

ssh_config="$DOTFILES_DIR/home/.ssh/config"
[[ -f $ssh_config ]] && link_file "$ssh_config" "$HOME/.ssh/config"

chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
chmod 700 "$HOME/.ssh" 2>/dev/null || true

if [[ ! -f $HOME/.honcho/config.json ]]; then
  echo "WARNING: ~/.honcho/config.json is still missing."
fi

echo "Dotfiles restore complete. Restart OpenCode to load the restored config."
