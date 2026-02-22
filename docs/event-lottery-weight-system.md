# Event Lottery Weight System

This document describes how Old World's event system selects which events fire using a two-stage weighted lottery mechanism.

## Overview

The event system uses a **two-stage weighted lottery** to select which events fire. Events pass through multiple filters before being entered into a weighted random selection pool.

## Stage 1: Event Trigger Level

When a trigger fires (e.g., `EVENTTRIGGER_TECHNOLOGY`, `EVENTTRIGGER_NEW_TURN`), the trigger itself has probability settings defined in `eventTrigger.xml`:

| Field | Description |
|-------|-------------|
| `iProb` | Base probability (1-100) that the trigger will check for events |
| `bLevel` | If true, probability is modified by game's EventLevel setting |

**Example:** A trigger like `EVENTTRIGGER_RELIGION_FOUNDED_THEM` has `iProb=50` meaning only a 50% chance events are checked when it fires.

## Stage 2: Event Story Pool Filtering

Once a trigger passes its probability check, events are filtered through multiple gates in `PlayerEvent.cs:12984-13004`:

```
1. canDoEventStory() - Basic eligibility check
2. iProb check - Random % chance event enters pool
3. MortalitySkipProb - Game mortality level can skip events
4. isValidEventClass() - Class restrictions
5. isValidEventStory() - Full validation (turns, laws, difficulty, etc.)
```

### The `iProb` Check

From `PlayerEvent.cs:12988-12989`:

```csharp
int iProb = infos().eventStory(eLoopEventStory).miProb;
if ((iProb == 0) ? true : (pRandom.Next(100) < iProb))
```

- `iProb=0` means always included (treated as 100%)
- `iProb=50` means 50% chance to enter the pool this turn
- Events with max priority or test flags bypass this check

## Stage 3: Subject Validation

Events that pass filtering must find valid subjects via `findEventStoryBestSubjects()`. An event with subjects like:

```xml
<aeSubjects>
    <zValue>SUBJECT_LEADER_US</zValue>
    <zValue>SUBJECT_CHARACTER_US</zValue>
</aeSubjects>
```

Must find matching characters that pass all `SubjectExtras`, `SubjectNotExtras`, and `SubjectRelations` tests.

## Stage 4: Weight Calculation

For events that find valid subjects, the final weight is computed in `PlayerEvent.cs:13025-13040`:

```csharp
int iWeight = infos().eventStory(eEventStory).miWeight;  // Base weight from XML

// Add rating modifiers
for (RatingType eLoopRating = 0; eLoopRating < infos().ratingsNum(); eLoopRating++)
{
    int iRatingWeight = infos().eventStory(eEventStory).maiRatingWeight[eLoopRating];
    if (iRatingWeight != 0)
    {
        iWeight += (pLeader.getRating(eLoopRating) * iRatingWeight);
    }
}

// Minimum weight enforced
mapEventStoryDie.Add((eEventStory, Math.Max(1, iWeight)));
```

### Weight Formula

```
Final Weight = max(1, BaseWeight + Σ(LeaderRating × RatingWeight))
```

### Example

From `eventStory.xml`:

```xml
<iWeight>1</iWeight>
<aiRatingWeight>
    <Pair>
        <zIndex>RATING_COURAGE</zIndex>
        <iValue>1</iValue>
    </Pair>
</aiRatingWeight>
```

If leader has Courage rating of 5, final weight = `max(1, 1 + (5 × 1)) = 6`

## Stage 5: Priority Filtering

Before the lottery, events are filtered by priority in `PlayerEvent.cs:13120-13137`:

1. If any event has `bMaxPriority`, remove all non-max-priority events
2. Find highest `iPriority` value among remaining events
3. Remove all events with lower priority

This means high-priority events **completely exclude** lower-priority events from selection.

## Stage 6: New Event Boost

Events that have never fired get a +1 weight boost in `PlayerEvent.cs:13140-13145`:

```csharp
if (getAllEventStoryTurn(mapEventStoryDie[iDieIndex].Item1) == -1)
{
    mapEventStoryDie[iDieIndex].Item2 += 1;  // +1 weight for fresh events
}
```

## Stage 7: Weighted Random Selection

The actual lottery uses `randomDieMap()` in `Utils.cs:402-428`:

```csharp
public virtual T randomDieMap<T>(List<(T, int)> mapDice, ulong seed, T defaultValue)
{
    int iDieSize = 0;
    foreach ((T, int weight) pair in mapDice)
        iDieSize += pair.weight;  // Sum all weights

    int iRoll = pRandom.Next(iDieSize);  // Roll 0 to total-1

    foreach ((T val, int weight) pair in mapDice)
    {
        if (iRoll < pair.weight)
            return pair.val;      // Selected!
        iRoll -= pair.weight;     // Move to next bucket
    }
    return defaultValue;
}
```

### How It Works

Events with weights [2, 3, 5] create a "die" of size 10:

- Roll 0-1 → first event (20% chance)
- Roll 2-4 → second event (30% chance)
- Roll 5-9 → third event (50% chance)

## Special Cases

### Multiple Events

Events marked with `bMultiples=1` bypass the lottery entirely and always fire if valid. They don't block other events.

### Repeat Turn Restrictions

The `iRepeatTurns` field controls event cooldowns:

- `-1` = Can only fire once per game
- `0` = Can fire every turn (no cooldown)
- `N` = Must wait N turns between firings

## XML Field Reference

### eventStory.xml Fields

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `iWeight` | int | 1-20 (0 disables) | Base weight for lottery selection |
| `iProb` | int | 1-100 (0 = always) | Probability event enters pool that turn |
| `iPriority` | int | 1+ | Higher priority events block lower priority |
| `aiRatingWeight` | array | Any | Modifier per leader rating type |
| `iMinTurns` | int | 0+ | Earliest turn event can fire |
| `iMaxTurns` | int | 0+ | Latest turn event can fire |
| `iRepeatTurns` | int | -1 or 0+ | Turns between event triggers |
| `bMultiples` | bool | 0/1 | Event bypasses lottery (always fires) |

### eventTrigger.xml Fields

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `iProb` | int | 1-100 | Probability the trigger fires any events |
| `bLevel` | bool | 0/1 | Scale probability by EventLevel |

## Complete Flow Diagram

```
Trigger Fires
    │
    ▼
Trigger iProb check (may abort)
    │
    ▼
For each event registered to trigger:
    ├─ canDoEventStory() check
    ├─ Event iProb check (random %)
    ├─ MortalitySkipProb check
    ├─ Class validation
    ├─ Full prereq validation
    └─ Subject finding
    │
    ▼
Events with subjects → Calculate weights
    │
    ▼
Priority filtering (highest priority only)
    │
    ▼
+1 boost for new events
    │
    ▼
randomDieMap() weighted lottery
    │
    ▼
Selected event fires
```

## Source Files

- `Reference/XML/Infos/eventStory.xml` - Event definitions
- `Reference/XML/Infos/eventTrigger.xml` - Trigger definitions
- `Reference/Source/Base/Game/GameCore/PlayerEvent.cs` - Core event system
- `Reference/Source/Base/Game/GameCore/Utils.cs` - Lottery function (`randomDieMap`)
