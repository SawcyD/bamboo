# Framework Toolkit

This document describes the reusable gameplay and AI tools included in the
template. The tools are intentionally generic: a game supplies its own NPC
definitions, animation profiles, damage rules, interaction callbacks, and
spawn data.

## Architecture

```text
Enums
  Shared names and stable categories
        |
        v
Brain
  Chooses the next state or behavior
        |
        +--> Perception / Targeting
        +--> Navigation
        +--> Combat / Hitbox
        +--> Interaction
        |
        v
Motion
  Plays the animation that represents the decision
```

The server should own gameplay decisions. Clients may use the same modules for
presentation and prediction, but the server remains authoritative for targets,
movement outcomes, damage, spawning, and interactions.

## Available tools

### `Brain`

State machines and behavior trees. Use it to decide what an actor is doing.

```lua
local Brain = Core:Get("Brain")

local machine = Brain.StateMachine.new({
	Idle = {
		Update = function(context)
			if context.Target then
				return "Chase"
			end
		end,
	},
	Chase = {},
}, context, "Idle")

machine:Start()
```

Use a state machine when the actor has one active mode. Use a behavior tree
when the actor needs fallbacks and nested decisions.

### `Motion`

Controls `AnimationTrack` objects for players and NPCs. It supports profiles,
track caching, layers, crossfades, locomotion speed, markers, preloading, and
cleanup.

```lua
local Motion = Core:Get("Motion")

local profile = Motion.Profiles.Create({
	Idle = Motion.Profiles.Animation("rbxassetid://IDLE", true, Enum.AnimationPriority.Movement),
	Walk = Motion.Profiles.Animation("rbxassetid://WALK", true, Enum.AnimationPriority.Movement),
	Attack = Motion.Profiles.Animation("rbxassetid://ATTACK", false, Enum.AnimationPriority.Action),
}, {
	Idle = "Idle",
	Walk = "Walk",
	WalkSpeed = 8,
})

local controller = Motion.Controller.new(npc, profile)
controller:UpdateLocomotion(horizontalSpeed)
controller:Play("Attack", { Layer = "Action", FadeTime = 0.1 })
```

Use `TweenPlus` for properties such as UI size, transparency, or CFrames. Use
`Motion` for skeletal rig animation.

### `Enums`

Stable string-backed custom enums are available through `Core.Index` or
`Core:GetShared("Enums")`.

```lua
local Enums = Core:GetShared("Enums")

local state = Enums.Brain.State.Chase
if Enums.Brain.State.Is(state) then
	print("valid state", state)
end
```

Enum groups currently include `Brain`, `Motion`, `NPC`, `Collectibles`, and
`Common`. Each enum has `Is`, `Get`, `Assert`, `List`, and `Metadata` helpers.

### `ActorRegistry`

Tracks runtime models and provides radius and nearest-actor queries.

```lua
local actors = Core:Get("ActorRegistry").new()
actors:Register(npc, { Type = "Enemy", Tags = { Hostile = true } })

local nearby = actors:FindWithin(npc:GetPivot().Position, 50, function(record)
	return record.Type == "Enemy"
end)
```

The registry removes actors automatically when their models leave the data
model.

### `Perception`

Provides field-of-view checks, line-of-sight raycasts, detection signals, and
short-term last-known-position memory.

```lua
local perception = Core:Get("Perception").new(npc, {
	VisionRadius = 80,
	FieldOfView = 120,
	MemoryDuration = 5,
})

if perception:CanSee(playerCharacter) then
	perception:Remember(playerCharacter)
end
```

Call `Scan` on a scheduler interval instead of every render frame.

### `Targeting`

Selects valid targets using common strategies:

- `Nearest`
- `LowestHealth`
- `HighestThreat`
- `Random`

```lua
local Targeting = Core:Get("Targeting")
local target = Targeting.Select(candidates, "Nearest", {
	Origin = npc:GetPivot().Position,
	MaxDistance = 60,
	Ignore = npc,
})
```

Supply `IsValid` and `GetThreat` callbacks for game-specific rules.

### `Navigation`

Wraps `PathfindingService` for humanoid actors. It computes paths, follows
waypoints, detects blocked paths, and reports completion.

```lua
local navigation = Core:Get("Navigation").new(npc, {
	AgentCanJump = true,
	RepathInterval = 0.5,
})

navigation:SetDestination(targetPosition)

-- Usually driven by one shared scheduler for all NPCs.
navigation:Update(deltaTime)
```

Do not create a separate Heartbeat connection for every NPC. Use the existing
`Scheduler` module to stagger updates.

### `Hitbox`

Creates box-overlap hitboxes with per-activation deduplication.

