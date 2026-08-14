# Adding a Shared Domain System

Use this guide when adding a reusable game domain such as:

- `Collectibles`
- `Pets`
- `Fish`
- `Artifacts`
- `Weapons`
- `Cards`
- `Quests`
- `Abilities`

The existing [Collectibles](../src/ReplicatedStorage/Core/Shared/Collectibles/)
folder is the reference pattern.

The goal is to put shared definitions and calculations in one place while
keeping ownership, persistence, authorization, and server-only decisions in
the server runtime.

## The boundary

```text
ReplicatedStorage/Core/Shared/<Domain>
  Shared definitions and deterministic rules
                |
                v
ServerRuntime/Services/<Domain>Service
  Ownership, rolls, persistence, authorization
                |
                v
ClientRuntime / UI
  Presentation and local prediction
```

The shared domain may be required by both the server and the client.

### Shared code may contain

- Stable IDs and names
- Definition/catalog data
- Shared type declarations
- Enum-like categories
- Rarity, tier, condition, or state tables
- Deterministic value and stat formulas
- Odds descriptions and pure weighted helpers
- Model, icon, and asset lookup keys
- Collection or set metadata
- Validation that does not require player authority

### Shared code must not contain

- Player inventory
- Currency changes
- DataStore/ProfileStore access
- Ownership checks
- Trading or auction authorization
- Server secrets
- Authoritative random rolls
- Client-trusted rewards

The client can calculate a preview, but the server must calculate and validate
the real result.

## Recommended folder layout

```text
src/ReplicatedStorage/Core/Shared/<Domain>/
├── init.luau
├── Types.luau
├── Definitions.luau
├── Catalog.luau
├── Categories.luau
├── Value.luau
├── Odds.luau
├── Models.luau
└── Sets.luau
```

Only create the files the domain needs. `Collectibles` currently uses:

```text
Types
Definitions
Rarity
Condition
Value
Odds
CollectionSets
	Models
```

The `init.luau` file is the public namespace. Internal modules should be
required through this namespace by callers.

## What each file does

### `init.luau` — public entry point

This is the only module callers should need to require. It gathers the domain's
public modules into one namespace.

```lua
return {
	Types = require(script.Types),
	Definitions = require(script.Definitions),
	Value = require(script.Value),
	Models = require(script.Models),
}
```

Do not put gameplay logic in `init.luau`. Use it as the public API map.

### `Types.luau` — type declarations

Defines the shapes used by the domain, such as definitions, instances, rolls,
and collection entries.

```lua
export type Definition = {
	id: string,
	name: string,
	baseValue: number,
}
```

This file should contain type exports and no player state, side effects, or
registration work.

### `Definitions.luau` — definition registry

Stores immutable templates for the things that can exist in the domain.

For `Collectibles`, a definition describes an item type such as `ember_dragon`.
It does not describe one player's copy.

Typical responsibilities:

- Register definitions
- Reject duplicate IDs
- Retrieve a definition by ID
- List all definitions

### `Catalog.luau` — game content registration

Contains the actual game-specific definitions and registers them with
`Definitions`.

This keeps the generic registry separate from the content. A framework template
can remain reusable while an individual game supplies its own catalog.

Examples:

```text
Pets/Catalog.luau       → pet definitions
Fish/Catalog.luau       → fish definitions
Artifacts/Catalog.luau  → artifact definitions
```

`Catalog.luau` is optional for an empty framework package, but recommended for
a real game domain.

### `Rarity.luau`, `Condition.luau`, and other rule tables

These modules contain shared categories and modifiers.

In `Collectibles`:

- `Rarity.luau` defines ranks, multipliers, and colors.
- `Condition.luau` defines condition multipliers.

Other domains may use different rule files:

```text
Pets/Tier.luau
Pets/GrowthStage.luau
Weapons/WeaponClass.luau
Fish/Size.luau
Artifacts/Quality.luau
```

Use these files for stable, reusable rules. Put individual content entries in
`Catalog.luau` instead.

### `Value.luau` — deterministic calculations

