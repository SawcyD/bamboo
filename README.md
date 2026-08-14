# Roblox Luau Framework Template

Batteries-included starting point for every game: data persistence with
replication, typed networking with built-in validation/rate-limiting, a
tag-based component system, and the boring-but-critical services (monetization,
settings, leaderboards, soft shutdown) already wired.

## Quick start

```powershell
rokit install          # rojo, wally, selene, stylua
wally install          # packages -> Packages/ & ServerPackages/
rojo sourcemap --output sourcemap.json
rojo serve             # connect from Studio with the Rojo plugin
```

Scaffold new files from templates:

```powershell
./scripts/new.ps1 service ShopService
./scripts/new.ps1 controller HudController
./scripts/new.ps1 event Shop
./scripts/new.ps1 component Door
```

## Layout

```
src/
  ReplicatedStorage/
    Core/                shared kernel
      Modules/           Component, RNG, Log, Spring, Bezier, Projectile, Replica, Janitor...
      Utils/             MathUtil, Cooldown, TableUtil, FormatUtil, StringUtil, DebounceUtil
      Shared/Enums/      Brain, Motion, NPC, Collectibles, and common custom enums
      Shared/Network/    Relay: typed channels over BridgeNet2 (validation + rate limits + telemetry)
      Classes/           plain-class conventions + templates
      Tests/             lightweight spec runner (require(...Tests).Run() in Studio)
      Index.luau         typed access with full autocomplete: require(Core.Index).RNG
    ClientRuntime/       controllers (auto-started): Settings, Input, Load, PerformanceDebug
    Audio/               sound library + playback with per-group volume scaling
    UI/                  UI runtime + modules
  ServerStorage/
    ServerRuntime/       services (auto-started)
      Services/          DataService, SettingsService, MonetizationService,
                         LeaderboardService, CharacterService, ShutdownService
```

`Server.server.luau` / `Client.client.luau` just call `:Start()` — services and
controllers in the runtime folders load automatically (files starting with `_`
are skipped).

## The big pieces

| System | What you get |
| --- | --- |
| **DataService** | ProfileStore sessions, append-only migrations, debounced saves, and a path API — `DataService.Increment(player, "Coins", 5)` saves **and** replicates in one call. Keys prefixed `_` (or in `Schema.PrivateKeys`) never reach the client. |
| **Relay (networking)** | Declarative channels with per-field validators, default 60 msg/s per-player rate limiting on c2s, invoke support, and opt-in bandwidth telemetry. |
| **Component** | CollectionService tag → class lifecycle (`Construct`/`Start`/`Stop`, auto Janitor, streaming-safe). |
| **RNG** | Weighted rolls with luck (boosts rare odds, never guarantees), pity rollers, odds labels for UI, seeded streams for tests. |
| **Settings** | Validated, persisted player preferences; `Volume_<Group>` keys drive the audio system out of the box. |
| **Monetization** | Idempotent `ProcessReceipt`, declarative product handlers, gamepass ownership cache + on-owned hooks. |
| **Projectile** | Client `Cast` for visuals, server `Validate` that re-simulates the trajectory before accepting hits. |
| **PerformanceDebug** | Press **L** (Studio/devs): FPS/ping/memory cards + per-bridge bandwidth table, including server-reported replica write traffic and an "untracked gap" row. |

Docs worth reading before building on top:

- [`docs/SERVER_AUTHORITY.md`](docs/SERVER_AUTHORITY.md) — how state flows, validation checklist
- [`docs/ADDING_A_SYSTEM.md`](docs/ADDING_A_SYSTEM.md) — recipes for services, events, components, products, settings
- [`docs/SCRIPT_STYLE_GUIDE.md`](docs/SCRIPT_STYLE_GUIDE.md) — code style

`docs/systems/COMPOSABLE_MONSTER_AI.md` documents the data-driven, composable
monster AI architecture built on sensors, abilities, state, and presentation.

`docs/FRAMEWORK_TOOLKIT.md` documents the Brain, Motion, NPC, combat, spawning,
debugging, and validation tools.

`docs/ADDING_A_SHARED_DOMAIN.md` explains how to create systems like
`Collectibles`, `Pets`, `Fish`, or `Artifacts` under `Core/Shared`.

## Tooling

- `selene src` — lints (0 warnings policy, CI-enforced)
- `stylua src` — formats (CI checks `--check`)
- CI builds the place with `rojo build` on every push/PR
- Tests: `require(game.ReplicatedStorage.Core.Tests).Run()` from the Studio
  command bar
