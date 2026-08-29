---
name: meeting-requirement-gathering
description: Skill para extrair requisitos, decisões, ações e riscos de transcrições de reuniões (tldv ou arquivo de texto). Usa Honcho para navegar pelos turnos da reunião via chat() contextualizado por peer. Faz questionário inicial obrigatório em 2 fases (escopo + desambiguação), escolhe peers automaticamente por densidade de contexto, dispara questionário temático adaptativo (generic + 5 sub-templates: release, feature, bugfix, contract, incident, onboarding), cruza respostas entre peers, sinaliza baixa confiança, e produz artefato HTML autocontido para impressão/PDF. Trigger: slash `/meeting-requirement-gathering` ou frases naturais ("extrair requisitos desta reunião", "discovery da call", "summarize this meeting").
---

# Meeting Requirement Gathering

Skill opencode que transforma transcrições brutas de reuniões (tldv ou arquivo de texto) em **artefatos estruturados de discovery + extração de requisitos**, usando o Honcho como store contextual.

## Princípios

1. **Comprometimento do usuário é obrigatório** — sem questionário pulado, sem defaults silenciosos. O usuário sempre confirma escopo antes da análise rodar.
2. **Honesto sobre incerteza** — quando o Honcho não tem contexto para um peer, o agente **não inventa**: relata, marca com flag amarelo no artefato, e sugere alinhamento entre as partes.
3. **Cruzar peers por densidade** — o agente testa todos os speakers da sessão em paralelo, descarta vazios, e mantém top-3 com ≥500 chars na primeira resposta.
4. **Artefato conversível** — HTML autocontido (CSS inline) gera PDF trivialmente via Ctrl+P; nativamente legível por humano e LLM.
5. **Sub-templating amplo** — release / feature / bugfix / contract / incident / onboarding cobrem os casos de uso mais comuns sem ficarem acoplados a BU/produto específico.

## Workflow (14 etapas)

### 1. Trigger
- Slash: `/meeting-requirement-gathering`
- Natural: usuário diz "extrair requisitos", "discovery da call", "summarize this meeting", ou similar

### 2. Questionário inicial — Fase 1 (6 perguntas obrigatórias)
O agente apresenta as 6 perguntas abaixo, em formato estruturado (heading por pergunta + linha de resposta esperada). O usuário responde em prompt livre, o agente parseia.

Perguntas (ver `lib/questionario.md` para texto completo):
0. **Fonte da reunião** — `tldv` / `meetgeek` / `arquivo de texto` / `outro` (default `arquivo de texto`)
1. **Projeto / repo-alvo** — workspace Honcho + repo onde gravar
2. **Time** — stakeholders/owners (Honcho vai precisar saber quem procurar)
3. **Reunião** — data + janela de tempo + tema aproximado (e meeting ID MCP quando fonte é MCP)
4. **Foco da discovery** — release / feature / bugfix / contract / incident / onboarding / outro
5. **Destino do artefato** — path completo (default: `<repo>/docs/notes/<YYYY-MM-DD>-<topic>-discovery.html`)

`outro` (P0) é uma pergunta de desambiguação obrigatória: nunca adivinhe um provider. Peça um source suportado pelo meetings MCP ou um path de arquivo antes de prosseguir.

### 3. Identificação da sessão Honcho (com aquisição via MCP)

Quatro caminhos, selecionados pelo P0:
- **P0 = `tldv` ou `meetgeek`** (aquisição via MCP — ver §Aquisição MCP abaixo):
  1. `meetings_search_transcripts query="<keywords do tema>" source=<tldv|meetgeek>` (com filtro temporal opcional) para obter candidatos.
  2. Para cada candidato relevante, `meetings_get_meeting source=<tldv|meetgeek> meeting_id=<id>` para metadados + transcrição.
  3. Resolver Honcho session via match de `session.metadata.source_meeting_id` ↔ `meeting.id`. Exigir **≥1 peer confirmado** com overlap do conjunto de participantes antes de validar o match. Sem match ou match ambíguo → lookup por data/tema **dentro do mesmo contexto de conta/credencial MCP** (não escopar para outras contas).
  4. Apresentar candidatos ranqueados para confirmação do operador quando a associação for ambígua.
