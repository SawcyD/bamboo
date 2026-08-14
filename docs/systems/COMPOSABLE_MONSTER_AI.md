# Composable Monster AI System

This document describes the proposed monster framework for monsters whose
identity comes from a small number of unusual mechanics rather than from a
large, one-off AI script.

The system is called **Composable Monster AI** because a monster is assembled
from reusable pieces:

- a shared AI state machine;
- one or more perception or gameplay sensors;
- one or more abilities or actions;
- a data-only monster definition;
- client-side presentation such as animation, audio, camera effects, and UI.

The design is also **data-driven**. A monster definition selects the pieces it
uses and supplies their tuning values. The core AI does not contain branches
such as `if monsterType == "Spectre" then ...`.

## The goal

The first two monsters are experiments with different player-facing hooks:

| Monster | MVP hook | Test goal |
| --- | --- | --- |
| Spectre | Reversed distance-based 3D sound and close-range possession | Determine whether inverted distance audio tricks players or feels confusing and broken. |
| Iris | Gaze/cone-of-sight checks combined with flashlight collision | Determine whether the player can make fast visual decisions using gaze, peripheral vision, and light. |

The framework should make it cheap to answer those questions. We should be
able to tune or replace a sensor without rewriting the state machine, and we
should be able to add a third monster without copying Spectre's or Iris's
controller.

## Where it lives

The system should follow the existing framework boundaries:

```text
src/
├── ReplicatedStorage/
│   └── Core/
│       ├── Shared/
│       │   └── Monsters/
│       │       ├── init.luau
│       │       ├── Types.luau
│       │       ├── Registry.luau
│       │       └── Catalog/
│       │           ├── Spectre.luau
│       │           └── Iris.luau
│       │
│       └── Modules/
│           └── MonsterAI/
│               ├── init.luau
│               ├── Agent.luau
│               ├── StateMachine.luau
│               ├── Blackboard.luau
│               ├── SensorRegistry.luau
│               ├── AbilityRegistry.luau
│               ├── Sensors/
│               │   ├── Proximity.luau
│               │   ├── ReversedDistanceSound.luau
│               │   ├── GazeCone.luau
│               │   └── FlashlightDetection.luau
│               └── Abilities/
│                   ├── Possession.luau
│                   └── Attack.luau
│
├── ServerStorage/
│   └── ServerRuntime/
│       ├── Services/
│       │   └── MonsterService.luau
│       └── Modules/
│           └── MonsterComponent.luau
│
└── ReplicatedStorage/
    └── ClientRuntime/
        ├── Controllers/
        │   └── MonsterPresentationController.luau
        └── Modules/
            └── MonsterPresentation.luau
```

This is a target layout, not a requirement that every file be created before
the first prototype works. The smallest useful implementation can start with
one registry, one agent, one server component, and one sensor.

## Existing systems this reuses

This system should not create a second animation framework.

- `Core/Shared/Animations` owns reusable animation profile definitions and the
  animation registry.
- `Core/Modules/Motion` owns runtime animation loading, track caching,
  crossfading, layers, markers, and cleanup.
- `ClientRuntime/Modules/AnimatedNPC` is the existing example of a tagged
  client-side visual component for stationary NPCs.
- `Core/Modules/Perception` already provides general vision, field-of-view,
  raycast, detection, and short-term memory behavior that specialized sensors
  can build on.
- `Core/Modules/Component` provides the CollectionService tag lifecycle.
- `ServerRuntime/Services` is where authoritative monster gameplay should be
  started and owned.

The monster AI decides that a state or ability changed. The presentation layer
turns that decision into Motion, sound, effects, and camera feedback.

## World authoring

A monster model in Workspace is authored with a CollectionService tag and a
small number of attributes:

```text
Tag:        Monster
Attribute:  MonsterType = "spectre"
```

The stable ID is a content ID, not necessarily the model's name. This lets a
level designer rename the model without changing which definition it uses.

Optional attributes can override safe presentation or tuning values, but the
definition registry remains the source of the normal configuration:

```text
MonsterType       = "spectre"
AnimationProfile  = "spectre"       -- optional override
DebugAI           = true             -- development-only option
```

The server-side component listens for the `Monster` tag. When a tagged model
appears, it:

1. validates that the instance is a usable model;
2. reads `MonsterType`;
3. retrieves the definition from `Monsters.Registry`;
4. constructs an AI agent for that model;
5. creates the configured sensors and abilities;
6. starts the agent's lifecycle;
7. destroys the agent when the tag is removed, the model is destroyed, or the
   model streams out.

The client can have a separate presentation component listening to the same
tag. It should not make authoritative gameplay decisions merely because it
observes the tag.

