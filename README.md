# NEXT HUB

Script hub for Roblox — Combat / Visuals.

## Usage

In any executor (Solara / Fluxus / Delta / Wave):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/lovepump008-bot/nexthub/main/loader.lua"))()
```

## Supported Places

| PlaceId | Version |
|---------|---------|
| `140583889607592` | 1.0 |

## Hotkeys

| Key | Action |
|-----|--------|
| **Right Shift** | Toggle UI |
| **E (hold)** | Aimbot |

## Features

- Aimbot (Hold / Toggle / Always / Mobile Fire)
- Aim Point: Head / HRP / Torso
- FOV + Smoothing slider
- Team Check / Wall Check
- No Recoil / No Spread
- ESP Highlight + Name/Distance
- Save config / Theme

## Repo Structure

```
nexthub/
├── loader.lua                      # Router — fetched by user
├── scripts/
│   └── 140583889607592.lua         # Main for this place
└── README.md
```

## Adding a new place

1. Create `scripts/<PlaceId>.lua`
2. Add entry to `loader.lua`:

```lua
local PLACES = {
    [140583889607592] = { file = "scripts/140583889607592.lua", version = "1.0" },
    [NEW_PLACE_ID]    = { file = "scripts/NEW_PLACE_ID.lua",    version = "1.0" },
}
```

3. Push to `main` — change takes effect immediately.
