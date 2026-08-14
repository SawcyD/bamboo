# Adding a System (Cookbook)

Recipes for the common "I need a new X" moments. The scaffold script writes the
boilerplate: `./scripts/new.ps1 <kind> <Name>`.

## New server service

```powershell
./scripts/new.ps1 service ShopService
```

- Lives in `ServerRuntime/Services/`, auto-loaded and `:Start(Framework)`-ed by
  `ServerRuntime:Start()`. No registration needed.
- Get other services lazily inside methods: `Framework:GetService("DataService")`
  (not at module top level — that's how circular requires happen).
- Files starting with `_` are skipped by the loader.

## New client controller

```powershell
./scripts/new.ps1 controller ShopController
```

Same deal, client-side: `ClientRuntime/Controllers/`, auto-started.

## New network event namespace

```powershell
./scripts/new.ps1 event Shop
```

Creates `Core/Shared/Network/Events/Shop.luau`. Define channels with validators
and (for c2s) a rate limit; they appear as `Relay.Shop.<ChannelName>`:

```lua
BuyItem = Channel({
    bridge = b("BuyItem"),
    direction = "c2s",
    rateLimit = 10,
    value = {
        itemId = function(v) return type(v) == "string" and #v > 0 end,
    },
}),
```

Server: `Relay.Shop.BuyItem.listen(function(payload, player) ... end)`
Client: `Relay.Shop.BuyItem.send({ itemId = "sword" })`

## New component (tagged-instance behavior)

```powershell
./scripts/new.ps1 component Door
```

Creates a component bound to the `Door` CollectionService tag. Require the module
once from a service/controller `Start` to activate the binding, then tag
instances in Studio. Lifecycle, Janitor, and streaming handling are automatic.
Server component = logic, client component = visuals; same tag, two modules.

## New plain class

```powershell
./scripts/new.ps1 class Match
```

`Core/Classes/<Name>.luau`, accessed via `Core:GetClass("Match")`. Convention:
`.new()`, a Janitor field, and `:Destroy()` that cleans it.

## New persisted data field

1. Add the default to `DataService/Schema.luau` (`defaultData`).
2. Existing players don't have it — append a migration in
   `DataService/Migrations.luau` (append-only; never edit old entries).
3. Server-only? Prefix the key with `_` or list it in `Schema.PrivateKeys`.
4. Read/write through the path API: `DataService.Increment(player, "Coins", 5)`.

## New player setting

```lua
-- in any service, before players join:
SettingsService.RegisterSetting("HideOtherPets", {
    default = false,
    validate = function(v) return type(v) == "boolean" end,
})
-- client UI:
SettingsController:Set("HideOtherPets", true)  -- applies + persists
```

Audio sliders need no registration — `Volume_<SoundGroup>` keys are built in.

## New developer product

```lua
MonetizationService.RegisterProduct(123456789, function(player, receipt)
    DataService.Increment(player, "Coins", 1000)
    return true
end)
```

Idempotency, retries, and receipt storage are handled; just grant the thing.

## New leaderboard

```lua
LeaderboardService.RegisterBoard("Coins", { dataPath = "Coins" })
-- UI side:
local rows = LeaderboardService.GetTopAsync("Coins", 50, "Weekly")
```

## Checklist before shipping a system

- [ ] All c2s channels have `value` validators and a sensible `rateLimit`.
- [ ] Server re-validates possibility (funds/ownership/distance/cooldown).
- [ ] Data writes go through `DataService.Set/Update/Increment` (never raw
      replica calls).
- [ ] `selene src` and `stylua --check src` pass (CI enforces both).
- [ ] Pure logic has a spec in `Core/Tests/` if it's worth keeping correct.
