# Total Yield Charts Mod for Old World

A reference for creating a Harmony mod that adds cumulative (total) yield charts to the existing Stats screen. Every method, field, and line reference in this document has been validated against the decompiled game code.

## Background

The Stats screen (`StatsPopup`) has a **Production** tab with sub-tabs for each yield (Food, Wood, Stone, Iron, Training, Civics, Money). Each sub-tab charts **yield rate per turn**. The game already tracks cumulative totals internally and shows them in the tooltip when hovering a data point, but there is no way to chart total yield over time.

## How the Stats Screen Works

### Key Source Files

| File | Role |
|------|------|
| `StatsPopup.cs` | Main popup class — tab management, data building, tooltip rendering |
| `MohawkLineGraph.cs` | Line graph renderer — `DrawSeries()`, coordinate mapping, point highlighting |
| `SpriteBasedLineRenderer.cs` | Low-level line drawing via sprites |

All are in `Assembly-CSharp.dll`.

### Class: StatsPopup

Inherits `Popup`. Implements `IUIEventListener`, `IGameReadyListener`.

#### Enums

```csharp
// Tab types — the top-level navigation
enum PopupTabType {
    NONE = -1,
    STATS,        // 0 — Summary statistics (table, not a graph)
    PRODUCTION,   // 1 — Yield rate per turn (has sub-tabs per yield)
    MILITARY,     // 2
    TERRITORY,    // 3
    EXPLORATION,  // 4
    PRICES,       // 5
    POINTS,       // 6
    LEGITIMACY,   // 7
    FAMILIES,     // 8
    RELIGIONS,    // 9
    NUM_TYPES     // 10
}

// Graph categories — groupings that contain sub-tabs
enum PopupGraphCategoryType {
    PRODUCTION,   // 0 — The only category; sub-tabs are yield types
    NUM_TYPES     // 1
}
```

#### Data Model: PointData

```csharp
public class PointData {
    public List<Vector2> points;   // (turn_number, value) pairs
    public PlayerType player;
    public string label;
    public string iconName;
    public Color color;
    public bool isRealSeries;
}
```

All series for the current graph live in `List<PointData> lineData` (line 100). Cleared on tab switch (line 905).

### How the Production Tab Builds Chart Data

#### 1. Tab initialization: `UpdateLabels()` (lines 190–217)

Iterates over `PopupGraphCategoryType`. For `PRODUCTION`, creates a sub-tab for each yield type that isn't hidden or a subtraction yield:

```csharp
for (YieldType yieldType = (YieldType)0; yieldType < mInfos.yieldsNum(); yieldType++) {
    if (mInfos.yield(yieldType).meSubtractFromYield == YieldType.NONE
        && !mInfos.yield(yieldType).mbHideOnUI) {
        UIAttributeTag subTag2 = subTag.GetSubTag("-Graph", num);
        subTag2.SetTEXT("Title", textManager, helpText.buildYieldLinkVariable(yieldType, false));
        subTag2.SetKey("Data", 1 + "," + ((int)yieldType).ToStringCached());
        // Data format: "tabIndex,subTabIndex" e.g. "1,3" for Production/Iron
        num++;
    }
}
subTag.SetInt("NumSubGraphs", num);
```

Category count is set at line 182: `popupTag.SetInt("NumCategories", 1)`.

#### 2. Graph dispatch: `UpdateGraph(PopupTabType)` (lines 473–559)

Switch on `eGraph`. The Production case (line 490):

```csharp
case PopupTabType.PRODUCTION:
    YieldType eYield = (YieldType)currentSubTab;
    UpdateGraph((Player player, int turn) =>
        (float)player.getTurnYieldRate(turn, eYield) / 10f);
    break;
```

**This is the primary patch target.** Swapping `getTurnYieldRate` with `getTurnYieldTotal` (and adjusting the divisor) would show cumulative totals.

#### 3. Per-player data building: `UpdateGraph(Func<Player, int, float>)` (lines 808–828)

Iterates all players, calls `UpdateGraph(Player, Func)` for visible ones:

```csharp
protected virtual void UpdateGraph(Func<Player, int, float> valueFunc) {
    for (PlayerType playerType = (PlayerType)0; playerType < mGame.getNumPlayers(); playerType++) {
        Player pPlayer = mGame.player(playerType);
        if (ShouldShowPlayer(pPlayer)) {
            UpdateGraph(mGame.player(playerType), valueFunc);
        }
        // ... removes hidden players from lineData
    }
}
```

