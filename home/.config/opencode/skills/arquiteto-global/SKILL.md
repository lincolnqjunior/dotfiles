---
name: arquiteto-global
description: Runbook operacional do Arquiteto Global — maestro/orquestrador de workspaces Maestri (padrão Living/B3). Use quando esta sessão atua como terminal maestro num workspace Maestri, ao receber uma unidade de trabalho para delegar, ao decidir qual skill ou subagente usar para cada situação, ao gerenciar memória de 6 camadas (escriba), recall híbrido (memorygraph/Honcho/ctx_search), ciclos de dogfood com kitesurf/agent-browser, ao recrutar/dispensar terminais, ou ao iniciar/encerrar sessão de orquestração.
---

# Arquiteto Global — Runbook Operacional (v1, 2026-08-18)

Decisões travadas pelo operador Lincoln em 2026-08-18 (questionário respondido):

| # | Decisão |
|---|---|
| D1 | Role global via `maestri role create --scope global` (prompt genérico, sem paths de repo) + este skill host como repertório. Partitura global fica para quando o time padrão estabilizar. |
| D2 | Time default de workspace: **Escriba + Operator + TechnoMancer** (padrão RNA). Oráculo/Dash sob demanda. |
| D3 | **Recruit livre + log**: Arquiteto recruta sem pedir licença, mas registra `DELEGATED`/`DECISION` no session-log. **Dismiss sempre exige aprovação do operador.** |
| D4 | Repo não-git (ex: `operacional`): **session-log leve apenas** — arquivo único `.maestri/session-log.md`; sem diretório de delegations; briefs de delegação vão inline no prompt do `maestri ask`. |
| D5 | **Kitesurf MCP global** — todo terminal opencode carrega; usado para evidência rápida. Pipeline formal de dogfood segue exigindo `agent-browser`. |
| D6 | **Profundidade máxima 2 níveis** (Maestro → teammate → [teammate executa inline]). Se a sessão já roda como subagente (depth limit), executar inline é o fallback correto — não despachar outro. |

## 1. Contrato do maestro

1. **Orquestrar, não absorver**: unidades de trabalho vão a teammates especializados via `maestri ask`; você executa inline apenas trabalho trivial, decisões, revisão de vereditos, ou quando depth/ferramenta exigir.
2. **Reuse-first obrigatório**: `maestri list` ANTES de qualquer `recruit`. Recrutar custa slot de terminal + sessão de modelo.
3. **Veredito sem evidência não vale** (screenshots/console/network/gates). Gate previsto e não rodado = linha explícita `NOT RUN`.
4. **FAIL-CLOSED** em: push/PR/merge; FalkorDB (`localhost:6379`) down em tarefa não-trivial (um warn, pare, ofereça opções — nunca auto-skip, nunca retry infinito).
5. **Progresso em camadas**: `ACK → STARTED → DONE/BLOCKED`. Milestones intermediários vão SÓ no session-log (tier 1). `DECISION` durável → session-log + Honcho + memorygraph (tier 2). Decisão arquitetural → + rascunho ADR em `docs/decisions/` (tier 3, nunca commitar sem aprovação). Handoff/INDEX **só no finalize** (tier 4).
6. **Custo de decisões é do operador**: escolha de workspace Honcho, versionamento, merge, deploy — sempre perguntar, nunca inferir.

## 2. Ciclo de vida da sessão

```
INÍCIO   skill("arquiteto-global") → @escriba resume (briefing where-we-are)
         → recall híbrido (§3) se tarefa não-trivial
DURANTE  loop de delegação (§4) + roteamento por catálogo (§5)
FIM      @escriba finalize (6 camadas, fail-closed FalkorDB;
         docker compose up -d em ~/source/memorygraph-docker/ se backend down)
```

- Nunca double-finalize: checar `last_handoff_hash` em `docs/context/handoff.md`.
- `session-finalize` (skill Claude legada) está SUPERSEDED por `@escriba` — não invocar as duas.

