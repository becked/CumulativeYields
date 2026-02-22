# Old World Vanilla Memory Levels

Reference data extracted from `Reference/XML/Infos/memoryLevel.xml`.

Memory levels control family/character opinion modifiers applied by events. Used via `<MemoryLevel>` in `memory-family-*.xml` files.

## All Memory Levels

| Memory Level | Opinion Value | Duration (Turns) |
|---|---:|---:|
| `MEMORYLEVEL_NEG_LOW_SHORT` | -20 | 20 |
| `MEMORYLEVEL_NEG_LOW_NORMAL` | -20 | 40 |
| `MEMORYLEVEL_NEG_LOW_LONG` | -20 | 80 |
| `MEMORYLEVEL_NEG_LOW_FOREVER` | -20 | forever |
| `MEMORYLEVEL_NEG_MEDIUM_SHORT` | -40 | 20 |
| `MEMORYLEVEL_NEG_MEDIUM_NORMAL` | -40 | 40 |
| `MEMORYLEVEL_NEG_MEDIUM_LONG` | -40 | 80 |
| `MEMORYLEVEL_NEG_MEDIUM_FOREVER` | -40 | forever |
| `MEMORYLEVEL_NEG_HIGH_SHORT` | -80 | 20 |
| `MEMORYLEVEL_NEG_HIGH_NORMAL` | -80 | 40 |
| `MEMORYLEVEL_NEG_HIGH_LONG` | -80 | 80 |
| `MEMORYLEVEL_NEG_HIGH_FOREVER` | -80 | forever |
| `MEMORYLEVEL_POS_LOW_SHORT` | +20 | 20 |
| `MEMORYLEVEL_POS_LOW_NORMAL` | +20 | 40 |
| `MEMORYLEVEL_POS_LOW_LONG` | +20 | 80 |
| `MEMORYLEVEL_POS_LOW_FOREVER` | +20 | forever |
| `MEMORYLEVEL_POS_MEDIUM_SHORT` | +40 | 20 |
| `MEMORYLEVEL_POS_MEDIUM_NORMAL` | +40 | 40 |
| `MEMORYLEVEL_POS_MEDIUM_LONG` | +40 | 80 |
| `MEMORYLEVEL_POS_MEDIUM_FOREVER` | +40 | forever |
| `MEMORYLEVEL_POS_HIGH_SHORT` | +80 | 20 |
| `MEMORYLEVEL_POS_HIGH_NORMAL` | +80 | 40 |
| `MEMORYLEVEL_POS_HIGH_LONG` | +80 | 80 |
| `MEMORYLEVEL_POS_HIGH_FOREVER` | +80 | forever |

## Quick Reference

**Magnitudes:** LOW = 20, MEDIUM = 40, HIGH = 80

**Durations:** SHORT = 20 turns, NORMAL = 40 turns, LONG = 80 turns, FOREVER = permanent

## Usage in This Mod

| Memory | MemoryLevel | Effect |
|---|---|---|
| `MEMORYFAMILY_REPUBLIC_ELEVATED` | `MEMORYLEVEL_POS_MEDIUM_SHORT` | +40 opinion, 20 turns |
| `MEMORYFAMILY_REPUBLIC_PASSED_OVER` | `MEMORYLEVEL_NEG_LOW_SHORT` | -20 opinion, 20 turns |

Net effect per election: winner's family = +40 - 20 = **+20**, other families = **-20**. Effects last 20 turns (2 election cycles).

## Alternative: Custom Values

Instead of `MemoryLevel`, you can use `iValue` and `iTurns` directly for non-standard values:

```xml
<Entry>
    <zType>MEMORYFAMILY_CUSTOM</zType>
    <iValue>30</iValue>
    <iTurns>15</iTurns>
</Entry>
```