```lua
local hitbox = Core:Get("Hitbox").new(attacker, {
	Size = Vector3.new(5, 4, 6),
	Offset = CFrame.new(0, 0, -3),
})

hitbox.Hit:Connect(function(target)
	print("hit", target)
end)

hitbox:Start(30)
```

Call `Reset` for a new attack activation. The hitbox will not report the same
target twice until it is reset.

### `Combat`

Provides validated damage, healing, invulnerability, death signals, and a
hitbox binding helper.

```lua
local combat = Core:Get("Combat").new({
	CanDamage = function(source, target)
		return source ~= target
	end,
})

combat:Damage(attacker, target, 25, { Ability = "Slash" })
```

Use this on the server. Client damage requests must be validated by a server
service before calling `Damage`.

### `Interaction`

Creates a validated `ProximityPrompt` interaction.

```lua
local interaction = Core:Get("Interaction").new(merchantPart, {
	ActionText = "Talk",
	ObjectText = "Merchant",
	CanInteract = function(player)
		return player.Character ~= nil
	end,
	OnInteract = function(player)
		openMerchantMenu(player)
	end,
})
```

The prompt is only a request boundary. The callback must still validate
ownership, distance, cooldowns, and permissions on the server.

### `SpawnService`

Provides bounded cloning, active-instance tracking, despawn cleanup, and
cancelable delayed respawning.

```lua
local spawner = Core:Get("SpawnService").new(enemyTemplate, {
	Parent = workspace.Enemies,
	MaxActive = 20,
})

local enemy = spawner:Spawn(spawnCFrame)
spawner:ScheduleRespawn(10, spawnCFrame)
```

Use `ObjectPool` instead when an actor can be safely reset and reused at high
frequency.

### `AnimationRegistry`

Stores named animation profiles for use with `Motion`.

```lua
local Motion = Core:Get("Motion")
local registry = Core:Get("AnimationRegistry")

registry.Register("Goblin", goblinProfile)
local profile = registry.Get("Goblin")
local controller = Motion.Controller.new(goblin, profile)
```

Keep asset IDs in profiles, not inside Brain states or NPC behavior code.

### `DebugDraw`

Visualizes points, lines, boxes, radii, and navigation paths in a temporary
`workspace.__FrameworkDebug` folder.

```lua
local DebugDraw = Core:Get("DebugDraw")
DebugDraw.Radius(npc:GetPivot().Position, 50, Color3.fromRGB(0, 255, 0), 1)
DebugDraw.Path(navigation:GetWaypoints(), Color3.fromRGB(0, 200, 255), 1)
```

Disable it in production with `DebugDraw.SetEnabled(false)`.

### `Profiler`

Measures named sections and records call count, total time, last time, and
maximum time.

```lua
local profiler = Core:Get("Profiler").new("NPC")
profiler:Begin("BrainTick")
brain:Tick(deltaTime)
profiler:End("BrainTick")

local snapshot = profiler:Snapshot()
```

Use one profiler per subsystem or service and report snapshots through a debug
tool rather than printing every frame.

### `Validation`

Validates payloads and definitions at boundaries.

```lua
local Validation = Core:Get("Validation")
local valid, errors = Validation.Table(payload, {
	Name = { Type = "string", Required = true },
	Damage = { Type = "number", Required = true, Min = 0, Max = 1000 },
})
```

Validation is especially important for client network payloads and content
profiles loaded from configuration.

## Recommended NPC composition

```text
NPCService
├── ActorRegistry
├── Brain
│   ├── Perception
│   ├── Targeting
│   └── Navigation
├── Motion
├── Hitbox
├── Combat
└── DebugDraw / Profiler
```

The NPC service owns lifecycle and scheduling. The Brain chooses behavior, the
Navigation tool moves the actor, the Motion tool presents the current action,
and Combat/Hitbox perform server-side gameplay effects.

## Update cadence

Use different rates for different work:

| Work | Suggested rate |
| --- | ---: |
| Combat hitbox | 20–30 Hz during an attack |
| Navigation update | 5–10 Hz |
| Perception scan | 5–10 Hz |
| Behavior tree tick | 5–15 Hz |
| Animation locomotion | 10–20 Hz or state-driven |
| Debug drawing | Only while debugging |

The values are starting points. Measure real workloads with `Profiler` and
adjust based on NPC count and device performance.

## Server-authority checklist

- Keep Brain decisions for NPC gameplay on the server.
- Validate client interaction and combat requests.
- Calculate damage and rewards on the server.
- Generate and enforce spawn limits on the server.
- Treat Motion and DebugDraw as presentation/development tools.
- Never trust client-provided target, damage, rarity, or ownership values.
