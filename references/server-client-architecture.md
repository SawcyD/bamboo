# Server / Client Architecture (this repository)

This document describes **game2** as laid out under Rojo (`src/`). Generic Roblox DataModel rules still apply; paths below are the ones this codebase uses daily.

---

## Rojo → Roblox map (`src/`)

| Rojo path | Roblox location | Who can require it |
|-----------|-----------------|-------------------|
| `src/ReplicatedStorage/**` | `ReplicatedStorage` | Server and every client (contents are visible to clients) |
| `src/ServerStorage/**` | `ServerStorage` | Server only |
| `src/ServerScriptService/**` | `ServerScriptService` | Server only |
| `src/StarterPlayer/**` | `StarterPlayer` (e.g. `StarterPlayerScripts`) | Client (per player) |

**Rule of thumb:** Anything under `ReplicatedStorage` must be treated as **public** — no API keys, ban lists, or authoritative secrets in ModuleScripts there.

---

## Boot sequence (entry scripts)

### Server — `src/ServerScriptService/Server.server.luau`

1. `require(ReplicatedStorage.Core)`
2. `require(ServerStorage.ServerRuntime)`
3. `Core:GetShared("Network")` — initializes / registers network layer used by services and clients.
4. `ServerRuntime:Start()` — discovers `ServerRuntime/Services`, `require`s each ModuleScript (skips names starting with `_`), caches instances, calls `service:Start(ServerRuntime)` when present.

Server game logic should live in **services** and **server modules**, not in long Scripts beside the entry file.

### Client — `src/StarterPlayer/StarterPlayerScripts/Client.client.luau`

1. `require(ReplicatedStorage.ClientRuntime)` → `ClientRuntime:Start()` (loads controllers under `ClientRuntime/Controllers`; skips `_` prefixed names).
2. `require(ReplicatedStorage.UI)` → `UI:Start()` — loads `UI/Buttons` and `UI/Frames` ModuleScripts and calls `:Start(UI)` when exported tables expose `Start`.

**Order matters:** run `ClientRuntime:Start()` before `UI:Start()` so controllers and shared state are ready for frames that depend on them.

---

## `Core` (`ReplicatedStorage.Core`)

Single shared facade for **Modules**, **Utils**, **Shared**, **Types**, **Packages**, and **Configs**.

| Method | Folder under `Core` | Purpose |
|--------|----------------------|---------|
| `Core:Get(name)` | `Modules` | Game systems (e.g. Replica, Janitor, GameFX) |
| `Core:GetUtil(name)` | `Utils` | Pure helpers |
| `Core:GetShared(name)` | `Shared` | Cross-cutting shared code; **`GetShared("Network")`** is the networking entry |
| `Core:GetType(name)` | `Types` | Shared type modules |
| `Core:GetPackage(name)` | `Packages` | Packaged dependencies surfaced through Core |
| `Core:GetConfig(name)` | `Configs` | Static gameplay config |

Implementation details (caching, concurrent load waits, folder-vs-`init` ModuleScript) live in `Core/init.luau`. Prefer `Core:Get*` over duplicating `require` paths across the game.

---

## `ClientRuntime` (`ReplicatedStorage.ClientRuntime`)

**Client only** — `assert(not RunService:IsServer(), ...)` in `init.luau`.

| Method | Folder | Purpose |
|--------|--------|---------|
| `ClientRuntime:GetController(name)` | `Controllers` | Feature controllers (Egg, Plot, …) |
| `ClientRuntime:GetModule(name)` | `Modules` | Client-only helpers |
| `ClientRuntime:GetConfig(name)` | `Configs` | Client config shards |
| `ClientRuntime:Start()` | — | Bootstraps controllers (see `init.luau`) |

Controllers should listen to shared data / network and drive visuals; **authoritative** changes still originate on the server.

---

## `ServerRuntime` (`ServerStorage.ServerRuntime`)

**Server only** — `assert(RunService:IsServer(), ...)` in `init.luau`.

| Method | Folder | Purpose |
|--------|--------|---------|
| `ServerRuntime:GetService(name)` | `Services` | Long-lived services (DataService, EggService, …) |
| `ServerRuntime:GetModule(name)` | `Modules` | Server-only library code |
| `ServerRuntime:GetConfig(name)` | `Configs` | Server-side config |
| `ServerRuntime:GetPackage(name)` | `Packages` | Server-side packages |
| `ServerRuntime:Start()` | — | Loads and starts each service module (skips `_` prefix); passes `ServerRuntime` into `service:Start(ServerRuntime)` |

Use `GetService` / `GetModule` for lazy access from other services instead of circular `require` graphs where possible.

---

## `UI` (`ReplicatedStorage.UI`)

**Client only** — asserts not server.

| Method | Folder | Purpose |
|--------|--------|---------|
| `UI:GetFrame(name)` | `Frames` | Screen / panel modules |
| `UI:GetButton(name)` | `Buttons` | Button modules |
| `UI:Start()` | — | Requires each public ModuleScript and calls `:Start(UI)` when defined |

Frames and buttons should stay thin: bind to controllers / replica data; avoid putting authoritative rules here.

---

## Networking (`Core:GetShared("Network")`)

`Core/Shared/Network` hosts Relay (signals, util) and generated / hand-written **event** modules under `Shared/Network/Events`. Treat every inbound payload as **untrusted** until the server validates types, ranges, and permissions.

Patterns to preserve:

