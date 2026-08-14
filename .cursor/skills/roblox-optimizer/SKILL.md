---
name: roblox-optimizer
description: >-
  Reviews and optimizes Roblox Luau in the game2 Rojo project for security, performance, server/client boundaries,
  and alignment with Core, ClientRuntime, ServerRuntime, and UI lazy loaders. Triggers on requests to review, optimize,
  or audit Luau; mentions of ReplicatedStorage, ServerStorage, ServerScriptService, StarterPlayer, remotes, replication,
  or server versus client; or Luau pasted in a Roblox context. Reads references/best-practices.md,
  references/server-client-architecture.md, and .cursor/rules/luau-script-style-guide.mdc when depth is needed.
---

# Roblox Script Optimizer (this project)

Structured review and optimization for **game2** (Rojo `src/` tree).

## Sources (read before a final verdict or large rewrite)

- `references/best-practices.md` — Luau habits, connections, Instance patterns, typing.
- `references/server-client-architecture.md` — runtimes, networking, replication, security boundaries.
- `.cursor/rules/luau-script-style-guide.mdc` — naming, file order, comments, controller/UI notes.

For a **section index and when to open which doc**, see [reference.md](reference.md) in this skill folder.

## Step 0 — Read the input

- **Single file**: Read that script end-to-end; note `require` targets and which runtime loads it.
- **Folder**: List `.luau` / `.lua` under the path, map requires to `Core`, `ClientRuntime`, `ServerRuntime`, or `UI`.
- **Pasted only**: Ask which context applies (server Script, client LocalScript/Module required on client, or shared Module under `ReplicatedStorage`) if you cannot infer from imports.

Use the workspace tools to open files; do not assume paths from memory.

## Step 1 — Classify each script

For each file, record:

| Property | Notes |
|----------|--------|
| **Runtime** | Server-only (`ServerRuntime`, `ServerScriptService`), client-only (`ClientRuntime`, `UI`, `StarterPlayerScripts`), or shared (`ReplicatedStorage.Core`, configs, etc.) |
| **Rojo path** | e.g. `src/ReplicatedStorage/...`, `src/ServerStorage/...` |
| **Role** | Service, controller, UI frame/button module, util, config, network event module, data layer |

Flag misplaced or risky patterns (server secrets in `ReplicatedStorage`, client-trusted economy, remotes without validation).

## Step 2 — Analyze (three tiers, no emoji markers)

### Critical (security / correctness)

- Server trusts client parameters without validation.
- Remote / bridge handlers missing type, range, permission, or cooldown checks.
- Sensitive or authoritative logic exposed where clients can read or bypass it.
- Leaks: connections, Heartbeat/RenderStep, threads never torn down.
- Dangerous yielding on server (e.g. blocking on client via `RemoteFunction` the wrong way).

### Performance (should fix)

- `Instance.new` with parent set too early; prefer properties then `.Parent` last.
- Hot paths: repeated `FindFirstChild` / `WaitForChild` where cache or reference is possible.
- `wait` / `spawn` / `delay` instead of `task.*`.
- `game.Players` etc. instead of `game:GetService(...)`.
- Heavy per-frame work without batching or throttling.

### Style / maintainability

- Match **this** repo: `.cursor/rules/luau-script-style-guide.mdc` (e.g. `PascalCase` public API, `_camelCase` helpers, `--!strict`, file section order).
- Magic numbers, deep nesting without guards, duplicated logic that should live in `Core` or a service.
- Missing types on non-trivial public surfaces when the file already uses `--!strict`.

## Step 3 — Architecture (folder or multi-file)

Use `references/server-client-architecture.md` for the canonical map of:

- `src/ServerScriptService`, `src/ServerStorage/ServerRuntime`, `src/ReplicatedStorage` (`Core`, `ClientRuntime`, `UI`, …), `src/StarterPlayer`.

Verify:

- Server boot: `Server.server.luau` → `Core:GetShared("Network")` then `ServerRuntime:Start()`.
- Client boot: `Client.client.luau` → `ClientRuntime:Start()` then `UI:Start()`.
- Lazy loading: `Core:Get*` / `ClientRuntime:Get*` / `ServerRuntime:Get*` / `UI:Get*` per that doc.

## Step 4 — Output format

Return, in order:

1. **Optimization Report** — script classification table; Critical; Performance; Style; Architecture notes if applicable.
2. **Rewritten code** (only if the user asked for edits) — per file, fenced `luau` blocks.

### Rewrite rules

1. Do not change gameplay or product intent unless the user asked for a behavior change; otherwise structure, safety, and performance only.
2. Prefer `task.wait` / `task.spawn` / `task.defer` over legacy globals.
3. `Instance.new`: configure instance, then set `Parent` last; connect signals after parenting when order matters.
4. Use `game:GetService("ServiceName")` for services.
5. Disconnect or unbind what you connect; prefer `:Once()` for one-shot listeners when appropriate.
6. Use guard clauses; avoid unnecessary depth.
7. Mark uncertain product decisions with `-- TODO:` briefly.
8. Match existing project loaders (`Core:Get…`, `ClientRuntime:Get…`, `ServerRuntime:Get…`, `UI:Get…`) instead of inventing new global singletons.

## Step 5 — Summary

After edits or a full review, add 3–8 bullets: what changed and why, plain English.

## Quick checks

- Client fires something the server listens to → server validates every argument and recomputes authoritative state.
- Module under `ReplicatedStorage` → treat as visible to exploiters; no secrets or trust-by-obscurity.
- `RemoteFunction` → never block the server waiting on a client; see architecture doc.
- `Core:GetShared("Network")` and event modules → validate payloads at boundaries; keep schema keys consistent with server.

---

## Using this skill in Cursor

This skill lives under **`.cursor/skills/roblox-optimizer/`** (`SKILL.md` plus optional [reference.md](reference.md)). Enable **project skills** for this workspace so the agent can auto-select it from the `description` triggers (review, optimize, remotes, server vs client, etc.). `@`-mention **`roblox-optimizer`** in chat when your build supports skill mentions.
