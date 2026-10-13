/**
 * herd-quota-cache.mjs — leitor da cache `herd-quota/v1` para o plugin do
 * statusline (QL5, #228).
 *
 * ## Papel (Q-A8.3: leitor + gatilho, NUNCA writer)
 *
 * Este arquivo **não** busca quota na rede e **não** escreve a cache. Ele:
 *   1. LÊ `~/.cache/herd-selector/quota-live/<provider>.json` (filesystem puro);
 *   2. quando a entrada está stale ou ausente, DISPARA `herd-quota refresh --if-stale`
 *      como processo separado e desacoplado.
 *
 * O parse dos 5 providers (e as 4 correções do A8.3) mora no writer, em
 * `desktop-link/infra/herdr/selector`. Este arquivo consome o resultado. Foi
 * justamente esse o motivo de trocar o engine embutido do plugin: o engine antigo
 * tinha os 4 defeitos do A8.3 e fazia 1 fetch por pane a cada 5 min (N panes = N
 * fetches); com a cache compartilhada o host faz ≤ 5 fetches por 5 min, e a
 * correção dos defeitos tem um só lugar.
 *
 * ## Por que um `lib/` e não dentro do plugin
 *
 * O plugin é um `.tsx` de 1 784 linhas com Solid/OpenTUI; esta lógica é pura e
 * testável fora dele. Precedente: `honcho-workspace-router-core.mjs`.
 *
 * ⚠️ **O `lib/` precisa morar DENTRO do checkout.** O commit 9a1de0e do dotfiles
 * conserta exatamente isso: um plugin symlinkado resolve import relativo contra o
 * realpath, então `../lib/` relativo a `~/.config/opencode/plugins/` symlinkado
 * aponta para fora do checkout e o import quebra com ERR_MODULE_NOT_FOUND. Por
 * isso `lib/` é `home/.config/opencode/lib/` no checkout, ao lado de `plugins/`.
 *
 * ## Números duplicados (e por que isso é aceitável)
 *
 * As durações canônicas e o `maxAgeMs` do leitor são copiados do selector porque
 * este arquivo roda em outro repositório. A rede que pega a divergência é
 * `desktop-link/infra/herdr/selector/tests/quota-cache-plugin-contract.test.ts`.
 * Ao mudar qualquer número daqui, mude lá junto.
 */
import { readFile } from "node:fs/promises"
import { spawn } from "node:child_process"
import { accessSync, constants } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

/** Versão do schema da cache. Entrada com outro valor é ignorada. */
export const CACHE_SCHEMA = "herd-quota/v1"

/**
 * Frescor do LEITOR (`quota.maxAgeMs`, QL3/#226). Diferente de
 * `quota.refreshTtlMs` (300 000), que é TTL do WRITER: usar o TTL aqui daria
 * janela errada — a mesma confusão que o handoff #2 do QL2 registrou.
 */
export const READER_MAX_AGE_MS = 900_000

/** Mesmo teto do hook do bootstrap (#227): rede viva, credencial lenta. */
export const REFRESH_TIMEOUT_MS = 20_000

/** Espelha `WINDOW_5H` / `WINDOW_7D` / `WINDOW_30D` do selector. */
const CANONICAL = new Map([
  [18_000, "5h"],
  [604_800, "7d"],
  [2_592_000, "30d"],
])

export function cacheDir(home) {
  return join(home ?? homedir(), ".cache", "herd-selector", "quota-live")
}

/**
 * Janela da cache → chave que o widget sabe desenhar.
 *
 * Classifica por **duração exata**, nunca por tempo até o reset: esse era o
 * defeito 3 do A8.3 (uma janela semanal a 3h do reset virava "5h" e colidia com
 * a primária). Duração não canônica devolve `undefined` e a janela simplesmente
 * não é desenhada — inventar um rótulo errado é pior que omitir.
 */
export function keyForSeconds(seconds) {
  return typeof seconds === "number" ? CANONICAL.get(seconds) : undefined
}

function ageMs(fetchedAt, now) {
  const ts = Date.parse(fetchedAt)
  if (!Number.isFinite(ts)) return Number.POSITIVE_INFINITY
  const age = now - ts
  // skew de clock: um `fetchedAt` no futuro não vira idade negativa.
  return age >= 0 ? age : 0
}