Contains formulas that derive a value, power, score, or stat from a definition
and its rolled properties.

For `Collectibles`, `Value.Compute` combines:

```text
base value × rarity multiplier × condition multiplier × variant multiplier
```

Keep one source of truth here. Selling, trading, auction, inventory, and UI
code should call this module instead of implementing their own formulas.

Other domains may call the file something more specific:

```text
Pets/Power.luau
Weapons/Damage.luau
Fish/Weight.luau
Artifacts/Appraisal.luau
```

### `Odds.luau` — pure weighted-roll helpers

Provides generic odds calculations or weighted selection helpers.

It may describe or perform a pure calculation, but the authoritative random
roll must happen in a server service. Do not use a shared module to decide what
a player receives.

The server should supply luck, pity, permissions, and other authoritative
modifiers before storing the result.

### `Models.luau` — visual asset lookup

Translates a stable definition ID into a visual asset key such as a model,
icon, animation profile, or preview name.

It should return keys, not directly own or clone Instances:

```lua
local modelName = Domain.Models.GetName("ember_dragon")
```

Client or world systems can then resolve that key against the game's asset
folders.

### `CollectionSets.luau` or `Sets.luau` — groups and completion rules

Defines groups of definitions and their metadata or rewards.

For `Collectibles`, a set might contain all items in a dragon collection. A set
module can describe membership, but the server should award completion rewards.

Use `Sets.luau` for a generic domain or keep the existing
`CollectionSets.luau` name when the feature is specifically a collection book.

### `Variants.luau` — optional rolled modifiers

Use this when a domain supports properties such as:

- Shiny fish
- Enchanted weapons
- Mutated pets
- Ancient artifacts

Keep variant definitions and deterministic multipliers shared. Generate the
actual variant for an owned instance on the server.

### `Validation.luau` — domain-specific shape checks

Use this for validation that is specific to the domain's content format, such
as checking that a pet has a valid growth curve or that a weapon has a valid
damage range.

Generic runtime validation belongs in `Core:Get("Validation")`. Domain-specific
validation can wrap it here.

### `Service` files — not part of the shared folder

Ownership and gameplay services belong under `ServerRuntime`:

```text
src/ServerStorage/ServerRuntime/Services/
└── PetService.luau
```

The service owns:

- Server rolls
- Player-owned instances
- Inventory capacity
- Persistence
- Currency
- Trading and auctions
- Server rewards
- Network request validation

Do not add these responsibilities to `Types`, `Definitions`, `Value`, or
`Models`.

### `Tests` — pure domain behavior

Tests do not live inside the domain folder. Put them under:

```text
src/ReplicatedStorage/Core/Tests/<Domain>.spec.luau
```

Test the catalog, lookup behavior, formulas, odds validation, and model keys.

## File decision table

| If the file answers… | Put it in… |
| --- | --- |
| “What shape does this data have?” | `Types.luau` |
| “What definitions exist?” | `Definitions.luau` / `Catalog.luau` |
| “What does this category mean?” | `Rarity.luau`, `Condition.luau`, or another rule table |
| “How is this value calculated?” | `Value.luau` or a domain-specific formula module |
| “What can be rolled?” | `Odds.luau` plus a server roll service |
| “Which visual asset represents it?” | `Models.luau` |
| “Which definitions form a group?” | `Sets.luau` / `CollectionSets.luau` |
| “What does the player own?” | A server service and profile schema |
| “Can the player sell, trade, or equip it?” | A server service |
| “How should the client display it?” | Client controller/UI |

## Step 1: Choose the domain name

Use a plural namespace for a catalog of things:

```text
Collectibles
Pets
Fish
Artifacts
```

Use PascalCase for the folder and public namespace. Use stable `snake_case`
IDs for individual definitions:

```lua
local id = "ember_dragon"
```

The ID is an internal contract. Do not change it just because the display name
changes.

## Step 2: Create the namespace

Copy the shape of `Collectibles`:

```text
src/ReplicatedStorage/Core/Shared/Pets/
├── init.luau
├── Types.luau
├── Definitions.luau
├── Catalog.luau
├── Rarity.luau
├── Value.luau
└── Models.luau
```