## The shared Monsters domain

`Core/Shared/Monsters` is a catalog and contract layer. It describes what
monster types exist and how they are composed. It does not own live AI state.

### `Types.luau`

This module describes the shape of definitions and configuration. A proposed
shape is:

```lua
export type SensorConfig = {
	[string]: any,
}

export type AbilityConfig = {
	[string]: any,
}

export type Definition = {
	Id: string,
	DisplayName: string,
	Sensors: {
		[string]: SensorConfig?,
	},
	Abilities: {
		[string]: AbilityConfig?,
	},
	InitialState: string,
	AnimationProfile: string?,
}
```

The exact type can become stricter once the first sensors and abilities have
settled. It should not contain a live target, current state, connections, or
Instances. Those belong to a runtime agent.

### `Registry.luau`

The registry maps stable IDs to definitions. It may lazily require catalog
modules, just like the animation registry:

```text
"spectre"    -> Catalog/Spectre.luau
"iris"       -> Catalog/Iris.luau
```

ModuleScript results are cached by Roblox. Asking for a definition again does
not recreate an AI agent or reload every animation. The registry only returns
configuration. Each spawned monster gets its own runtime agent.

The registry should expose a small API:

```lua
Monsters.Registry.Get("spectre")       -- returns nil for an unknown ID
Monsters.Registry.Require("spectre")   -- errors for an invalid ID
Monsters.Registry.List()                -- useful for tools and tests
```

### Catalog definitions

Catalog modules should be small and declarative. They select named sensors and
abilities and provide tuning values:

```lua
-- Core/Shared/Monsters/Catalog/Spectre.luau

return {
	Id = "spectre",
	DisplayName = "Spectre",
	InitialState = "Stalk",
	AnimationProfile = "spectre",

	Sensors = {
		Proximity = {
			PossessionRange = 12,
		},
	},

	Abilities = {
		Possession = {
			Cooldown = 20,
		},
	},
}
```

```lua
-- Core/Shared/Monsters/Catalog/Iris.luau

return {
	Id = "iris",
	DisplayName = "Iris",
	InitialState = "Observe",
	AnimationProfile = "iris",

	Sensors = {
		GazeCone = {
			FieldOfView = 35,
			Range = 100,
		},
		FlashlightDetection = {
			Range = 60,
			RequiredExposure = 0.25,
		},
	},

	Abilities = {
		Attack = {
			Cooldown = 4,
		},
	},
}
```

The strings `Proximity`, `GazeCone`, `Possession`, and `Attack` are registry
keys. The definition does not require the implementation module directly.
That keeps content separate from runtime behavior and prevents every catalog
file from constructing its own classes.

## Runtime pieces

### MonsterService

`MonsterService` is the server entry point. It starts the monster component or
the monster manager and owns the collection of active agents.

Its responsibilities are:

- activate the `Monster` tag binding;
- provide the server update loop or scheduler hook;
- create and destroy agents;
- expose controlled debug and test hooks;
- coordinate server-side monster events;
- avoid putting one-off Spectre or Iris logic in the service.

It should not become a giant switch statement. If the service needs to know
whether a monster is a Spectre, the definition or an ability should own that
decision instead.

### MonsterComponent

The component is the bridge between a Workspace model and an agent:

```text
CollectionService tag "Monster"
            |
            v
MonsterComponent(model)
            |
            v
MonsterAI.Agent.new(model, definition)
```

The component owns the agent's lifetime. The agent owns the AI state, sensor
instances, ability instances, blackboard, and cleanup connections.

### Agent

An agent is one live monster. Two Spectre models use the same definition but
have different agents and different runtime state.

An agent contains:

```text
Agent
├── Model
├── Definition
├── StateMachine
├── Blackboard
├── Sensors
├── Abilities
└── Janitor/connections
```

The agent provides the shared lifecycle:

```lua
Agent:Start()
Agent:Update(dt)
Agent:TransitionTo("Chase")
Agent:Trigger("Possession", target)
Agent:Destroy()
```

These are conceptual APIs. The first implementation should keep the public
surface small and grow it only when a real monster needs another operation.

### StateMachine

The state machine coordinates behavior but does not know the implementation
details of each monster's special mechanic.

Common states could be:

```text
Dormant
Observe
Patrol
Investigate
Stalk
Chase
Attack
Recover
Disabled
Dead
```

The first MVP does not need every state. Spectre might start with `Stalk`,
`Possessing`, and `Recover`. Iris might start with `Observe`, `Exposed`, and
`Attack`.

A state reads normalized sensor results from the blackboard and invokes an
ability when its conditions are met. It should not perform raw raycasts or
directly manipulate animation tracks.

### Blackboard

