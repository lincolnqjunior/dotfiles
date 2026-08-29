// Honcho Workspace Router — global OpenCode plugin
//
// Detects the GitHub org of the current repo (via `git remote get-url origin`)
// and sets HONCHO_WORKSPACE_ID before the @honcho-ai/opencode-honcho plugin's
// hooks ever read it, so each repo/org routes to its own Honcho workspace
// instead of always falling back to the single workspace configured in
// hosts.opencode.workspace.
//
// Source of truth: ~/.honcho/config.json -> repoToWorkspace (same field the
// Claude Code Honcho plugin already reads/writes). If an org has no mapping,
// a new workspace id is derived from the org name and persisted back so
// future runs (and Claude Code) pick it up automatically.
//
// Does NOT modify @honcho-ai/opencode-honcho itself, so `opencode plugin
// "@honcho-ai/opencode-honcho" --force` cannot break this file. If the
// upstream plugin ever stops reading HONCHO_WORKSPACE_ID, this router
// fails open (env var is simply ignored, default workspace behavior
// resumes) — it never throws in a way that blocks opencode startup.
//
// IMPORTANT: OpenCode treats EVERY export of a file under
// ~/.config/opencode/plugins/ as a plugin factory and calls it with the
// plugin context object. This file therefore exports exactly ONE thing
// (the default plugin factory below) — all testable pure logic lives in
// ../lib/honcho-workspace-router-core.mjs, which is outside the
// auto-scanned plugins directory.

import { HONCHO_CONFIG_PATH, detectWorkspaceRoute, persistOrgMapping } from "../lib/honcho-workspace-router-core.mjs";

const HonchoWorkspaceRouterPlugin = async ({ directory, worktree, client } = {}) => {
  const cwd = worktree || directory || process.cwd();
  const log = async (level, message, extra) => {
    try {
      if (client && client.app && typeof client.app.log === "function") {
        await client.app.log({
          body: { service: "honcho-workspace-router", level, message, extra: extra || {} },
        });
      }
    } catch {
      // Logging must never break plugin init.
    }
  };

  try {
    const route = detectWorkspaceRoute(cwd);

    if (route.status === "no-git" || route.status === "no-remote" || route.status === "no-org") {
      await log("info", "No GitHub org detected; leaving Honcho workspace at its configured default.", { cwd, status: route.status });
      return {};
    }

    if (route.status === "config-unreadable") {
      await log("warn", "Honcho config unreadable; skipping workspace routing for this session.", { cwd, org: route.org, reason: route.configReason });
      return {};
    }

    process.env.HONCHO_WORKSPACE_ID = route.workspaceId;

    if (route.created) {
      const result = persistOrgMapping(HONCHO_CONFIG_PATH, route.org, route.workspaceId);
      await log("info", "Routed to newly-created Honcho workspace for unmapped org.", {
        cwd,
        org: route.org,
        workspaceId: route.workspaceId,
        persisted: result.persisted,
        persistReason: result.reason,
      });
    } else {
      await log("info", "Routed to existing Honcho workspace mapping.", {
        cwd,
        org: route.org,
        workspaceId: route.workspaceId,
      });
    }
  } catch (err) {
    // Never let routing failures block opencode startup.
    await log("error", "Honcho workspace routing failed; leaving default workspace in place.", {
      cwd,
      error: err instanceof Error ? err.message : String(err),
    });
  }

  return {};
};

export default HonchoWorkspaceRouterPlugin;
