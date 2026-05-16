# QuickStack

A Subnautica 2 mod that adds a "Quick Stack" keybind (default: N) to automatically sort your inventory items into nearby storage containers that already contain matching items.

## Requirements

- Subnautica 2 (Steam/Game Pass)
- [UE4SS for Subnautica 2](https://github.com/Subnautica2Modding/Subnautica2-UE4SS)

## Installation

1. Install UE4SS for Subnautica 2
2. Download the latest release from [Releases](../../releases)
3. Extract the `QuickStack` folder into `Subnautica2/Subnautica2/Binaries/Win64/ue4ss/Mods/`
4. Launch the game

## Configuration

Edit `Mods/QuickStack/config.txt`:

| Setting | Default | Description |
|---------|---------|-------------|
| keybind | N | Key to trigger quick-stack |
| radius | 25 | Meters to scan for containers |
| cooldown | 1.0 | Seconds between activations |
| notify | true | Show on-screen notifications |

## License

MIT
