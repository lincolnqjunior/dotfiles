// Honcho Workspace Router — pure logic module.
//
// Deliberately lives OUTSIDE ~/.config/opencode/plugins/ because OpenCode
// treats every export from a file in that directory as a plugin factory
// and invokes it with the plugin context object. Keeping the testable
// pure functions here (imported by the actual plugin file) avoids that
// footgun — see docs/runbooks/honcho-workspace-router.md for the
// discovery (E2E run against real opencode surfaced
// "fn is not a function" until this split was made).

import { existsSync, readFileSync, writeFileSync, renameSync, openSync, closeSync, unlinkSync } from "fs";
import { execFileSync } from "child_process";
import { homedir } from "os";
import path from "path";

export const HONCHO_CONFIG_PATH = path.join(homedir(), ".honcho", "config.json");
const LOCK_MAX_ATTEMPTS = 20;
const LOCK_RETRY_DELAY_MS = 50;

/**
 * Extract the GitHub org/owner from a remote URL.
 * Supports HTTPS (https://github.com/org/repo.git) and SSH
 * (git@github.com:org/repo.git) forms, with or without trailing
 * `.git` / trailing slash. Case of the captured org is preserved
 * (repoToWorkspace keys are case-sensitive, matching the Claude
 * Code plugin's getGitHubOrg behavior).
 *
 * @param {string | null | undefined} remoteUrl
 * @returns {string | null}
 */