Start with the smallest useful loop. For example, a new `Pets` domain can start
with only:

```text
Types
Definitions
Catalog
Value
init
```

Add breeding, abilities, evolution, or collections only when the game needs
them.

## Step 3: Define the shared types

`Types.luau` describes the shape of data. It does not store player-owned
instances.

```lua
--!strict

export type Tier = "Common" | "Rare" | "Epic" | "Legendary"

export type Definition = {
	id: string,
	name: string,
	species: string,
	basePower: number,
	weight: number,
	tier: Tier,
	modelName: string?,
	iconName: string?,
}

export type Instance = {
	instanceId: string,
	definitionId: string,
	level: number,
	power: number,
	createdAt: number,
	locked: boolean,
}

return {}
```

Keep the definition and instance separate:

```text
Definition = what the item type is
Instance   = one owned copy of that type
```

Duplicate owned items must have different `instanceId` values.

## Step 4: Add the definition registry

Follow the `Collectibles.Definitions` pattern:

```lua
--!strict

local definitions = {}
local Definitions = {}

function Definitions.Register(definition: any)
	assert(type(definition.id) == "string" and definition.id ~= "", "Pet id is required")
	assert(definitions[definition.id] == nil, "Duplicate pet: " .. definition.id)
	definitions[definition.id] = table.freeze(definition)
end

function Definitions.Get(id: string): any
	return definitions[id]
end

function Definitions.List(): { any }
	local result = {}
	for _, definition in definitions do
		table.insert(result, definition)
	end
	return result
end

return Definitions
```

Definitions should be immutable after registration. If content needs to change
during development, replace the catalog and restart the server rather than
mutating definitions during a live session.

## Step 5: Register the catalog

Put game content in `Catalog.luau`, not inside a server service:

```lua
--!strict

local Definitions = require(script.Parent.Definitions)

Definitions.Register({
	id = "ember_dragon",
	name = "Ember Dragon",
	species = "Dragon",
	basePower = 100,
	weight = 10,
	tier = "Legendary",
	modelName = "EmberDragon",
	iconName = "EmberDragon",
})

Definitions.Register({
	id = "forest_fox",
	name = "Forest Fox",
	species = "Fox",
	basePower = 25,
	weight = 60,
	tier = "Common",
	modelName = "ForestFox",
	iconName = "ForestFox",
})

return Definitions
```

Require the catalog from `init.luau` before returning the public namespace:

```lua
--!strict

local Definitions = require(script.Definitions)
require(script.Catalog)

return {
	Types = require(script.Types),
	Definitions = Definitions,
	Value = require(script.Value),
	Models = require(script.Models),
}
```

This makes the public namespace ready immediately after it is required.

## Step 6: Add deterministic shared calculations

Keep formulas in one module. Do not repeat the formula in inventory, UI,
selling, and auction code.

```lua
--!strict

local Definitions = require(script.Parent.Definitions)
local Tiers = require(script.Parent.Tiers)

local Value = {}

function Value.Compute(definitionId: string, tier: string, level: number): number
	local definition = Definitions.Get(definitionId)
	local tierData = Tiers.Get(tier)
	assert(definition and tierData, "Invalid pet definition or tier")
	return math.floor(definition.basePower * tierData.multiplier * (1 + level * 0.1))
end

return Value
```

Shared calculations must be deterministic and side-effect free. They may be
used for UI previews, but the server still owns the authoritative call.

## Step 7: Add enums when categories are stable

Use `Core/Shared/Enums/<Domain>.luau` for stable categories shared by multiple
systems:

```lua
local Create = require(script.Parent.Enum).Create

return table.freeze({
	Tier = Create({ "Common", "Rare", "Epic", "Legendary" }),
	GrowthStage = Create({ "Baby", "Young", "Adult", "Elder" }),
})
```

Do not create an enum for values that are content data or likely to change.
Those belong in definitions or configuration tables.

## Step 8: Add model and asset lookup helpers