The blackboard is short-lived runtime knowledge for one agent. It is not
player data and should not be replicated as a large table every frame.

Example values:

```text
Target                 = Player
TargetPosition         = Vector3
LastKnownPosition      = Vector3
DistanceToTarget       = number
IsTargetVisible        = boolean
IsTargetLookingAtMe    = boolean
IsTargetIlluminatingMe = boolean
LastSensorEventAt      = number
```

Sensors write observations. States and abilities read them. This keeps sensor
implementations independent from state implementations.

## Sensors

A sensor answers one question about the world or produces an observation. It
should have a narrow responsibility and be independently testable.

A normalized sensor result might look like:

```lua
{
	Kind = "TargetDetected",
	Target = player,
	Position = targetPosition,
	Confidence = 1,
	ObservedAt = workspace:GetServerTimeNow(),
}
```

Possible sensor lifecycle:

```lua
local sensor = Sensor.new(agent, config)
sensor.Observed:Connect(function(observation)
	agent.Blackboard:Apply(observation)
end)

sensor:Update(dt)
sensor:Destroy()
```

Sensors should not directly start an attack or possession. They report facts;
the state machine and ability rules decide what those facts mean.

### Shared perception

The existing `Perception` module is a good base for generic vision:

- radius check;
- field-of-view check;
- raycast occlusion check;
- detected/lost signals;
- last-known-position memory.

Specialized sensors can wrap it or use it as one part of a larger check.

### Spectre sensor and audio hook

The Spectre experiment has two related but separate concerns:

1. **Gameplay proximity**: the server determines whether a player is in range
   for a possession attempt.
2. **Reversed distance audio**: the client presents the audio response based on
   the monster-player distance.

The audio should not be used as proof of gameplay state. It can be intentionally
misleading. The exact inverse curve should be tunable:

```text
distance -> normalized value -> volume / EQ / spatial effect
```

For example, the sound could become louder, clearer, or more directional as
the player moves away. The system should make this curve easy to replace while
the test is running between playtests.

The possession range check remains server-authoritative. The client receives
the approved possession event and plays the corresponding animation, camera
effect, sound, or input treatment.

### Iris gaze sensor

The Iris experiment depends on the player's camera direction. The client has
the most accurate local gaze information, but the client is not authoritative.

The safe pattern is:

```text
client observes camera/gaze
        |
        v
client sends a typed observation/request
        |
        v
server validates target, range, line of sight, and timing
        |
        v
server accepts or rejects the state change
```

The server should independently check the important parts with a raycast and
known replicated character state. A client message can be a useful hint, but
it must not by itself grant damage, possession, escape, or another important
result.

### Iris flashlight sensor

The flashlight sensor can combine:

- flashlight enabled state;
- beam origin and direction;
- distance to Iris;
- cone intersection;
- raycast collision or obstruction;
- required exposure time.

The sensor should output an observation such as `Illuminated` or
`LostIllumination`. The Iris state machine can then decide whether Iris freezes,
retreats, attacks, or becomes vulnerable.

## Abilities

An ability performs an intentional action. It may have:

- a condition check;
- a cooldown;
- a target;
- a start event;
- a duration;
- an end or cancellation event;
- server-side validation;
- a client presentation event.

Conceptually:

```lua
local ability = Ability.new(agent, config)

if ability:CanStart(target) then
	ability:Start(target)
end
```

### Possession

The Spectre's possession ability should be server-owned because it changes the
player's gameplay state.

The server validates at least:

- the Spectre and target still exist;
- the target is a valid player character;
- the distance is within range;
- the ability is off cooldown;
- the Spectre is allowed to act in its current state;
- the target is not already protected, dead, or possessed.

After validation, the server emits the approved event. The client can then:

- play a possession animation through Motion;
- play the associated sound and visual effect;
- apply camera or UI treatment;
- show a temporary control effect if that is part of the design.

The client must not be able to declare that possession succeeded.

### Attack and other abilities

Iris can use the same ability contract for an attack, retreat, reveal, or
flashlight reaction. The behavior is selected by the definition and state
machine rather than by duplicating a complete Iris controller.

## Presentation and animation

The monster AI should communicate presentation through semantic state names:

```text
Monster state: "Observe"
Animation state: "Idle"

Monster state: "Possessing"
Animation state: "Possess"
```

The presentation layer resolves the monster's animation profile through the
existing animation domain:

```text
Monster definition
    └── AnimationProfile = "spectre"
             |
             v
Core/Shared/Animations/Registry
             |
             v
Core/Modules/Motion/AnimationController
```

This keeps AI behavior independent from asset IDs. Replacing a Spectre's
animation should normally mean editing its animation profile, not editing the
AI state machine.

