# Script Style Guide

This guide is the default standard for script structure, naming, and comments in this project.

## Core Rules

- Keep code simple and readable first.
- Match existing project patterns when unsure.
- Prefer short functions with one clear purpose.
- Avoid clever code that is hard to scan.

## Naming Conventions

- **Main/public functions:** `PascalCase`
  - Example: `ShowRevealVFX()`, `PlayHatchSequence()`, `CollectAtm()`
- **Helper/private functions:** `_camelCase` (leading underscore)
  - Example: `_resolvePetPart()`, `_formatBillboardCash()`, `_refreshCounters()`
- **Local variables:** `camelCase`
  - Example: `petModel`, `peakRarity`, `emitCount`
- **Module tables:** `PascalCase`
  - Example: `EggController`, `PlotController`, `MessageToast`
- **Constants:** `UPPER_SNAKE_CASE`
  - Example: `EGG_HATCH_RENDER_BIND_PRIORITY`, `OPEN_COOLDOWN`
- **Types:** `PascalCase`
  - Example: `HatchResultRow`, `RevealDismissOpts`

## Script Structure Order

Use this order in most Luau scripts:

1. `--!strict` (or project-required pragma)
2. Short top-level purpose comment (only if useful)
3. Services
4. Required modules
5. Constants
6. Types
7. Private state
8. Private/helper functions (`_camelCase`)
9. Public API (`PascalCase` methods/functions)
10. `return ModuleTable`

## Function Style

- Keep function names action-oriented (`Show...`, `Play...`, `Bind...`, `Refresh...`).
- Prefer early returns to reduce deep nesting.
- Use small helpers for repeated logic.
- Keep side effects obvious (naming and placement).

## Comment Style

- Keep comments short and simple.
- Add comments only when they explain intent, assumptions, or non-obvious behavior.
- Do not comment obvious lines.
- Prefer 1-2 line comments above the block they explain.
- For public helpers, use short block doc comments (`--[[ ... ]]`) for params/behavior when helpful.

## Function Doc Blocks

Use this style when a function needs explanation.

- Include doc blocks for:
  - public/main functions (`PascalCase`)
  - helper functions with non-obvious behavior
- Skip doc blocks for very obvious one-liners.
- Keep doc blocks short.

Recommended format:

```lua
--[[
	One-line summary of what this function does.
	@param petModel Model The revealed pet model.
	@param rarity string Rarity key used to choose a VFX template.
	@return boolean True when VFX was spawned.
]]
function ShowRevealVFX(petModel: Model, rarity: string): boolean
	-- ...
end
```

Parameter rule:

- Always describe what the parameter means in gameplay/system terms, not just its type.
- Example: prefer "Rarity key used to choose template" over "A string".

Good:

- `-- Single post-camera bind drives all eggs during float-in idle.`
- `-- Fallback: use Common template when rarity entry is missing.`

Avoid:

- `-- Increment i by 1`
- Long paragraph comments for simple code.

## UI/Controller Patterns

- In controllers, keep update loops centralized where possible.
- Prefer one shared render/update handler over many duplicate handlers.
- Use explicit bind names for `BindToRenderStep` and cleanly unbind on cleanup.
- Keep UI formatting logic in small helpers (`_format...`, `_refresh...`).

## Data + Network Patterns

- Validate payloads at boundaries.
- Keep schema keys and runtime keys consistently named.
- Use explicit fallback values for missing/invalid data.
- Keep replica listeners narrow and keyed to relevant roots/paths.

## Error Handling

- Use guarded fallbacks for optional assets/templates.
- Warn once for missing optional resources where possible.
- Return safely instead of throwing when a non-critical visual effect fails.

## Quick Checklist

- Are main functions `PascalCase`?
- Are helper functions `_camelCase`?
- Are constants `UPPER_SNAKE_CASE`?
- Are comments short and only where needed?
- Is file order consistent with this guide?
- Are cleanup paths explicit for connections/tweens/temporary instances?