The shared domain should store asset keys, not direct references to workspace
instances:

```lua
-- Models.luau
local Definitions = require(script.Parent.Definitions)

local Models = {}

function Models.GetName(definitionId: string): string?
	local definition = Definitions.Get(definitionId)
	return definition and definition.modelName
end

return Models
```

A client presentation system can resolve `modelName` against
`ReplicatedStorage.Assets`. The shared domain should not depend on a specific
asset folder layout.

## Step 9: Expose and consume the namespace

Any shared or client code can use:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Core = require(ReplicatedStorage:WaitForChild("Core"))
local Pets = Core:GetShared("Pets")

local pet = Pets.Definitions.Get("ember_dragon")
local power = Pets.Value.Compute("ember_dragon", "Legendary", 5)
```

For frequently used domains, add the folder to `Core.Index` so it has typed
access:

```lua
local Index = require(ReplicatedStorage.Core.Index)
local Pets = Index.Pets
```

Add the domain to the index only after its public API is stable. Dynamic
`Core:GetShared` access is sufficient during early development.

## Step 10: Add server-owned gameplay

The shared namespace describes the domain. The server service performs actions.

Recommended server locations:

```text
src/ServerStorage/ServerRuntime/Services/
└── PetService.luau
```

The service may own:

- Server-side rolls
- Player ownership
- Capacity checks
- Unique instance IDs
- DataService writes
- Selling, trading, or equipping
- Server-side rewards
- Network request validation

Example boundary:

```lua
function PetService:Grant(player: Player, definitionId: string): any?
	local definition = Pets.Definitions.Get(definitionId)
	if not definition then
		return nil
	end

	-- Validate capacity, generate the instance ID, write profile data,
	-- and replicate the authoritative result here.
	return self:_createOwnedInstance(player, definition)
end
```

Never accept client-provided `definitionId`, tier, value, or ownership without
validating it against server rules.

## Step 11: Add network events only for requests and results

Use the shared network namespace for actions that cross the client/server
boundary:

```text
Core/Shared/Network/Events/Pets.luau
```

Good request payload:

```lua
{
	action = "Equip",
	instanceId = "pet-instance-id",
}
```

The server should look up the instance and decide whether the action succeeds.
Do not let the client send the full pet definition as authority.

## Step 12: Add tests

Keep shared-domain tests pure and place them under `Core/Tests`:

```text
Core/Tests/Pets.spec.luau
```

Test at least:

- Definitions have unique IDs
- Unknown IDs fail safely
- Formulas return expected values
- Invalid tiers or conditions are rejected
- Odds tables do not accept invalid weights
- Model lookup returns the expected key

Example:

```lua
local Pets = require(script.Parent.Parent.Shared.Pets.init)

return function(t)
	t.test("catalog contains the expected pet", function()
		t.expect(Pets.Definitions.Get("ember_dragon").name).toBe("Ember Dragon")
	end)

	t.test("unknown definitions are missing", function()
		t.expect(Pets.Definitions.Get("missing")).toBeNil()
	end)
end
```

Run the complete test suite from the Studio command bar:

```lua
require(game.ReplicatedStorage.Core.Tests).Run()
```

## Naming checklist

- Folder and namespace use PascalCase and plural nouns.
- Definition IDs are stable `snake_case` strings.
- Definitions and instances are separate types.
- Shared formulas do not mutate player data.
- Server services own inventory, currency, and authorization.
- Client code only presents or requests actions.
- Direct asset references stay outside the shared domain.
- New enums go in `Core/Shared/Enums`.
- New definitions are registered through a catalog.
- The public API is exposed through `init.luau`.
- Tests cover definitions and deterministic calculations.

## Before calling the domain complete

```text
Shared namespace
  → definitions registered
  → deterministic calculations
  → model/icon lookup keys
  → server service
  → persistence schema/migration
  → validated network request
  → client presentation
  → pure tests
```

Start with the shared namespace and one complete server-owned action. Add
trading, auctions, crafting, collection sets, and bonuses only after the basic
flow is reliable.
