# lincolnqjunior/dotfiles

Omarchy-ready dotfiles snapshot from Windows 11 â†’ VPS-restoreable.
Created during Omarchy migration on 2026-08-29.

## Files
- `home/.config/opencode/opencode.jsonc` â€” uses `${env:...}` placeholders for secrets
- `home/.config/opencode/opencode.jsonc.example` â€” redacted template (committed to repo)
- `home/.config/opencode/{agents,prompts,plugins}/` â€” vendored agent + prompt + plugin content
- `home/.config/opencode/skills/` + `home/.agents/skills/` â€” SKILL.md per skill only
- `home/.ssh/{config,*.pub}` â€” SSH config + public keys (NO private keys)
- `home/.honcho/config.json.example` â€” Honcho binding template
- `home/.memorygraph/neo4j.env.example` â€” Memgraph env template
- `home/infra/9router/9router.service` â€” systemd unit
- `restore.sh` â€” idempotent Omarchy bring-up after Tailscale auth
- `first-boot.sh` â€” full bootstrap (Tailscale + secrets + dotfiles + opencode + smoke test)

## What's NOT here (intentional, .gitignore'd)
- `.env.keys` â€” local file (chmod 600), restored from VPS bundle
- Private SSH keys â€” backed up to VPS `/home/lincoln/backups/ssh-keys-*.7z`
- `napkin.md` â€” operational runbook (per-repo, not user-portable)
- `known_hosts` â€” server fingerprint list

## Bootstrap on Omarchy
```bash
git clone https://github.com/lincolnqjunior/dotfiles.git
cd dotfiles
bash first-boot.sh
```

Prereqs: Omarchy installed, network up, sudo access.

## Manual restore (after Tailscale auth)
```bash
bash restore.sh ~/dotfiles-checkout
```