- **P0 = `arquivo de texto`** (caminho legado, preservado):
  - `meetings_search_transcripts` não é chamado.
  - Parser local do arquivo de transcrição (markdown com headers `Speaker:`/`[hh:mm]`, ou JSON do tldv) → criar sessão efêmera local ou usar Honcho workspace `lincoln-hub` + peer `tldv`.
- **Usuário passou horário/tema** (qualquer P0) → `POST /v3/workspaces/{ws}/sessions/list` com filtros de data → apresentar top-5 candidatas → usuário confirma.
- **Usuário passou ID** (Honcho ou meetings MCP) → usar direto.

Endpoint de referência Honcho: `POST /v3/workspaces/{workspace_id}/sessions/list` (POST, não GET).

#### Aquisição MCP (apenas P0 ∈ {`tldv`, `meetgeek`})

Ferramentas (registradas no parent via MCP `meetings`):
- `meetings_list_my_meetings` — panorama bruto (opcional).
- `meetings_search_transcripts` — busca por keyword + filtros (`source`, `start_date`, `end_date`, `team`).
- `meetings_get_meeting` — `source=<tldv|meetgeek> meeting_id=<id>` → metadados + transcrição.

**Redaction (sempre, antes de mostrar ao operador):**
- Títulos de reunião truncados para um token estável (`<prefixo>-<id-curto>`).
- Participantes: contagem + primeiro caractere de cada nome (ex.: `4 (M., R., L., J.)`). Nunca liste nomes completos do MCP no chat.
- Snippets de busca do MCP: nunca reproduzidos literalmente; reescreva como `1 candidato em <data curta>`.

**Classificação de falhas (não cair em fallback silencioso):**

| Classe | Resposta MCP | Ação |
|---|---|---|
| **Stop — identity** | `identity_required`, `401` sem bearer válido, `403` por `x-user-email` faltando | Parar; pedir o identity correto. **Não** cair para fallback. |
| **Stop — autorização** | `403` por workspace/scope, ACL do MCP | Parar; emitir mensagem fixa sem ecoar o texto de erro do MCP (risco de vazar credencial/scope). |
| **Stop — metadata-OK / transcript-denied** | metadados retornados, transcrição vazia ou `403` específica de transcript | Parar; o ponto da skill é a transcrição; conteúdo parcial não serve. |
| **Fallback — timeout / unavailable / not-found** | `timeout`, `5xx`, `404` | Aviso informativo (sem eco do MCP) e lookup Honcho por data/tema dentro do **mesmo** contexto de conta/credencial MCP. |

Mensagem fixa de authorization-failure (template, não editável pelo MCP):

> "Falha de autorização no meetings MCP. Verifique o `x-user-email` configurado para esta conta. A skill não fará fallback para evitar mascarar erros de identidade."

**Timeout recomendado:** `120s` por chamada MCP (mesmo `MREQ_TIMEOUT` da skill). Se o limite real ficar abaixo, ajustar durante implementação.

### 4. Identificação dos peers com contexto

Para a sessão escolhida:
- Listar peers em `POST /v3/workspaces/{ws}/peers/list`
- **Em paralelo**: disparar `chat()` pergunta-1 (overview curta) para **todos** os speakers
- Manter **top-3 com ≥500 chars**
- Descartar peers com resposta vazia ou <500 chars (marca como "peer fraco")
- Em caso de conflito (todos vazios ou densidades similares): perguntar ao usuário
- **Fallback de origem MCP**: participantes do MCP são usados apenas como **candidatos** para identificação de peers; nada do transcript é ingerido em Honcho.

