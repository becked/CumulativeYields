# Old World C# Modding Guide

This guide explains how to create C# mods for Old World, the historical strategy game by Mohawk Games.

**For XML-only modding** (events, game options, text — no C# needed), see [modding-guide-xml.md](modding-guide-xml.md).

**Authoritative external resource**: [dales.world](https://dales.world) has excellent tutorials on Old World modding.

## Prerequisites

- **.NET SDK** (supports .NET Framework 4.7.2)
- **Old World** installed via Steam, Epic, or GOG
- **IDE** - Visual Studio, VS Code, or JetBrains Rider
- Basic C# knowledge

## Two Approaches to Modifying Game Behavior

Old World supports two approaches for modifying game logic with C#:

| Approach | Best For | Multi-Mod Compatible? |
|----------|----------|----------------------|
| **GameFactory Override** | Total conversion mods, scenarios | No - only one mod can use this |
| **Harmony Patching** | Targeted behavior changes | Yes - multiple mods can coexist |

### Quick Decision Guide

- **Use GameFactory Override** if you're creating a scenario or total conversion and need to replace entire classes (Player, PlayerAI, City, etc.). This is how all official DLC scenarios (Egypt, Greece, Carthage) work.
- **Use Harmony Patching** if you want to modify specific methods while remaining compatible with other mods. Multiple Harmony mods can patch the same method (postfixes stack), though prefixes that skip the original can conflict.
- **You can combine both** in the same mod — use GameFactory for class overrides and Harmony for patching methods you can't override via the factory.

---

## Project Structure

A minimal Old World mod requires:

```
MyMod/
├── Source/
│   ├── MyMod.cs              # Mod entry point + patches
│   └── Patches/              # Harmony patches (optional organization)
│       └── MyPatches.cs
├── MyMod.csproj              # Project file
├── ModInfo.xml               # Mod manifest (required)
└── .env                      # Local config (gitignored)
```

For simpler mods, a single `.cs` file works fine — the subdirectory structure is optional.

## Step 1: Create the Project File

Create `MyMod.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net472</TargetFramework>
    <AssemblyName>MyMod</AssemblyName>
    <RootNamespace>MyMod</RootNamespace>
    <LangVersion>9.0</LangVersion>
    <OutputType>Library</OutputType>
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <OutputPath>bin/</OutputPath>
  </PropertyGroup>

  <!-- Platform-specific paths to game assemblies.
       Pass OldWorldPath via: dotnet build -p:OldWorldPath="/path/to/Old World" -->
  <PropertyGroup Condition="$([MSBuild]::IsOSPlatform('Windows'))">
    <OldWorldManagedPath>$(OldWorldPath)\OldWorld_Data\Managed</OldWorldManagedPath>
  </PropertyGroup>
  <PropertyGroup Condition="$([MSBuild]::IsOSPlatform('OSX'))">
    <OldWorldManagedPath>$(OldWorldPath)/OldWorld.app/Contents/Resources/Data/Managed</OldWorldManagedPath>
  </PropertyGroup>
  <PropertyGroup Condition="$([MSBuild]::IsOSPlatform('Linux'))">
    <OldWorldManagedPath>$(OldWorldPath)/OldWorld_Data/Managed</OldWorldManagedPath>
  </PropertyGroup>

  <ItemGroup>
    <Compile Include="Source/**/*.cs" />
  </ItemGroup>

  <!-- Harmony via NuGet (only needed if using Harmony patching) -->
  <ItemGroup>
    <PackageReference Include="Lib.Harmony" Version="2.4.2" />
  </ItemGroup>

  <!-- Game assembly references (Private=false: don't copy to output) -->
  <ItemGroup>
    <Reference Include="TenCrowns.GameCore">
      <HintPath>$(OldWorldManagedPath)/TenCrowns.GameCore.dll</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="Mohawk.SystemCore">
      <HintPath>$(OldWorldManagedPath)/Mohawk.SystemCore.dll</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="UnityEngine">
      <HintPath>$(OldWorldManagedPath)/UnityEngine.dll</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="UnityEngine.CoreModule">
      <HintPath>$(OldWorldManagedPath)/UnityEngine.CoreModule.dll</HintPath>
      <Private>false</Private>
    </Reference>
  </ItemGroup>

</Project>
```

### Assembly Reference Guide

The game ships these assemblies in its `Managed/` directory:

| Assembly | Contains | When to Reference |
|----------|----------|-------------------|
| `TenCrowns.GameCore.dll` | Game logic: `Game`, `Player`, `City`, `Tile`, `Unit`, `Character`, `Infos`, `GameFactory`, `ModSettings`. Also contains `TenCrowns.AppCore` (`ModEntryPointAdapter`) and `TenCrowns.ClientCore` (`ClientUI`, `ClientManager`) namespaces. | Always |
| `Mohawk.SystemCore.dll` | Utility types: `StringBuilder`, `CollectionCache`, collections, math | Always (used by GameCore types) |
| `UnityEngine.CoreModule.dll` | `Debug.Log`, `MonoBehaviour`, core Unity types | Always (for logging) |
| `Assembly-CSharp.dll` | `AppMain`, UI screens, Unity glue code | **Never reference directly** — the game blocks mods from loading it. Use reflection if needed (see [Accessing Game Data](#accessing-game-data)). |

### Common Namespaces

```csharp
using TenCrowns.AppCore;       // ModEntryPointAdapter (in TenCrowns.GameCore.dll)
using TenCrowns.GameCore;      // Game, Player, City, Tile, Unit, Character, Infos, GameFactory
using TenCrowns.GameCore.Text; // TextManager, HelpText, TextExtensions
using TenCrowns.ClientCore;    // ClientUI, ClientRenderer, ClientManager (for UI mods)
using Mohawk.SystemCore;       // StringBuilder, CollectionCache, utility types
using UnityEngine;             // Debug.Log
using HarmonyLib;              // Harmony, HarmonyPatch, AccessTools (if using Harmony)
```

> **Note**: `TenCrowns.AppCore` and `TenCrowns.ClientCore` are namespaces inside `TenCrowns.GameCore.dll` — there are no separate DLLs for them.

### Managed Path by Platform

The `OldWorldManagedPath` differs by OS:

| Platform | Path (relative to game install) |
|----------|------|
| **Windows** | `OldWorld_Data\Managed` |
| **macOS** | `OldWorld.app/Contents/Resources/Data/Managed` |
| **Linux** | `OldWorld_Data/Managed` |

The `.csproj` derives this automatically from `$(OldWorldPath)` using MSBuild platform conditionals. Pass it via: `dotnet build -p:OldWorldPath="/path/to/Old World"`

## Step 2: Create ModInfo.xml

Every mod needs a `ModInfo.xml` manifest:

```xml
<?xml version="1.0"?>
<ModInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <displayName>My Awesome Mod</displayName>
  <description>Description of what your mod does.</description>
  <modpicture>MyMod.png</modpicture>
  <author>YourName</author>
  <modversion>1.0.0</modversion>
  <modbuild>1.0.81098</modbuild>
  <tags>GameInfo</tags>
  <singlePlayer>true</singlePlayer>
  <multiplayer>false</multiplayer>
  <scenario>false</scenario>
  <scenarioToggle>false</scenarioToggle>
  <blocksMods>false</blocksMods>
  <modDependencies />
  <modIncompatibilities />
  <modWhitelist />
  <gameContentRequired>NONE</gameContentRequired>
</ModInfo>
```

### Key Fields

| Field | Description |
|-------|-------------|
| `displayName` | Shown in the Mod Manager |
| `description` | Supports Steam BBCode formatting |
| `modpicture` | Image file shown in Mod Manager (place in mod folder) |
| `modversion` | Semantic version (e.g., 1.0.0) |
| `modbuild` | Game version this was built for |
| `tags` | Category: GameInfo, Character, Map, etc. |
| `singlePlayer` | Enable for single-player games |
| `multiplayer` | Enable for multiplayer (requires careful design) |
| `scenario` | Set to `true` for scenario mods |
| `blocksMods` | If true, prevents other mods from loading |

---

## Step 3: Create the Entry Point

Your mod must extend `ModEntryPointAdapter` (from `TenCrowns.AppCore`). This is the class the game instantiates when your mod loads.

### Minimal Entry Point (GameFactory only)

This is the pattern used by all official DLC scenarios (Egypt3, Greece3, Carthage):

```csharp
using TenCrowns.AppCore;
using TenCrowns.GameCore;
using UnityEngine;

namespace MyMod
{
    public class MyModEntryPoint : ModEntryPointAdapter
    {
        public override void Initialize(ModSettings modSettings)
        {
            Debug.Log("[MyMod] Initializing...");
            base.Initialize(modSettings);
            modSettings.Factory = new MyModGameFactory();
        }
    }
}
```

### Minimal Entry Point (Harmony only)

```csharp
using System;
using HarmonyLib;
using TenCrowns.AppCore;
using TenCrowns.GameCore;
using UnityEngine;

namespace MyMod
{
    public class MyMod : ModEntryPointAdapter
    {
        private static Harmony _harmony;
        private const string HarmonyId = "com.yourname.mymod";

        public override void Initialize(ModSettings modSettings)
        {
            base.Initialize(modSettings);

            if (_harmony != null) return; // Already patched (see triple-load note below)

            try
            {
                _harmony = new Harmony(HarmonyId);
                // Apply patches here (see Harmony section for options)
                Debug.Log("[MyMod] Harmony patches applied");
            }
            catch (Exception ex)
            {
                Debug.LogError($"[MyMod] Failed to apply patches: {ex}");
            }
        }

        public override void Shutdown()
        {
            _harmony?.UnpatchAll(HarmonyId);
            _harmony = null;
            base.Shutdown();
        }
    }
}
```

> **Triple-load warning**: Old World loads your DLL three times — once each for the controller, server, and client. Without the `if (_harmony != null) return;` guard, you'd apply the same patches three times, which can cause errors or unexpected behavior. Always use a static guard.

### Available Lifecycle Hooks

The full `IModEntryPoint` interface (from `Reference/Source/Base/Game/AppCore/IModEntryPoint.cs`):

| Method | When Called | Use Case |
|--------|-------------|----------|
| `Initialize(ModSettings)` | Mod loaded | Setup, Harmony patches, factory registration |
| `Shutdown()` | Mod unloaded | Cleanup, unpatch Harmony |
| `OnPreGameServer()` | Before game server starts | Pre-game setup |
| `OnGameServerReady()` | Game server starts/loads | Initialize game-dependent state |
| `OnGameClientReady()` | Game client ready | Client-side initialization |
| `OnPreLoad()` | Before loading a save | Pre-load setup |
| `OnPostLoad()` | After loading a save | Post-load adjustments |
| `OnRendererReady()` | Renderer initialized | Visual setup |
| `OnNewTurnServer()` | Turn ends (server-side) | React to game state changes |
| `OnServerUpdate()` | Server update tick | Server-side continuous processing |
| `OnClientUpdate()` | Every frame (client-side) | Continuous processing (use sparingly) |
| `OnClientPostUpdate()` | After client update | Post-frame processing |
| `CallOnGUI()` | Check if OnGUI needed | Return `true` to enable OnGUI calls |
| `OnGUI()` | Unity GUI event | Custom UI rendering (requires CallOnGUI = true) |
| `OnGameOver()` | Game ends | End-game handling |
| `OnExitGame()` | Exiting to menu | Game exit cleanup |

`ModEntryPointAdapter` provides empty implementations for all hooks, so you only override what you need.

---

## Approach 1: GameFactory Override

The GameFactory pattern lets you replace entire game classes with custom subclasses. This is how all official DLC scenarios work.

**Limitation**: Only ONE mod can set `modSettings.Factory` at a time.

### How It Works

1. Create a custom `GameFactory` that overrides creation methods
2. Create custom classes that inherit from base game classes
3. Set the factory in `Initialize()` — the game uses your factory for all object creation

### Example: Custom GameFactory

From `Reference/Source/Mods/Egypt3/Egypt3GameFactory.cs`:

```csharp
using TenCrowns.ClientCore;
using TenCrowns.GameCore;
using TenCrowns.GameCore.Text;

namespace MyMod
{
    public class MyModGameFactory : GameFactory
    {
        public override Game CreateGame(ModSettings pModSettings, IApplication pApp, bool bShowGame)
        {
            return new MyModGame(pModSettings, pApp, bShowGame);
        }

        public override Player CreatePlayer()
        {
            return new MyModPlayer();
        }

        public override Player.PlayerAI CreatePlayerAI()
        {
            return new MyModPlayerAI();
        }

        // Only override what you need — everything else uses the base implementation
    }
}
```

### Example: Custom Player with AI

From `Reference/Source/Mods/Greece3/Greece3Player.cs`:

```csharp
using TenCrowns.GameCore;

namespace MyMod
{
    public class MyModPlayer : Player
    {
        public override bool canDeclareWarTribe(TribeType eTribe, bool bTestTurns = true)
        {
            if (!isHuman())
                return false; // AI can't declare war on tribes
            return base.canDeclareWarTribe(eTribe, bTestTurns);
        }
    }

    public class MyModPlayerAI : Player.PlayerAI
    {
        public override int getWarOfferPercent(PlayerType eOtherPlayer,
            bool bDeclare = true, bool bPreparedOnly = false, bool bCurrentPlayer = true)
        {
            Player pOtherPlayer = game.player(eOtherPlayer);
            if (!pOtherPlayer.isHuman())
                return 0; // AI never declares war on other AI

            return base.getWarOfferPercent(eOtherPlayer, bDeclare, bPreparedOnly, bCurrentPlayer);
        }
    }
}
```

### Available Factory Methods

All methods from `GameFactory` (`Reference/Source/Base/Game/GameCore/GameFactory.cs`):

| Method | Creates | Common Override? |
|--------|---------|-----------------|
| `CreateGame(ModSettings, IApplication, bool)` | `Game` instance | Yes — scenario logic hub |
| `CreatePlayer()` | `Player` instance | Yes — player rules |
| `CreatePlayerAI()` | `Player.PlayerAI` instance | Yes — AI behavior |
| `CreateCity()` | `City` instance | Sometimes |
| `CreateUnit()` | `Unit` instance | Sometimes |
| `CreateUnitAI()` | `Unit.UnitAI` instance | Sometimes |
| `CreateTile()` | `Tile` instance | Sometimes |
| `CreateCharacter()` | `Character` instance | Sometimes |
| `CreateClientUI(IApplication)` | `ClientUI` instance | Yes — custom UI |
| `CreateHelpText(TextManager)` | `HelpText` instance | Yes — custom tooltips |
| `CreateInfos(ModSettings)` | `Infos` instance | Rarely |
| `CreateInfoHelpers(Infos)` | `InfoHelpers` instance | Sometimes |
| `CreateInfoGlobals()` | `InfoGlobals` instance | Rarely |
| `CreateInfoValidator(bool, ILogger)` | `IInfoValidator` instance | Rarely |
| `CreateTextManager(Infos, LanguageType)` | `TextManager` instance | Rarely |
| `CreateColorManager(Infos, TextManager)` | `ColorManager` instance | Rarely |
| `CreateTribe()` | `Tribe` instance | Rarely |
| `CreateTechTree()` | `TechTree` instance | Rarely |
| `CreateTileData(int)` | `TileData` instance | Rarely |
| `CreateUnitRoleManager(Game)` | `UnitRoleManager` instance | Rarely |
| `CreateClientInput(IApplication)` | `ClientInput` instance | Rarely |
| `CreateClientRenderer(IApplication)` | `ClientRenderer` instance | Rarely |
| `CreateClientSelection(IApplication)` | `ClientSelection` instance | Rarely |
| `CreateClientManager(GameInterfaces)` | `ClientManager` instance | Rarely |
| `CreateClientConsoleCommands(IApplication)` | Console commands | Rarely |
| `CreateMapBuilder()` | `MapBuilder` instance | Rarely |
| `CreatePathfinder()` | `PathFinder` instance | Rarely |
| `CreateRoadPathfinder(Game)` | `RoadPathfinder` instance | Rarely |
| `CreateTradeNetworkSolver(Game)` | `TradeNetworkSolver` instance | Rarely |
| `CreateActionData(ActionType, PlayerType)` | `ActionData` instance | Rarely |
| `CreateGameHelperInstance()` | `GameHelpers` instance | Rarely |
| `CreateUtils()` | `Utils` instance | Rarely |

See `Reference/Source/Mods/Greece3/` and `Reference/Source/Mods/Egypt3/` for complete examples.

---

## Approach 2: Harmony Patching

Harmony is a .NET library that patches methods at runtime without replacing entire classes. Multiple Harmony mods can coexist — postfixes stack, and multiple prefixes work as long as they don't all skip the original method.

**Reference**: See [dales.world/HarmonyDLLs.html](https://dales.world/HarmonyDLLs.html) for a detailed tutorial.

Harmony supports two ways to register patches: **attribute-based** (automatic discovery) and **manual** (explicit registration). Both are equally valid.

### Option A: Attribute-Based Patching

Use `[HarmonyPatch]` attributes and call `PatchAll()` to auto-discover patches:

```csharp
public override void Initialize(ModSettings modSettings)
{
    base.Initialize(modSettings);
    if (_harmony != null) return;

    _harmony = new Harmony(HarmonyId);
    _harmony.PatchAll(); // Finds all [HarmonyPatch] classes in the assembly
    Debug.Log("[MyMod] Patches applied");
}
```

#### Prefix — Runs BEFORE the original method

```csharp
[HarmonyPatch(typeof(Player.PlayerAI), nameof(Player.PlayerAI.getWarOfferPercent))]
public static class WarOfferPatch
{
    // Return false to skip the original method entirely
    // __instance is the object the method is called on
    static bool Prefix(Player.PlayerAI __instance, PlayerType eOtherPlayer, ref int __result)
    {
        if (__instance.game.player(eOtherPlayer).getNation() == NationType.ROME)
        {
            __result = 100;
            return false;  // Skip original method
        }
        return true;  // Run original method
    }
}
```

#### Postfix — Runs AFTER the original method

```csharp
[HarmonyPatch(typeof(Player.PlayerAI), nameof(Player.PlayerAI.getWarOfferPercent))]
public static class WarOfferPostfixPatch
{
    // __result is the return value (use ref to modify it)
    static void Postfix(Player.PlayerAI __instance, PlayerType eOtherPlayer,
        bool bDeclare, ref int __result)
    {
        Player pOtherPlayer = __instance.game.player(eOtherPlayer);
        if (pOtherPlayer.isHuman())
            return;

        if (__result > 0 && bDeclare)
        {
            __result = __result * 3 / 2;  // +50% AI-vs-AI war chance
            __result = Math.Min(__result, 100);
        }
    }
}
```

#### Patching Overloaded Methods

Specify parameter types to target a specific overload:

```csharp
[HarmonyPatch(typeof(Player.PlayerAI),
    nameof(Player.PlayerAI.getWarOfferPercent),
    new Type[] { typeof(PlayerType), typeof(bool), typeof(bool), typeof(bool) })]
public static class WarOfferPlayerPatch
{
    static void Postfix(ref int __result) { /* ... */ }
}
```

### Option B: Manual Patching

Register patches explicitly with `_harmony.Patch()`. This gives you full control over which methods to patch and avoids attribute scanning:

```csharp
public override void Initialize(ModSettings modSettings)
{
    base.Initialize(modSettings);
    if (_harmony != null) return;

    _harmony = new Harmony(HarmonyId);

    // Manually register a postfix on Tile.setImprovement
    _harmony.Patch(
        AccessTools.Method(typeof(Tile), "setImprovement"),
        postfix: new HarmonyMethod(AccessTools.Method(
            typeof(MyPatch), nameof(MyPatch.Postfix)))
    );

    // Manually register a prefix on ModSettings.CreateServerGame
    _harmony.Patch(
        AccessTools.Method(typeof(ModSettings), nameof(ModSettings.CreateServerGame)),
        prefix: new HarmonyMethod(AccessTools.Method(
            typeof(AnotherPatch), nameof(AnotherPatch.Prefix)))
    );

    Debug.Log("[MyMod] Patches applied");
}
```

With manual patching, your patch classes don't need `[HarmonyPatch]` attributes:

```csharp
public static class MyPatch
{
    // __instance is the Tile that setImprovement was called on
    // eNewImprovement is the method parameter
    public static void Postfix(Tile __instance, ImprovementType eNewImprovement)
    {
        if (eNewImprovement == __instance.game().infos().getType<ImprovementType>("IMPROVEMENT_FORT"))
        {
            Debug.Log("[MyMod] Fort placed on tile " + __instance.getID());
        }
    }
}
```

### When to Use Each Approach

| | Attribute-Based (`PatchAll`) | Manual (`Patch`) |
|---|---|---|
| **Pros** | Less boilerplate, self-documenting | Full control, no scanning |
| **Cons** | Patches all attributed classes (all-or-nothing) | More verbose |
| **Best for** | Mods with many patches | Mods with few targeted patches |

### Harmony Special Parameters

Harmony injects special values based on parameter names:

| Parameter | Type | Meaning |
|-----------|------|---------|
| `__instance` | Declaring type | The object the method was called on |
| `__result` | Return type (with `ref`) | The method's return value (postfix only) |
| `__state` | Any (with `ref` in prefix) | State passed from prefix to postfix |
| Named params | Original param types | Method parameters by matching name |

### Harmony Notes

- Use liberal `Debug.Log` during development
- Always include null checks — Old World uses parallel processing
- Always wrap patch bodies in try/catch to avoid crashing the game
- Postfixes from multiple mods stack safely; prefixes that return `false` prevent later patches from running
- Harmony 2.4.2+ is required for Apple Silicon Mac support

---

## Accessing Game Data

### The Assembly-CSharp Constraint

Old World blocks mods from directly referencing `Assembly-CSharp.dll`. You cannot import `AppMain` or access `AppMain.gApp.Client.Game` directly.

**Within Harmony patches**, this is usually not a problem — the `__instance` parameter gives you the object being patched, which typically has access to the game via methods like `.game()` or `.infos()`.

**Within lifecycle hooks** (like `OnNewTurnServer`), you need reflection to access the Game object:

```csharp
using System;
using System.Reflection;
using TenCrowns.GameCore;
using UnityEngine;

public partial class MyMod : ModEntryPointAdapter
{
    private static Type _appMainType;
    private static FieldInfo _gAppField;
    private static PropertyInfo _clientProperty;
    private static PropertyInfo _gameProperty;
    private static bool _reflectionInitialized;

    private void InitializeReflection()
    {
        if (_reflectionInitialized) return;

        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            if (assembly.GetName().Name == "Assembly-CSharp")
            {
                _appMainType = assembly.GetType("AppMain");
                break;
            }
        }

        if (_appMainType != null)
        {
            _gAppField = _appMainType.GetField("gApp",
                BindingFlags.Public | BindingFlags.Static);
            _clientProperty = _appMainType.GetProperty("Client",
                BindingFlags.Public | BindingFlags.Instance);

            if (_clientProperty != null)
            {
                var clientType = _clientProperty.PropertyType;
                _gameProperty = clientType.GetProperty("Game",
                    BindingFlags.Public | BindingFlags.Instance);
            }
        }

        _reflectionInitialized = true;
    }

    private Game GetGame()
    {
        InitializeReflection();

        var appMain = _gAppField?.GetValue(null);
        if (appMain == null) return null;

        var client = _clientProperty?.GetValue(appMain);
        if (client == null) return null;

        return _gameProperty?.GetValue(client) as Game;
    }
}
```

### Working with Game Types

```csharp
public override void OnNewTurnServer()
{
    Game game = GetGame();
    if (game == null) return;

    int turn = game.getTurn();
    Infos infos = game.infos();

    foreach (Player player in game.getPlayers())
    {
        if (player == null) continue;

        // Use mzType for string identifiers (enum ToString() returns numbers)
        string nation = infos.nation(player.getNation()).mzType;  // "NATION_ROME"

        int food = player.getYieldStockpileWhole(infos.Globals.YIELD_FOOD);
        int gold = player.getYieldStockpileWhole(infos.Globals.YIELD_MONEY);

        Debug.Log($"[MyMod] {nation}: Food={food}, Gold={gold}");
    }
}
```

---

## Building Your Mod

### Environment Setup

Create a `.env` file (don't commit this):

```bash
# Path to Old World game install (needed for C# build)
# macOS (Steam):
OLDWORLD_PATH="/Users/yourusername/Library/Application Support/Steam/steamapps/common/Old World"
# Windows (Steam):
# OLDWORLD_PATH="C:\Program Files (x86)\Steam\steamapps\common\Old World"

# Path to Old World's Mods directory (for deployment)
# macOS:
OLDWORLD_MODS_PATH="/Users/yourusername/Library/Application Support/OldWorld/Mods"
# Windows:
# OLDWORLD_MODS_PATH="C:\Users\yourusername\Documents\My Games\OldWorld\Mods"
```

### Build and Deploy

If you're using the template's `scripts/deploy.sh`, it handles building and deploying automatically — just run `./scripts/deploy.sh`. The script detects the `.csproj`, builds it, and copies all files including DLLs.

For manual builds:

```bash
dotnet build MyMod.csproj -c Release -p:OldWorldPath="$OLDWORLD_PATH"
```

This outputs `bin/MyMod.dll` and `bin/0Harmony.dll` (flat output, no `Release/net472` subdirectory).

> **Important**: Always `rm -rf` the target mod directory before copying. `cp -r` doesn't remove stale files, so old XML or DLL files can linger and cause confusing bugs.

### Build Script (Windows PowerShell)

Create `deploy.ps1`:

```powershell
$ErrorActionPreference = "Stop"

# Load .env
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        $name = $matches[1]
        $value = $matches[2] -replace '^"(.*)"$', '$1'
        $value = [Environment]::ExpandEnvironmentVariables($value)
        Set-Item -Path "Env:$name" -Value $value
    }
}

$ModName = "MyMod"
$ModDir = "$env:OLDWORLD_MODS_PATH\$ModName"

Write-Host "Building..."
dotnet build "$ModName.csproj" -c Release -p:OldWorldPath="$env:OLDWORLD_PATH"

Write-Host "Deploying to $ModDir..."
if (Test-Path $ModDir) { Remove-Item -Recurse -Force $ModDir }
New-Item -ItemType Directory -Force -Path $ModDir | Out-Null

Copy-Item ModInfo.xml $ModDir
Copy-Item "bin\$ModName.dll" $ModDir

# Copy Harmony DLL if present
if (Test-Path "bin\0Harmony.dll") {
    Copy-Item "bin\0Harmony.dll" $ModDir
}

Write-Host "Done!"
```

### Harmony DLL Bundling

When you use the `Lib.Harmony` NuGet package, the build output includes `0Harmony.dll`. **You must deploy this alongside your mod DLL.** The game does not ship Harmony — your mod must bundle it.

---

## Testing Your Mod

### Manual Testing

1. Run `./deploy.sh` (or `.\deploy.ps1` on Windows)
2. Launch Old World
3. Go to **Mod Manager** and enable your mod
4. Start or load a game
5. Check the game log for your debug messages

### Log Location

- **Windows**: `%USERPROFILE%\AppData\LocalLow\Mohawk Games\Old World\Player.log`
- **macOS**: `~/Library/Logs/MohawkGames/OldWorld/Player.log`
- **Linux**: `~/.config/unity3d/Mohawk Games/Old World/Player.log`

### Headless Mode Testing

Old World supports headless mode for automated testing:

```bash
# macOS
"$OLDWORLD_PATH/OldWorld.app/Contents/MacOS/OldWorld" \
    -batchmode -nographics \
    "/path/to/save.zip" \
    -turns 2

# Windows
"C:\path\to\Old World\OldWorld.exe" ^
    -batchmode -nographics ^
    "C:\path\to\save.zip" ^
    -turns 2
```

---

## Tips and Gotchas

1. **DLL loads three times** — Old World loads your DLL for the controller, server, and client. Use a static guard (`if (_harmony != null) return;`) in `Initialize()` to prevent applying patches multiple times.

2. **Never reference Assembly-CSharp directly** — Use reflection as shown above. The game will refuse to load your mod if it has a direct assembly reference.

3. **Game may be null** — During menus, loading screens, or between sessions. Always null-check before accessing game state.

4. **Use mzType for strings** — Enum `.ToString()` returns integer values, not string identifiers. Use `infos.nation(player.getNation()).mzType` to get `"NATION_ROME"`.

5. **Null safety is critical** — Old World uses parallel processing. Always check for null, especially in Harmony patches.

6. **Wrap patch bodies in try/catch** — An unhandled exception in a Harmony patch can crash the game. Log the error and fail gracefully.

7. **GameFactory is exclusive** — Only one mod can set `modSettings.Factory`. If two mods both set it, the last one wins.

8. **Clean deploys prevent stale file bugs** — Always `rm -rf` the target mod directory before copying. Old XML files left behind cause confusing behavior.

9. **Harmony 2.4.2+** — Required for Apple Silicon Mac support.

10. **Check the game source** — `Reference/Source/` contains decompiled code. `Reference/Source/Mods/` has complete official scenario examples (Egypt3, Greece3, Carthage).

---

## Further Resources

- **[dales.world](https://dales.world)** — Authoritative Old World modding tutorials
  - [Putting It All Together](https://dales.world/PuttingAllTogether.html) — GameFactory approach
  - [Harmony DLLs](https://dales.world/HarmonyDLLs.html) — Harmony patching guide
- **Old World Discord** — Official modding support channel
- **Reference Source** — `Reference/Source/` in game folder contains decompiled code
- **Example Mods** — `Reference/Source/Mods/Egypt3/` and `Reference/Source/Mods/Greece3/` show complete scenario mods
