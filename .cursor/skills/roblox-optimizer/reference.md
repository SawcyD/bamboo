# Roblox optimizer — deep reference (read on demand)

Use this file when the task needs detail beyond `SKILL.md`. All paths are from the **repository root** (`game2`).

## Source documents (ground truth)

| Path | Use when |
|------|----------|
| `references/server-client-architecture.md` | Boot order, `Core` / `ClientRuntime` / `ServerRuntime` / `UI`, networking, replication, where code must live |
| `references/best-practices.md` | Luau patterns: connections, `Instance.new`, `GetService`, typing, DRY, deprecated APIs |
| `.cursor/rules/luau-script-style-guide.mdc` | Naming, file section order, controller/UI conventions for **this** repo |

## Section map — `references/server-client-architecture.md`

- **Rojo → Roblox map** — who can `require` which tree
- **Boot sequence** — `Server.server.luau` vs `Client.client.luau`, `Start()` order
- **`Core` / `ClientRuntime` / `ServerRuntime` / `UI`** — `Get*` APIs and roles
- **Networking** — `Core:GetShared("Network")`, RemoteFunction cautions
- **What lives where / Common mistakes** — misplaced authority, client trust

## Section map — `references/best-practices.md`

- **This repository (game2)** — lazy loaders table (`Core:Get`, `ServerRuntime:GetService`, …)
- **Connections — Clean up or leak** — Janitor / disconnect discipline
- **Deprecated APIs** — `task.*` vs legacy
- **Instance.new — Parent last** — property order
- **GetService** — no raw `game.Players` shortcuts
- **Type annotations / Scalability** — `--!strict`, magic numbers

## Quick path cheatsheet

- Server entry: `src/ServerScriptService/Server.server.luau`
- Client entry: `src/StarterPlayer/StarterPlayerScripts/Client.client.luau`
- Shared facade: `src/ReplicatedStorage/Core/`
- Client controllers: `src/ReplicatedStorage/ClientRuntime/Controllers/`
- Server services: `src/ServerStorage/ServerRuntime/Services/`
