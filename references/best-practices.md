# Roblox / Luau Best Practices Reference

Source: CodedJack's Best Practices Handbook (DevForum, Sept 2023) + Roblox official docs. **This game** adds Rojo layout and lazy loaders under `ReplicatedStorage.Core`, `ClientRuntime`, `ServerRuntime`, and `UI` — see `references/server-client-architecture.md`.

---

## This repository (game2)

- **Strict + style**: Prefer `--!strict` and follow `.cursor/rules/luau-script-style-guide.mdc` (public API `PascalCase`, private helpers `_camelCase`, file section order, short intent comments).
- **Shared code**: Load through `Core` (see architecture doc), not long chains of `script.Parent.Parent...` unless there is already a local pattern.
- **Naming vs generic handbooks**: Handbooks often use `camelCase` for all functions; **this project** uses `PascalCase` for public module entry points and `camelCase` for locals — follow the Cursor rule file when it disagrees with tables below.

### Module loading (lazy, cached)

| API | Resolves under | Typical use |
|-----|----------------|-------------|
| `Core:Get(name)` | `ReplicatedStorage/Core/Modules` | Shared systems (Replica, Janitor, GameFX, …) |
| `Core:GetUtil(name)` | `Core/Utils` | StringUtil, FormatUtil, … |
| `Core:GetShared(name)` | `Core/Shared` | **`"Network"`** (Relay, channels, events) |
| `Core:GetConfig(name)` | `Core/Configs` | Data configs readable on both sides |
| `Core:GetType(name)` | `Core/Types` | Shared types |
| `Core:GetPackage(name)` | `Core/Packages` | Wally / vendored deps exposed through Core |
| `ClientRuntime:GetController(name)` | `ClientRuntime/Controllers` | Per-client controllers |
| `ClientRuntime:GetModule(name)` | `ClientRuntime/Modules` | Client-only helpers |
| `ClientRuntime:GetConfig(name)` | `ClientRuntime/Configs` | Client-side config copies |
| `ServerRuntime:GetService(name)` | `ServerStorage/ServerRuntime/Services` | DataService, EggService, … |
| `ServerRuntime:GetModule(name)` | `ServerRuntime/Modules` | Server-only modules |
| `ServerRuntime:GetConfig(name)` | `ServerRuntime/Configs` | Server configs |
| `ServerRuntime:GetPackage(name)` | `ServerRuntime/Packages` | Server-side packages |
| `UI:GetFrame(name)` | `ReplicatedStorage/UI/Frames` | Screen modules |
| `UI:GetButton(name)` | `ReplicatedStorage/UI/Buttons` | Button modules |

`Core` resolves folder children by name (ModuleScript or folder with `init` ModuleScript). `ClientRuntime` / `ServerRuntime` use similar rules; see each `init.luau` for concurrent-load and circular-dependency behavior.

---

## Naming Conventions

| Thing | Convention | Example |
|-------|-----------|---------|
| Variables | camelCase | `playerHealth`, `maxSpeed` |
| Functions | camelCase | `findClosestPlayer()` |
| Public module methods | PascalCase | `MyModule:GetData()` |
| Classes (OOP) | PascalCase | `EnemyController` |
| Constants | SCREAMING_SNAKE | `MAX_PLAYERS`, `BASE_DAMAGE` |
| Private module fields | _camelCase | `_cache`, `_connection` |
| Booleans | is/has prefix | `isAlive`, `hasStarted` |

---

## Guard Clauses

Always return early to avoid deep nesting.

```luau
-- BAD
local function process(player: Player, isValid: boolean)
    if isValid then
        if player then
            if player.Character then
                -- do stuff
            end
        end
    end
end

-- GOOD
local function process(player: Player, isValid: boolean)
    if not isValid then return end
    if not player then return end
    if not player.Character then return end
    -- do stuff
end
```

Use `assert()` as a guard when an invalid state is a hard error:
```luau
assert(player.Character, "Character must exist before calling this function")
```

---

## Module Scripts

Use ModuleScripts for all shared logic. Never duplicate code across scripts.

```luau
-- ModuleScript in ReplicatedStorage or ServerScriptService
local MyModule = {}

-- Type-annotated public method
function MyModule.GetDisplayName(player: Player): string
    return player.DisplayName .. " (#" .. player.UserId .. ")"
end

return MyModule
```

**This project**: Prefer the root facades instead of ad-hoc deep `require` paths:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Core = require(ReplicatedStorage:WaitForChild("Core"))