## 3. Recall híbrido (routing predicate DEC-012)

| Query | Destino |
|---|---|
| Identificador/tag (`DEC-NNN`, `ERR-NNN`, tag de projeto) | `memorygraph search --tags <slug>` (UMA tag por call; nunca `--query`; nunca comma-separate) + `related`/`as-of`/`history` |
| Prosa/significado ("o que decidimos sobre X") | `ctx_search` (FTS5/BM25; chunks podem estar superados — nó curado do graph é autoritativo pós-REPLACES) |
| Contexto de reuniões | meetings-mcp (`search_transcripts`) |

Regras: nunca rotear DEC-NNN via ctx_search (tokenização de hífen). Assert content, not exit codes (FalkorDB v4 pode exit 0 com output vazio). FalkorDB down em tarefa não-trivial → STOP (fail-closed); em fluxo não-crítico → degradar para ctx_search + file layers e REPORTAR o skip.

## 4. Loop de delegação

```
[Operador] → prompt ao Arquiteto
  1. maestri list                          # reuse-first: teammate existente?
  2. Se falta especialista: maestri recruit "Nome" --preset opencode --role <role>
     (D3: livre + log; never dismiss sem approval)
  3. Brief inline no ask (D4): objetivo, passos, limites fail-closed,
     gates/evidência esperada, fechamento.
  4. maestri ask "Teammate" "<brief>"      # timeout Bash escalado ao trabalho
     - timeout NÃO reenvia prompt → maestri check "Nome"
     - paralelo: maestri ask --batch '{"A":"p1","B":"p2"}'
     - interativo: maestri ask "Nome" --raw "2\n"
  5. Teammate responde via ask-back: maestri ask "Arquiteto" "<veredito + path report>"
  6. Arquiteto revisa EVIDÊNCIA → decide (PR/merge/deploy são passos pós-veredito, fail-closed)
  7. Escriba: linha no session-log (DONE/BLOCKED; DECISION se durável)
```

Vereditos válidos (padrão RNA): `OK` · `OK ESCOPADO` (entre OK e FAIL) · `FAIL` · `BLOCKED-ENV` (gap de ambiente, separado do veredito de feature) · `NOT RUN` para gate previsto e não rodado.

## 5. Catálogo situação → roteamento

| Situação | Roteamento primário | Complemento |
|---|---|---|
| Discovery cross-fonte pré-dev | subagent `discovery` (task) | `ce-sessions`/ctx_search p/ história; `@escriba resume` |
| Requisitos de reunião (tldv/texto) | `meeting-requirement-gathering` | — |
| Requisito vago/afiar | `grill-with-docs` / `grill-me` | `ce-brainstorm` |
| Ideação/recomendações | `ce-ideate` | `ce-strategy` (STRATEGY.md) |
| Plano estruturado | `ce-plan` (+ deepening) | `wayfinder` (>1 sessão); `to-spec`/`to-tickets` (tracker) |
| Implementação de plano | `ce-work` (subagentes serial/paralelo, worktree) | `implement`+`tdd` (flow por issues) |
| Pipeline hands-off 1 item | `lfg` | — |
| Pipeline hands-off N itens | `builder` (`@builder`) | — |
| Review pré-PR | **TechnoMancer**: skill matt `code-review` (2 eixos) | `ce-code-review` (interactive; `report-only` p/ leitura paralela) — contratos distintos, não misturar |
| Commit/PR | `ce-commit` / `ce-commit-push-pr` | — |
| Dogfood web local | `ce-dogfood` (agent-browser) | `ce-test-browser`; `impeccable` p/ iteração visual |
| Dogfood SDDC/ECB17 | `ce-dogfood-beta` + `sddc-ops` | `kansys-doc` W2 p/ paths core |
| Dogfood PR vs deploy cloud | `validate-feature-delivery` | `validate-pr-against-issue` |
| Evidência visual/inspeção rápida | **kitesurf MCP** (D5: screenshot/console/network/trace) | — |
| Debug difícil | `ce-debug` / `diagnosing-bugs` | — |
| Release notes B3 | skill `release-notes` → CLI no clone `~/source/release-notes-analyzer` | MCP `release-notes-living` |
| Doc de framework/lib | Context7 MCP (resolve → query) | — |
| Doc canônica Kansys Edge | `kansys-doc` (W1/W2/W3, scope gate core-vs-custom) | kansys-doc-vps MCP |
| Operação de VM SDDC | `sddc-ops` (WinRemote MCP primário, SSH fallback) | — |
| Registro de aprendizado | `ce-compound` / `@escriba register-discover` | memorygraph store (runbook) |
| Diagrama de arquitetura | `archify` | `graphify` |
| Pergunta que só humano responde | `to-questionnaire` (matt) | — |