/**
 * Lê a janela da cache de um provider. **Nunca lança.**
 *
 * Ausente, ilegível, JSON inválido, shape desconhecido, status != "ok" — tudo
 * devolve `{ windows: [], stale: true }`: o widget some e o opencode continua.
 *
 * Só desenha janelas `governs: true` — é o que impede a cota MCP mensal do
 * Z.AI (defeito 1 do A8.3) de aparecer como se fosse quota de modelo.
 */
export async function readQuotaWindows(providerID, options = {}) {
  const empty = { windows: [], stale: true, status: null }
  if (!providerID) return empty

  const now = options.now ?? Date.now()
  const maxAgeMs = options.maxAgeMs ?? READER_MAX_AGE_MS
  const dir = options.dir ?? cacheDir(options.home)

  let raw
  try {
    raw = JSON.parse(await readFile(join(dir, `${providerID}.json`), "utf8"))
  } catch {
    return empty
  }
  if (raw === null || typeof raw !== "object") return empty

  const entry = /** @type {Record<string, unknown>} */ (raw)
  if (entry.schema !== CACHE_SCHEMA) return empty

  const status = typeof entry.status === "string" ? entry.status : null
  if (status !== "ok") return { windows: [], stale: true, status }

  const stale = ageMs(typeof entry.fetchedAt === "string" ? entry.fetchedAt : undefined, now) > maxAgeMs
  const source = Array.isArray(entry.windows) ? entry.windows : []

  const windows = []
  for (const item of source) {
    if (item === null || typeof item !== "object") continue
    const w = /** @type {Record<string, unknown>} */ (item)
    if (w.governs !== true) continue
    const key = keyForSeconds(w.windowSeconds)
    if (key === undefined) continue
    const usedPct = typeof w.usedPct === "number" && Number.isFinite(w.usedPct) ? w.usedPct : undefined
    if (usedPct === undefined) continue
    windows.push({ key, usedPct: Math.round(usedPct) })
  }
  return { windows, stale, status }
}

/**
 * `HERD_QUOTA_BIN` → PATH → árvore do hub. Mesma cadeia do `SELECT_BIN` no
 * `bootstrap-herd.sh` (#227), porque é o mesmo problema: num host real o binário
 * não está no PATH do processo que dispara.
 */
export function resolveQuotaBin(options = {}) {
  const env = options.env ?? process.env
  // `X_OK`, como o `[ -x ]` do `bootstrap-herd.sh` (#227): existir não basta,
  // o binário precisa ser executável para o spawn servir.
  const runnable = (p) => {
    try {
      accessSync(p, constants.X_OK)
      return true
    } catch {
      return false
    }
  }

  const fromEnv = env.HERD_QUOTA_BIN
  if (fromEnv && runnable(fromEnv)) return fromEnv

  const fromPath = (env.PATH ?? "").split(":").find((dir) => dir && runnable(join(dir, "herd-quota")))
  if (fromPath) return join(fromPath, "herd-quota")

  const hubRoot = options.hubRoot ?? env.HERDR_HUB_ROOT ?? join(env.HOME ?? homedir(), "Projects", "desktop-link")
  const inHub = join(hubRoot, "infra", "herdr", "selector", "bin", "herd-quota")
  return runnable(inHub) ? inHub : null
}

/**
 * Gatilho: dispara o writer e **não espera**. `detached` + `unref` + `stdio:
 * "ignore"` para que o processo do opencode não fique preso ao refresh e para
 * que nada seja escrito no TUI. `timeout` do `spawn` é o único teto.
 *
 * Devolve `false` (e nunca lança) se não achou bin — o cache é reidratado pelo
 * timer systemd (#227) de qualquer forma.
 */
export function triggerQuotaRefresh(options = {}) {
  const env = options.env ?? process.env
  const spawnFn = options.spawnFn ?? spawn
  const bin = resolveQuotaBin({ env, hubRoot: options.hubRoot })
  if (bin === null) return false
  try {
    const child = spawnFn(bin, ["refresh", "--if-stale"], {
      detached: true,
      stdio: "ignore",
      timeout: REFRESH_TIMEOUT_MS,
      env,
    })
    child.on("error", () => {})
    child.unref()
    return true
  } catch {
    return false
  }
}