#### 4. Point generation: `UpdateGraph(Player, Func)` (lines 830–837)

```csharp
protected virtual void UpdateGraph(Player pPlayer, Func<Player, int, float> valueFunc) {
    PointData pointData = FindMatchingSeriesOrCreate(pPlayer.getPlayer(), isReal: true,
        helpText.buildPlayerLinkVariable(pPlayer, pActivePlayer).ToString(textManager),
        "", mManager.ColorManager.GetColor(pPlayer.getPlayerNameColor(pActivePlayer)));
    for (int i = pointData.points.Count + 1; i <= mGame.getTurn(); i++) {
        pointData.points.Add(new Vector2(i, valueFunc(pPlayer, i)));
    }
}
```

Points are built incrementally — only new turns are appended.

### Existing Total Yield Data

The game already has `player.getTurnYieldTotal(turn, yieldType)`. It's used in the Production chart tooltip (lines 1215–1231 of `buildGraphHelp()`):

```csharp
if (eYield != YieldType.NONE && num2 > 0) {
    helpText.buildDividerText(builder);
    builder.Add(helpText.TEXTVAR_TYPE("TEXT_HELPTEXT_TOTALS"));
    foreach (PointData lineDatum2 in lineData) {
        if (ShouldShowPlayer(mGame.player(lineDatum2.player))) {
            acquireScope.Value.Add((lineDatum2.player,
                mGame.player(lineDatum2.player).getTurnYieldTotal(turn, eYield)));
        }
    }
    // ... sorts descending and renders
}
```

This confirms `getTurnYieldTotal` returns cumulative yield through the given turn for a player/yield pair. The data is already stored and accessible — no new tracking needed.

### Graph Title

`UpdateGraphTitle()` (lines 857–867):

```csharp
if (currentTab == PopupTabType.PRODUCTION) {
    popupTag.SetKey("CurrentGraph-Title",
        textManager.TEXT("TEXT_UI_GRAPHS_YIELD",
            helpText.buildYieldLinkVariable((YieldType)currentSubTab, false)));
} else {
    popupTag.SetKey("CurrentGraph-Title",
        textManager.TEXT("TEXT_UI_GRAPHS_" + currentTab.ToStringCached()));
}
```

### Tab Click Handling

`OnWidgetClicked()` (lines 869–910) handles `ItemType.STATS_SCREEN_TAB`. Reads `data.GetDataInt(0)` as the tab index and `data.GetDataInt(1)` as the sub-tab index. The `"Data"` key set in `UpdateLabels()` is what feeds these values.

## Design Constraints

### Enum limitation

`PopupTabType` and `PopupGraphCategoryType` are compiled C# enums. Adding new values at runtime is not possible. Options:

1. **Toggle mode on the existing Production tab** — simplest. Reuse the same tab/sub-tab structure but switch the data source between rate and total.
2. **Use out-of-range integer sentinels** — cast ints beyond `NUM_TYPES` to the enum type and intercept in a Prefix before the switch statement. Fragile; requires careful handling throughout.
3. **Add a second graph category** — increment `NumCategories` and populate sub-tabs under category index 1. Less fragile than option 2 but depends on the UI layout supporting multiple categories.

### GameFactory exclusivity

Only one mod can set `modSettings.Factory`. Adding entirely new UI widgets requires a GameFactory override. A toggle approach avoids this constraint entirely.

### Triple-load guard

Old World loads mod DLLs three times (controller, server, client). Harmony patches must be guarded:

```csharp
private static bool _patched = false;

public override void Initialize(ModSettings modSettings) {
    if (_patched) return;
    _patched = true;
    var harmony = new Harmony("com.example.totalyieldcharts");
    harmony.PatchAll();
}
```

## Recommended Approach: Toggle on Production Tab

### User interaction

While viewing any Production sub-tab chart, pressing a key (e.g., `T`) toggles between "Rate" and "Total" mode. The graph title updates to reflect the mode (e.g., "Total Food" vs "Food").

### Static state

```csharp
internal static bool ShowTotals = false;
```

### Patch 1: Intercept graph data — Prefix on `UpdateGraph(PopupTabType)`

Target: `StatsPopup.UpdateGraph(PopupTabType)` (line 473).