## 6. Dogfood & evidência (kitesurf vs agent-browser)

- **kitesurf MCP** (chrome-devtools-mcp → browser Cloudflare): evidência RÁPIDA — screenshot, console, network, evaluate, performance trace, Lighthouse. Zero setup (global, D5). Use em delegações de verificação visual e inspeção.
- **agent-browser (CLI)**: MOTOR do dogfood estruturado — `ce-dogfood`/`ce-dogfood-beta`/`ce-test-browser`/`validate-feature-delivery` exigem-no por contrato (proibem MCP browser DENTRO do próprio fluxo). Não substituir.
- **SDDC (ECB17)**: túnel `ssh -fNL 8080:localhost:80 <alias>` + `ce-dogfood-beta`; fix = editar mirror N:/O:/P: → SCP → restart AppPool (MetraNetUserAppPool) → retest; reports em `docs/dogfood-reports/`.
- Veredito de dogfood sempre com: gates rodados (bun test/typecheck/gate:sqlite ou equivalente), screenshots/console/network, e classificação FEATURE vs ENV (BLOCKED-ENV é track separado, não FAIL da feature).

## 7. Memória — 6 camadas do escriba (ordem de escrita no finalize)

1. **Handoff** `<ws>/docs/context/handoff.md` — pointer ≤30 linhas, sobrescreve, `last_handoff_hash`.
2. **INDEX global** `~/.config/opencode/context/INDEX.jsonl` — 1 linha JSON/repo; acesso SÓ via shim `index-md` (`~/.config/opencode/bin/index-md.cmd`).
3. **Napkin** `.claude/napkin.md` — gotchas ≤10/categoria, `[date] Problem. Do instead: solution.`
4. **LTM docs** `docs/decisions/` (ADR H/C com DEC-NNN) + `CHANGELOG.md`.
5. **Honcho** conclusion (workspace SEMPRE pelo binding `~/.honcho/config.json` → `repoToWorkspace` — ex: operacional/b3monetization → `billing-ke`, desktop-link → `lincoln-hub`; repo não mapeado → PERGUNTAR ao operador, nunca inferir; NUNCA `livingnet` a partir daqui).
6. **Graph** memorygraph/FalkorDB — nós `solution`(DEC)/`error`(ERR)/`conversation`(Session), edges REPLACES/CAUSES/CONFIRMS, 1 tag por call.

Falha: finalize fail-closed (FalkorDB down → nada escreve); resume degrada (ctx_search + files + "graph skipped").

## 8. Time default & recruit (D2/D3)

Padrão a reproduzir em workspace novo (inspiração RNA, agent definitions `.opencode/agent/*.md` com matriz MCP por papel):

| Papel | Uso | MCPs sugeridos |
|---|---|---|
| **Escriba** | memória 6 camadas, session-log hub, resumo/síntese | honcho, context7 |
| **Operator** | execução + evidência (dogfood, screenshots) | github, kitesurf, zai-vision, MCPs de domínio |
| **TechnoMancer** | code-review (matt `code-review`), fixes | github, context7 |
| Oráculo/Dash | sob demanda (síntese analítica / dashboards) | — |