### 5. Checkpoint 1 — Apresentar panorama
Mostrar ao usuário:
- Overview consolidado (1 parágrafo por peer denso)
- Quais peers foram escolhidos e por quê
- Quais peers foram descartados (motivo: vazio/fraco)
- Lista de nomenclaturas divergentes detectadas (ex.: "SB 17" vs "ECB 17")
- Hipóteses iniciais sobre o foco

Perguntar ao usuário se está alinhado antes de prosseguir.

### 6. Questionário — Fase 2 (desambiguação, ≤3 perguntas)
Baseado no que Honcho retornou no passo 4, gerar perguntas específicas:
- Ex.: "Honcho menciona 'SB 17' — isso é o mesmo que ECB 17? Kansys Edge 17? Outro?"
- Ex.: "Vi referência a 'develop edge' — é nome de branch? branding? ferramenta?"
- Ex.: "Os stakeholders mencionados são <lista> — confirma ou adiciona?"

### 7. Questionário temático (template-driven)
Baseado na resposta de Fase 1.4 (foco), selecionar template:
- `generic` → padrão
- `release` → adiciona Q0 sobre branch de release / pacotes / gate
- `feature` → adiciona Q0 sobre user stories / acceptance criteria
- `bugfix` → adiciona Q0 sobre reprodução / severidade
- `contract` → adiciona Q0 sobre API surface / OpenAPI / breaking changes
- `incident` → adiciona Q0 sobre timeline / blast radius / RCA
- `onboarding` → adiciona Q0 sobre contexto para novo membro

**8 perguntas padrão** (aplicadas a todos os templates):
- Q1 — Visão geral (≤ 1 página, foco no template)
- Q2 — Decisões explícitas + quem decidiu + pendências de validação
- Q3 — Requisitos funcionais e não-funcionais
- Q4 — Restrições / ambiente / dependências externas
- Q5 — Ações com dono / prazo / status
- Q6 — Riscos / dúvidas / gaps
- Q7 — Repos / paths / branches / sistemas
- Q8 — Adversarial (premissas implícitas, conflitos, baixa confiança)

**Disparo**: em paralelo nos top-3 peers, ~60s timeout por chamada.

### 8. Cross-check com `honcho.search()` e `context()`
Para cada RF/RNF detectado em **apenas 1 peer** (fonte fraca):
- Rodar `session.context({ tokens: 1500, summary: true, searchQuery: "<keyword>" })` ou
- Rodar `peer.search({ query: "<keyword>" })`
- Se cross-check confirma → flag verde
- Se cross-check contradiz → flag vermelho + pedir desempate ao usuário
- Se cross-check silencioso → flag amarelo "fonte fraca — alinhar com time"

### 9. Compilação do artefato HTML autocontido
Estrutura padrão (todos os templates):
- **Cover page** (título, data, meeting ID/horário, projeto, foco, autores)
- **Índice** (links âncora para seções)
- **Resumo executivo** (≤ 1 página)
- **Nomenclaturas resolvidas** (tabela)
- **Requisitos funcionais** (RF1, RF2, ... numerados com fonte)
- **Requisitos não-funcionais** (RNF1, ...)
- **Ações com owners / prazos / status** (tabela)
- **Riscos** (lista com severidade inferida)
- **Gaps / divergências** (cross-peer)
- **Sinalizações** (verde / amarelo / vermelho — confiança)
- **Cobertura por peer** (tabela: quem falou sobre o quê)
- **Pontos a alinhar com o time** (lista final)

Template cover page em `templates/cover.html` (gerado pelo agente).

### 10. Checkpoint 2 — Apresentar artefato
Mostrar artefato renderizado (ou caminho) e perguntar:
- "Está bom para gravar?"
- "Quer ajustar nomenclatura, formato ou seção?"
- "Quer commitar ou só gravar o arquivo?"