When `ShowTotals == true` and `eGraph == PopupTabType.PRODUCTION`:
- Call `UpdateGraph(Func)` with `getTurnYieldTotal` instead of `getTurnYieldRate`
- Return `false` to skip the original method

```
Method: StatsPopup.UpdateGraph(PopupTabType)
Patch type: Prefix
Signature: static bool Prefix(StatsPopup __instance, PopupTabType eGraph)
Skip original: return false when handling totals
```

Key consideration: `currentSubTab` and `lineData` are instance fields. Access via Harmony's `__instance` and reflection (or Traverse). `currentSubTab` maps to `(YieldType)currentSubTab` for the yield type. `lineData` must be cleared/populated the same way the original does.

The divisor needs investigation: rate uses `/ 10f`. Totals from `getTurnYieldTotal` likely use the same x10 internal representation, so `/ 10f` probably still applies. Verify by comparing tooltip total values with `getTurnYieldTotal` raw output.

### Patch 2: Update graph title — Postfix on `UpdateGraphTitle()`

Target: `StatsPopup.UpdateGraphTitle()` (line 857).

When `ShowTotals == true` and `currentTab == PopupTabType.PRODUCTION`:
- Override the title to indicate total mode (e.g., prepend "Total" or use a distinct text key)

```
Method: StatsPopup.UpdateGraphTitle()
Patch type: Postfix
Signature: static void Postfix(StatsPopup __instance)
```

### Patch 3: Adjust tooltip — Prefix on `buildGraphHelp()`

Target: `StatsPopup.buildGraphHelp(TextBuilder, int, PlayerType, YieldType, Func<int, TextVariable>)` (line 1181).

When `ShowTotals == true`:
- Skip the "Totals" section at the bottom (lines 1215–1231) since the chart already shows totals
- Optionally show rate in the tooltip instead (inverse of current behavior)

### Patch 4: Toggle input — Postfix on `Update()`

Target: `StatsPopup.Update()` (line 219).

Check for keypress (e.g., `UnityEngine.Input.GetKeyDown(KeyCode.T)`). On toggle:
- Flip `ShowTotals`
- Set `isPopupDirty = true` to force redraw
- Clear `lineData` so points are rebuilt with the new data source
- Call `UpdateGraphTitle()` to refresh the title

### Patch 5: Force redraw on toggle — clearing cached data

When toggling, `lineData` must be cleared. The incremental point building in `UpdateGraph(Player, Func)` (line 833) appends only new turns. If `lineData` isn't cleared, old rate-based points persist and new total-based points are appended only for subsequent turns.

Access `lineData` via `Traverse.Create(__instance).Field("lineData").GetValue<List<PointData>>()` and call `.Clear()`.

## Fields Requiring Reflection Access

| Field | Type | Access | Line |
|-------|------|--------|------|
| `lineData` | `List<PointData>` | private | 100 |
| `currentTab` | `PopupTabType` | protected | ~105 |
| `currentSubTab` | `int` | protected | ~106 |
| `isPopupDirty` | `bool` | protected | 92 |
| `mGame` | `Game` | inherited from Popup | — |

Since these are `protected`/`private`, use `AccessTools.Field()` or `Traverse` from Harmony.

## Player API Reference

```csharp
// Yield rate for a specific turn (what Production tab currently charts)
// Returns value in x10 format (divide by 10 for display)
int Player.getTurnYieldRate(int turn, YieldType yieldType)

// Cumulative yield through a specific turn (what we want to chart)
// Returns value in x10 format (divide by 10 for display)
int Player.getTurnYieldTotal(int turn, YieldType yieldType)

// Military power at a specific turn
float Player.getTurnMilitaryPower(int turn)

// Legitimacy at a specific turn
float Player.getTurnLegitimacy(int turn)

// Victory points at a specific turn
float Player.getTurnPoints(int turn)
```

## Testing Checklist

- [ ] Toggle key switches between Rate and Total mode on all yield sub-tabs
- [ ] Graph title reflects current mode
- [ ] Tooltip shows correct values (rate values when viewing totals, total values when viewing rate)
- [ ] Switching yield sub-tabs preserves the current mode
- [ ] Switching away from Production tab and back preserves mode
- [ ] Multi-player lines all render correctly in both modes
- [ ] Y-axis scaling adjusts (totals will be much larger numbers than rates)
- [ ] No errors on game load (triple-load guard)
- [ ] Works in single-player and multiplayer observer mode
