---
name: herdr-maestro
description: Orquestra a herd herdr (tars, case, oraculo, technomancer + efêmeros/locais) em qualquer repo do operador — delegar tarefas entre agentes opencode, checar estado working/blocked/idle, recrutar com briefing da biblioteca global (infra/herdr/roles) composto com o pack de escopo (living/ke-billing/red-labs), demitir, notificar, esperar por bloqueio e fazer onboard de novos repos. Use quando precisar coordenar outros agentes da herd, disparar trabalho neles, ou reportar ao TARS. Trigger exato @herd.
---

# Herdr Maestro

Loop maestro da herd herdr — substitui o protocolo maestri-manager no runtime Herdr (dual-run DEC-050: Maestri permanece como fallback legado; NUNCA escreva em `.maestri/`).

## 0. Pre-flight

1. herdr no PATH (fallback `%LOCALAPPDATA%\Programs\Herdr\bin\herdr.exe`).
2. Server reachável: `herdr agent list` (se falhar: `infra/herdr/bootstrap-herd.ps1` do hub desktop-link sobe server headless + herd).
3. Biblioteca de roles (hub desktop-link): `infra/herdr/roles/global/*.md` (protocolo scope-agnostic, placeholders `{{REPO}}`/`{{REPO_NAME}}`), `infra/herdr/roles/local/*.md` (efêmeros, só no hub), `infra/herdr/scopes/*.md` (context packs: `living` = org GitHub `living`; `ke-billing` = org `b3monetization`; `red-labs` = pessoal/Red-Lab-Solutions/lincolnqjunior).
4. Briefing de agente global = role body (placeholders resolvidos) + pack de escopo anexado. O pack define org GitHub, fontes de evidência, Honcho workspace e tags memorygraph do escopo.
5. Leia o AGENTS.md do repo e .claude/napkin.md (quando existir) antes de operar.

## 1. Inventário (antes de cada tarefa)

```
herdr agent list
herdr agent get <nome>
```

Estados: `working` / `blocked` (precisa de resposta) / `idle` / `done` / `unknown`.

## 2. Delegar (ask)

```
herdr agent prompt <nome> "<tarefa + contexto mínimo>" --wait --until blocked --timeout 120000
```

**Contrato outbox (obrigatório em toda delegação):** a tarefa deve instruir o agente a (a) escrever a resposta completa em `docs/herd/outbox/<nome>--<slug>.md` do repo em questão e (b) reportar ao TARS com `herdr agent prompt tars "<resumo de 1-3 linhas + caminho do arquivo>"`. O maestro lê o ARQUIVO — nunca dependa de ler a tela do agente (opencode renderiza em alternate screen; `agent read` além do visível só funciona com agente idle).

Checagem rápida de tela: `herdr agent read <nome> --source recent-unwrapped --lines 120`.

## 3. Recrutar / onboard

**Onboard de repo (zero prompt escrito à mão):**

```powershell
# no hub desktop-link — cria workspace + 4 agentes globais briefed com o escopo
infra\herdr\bootstrap-herd.ps1 -RepoRoot <path-do-repo> -Scope <living|ke-billing|red-labs> -Brief
```

O script é idempotente (agentes vivos são pulados), cria tab por agente, aplica `--model` do frontmatter e compõe briefing global+escopo.

**Recruta manual (caso ad hoc):**

```
$tab = herdr tab create --workspace <id> --cwd <repo> --label <nome> --no-focus   # captura pane_id do JSON
herdr agent start <nome> --kind opencode --pane <pane_id> [-- --model <modelo>]
herdr agent prompt <nome> "<briefing global com {{REPO}} resolvido + pack de escopo>"
```

- Nomes: `[a-z][a-z0-9_-]{0,31}`.
- O pane precisa estar no prompt do shell antes de `agent start`.
- `scope: durable|ephemeral|domain`; ephemeral é atrelado a ticket (demita ao fechar).
- Agente reiniciado = sessão nova SEM memória da conversa anterior — sempre re-briefing (doutrina do `--replace` do Maestri, DEC-044).

## 4. Demitir

```
herdr agent get <nome>   # capture o pane
herdr pane close <pane_id>
```

## 5. Notificar (somente quando o usuário pedir avisos)

```
herdr notification show "<título>" --body "<mensagem>" --sound request
```

## 6. Esperar / monitorar

```
herdr agent wait <nome> --until blocked --timeout 300000
herdr agent wait <nome> --until idle --until done
```

- Sem `--timeout` o wait é infinito — sempre defina.
- Agente já `blocked` + novo prompt → erro `agent_blocked` SEM enviar: inspecione com `herdr agent read` e responda com `herdr agent send-keys <nome> <tecla>` (esc/enter/up/ctrl+c).
- Não reenvie prompt em timeout: primeiro `herdr agent read`, depois decida.

## 7. Memória (roteamento por escopo)

O pack de escopo define os alvos; resumo canônico:

| Escopo | Honcho | memorygraph |
|---|---|---|
| living | local `living` (sessões) / cloud `livingnet` (só archival MCP/meetings) | tag do projeto, co-tag `living` |
| ke-billing | local `billing-ke` | tag do projeto, co-tag `billing-ke` (uma tag por chamada no CLI) |
| red-labs | local `lincoln-hub` | tag por repo (ex.: `desktop-link`) |

- Backend memorygraph canônico: Neo4j VPS `bolt://100.99.168.33:7687` (`MEMORY_BACKEND=memgraph` — DEC-048). Pre-flight: Tailscale up + container `neo4j-prod-shadow`.
- Recall identifier/tag (DEC-NNN, ERR-NNN): `memorygraph search --tags <tag>` (UMA tag por chamada; hyphen quebra FTS). Prosa: `ctx_search`.
- Degradação: graph down em leitura → ctx_search + file layers + "graph skipped" no report; em `finalize` → fail-closed.

## 8. Autoridade e limites

- Commits/PRs/merges somente com autorização do operador (ou TARS, quando você não for o TARS).
- Nunca recrute/demita/reconecte agentes sem passar pelo TARS.
- Gates que não pôde rodar = linha `NOT RUN — operator action required` no report, nunca claim silencioso.
- Decisões arquiteturais viram ADR DEC-NNN em `docs/decisions/` do repo em questão.
- Escopo ke-billing: política (prazos, credenciais, merges, custo) → operador, fail-closed.