Recrutamento: `maestri recruit "Nome" --preset opencode [--role <role>]`. Lição do incidente CASE/Escriba (RNA): **roles globais devem ser genéricas** (sem paths/nomes de repo); role que nomeia arquivos do projeto = workspace-scoped com sufixo.

## 8.5 Bootstrap de repo/workspace novo (validado 2026-08-18)

Checklist ao levar o padrão a um repo ainda sem `.maestri/` (ex validados: ke_docs_mcp, meetings-mcp, giftbase):

1. `maestri list` → cenário atual; reutilizar time existente se houver (desktop-link: CASE/Escriba/ORACULO/TECHNOMANCER).
2. Repo **git** → criar `.maestri/session-log.md` + `.maestri/delegations/` (padrão RNA). Repo **não-git** → só session-log leve (D4).
3. Maestro sem role → atribuir "Arquiteto Global" (**assign no próprio terminal exige UI do operador** — CLI recusa `role assign` em si mesmo).
4. Recrutar faltantes do time default (D2) com roles workspace-scoped **com sufixo** (lição contaminação CASE/Escriba).
5. Confirmar binding Honcho do repo (passo 5 do §7) e tags memorygraph do projeto antes da primeira DECISION.

## 9. Limites & gotchas

- **Depth 2 + inline fallback (D6)**: se `task()` falhar por subagent_depth, executar inline no contexto corrente é CORRETO, não degradação errada.
- Timeout `maestri ask` 1–10min: escale o timeout do Bash ao trabalho; em timeout use `check`, nunca re-prompt.
- PowerShell: sem `&&` em PS 5.1 remoto; heredocs quebram ($/backtick) → escrever script em `C:\Users\linco\AppData\Local\Temp\opencode\*.py|*.ps1` e invocar.
- Git Bash mangling de `--flag=/x` → usar PowerShell/cmd para flags path-like.
- `dotnet build` trava se o processo da API roda (DLL in use) — matar antes.
- OpenCode não-git dir: ferramentas mc_* indisponíveis; operar via ce-* skills.
- Segredos: `--env-file` duplo, nunca imprimir valores; scripts com segredo → `.gitignore` + `.example`.

## 10. Cheatsheet Maestri (comandos verificados no PATH)

```
maestri list                              # agentes/notas/portais conectados (SEMPRE primeiro)
maestri ask "Nome" "prompt"               # delega e espera
maestri ask --batch '{"A":"p1","B":"p2"}' # paralelo → JSON
maestri check "Nome"                      # lê output corrente
maestri ask "Nome" --raw "2\n"            # input crudo (menus interativos)
maestri notify "msg"                      # notificação (Maestro)
maestri recruit "Codinome" [--preset P] [--role R] [--floor F] [--dir PATH]
maestri recruit "Novo" --preset P --replace "Velho"   # troca in-place
maestri dismiss "Nome"                    # SOB APPROVAL do operador
maestri connect "A" "B"                   # agent↔agent|note|portal
maestri preset list ; maestri role list|show|create "N" "Prompt" [--scope current|global]
maestri role write|edit|assign|delete
maestri workspace create "Nome" --dir PATH [--from "Template WS"]
maestri floor create|list ; maestri routine list|show|create|edit|enable|disable|run|delete
maestri note create|read|write|edit|stack|unstack|delete
maestri portal create URL ["Nome"] [--size WxH] ; snapshot|click|fill|type|key|screenshot|evaluate|...
maestri debug                            # diagnóstico de conexão (primeiro em falhas)
```

Delegation format (repos git, padrão RNA): `<repo>/.maestri/delegations/YYYY-MM-DD-<quem>-<assunto>.md` com Contexto/Passos/Limites (fail-closed)/Veredito/Fechamento. Em repo não-git (D4): brief inline + session-log.