### 11. Gravar artefato
- Path do Fase 1.5
- Permissões: 644
- Encoding: UTF-8
- Backup: se já existir arquivo no path, fazer `.bak-<timestamp>` antes

### 12. Criar conclusão Honcho
Resumir o que foi extraído em 1-3 frases via `honcho.create_conclusion` usando o **schema unificado** compartilhado com `@discovery` (R5):

```
Discovery <type> <scope-curto> (<YYYY-MM-DD>): <N> RFs, <M> RNFs, <K> ações, <J> riscos. Fontes: <lista>. Artefato: <path ou "inline">.
```

- `<type>` ∈ {`meeting`, `discovery`, `release`, `feature`, `bugfix`, `incident`, `contract`, `onboarding`}; esta skill usa o `<foco-da-P4>` mapeado (`release` → `release`, `feature` → `feature`, etc., default `meeting`).
- `<scope-curto>` é kebab-case slug (ex.: `meeting-6a674834`, `desktop-link-multi-janelas`).
- Vinculada ao peer primário usado; workspace = mesmo da reunião.
- O prefixo `Discovery ` é preservado para compatibilidade de `honcho_search` retroativo. Conclusões antigas permanecem pesquisáveis — **não migre**.

**Read-back obrigatório (gate do bridge):** após criar a conclusão, ler de volta pelo ID (`honcho_search` filtrando por conteúdo ou o retorno direto do `honcho_create_conclusion`). Se o ID estiver missing, vazio ou ilegível, **tratar como falha bridge-bloqueante**: oferecer retry, **não** apresentar o opt-in do passo 14. O ID da conclusão da skill é o que será propagado como `Ref:` no discovery cross-check.

### 13. Resumir ao usuário
- Path do arquivo HTML gerado
- Honcho conclusion ID (validado pelo read-back do passo 12)
- Estatísticas (peers usados, tokens consumidos, perguntas disparadas)

### 14. Opt-in bridge para `@discovery` (cross-check multi-fonte)

Este passo só roda após Checkpoint 2 (passo 10) e read-back válido da conclusão (passo 12). É **opt-in**, sem default afirmativo.

**14.1 Perguntar ao operador** (R1):
> "Quer que eu rode um cross-check multi-fonte via `@discovery` (~`X–Y` tokens estimados, aproximado)? Isso valida o discovery contra Honcho + memory-graph + context-mode + codebase. [sim/não]"

**Sem default afirmativo** — se o operador não responder, registrar aviso e encerrar.

**14.2 Se aceito, despachar `@discovery`** (R2):
- Via `task` tool com `subagent_type: "discovery"` (registro explícito em `opencode.jsonc` — U1).
- Cabeçalho estruturado **obrigatório** (o agente parseia para o recursion guard):
  ```
  bridge=meeting-skill ref=<skill-conclusion-id> artifact=<html-path> workspace=<honcho-ws> source=<tldv|meetgeek|arquivo de texto> meeting_id=<id-ou-vazio>
  ```
- Objetivo no formato existente `<repo> <objetivo>`:
  ```
  <repo-da-P1> validar discovery-de-<scope-curto> cross-check pós-skill
  ```
- O agente **não deve** invocar `skill("meeting-requirement-gathering")` enquanto o cabeçalho `bridge=meeting-skill` estiver presente (recursion guard via prompt contract — U1).

**14.3 Boundar a espera** com o mesmo `MREQ_TIMEOUT` da skill (default 120s por chamada, mas a chamada do `task` pode levar mais).
- Em caso de timeout do brief, **não bloquear** — fazer `honcho_search` filtrando pela conclusão `Ref: <skill-conclusion-id>` (a discovery já criou a sua; só não retornou ao chat) e surfacear:
  > "Conclusão existe no Honcho (`<discovery-conclusion-id>`), mas o brief não retornou dentro do limite. Veja Honcho ou peça nova execução."