export function extractGitHubOrg(remoteUrl) {
  if (!remoteUrl || typeof remoteUrl !== "string") {
    return null;
  }
  const httpsMatch = remoteUrl.match(/github\.com\/([^/]+)\//i);
  if (httpsMatch) {
    return httpsMatch[1];
  }
  const sshMatch = remoteUrl.match(/github\.com:([^/]+)\//i);
  if (sshMatch) {
    return sshMatch[1];
  }
  return null;
}

/**
 * Normalize an org name into a Honcho-safe workspace id: lowercase,
 * non [a-z0-9_-] runs collapsed to a single hyphen, leading/trailing
 * hyphens trimmed. Mirrors @honcho-ai/opencode-honcho's own
 * normalizeId() so ids we mint are consistent with ids it mints.
 *
 * @param {string} org
 * @returns {string}
 */
export function normalizeWorkspaceId(org) {
  if (!org || typeof org !== "string") {
    return "default";
  }
  const collapsed = org.toLowerCase().replace(/[^a-z0-9_-]+/g, "-");
  const trimmed = collapsed.replace(/^-+/, "").replace(/-+$/, "");
  return trimmed || "default";
}

/**
 * Decide which workspace an org routes to, given the existing
 * repoToWorkspace map. Exact case-sensitive match first; if absent,
 * mint a new normalized workspace id from the org name.
 *
 * @param {string} org
 * @param {Record<string, string> | null | undefined} repoToWorkspace
 * @returns {{ workspaceId: string, created: boolean }}
 */
export function resolveWorkspaceForOrg(org, repoToWorkspace) {
  if (repoToWorkspace && Object.prototype.hasOwnProperty.call(repoToWorkspace, org)) {
    return { workspaceId: repoToWorkspace[org], created: false };
  }
  return { workspaceId: normalizeWorkspaceId(org), created: true };
}

/**
 * Check whether cwd is (the root of, or inside) a git repo.
 * @param {string} cwd
 */
export function isGitRepo(cwd) {
  try {
    return existsSync(path.join(cwd, ".git"));
  } catch {
    return false;
  }
}

/**
 * Read the origin remote URL for a directory. Returns null on any
 * failure (not a git repo, no origin remote, git not installed,
 * directory missing) — never throws.
 *
 * @param {string} cwd
 * @returns {string | null}
 */
export function getGitRemoteOrigin(cwd) {
  try {
    const out = execFileSync("git", ["remote", "get-url", "origin"], {
      cwd,
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 5000,
      windowsHide: true,
    });
    const trimmed = out.toString("utf-8").trim();
    return trimmed || null;
  } catch {
    return null;
  }
}

/**
 * Read ~/.honcho/config.json. Returns null on missing file or
 * invalid JSON — callers must fail open (treat as "no mapping data"),
 * never crash plugin init over a corrupt config file.
 *
 * @param {string} configPath
 * @returns {{ ok: true, config: Record<string, any> } | { ok: false, reason: string }}
 */
export function readHonchoConfig(configPath) {
  let raw;
  try {
    raw = readFileSync(configPath, "utf-8");
  } catch (err) {
    if (err && err.code === "ENOENT") {
      return { ok: false, reason: "missing" };
    }
    return { ok: false, reason: `read-error: ${err instanceof Error ? err.message : String(err)}` };
  }
  try {
    return { ok: true, config: JSON.parse(raw) };
  } catch (err) {
    return { ok: false, reason: `invalid-json: ${err instanceof Error ? err.message : String(err)}` };
  }
}

/**
 * Acquire a simple exclusive lock (lockfile via O_EXCL) around fn,
 * retrying with a fixed delay if another process holds it. Blocking
 * is intentional and acceptable here: this only runs once per
 * plugin init (opencode startup), never per-request.
 *
 * @template T
 * @param {string} configPath
 * @param {() => T} fn
 * @returns {T}
 */
export function withConfigLock(configPath, fn) {
  const lockPath = `${configPath}.lock`;
  for (let attempt = 0; attempt < LOCK_MAX_ATTEMPTS; attempt++) {
    let fd;
    try {
      fd = openSync(lockPath, "wx");
    } catch (err) {
      if (err && err.code === "EEXIST") {
        const start = Date.now();
        while (Date.now() - start < LOCK_RETRY_DELAY_MS) {
          // intentional short synchronous spin; see doc comment above
        }
        continue;
      }
      throw err;
    }
    try {
      return fn();
    } finally {
      closeSync(fd);
      try {
        unlinkSync(lockPath);
      } catch {
        // lock already gone; nothing to clean up
      }
    }
  }
  throw new Error(`Could not acquire ${lockPath} after ${LOCK_MAX_ATTEMPTS} attempts`);
}

/**
 * Persist an updated repoToWorkspace mapping into ~/.honcho/config.json,
 * re-reading fresh under the lock so we never blindly overwrite a
 * concurrent writer's change. Writes atomically via write-tmp + rename.
 *
 * @param {string} configPath
 * @param {string} org
 * @param {string} workspaceId
 * @returns {{ persisted: boolean, reason?: string }}
 */
export function persistOrgMapping(configPath, org, workspaceId) {
  return withConfigLock(configPath, () => {
    const fresh = readHonchoConfig(configPath);
    if (!fresh.ok) {
      // Config missing or corrupt: don't fabricate a new file out of
      // thin air here — that's a bigger blast radius than this plugin
      // should own. Fail open: env var still gets set by the caller,
      // just the mapping isn't persisted this run.
      return { persisted: false, reason: fresh.reason };
    }
    const config = fresh.config;
    if (Object.prototype.hasOwnProperty.call(config, "repoToWorkspace") && Object.prototype.hasOwnProperty.call(config.repoToWorkspace, org)) {
      // Someone else (another concurrent process) already mapped this
      // org while we were detecting it. Nothing to do.
      return { persisted: false, reason: "already-mapped-concurrently" };
    }
    const nextConfig = {
      ...config,
      repoToWorkspace: {
        ...(config.repoToWorkspace || {}),
        [org]: workspaceId,
      },
    };
    const tmpPath = `${configPath}.tmp-${process.pid}-${Date.now()}`;
    writeFileSync(tmpPath, `${JSON.stringify(nextConfig, null, 2)}\n`, "utf-8");
    renameSync(tmpPath, configPath);
    return { persisted: true };
  });
}

/**
 * Full detection + resolution pipeline for a single directory, with
 * no side effects on process.env or the filesystem — pure enough to
 * unit test directly. The caller (plugin factory) applies the result.
 *
 * @param {string} cwd
 * @param {string} [configPath]
 * @returns {{ status: "no-git" | "no-remote" | "no-org" | "config-unreadable" | "routed", org?: string, workspaceId?: string, created?: boolean, configReason?: string }}
 */
export function detectWorkspaceRoute(cwd, configPath = HONCHO_CONFIG_PATH) {
  if (!isGitRepo(cwd)) {
    return { status: "no-git" };
  }
  const remoteUrl = getGitRemoteOrigin(cwd);
  if (!remoteUrl) {
    return { status: "no-remote" };
  }
  const org = extractGitHubOrg(remoteUrl);
  if (!org) {
    return { status: "no-org" };
  }
  const configResult = readHonchoConfig(configPath);
  if (!configResult.ok) {
    return { status: "config-unreadable", org, configReason: configResult.reason };
  }
  const { workspaceId, created } = resolveWorkspaceForOrg(org, configResult.config.repoToWorkspace);
  return { status: "routed", org, workspaceId, created };
}