- **Server authority** — economy, inventory, hatch results, etc. are computed on the server; clients display outcomes.
- **Validate at boundaries** — match event names and payload shapes to one schema; reject malformed or out-of-range data early (`typeof`, caps, ownership).

### RemoteEvent-style usage (conceptual)

Bridge / table payloads replace classic `RemoteEvent` snippets in many places, but the **same security rules** apply: server listeners must not trust client-supplied currency, damage, or IDs without checks.

### RemoteFunction caution

Do not block the server waiting on a client response. Prefer events or server-computed replies. If `RemoteFunction` exists for a legacy path, keep server invoke handlers short and never yield on client completion.

---

## Script type rules (Roblox)

| Script kind | Runs on | Notes |
|-------------|---------|--------|
| `Script` | Server | e.g. `Server.server.luau` |
| `LocalScript` / client `ModuleScript` required from client | Client | `Client.client.luau`, UI, controllers |
| `ModuleScript` | Whoever required it | Same file on disk in `ReplicatedStorage` runs in **separate** VMs on server vs each client — state is not shared |

---

## Golden rule (unchanged)

> **The server is the authority. The client is never trusted.**

Every client → server path MUST:

1. Validate **type** of each argument.
2. Validate **range / domain** (no negative costs, no impossible IDs).
3. Check **permission** (player owns plot, item, cooldown OK).
4. Apply state on the **server**; never accept a client-precomputed balance or reward.

```luau
-- BAD — trusting client numbers
PurchaseItem.OnServerEvent:Connect(function(player, itemId, newCoinTotal)
	player.leaderstats.Coins.Value = newCoinTotal
end)

-- GOOD — server recomputes
PurchaseItem.OnServerEvent:Connect(function(player, itemId)
	if typeof(itemId) ~= "string" then return end
	local cost = ShopModule.GetCost(itemId)
	if not cost then return end
	-- read authoritative currency from server data, debit, grant item
end)
```

---

## What lives where (project-specific)

| Need | Location in this repo |
|------|-------------------------|
| Shared modules, configs, utils | `ReplicatedStorage/Core/...` via `Core:Get*` |
| Shared networking | `Core:GetShared("Network")` and `Core/Shared/Network/**` |
| Client controllers | `ReplicatedStorage/ClientRuntime/Controllers` via `ClientRuntime:GetController` |
| Client UI pieces | `ReplicatedStorage/UI/Frames`, `UI/Buttons` via `UI:GetFrame` / `GetButton` |
| Server services | `ServerStorage/ServerRuntime/Services` via `ServerRuntime:GetService` or `Start()` |
| Server-only helpers | `ServerStorage/ServerRuntime/Modules` |
| Server entry | `ServerScriptService/Server.server.luau` |
| Client entry | `StarterPlayer/StarterPlayerScripts/Client.client.luau` |
| Secrets, server-only assets | `ServerStorage` (never replicate to clients) |

---

## Replication and data

When this game uses **Replica** (or similar) under `Core`, treat replicated blobs as **display + prediction** inputs unless the server has already validated the action. UI and controllers react to replica changes; services mutate data and push updates through the established adapter.

Use attributes or tagged instances for simple replicated state only when the pipeline already standardizes it — avoid ad-hoc parallel sources of truth.

---

## Common mistakes (updated for this tree)

| Mistake | Fix |
|---------|-----|
| `require` deep paths to `Core/Modules/...` everywhere | Use `Core:Get("...")` / `GetUtil` / `GetShared` for consistency and cache behavior |
| Skipping `Core:GetShared("Network")` on server | Server boot must initialize network before relying on bridges |
| Calling `UI:Start()` before `ClientRuntime:Start()` | Flip order in `Client.client.luau` |
| Putting secrets in `ReplicatedStorage` | Move to `ServerStorage` or server-only modules |
| Trusting client event payloads | Validate in the service or dedicated network boundary |
| Blocking server on client | Avoid server → client `RemoteFunction` patterns that yield |

---

## Service references (`game:GetService`)

Keep using `game:GetService("Players")`, `RunService`, `ReplicatedStorage`, `ServerStorage`, etc. At the top of scripts; pair with the loaders above instead of hard-coding long instance chains.

```luau
local RunService = game:GetService("RunService")
local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()
```

---

## Folder skeleton (this repo)

```
src/
├── ReplicatedStorage/
│   ├── Core/                  # Core:Get*, Shared (Network), Modules, Utils, Configs, Types, Packages
│   ├── ClientRuntime/       # Controllers, Modules, Configs + :Start()
│   ├── UI/                    # Frames, Buttons + :Start()
│   └── Audio/                 # (and other shared roots as needed)
├── ServerStorage/
│   └── ServerRuntime/         # Services, Modules, Configs, Packages + :Start()
├── ServerScriptService/
│   └── Server.server.luau
└── StarterPlayer/
    └── StarterPlayerScripts/
        └── Client.client.luau
```

Extend subfolders as the game grows; new **services** go under `ServerRuntime/Services`, new **controllers** under `ClientRuntime/Controllers`, new **UI** under `UI/Frames` or `UI/Buttons`, and shared logic under `Core` with the appropriate `Get*` family.

---

## Related

- `references/best-practices.md` — Luau habits, connections, `GetService`, typing, project loader examples.
- `.cursor/skills/roblox-optimizer/SKILL.md` — structured review steps (Critical / Performance / Style) and rewrite rules for this codebase.