Static shopkeepers remain handled by `AnimatedNPC`. Moving or behavior-driven
monsters use a monster presentation component, but both use the same Motion
controller underneath.

## Server and client ownership

The rule for this system is:

```text
Server: gameplay truth
Client: local observation and presentation
```

### Server owns

- monster state that affects gameplay;
- target selection when it matters;
- movement and attack decisions;
- possession, damage, vulnerability, and cooldowns;
- validation of client-derived observations;
- spawning and destroying authoritative monsters;
- replicated state or approved action events.

### Client owns

- animation playback;
- 3D sound and reversed audio curves;
- camera effects;
- local flashlight and camera sampling;
- UI and feedback;
- optional prediction that is corrected by the server.

Do not replicate the entire blackboard every frame. Replicate only the state,
action, or event needed by clients. High-frequency visual calculations can stay
local when they do not determine authoritative gameplay.

## Complete example flows

### Spectre

```text
1. Workspace model has tag "Monster" and MonsterType = "spectre".
2. MonsterComponent gets the Spectre definition.
3. Agent creates Proximity sensor and Possession ability.
4. StateMachine starts in Stalk.
5. Client presentation calculates the reversed distance audio curve.
6. Proximity reports a player inside possession range.
7. StateMachine asks Possession whether it can start.
8. Server validates range, cooldown, target, and current state.
9. Server starts Possession and sends an approved presentation event.
10. Client plays the Spectre possession animation and effects through Motion.
11. Ability ends or is cancelled; the agent enters Recover or Stalk.
```

### Iris

```text
1. Workspace model has tag "Monster" and MonsterType = "iris".
2. MonsterComponent gets the Iris definition.
3. Agent creates GazeCone and FlashlightDetection sensors.
4. StateMachine starts in Observe.
5. Client samples player gaze and flashlight direction.
6. Client sends a typed observation or interaction request when appropriate.
7. Server validates distance, raycast visibility, timing, and flashlight state.
8. Validated observations update Iris's blackboard.
9. StateMachine transitions to Exposed, Attack, Retreat, or another state.
10. Client presentation plays the matching animation, sound, and visual effect.
```

## What should not happen

Avoid these designs:

```lua
if monsterType == "spectre" then
	-- hundreds of lines of Spectre behavior
elseif monsterType == "iris" then
	-- hundreds of lines of Iris behavior
end
```

Also avoid:

- putting live targets and state inside shared catalog definitions;
- letting the client decide that possession or damage succeeded;
- putting AnimationTrack objects in the shared registry;
- making every sensor directly play animations or modify player state;
- replicating the entire blackboard every frame;
- creating a separate animation loader for monsters;
- creating one server service per monster type.

The registry stores definitions. Runtime agents store state. Sensors report
observations. Abilities perform actions. Motion handles animation.

## Testing strategy

The system should be testable at three levels.

### Pure tests

Test without Workspace or live players:

- registry lookup and unknown IDs;
- definition validation;
- inverse audio curve calculations;
- gaze-cone dot-product calculations;
- flashlight exposure calculations;
- state transition rules;
- cooldown and ability eligibility.

### Runtime tests

Test in Studio with tagged dummy models:

- agent creation and destruction;
- streaming and untagging cleanup;
- sensor signals;
- state changes;
- animation profile resolution;
- Motion track cleanup.

### Playtests

For Spectre, record:

- whether players correctly understand the audio direction;
- how long it takes them to identify the threat;
- whether the inverse curve feels intentional or bugged;
- whether possession is readable before it happens.

For Iris, record:

- whether players notice Iris in peripheral vision;
- whether the gaze/flashlight interaction feels controllable;
- whether players understand what caused Iris to react;
- whether the flashlight creates interesting decisions rather than a single
  obvious answer.

Tuning values should remain in definitions or dedicated test configuration so
these experiments do not require changing framework code.

## Recommended implementation order

Build the smallest vertical slice in this order:

1. Create `Core/Shared/Monsters` with types, registry, and one Spectre
   definition.
2. Create the runtime `Agent`, a minimal state machine, and the server tag
   component.
3. Add a generic proximity sensor and a server-validated ability contract.
4. Add Spectre possession with a placeholder client presentation event.
5. Add the reversed distance audio presentation and test it in-game.
6. Add Iris as a second definition without changing the core state machine.
7. Add gaze and flashlight sensors with server validation.
8. Add debugging tools and pure tests for curves, transitions, and cooldowns.
9. Add richer movement, patrol, attack, and animation states only after the
   two MVP hooks are fun and readable.

The important milestone is not “all monsters work.” It is “a new monster can
be composed from existing pieces, and a new mechanic can be tested without
rewriting the framework.”