**14.4 Falhas de discovery** (R4):
- `task` indisponível ou `subagent_type: "discovery"` não resolve → reportar **partial bridge failure**, mas **não deletar nem substituir** o HTML + conclusão da skill.
- `memorygraph` indisponível → `@discovery` retorna com sinalização amarela; skill aceita o retorno parcial.
- A skill **nunca retenta** automaticamente. O operador decide.

**14.5 Saída combinada** (R4): o operador recebe, lado a lado:
- Path do HTML da skill
- ID da conclusão da skill
- ID da conclusão da discovery (criada com `Ref: <skill-conclusion-id>` no schema unificado)
- Brief inline do `@discovery`
- HTML da skill é preservado — discovery **não substitui** artefato.

**14.6 Reentrância**: aceitar o opt-in múltiplas vezes para a mesma meeting gera conclusões **append-only** (sem deduplicação), todas com `Ref: <skill-conclusion-id>` apontando para a mesma âncora. Honcho `search` reconstrói a cadeia.

## Permissões

| Operação | Permissão |
|---|---|
| `read` | `allow` |
| `glob`, `grep`, `list` | `allow` |
| `webfetch` | `allow` (para docs opencode/Honcho) |
| `bash` | `allow` com prompt (curl Honcho, parser de transcrição) |
| `todowrite` | `allow` |
| `question` | `allow` (Fase 1 + Fase 2 + checkpoints + bridge opt-in) |
| `task` | `allow` (U1 — `opencode.jsonc` top-level `permission.task=allow`; esta skill despacha `subagent_type="discovery"` no passo 14) |
| `edit` / `write` | `deny` (até aprovação no Checkpoint 2) |
| `external_directory` | `ask` (gravar artefato em repo-alvo) |

## Modelo

Perguntar ao usuário na Fase 1 ou usar o modelo da sessão atual. Default sugerido: o modelo do Honcho configurado (atualmente `minimax/MiniMax-M3` no ambiente Living).

## Templates

Ver `templates/`:
- `discovery-generic.md` — base, 8 perguntas padrão
- `discovery-release.md` — + Q0 sobre branch de release / pacotes / gate
- `discovery-feature.md` — + Q0 sobre user stories / acceptance
- `discovery-bugfix.md` — + Q0 sobre reprodução / severidade
- `discovery-contract.md` — + Q0 sobre API surface / OpenAPI / breaking
- `discovery-incident.md` — + Q0 sobre timeline / blast radius / RCA
- `discovery-onboarding.md` — + Q0 sobre contexto para novo membro

## Honcho API

Ver `lib/honcho_api.md` para snippets curl/bash:
- `chat()` por peer — `POST /v3/workspaces/{ws}/peers/{peer_id}/chat`
- `context()` por sessão — `GET /v3/workspaces/{ws}/sessions/{sid}/context?tokens=N`
- `search()` por peer — `POST /v3/workspaces/{ws}/peers/{peer_id}/search`
- `sessions/list` — `POST /v3/workspaces/{ws}/sessions/list`
- `peers/list` — `POST /v3/workspaces/{ws}/peers/list`
- `messages/list` — `POST /v3/workspaces/{ws}/sessions/{sid}/messages/list`
- `conclusions` — `POST /v3/workspaces/{ws}/conclusions/list` + `POST /v3/workspaces/{ws}/conclusions` (criar)

## Scratch

Artefatos temporários em `C:\Users\linco\AppData\Local\Temp\opencode\meeting-requirement-gathering\` (configurável via env `MREQ_SCRATCH_DIR`).

## Limitações conhecidas

- Honcho pode ter peer vazio (caso `tldv` nesta sessão). Workaround: usar peers dos participantes.
- Transcrições >50k tokens exigem `context({ summary: true })` em vez de carregar tudo.
- Sem persistência cross-sessão no Honcho (conclusões são a única memória durável).
- Honcho ainda é single-tenant local (placeholder `'local-dev'`).