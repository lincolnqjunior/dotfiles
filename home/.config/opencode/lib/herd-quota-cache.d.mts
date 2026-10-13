// Tipos de herd-quota-cache.mjs.
//
// O helper é `.mjs` (mesmo formato do precedente `honcho-workspace-router-core.mjs`)
// e o plugin é TypeScript strict. Sem esta declaração o import cai em
// "could not find a declaration file" e o `tsc` do plugins dir quebra — e a
// saída seria `any`, que este repo não aceita.

/** Janela no formato que o widget do statusline já sabe desenhar. */
export interface CacheQuotaWindow {
  key: "5h" | "7d" | "30d";
  usedPct: number;
}

export interface QuotaReadResult {
  /** Janelas `governs: true` com duração canônica. Vazio = nada a desenhar. */
  windows: CacheQuotaWindow[];
  /** true ⇒ entrada velha/ausente/erro: o writer precisa ser disparado. */
  stale: boolean;
  /** `status` da entrada (`"ok"`, `"auth_error"`, ...) ou null se ilegível. */
  status: string | null;
}

export interface ReadQuotaWindowsOptions {
  now?: number;
  maxAgeMs?: number;
  dir?: string;
  home?: string;
}

export interface ResolveQuotaBinOptions {
  env?: Record<string, string | undefined>;
  hubRoot?: string;
}

export interface TriggerQuotaRefreshOptions extends ResolveQuotaBinOptions {
  spawnFn?: typeof import("node:child_process").spawn;
}

export declare const CACHE_SCHEMA: "herd-quota/v1";
export declare const READER_MAX_AGE_MS: number;
export declare const REFRESH_TIMEOUT_MS: number;

export declare function cacheDir(home?: string): string;
export declare function keyForSeconds(seconds: unknown): "5h" | "7d" | "30d" | undefined;
export declare function readQuotaWindows(providerID: string, options?: ReadQuotaWindowsOptions): Promise<QuotaReadResult>;
export declare function resolveQuotaBin(options?: ResolveQuotaBinOptions): string | null;
export declare function triggerQuotaRefresh(options?: TriggerQuotaRefreshOptions): boolean;