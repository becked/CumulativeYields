# Old World Mod Template

A starter template for building [Old World](https://store.steampowered.com/app/597180/Old_World/) mods. Provides project scaffolding, automated validation, and one-command deployment to Steam Workshop and mod.io — so you can focus on the mod itself instead of the tooling around it.

Supports both XML-only mods (bonuses, events, units, etc.) and C# DLL mods using [Harmony](https://github.com/pardeike/Harmony) for runtime patching.

## Features

- **XML and C# support** — start with XML-only or add a `.csproj` for Harmony-based C# patching; build scripts detect which mode you're using automatically
- **One-command deploy and upload** — deploy locally for testing, or publish to Steam Workshop (`steamcmd`) and mod.io from the command line, with `--dry-run` support
- **Cross-platform scripts** — every script ships as both bash (`.sh`) and PowerShell (`.ps1`)
- **Automatic validation** — pre-commit hook and standalone validator catch missing UTF-8 BOMs on text files and malformed XML before they reach the game
- **Game reference symlink** — point `Reference/` at your Old World install to browse vanilla XML data and decompiled C# source without leaving the repo
- **Old World changelog** — [`OLDWORLD-CHANGELOG.md`](OLDWORLD-CHANGELOG.md) tracks game-update diffs across `Source/` and `Reference/`, documenting new APIs, breaking changes, and balance shifts so modders can stay current between patches

## Installation

Subscribe on [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=TODO) or [mod.io](https://mod.io/g/oldworld/m/TODO), or copy the mod folder to your Old World mods directory manually.

## Resources

- **[Pinacotheca](https://becked.github.io/pinacotheca/)** — Browsable gallery of all in-game art assets (portraits, icons, illustrations)
- **[dales.world](https://dales.world)** — Authoritative Old World modding tutorials

## Compatibility

- Single-player and multiplayer
- No DLC required

## Development

### Setup

1. **Clone this repo** — use it as a starting point for your own mod
2. **Copy `.env.example` to `.env`** and fill in your paths — the deploy and upload scripts read this to know where your game and mods folder are, and where to publish. At minimum you need `OLDWORLD_MODS_PATH` for local testing; the Steam/mod.io credentials are only needed if you plan to upload.
3. **Set up the Reference symlink** (see [CLAUDE.md](CLAUDE.md#setting-up-the-reference-symlink)) — this points `Reference/` at your Old World install so you can browse vanilla XML data and decompiled source directly from the repo, which is useful for looking up field names, valid enum values, and existing game behavior
4. **Install the pre-commit hook** — catches common mistakes (missing UTF-8 BOMs on text files, malformed XML) before they get committed, saving you from silent in-game failures:
   - **bash:** `./scripts/install-hooks.sh`
   - **PowerShell:** `.\scripts\install-hooks.ps1`

### XML-Only Mods

Most Old World mods only need XML. Add or override game data in `Infos/` — bonuses, events, units, text strings, etc. No build step needed, just deploy and test. See `docs/modding-guide-xml.md` for the full XML modding guide.

```bash
./scripts/deploy.sh            # bash (macOS/Linux)
.\scripts\deploy.ps1           # PowerShell (Windows)
```

### C# Mods

For changes that can't be made through XML alone (e.g., camera behavior, UI modifications, custom game logic). The template includes a `.csproj` and `Source/ModEntryPoint.cs` with Harmony scaffolding. To use:

1. **Rename `MyMod.csproj`** to match your mod name
2. **Update `AssemblyName` and `RootNamespace`** in the `.csproj`
3. **Set `OLDWORLD_PATH`** in your `.env` — the build needs this to find the game's DLLs for compilation
4. **Edit `Source/ModEntryPoint.cs`** with your mod logic

The deploy and upload scripts automatically detect the `.csproj` and build before deploying. If you don't need C#, delete `MyMod.csproj` and `Source/` — the scripts will skip the build step.

See `docs/modding-guide-csharp.md` for a comprehensive C# modding guide covering both GameFactory and Harmony approaches.

### Deploy and Upload

All scripts run validation before deploying. Use `--dry-run` / `-DryRun` to preview an upload without actually publishing.

**bash (macOS/Linux):**
```bash
./scripts/deploy.sh                          # Copy mod to local mods folder for testing
./scripts/workshop-upload.sh [--dry-run]     # Publish to Steam Workshop via steamcmd
./scripts/modio-upload.sh [--dry-run]        # Publish to mod.io via API
```

**PowerShell (Windows):**
```powershell
.\scripts\deploy.ps1                         # Copy mod to local mods folder for testing
.\scripts\workshop-upload.ps1 [-DryRun]      # Publish to Steam Workshop via steamcmd
.\scripts\modio-upload.ps1 [-DryRun]         # Publish to mod.io via API
```