local Replica = Core:Get("Replica")
local StringUtil = Core:GetUtil("StringUtil")
local Net = Core:GetShared("Network")
```

- **Server-only** services: `require(ServerStorage.ServerRuntime)` then `ServerRuntime:GetService("EggService")` (or rely on `ServerRuntime:Start()` lifecycle).
- **Client-only** controllers: `require(ReplicatedStorage.ClientRuntime)` then `ClientRuntime:GetController("PlotController")`.
- **UI** modules: `require(ReplicatedStorage.UI)` then `UI:GetFrame("Inventory")` after `UI:Start()` has run (see architecture doc for boot order).

---

## DRY — Don't Repeat Yourself

If the same logic appears twice, it belongs in a ModuleScript function.

---

## Connections — Clean Up or Leak

```luau
-- One-shot: use :Once()
part.Touched:Once(function()
    -- fires once, auto-disconnects
end)

-- Stored connection: disconnect on cleanup
local connection = RunService.Heartbeat:Connect(function(dt)
    -- per-frame work
end)

-- Later, when done:
connection:Disconnect()
connection = nil
```

Store all connections that need cleanup. For player-scoped connections, disconnect in `Players.PlayerRemoving`.

---

## Deprecated APIs — Always Replace

| Old (deprecated) | New |
|-----------------|-----|
| `wait(n)` | `task.wait(n)` |
| `spawn(fn)` | `task.spawn(fn)` |
| `delay(n, fn)` | `task.delay(n, fn)` |
| `game.Players` (direct index) | `game:GetService("Players")` |
| `Instance.new("Part", parent)` | Set `.Parent` after all properties |

---

## Instance.new — Parent Last

```luau
-- BAD: triggers replication on every property change
local part = Instance.new("Part", workspace)
part.Size = Vector3.new(2, 2, 2)

-- GOOD: one replication event when parent is set
local part = Instance.new("Part")
part.Size = Vector3.new(2, 2, 2)
part.Anchored = true
part.Parent = workspace
-- Then connect signals AFTER parent is set
part.Touched:Connect(onTouched)
```

Order: `Instance.new` → assign properties → set `.Parent` → connect signals.

---

## Cloning vs Instance.new

If you need many identical objects, put a template in ReplicatedStorage or ServerStorage and `:Clone()` it. Cloning is significantly cheaper than building from `Instance.new` property by property.

```luau
local template = ReplicatedStorage.Templates.CoinPickup
local newCoin = template:Clone()
newCoin.Position = spawnPosition
newCoin.Parent = workspace
```

---

## GetService

Always use `game:GetService()` — never index services directly.

```luau
-- BAD
local players = game.Players
local rs = game.ReplicatedStorage

-- GOOD
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
```

---

## Type Annotations

Add type annotations to all non-trivial functions, especially in ModuleScripts.

```luau
type PlayerData = {
    coins: number,
    level: number,
    xp: number,
}

local function awardCoins(player: Player, amount: number): ()
    -- ...
end

local function getPlayerData(userId: number): PlayerData?
    -- returns nil if not found
end
```

---

## Comments and TODOs

```luau
-- TODO: Add mobile support before launch
-- NOTE: This fires once per server restart, not per player

-- Section separator for large scripts
-- ─────────────────────────────────────
-- COMBAT LOGIC
-- ─────────────────────────────────────
```

---

## Scalability — No Magic Numbers

```luau
-- BAD
if player.leaderstats.Coins.Value >= 500 then

-- GOOD
local SHOP_UNLOCK_COST = 500
if player.leaderstats.Coins.Value >= SHOP_UNLOCK_COST then
```

---

## YAGNI

Do not write code for features that don't exist yet. Dead code makes maintenance harder and confuses future readers (including yourself 3 months later).

---

## Goldilocks / Readability vs Performance

Readable code is the default. Only optimize for performance when profiling shows a real bottleneck. Over-engineering for imagined performance is a form of YAGNI.

---

## Whitespace and Structure

Prefer the file order from `.cursor/rules/luau-script-style-guide.mdc` (pragma, optional purpose line, services, requires, constants, types, private state, helpers, public API, `return`).

```luau
-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules (this repo)
local Core = require(ReplicatedStorage:WaitForChild("Core"))
local DataModule = Core:Get("SomeModule")

-- Constants
local RESPAWN_TIME = 5
local MAX_HEALTH = 100

-- State
local playerCache: {[number]: PlayerData} = {}

-- ─── Helper Functions ───────────────────────────

local function onPlayerAdded(player: Player): ()
    -- ...
end

-- ─── Connections ────────────────────────────────

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
```

---

## Related

- `references/server-client-architecture.md` — Rojo map, boot order, `Core` / `ClientRuntime` / `ServerRuntime` / `UI`, networking boundaries.
- `.cursor/skills/roblox-optimizer/SKILL.md` — agent workflow for reviews and optimizations against this repo.