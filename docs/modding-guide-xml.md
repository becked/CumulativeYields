# Old World XML Modding Guide

This guide covers XML-only modding for Old World — adding events, game options, text, and bonuses without any C# code.

**For C# modding** (GameFactory, Harmony patching), see [modding-guide-csharp.md](modding-guide-csharp.md).

**Authoritative external resource**: [dales.world](https://dales.world) has excellent tutorials on Old World modding.

## Project Structure

A minimal XML-only mod requires:

```
MyMod/
├── ModInfo.xml               # Mod manifest (required)
├── logo-512.png              # Mod icon (512x512 PNG)
└── Infos/
    ├── eventStory-add.xml    # Event definitions
    ├── bonus-event-add.xml   # Bonus effects applied by events
    ├── memory-family-add.xml # Family opinion memory effects
    ├── gameOption-add.xml    # Game setup toggles
    ├── text-add.xml          # Text strings (needs UTF-8 BOM)
    └── text-new-add.xml      # Additional text strings (needs UTF-8 BOM)
```

Include only the files you need. Mod files must be in `Infos/` (not `XML/Infos/`) and use the `-add.xml` suffix.

## File Naming Conventions

| File Type | Correct Name | Notes |
|-----------|--------------|-------|
| Text strings | `text-new-add.xml` | `text-add.xml` also works; needs UTF-8 BOM |
| Event stories | `eventStory-add.xml` | No BOM needed |
| Event bonuses | `bonus-event-add.xml` | No `encoding="utf-8"` in XML declaration |
| Family memories | `memory-family-add.xml` | |
| Game options | `gameOption-add.xml` | |
| Event options | `eventOption-add.xml` | Only if using separate file (not recommended) |

## UTF-8 BOM Requirement

Text files (`text-*-add.xml`) **must** have a UTF-8 BOM (byte order mark: `ef bb bf`) at the start of the file. Without the BOM, the game silently fails to load the text and events that reference it won't fire.

**Symptom:** Events never fire, no errors in logs.

**Fix:** Add BOM to text files:
```bash
printf '\xef\xbb\xbf' > temp.xml && cat original.xml >> temp.xml && mv temp.xml original.xml
```

**Verify BOM exists:**
```bash
xxd yourfile.xml | head -1
# Should start with: efbb bf3c 3f78 6d6c
```

Note: Only text files need BOM. Event, bonus, and other XML files do not.

## XML Format: Old vs New Syntax

The game supports two XML formats for events. Use the **new format** with aliases:

### New Format (Recommended)
```xml
<Subjects>
    <Subject alias="leader">
        <Type>SUBJECT_LEADER_US</Type>
    </Subject>
    <Subject alias="candidate">
        <Type>SUBJECT_FAMILY_HEAD_US</Type>
        <Extra>SUBJECT_ADULT</Extra>
        <Extra>SUBJECT_HEALTHY</Extra>
    </Subject>
</Subjects>
<EventOptions>
    <EventOption>
        <Text>TEXT_EVENTOPTION_EXAMPLE</Text>
    </EventOption>
</EventOptions>
```

### Old Format (Avoid)
```xml
<aeSubjects>
    <zValue>SUBJECT_LEADER_US</zValue>
    <zValue>SUBJECT_FAMILY_HEAD_US</zValue>
</aeSubjects>
<aeOptions>
    <zValue>EVENTOPTION_EXAMPLE</zValue>
</aeOptions>
```

---

## Text Strings

### Format

Use `<en-US>` tag for English text, **not** `<English>`:

```xml
<Entry>
    <zType>TEXT_EVENTSTORY_EXAMPLE</zType>
    <en-US>Your text here with {CHARACTER-0} references.</en-US>
</Entry>
```

### Character and Subject References

Use **numeric indices** based on subject order, not alias names:

| Subject Index | Reference | Short Form |
|---------------|-----------|------------|
| 0 | `{CHARACTER-0}` | `{CHARACTER-SHORT-0}` |
| 1 | `{CHARACTER-1}` | `{CHARACTER-SHORT-1}` |
| 2 (if family) | `{FAMILY-2}` | - |

**Wrong:** `{leader:name}`, `{candidate}`
**Correct:** `{CHARACTER-0}`, `{CHARACTER-1}`

---

## Events

### Triggers

Events without an explicit `<Trigger>` element default to `EVENTTRIGGER_NONE`. These go through a **random probability gate** based on event level:

| Event Level | Chance Per Turn |
|-------------|-----------------|
| High | 1/4 = 25% |
| Moderate | 1/6 = ~17% |
| Low | 1/8 = 12.5% |

For reliable per-turn firing, use an explicit trigger:

```xml
<Trigger>EVENTTRIGGER_NEW_TURN</Trigger>
<iMinTurns>1</iMinTurns>
<iPriority>10</iPriority>
<iWeight>10</iWeight>
<iProb>100</iProb>
<iRepeatTurns>2</iRepeatTurns>
```

`EVENTTRIGGER_NEW_TURN` has no probability gate — it fires every turn (subject to other conditions).

### Priority and Weight

| Field | Description | Recommended Value |
|-------|-------------|-------------------|
| `iPriority` | Higher beats lower; vanilla max is 9 | 10+ to beat vanilla |
| `iWeight` | Relative weight in lottery | 1-20 |
| `iProb` | % chance to enter pool (0 or 100 = always) | 100 |
| `iRepeatTurns` | Turns between firings; -1 = once ever | As needed |

### Conditional Options (IndexSubject)

Use `<IndexSubject>` to show/hide options based on subject conditions:

```xml
<EventOption>
    <Text>TEXT_EVENTOPTION_KEEP_LEADER</Text>
    <IndexSubject>
        <Pair>
            <First>2</First>  <!-- Subject index -->
            <Second>SUBJECT_FAMILY_MIN_PLEASED</Second>  <!-- Condition -->
        </Pair>
    </IndexSubject>
</EventOption>
```

This option only appears if the subject at index 2 meets `SUBJECT_FAMILY_MIN_PLEASED`.

**Useful family opinion subjects:**

| Subject | Meaning |
|---------|---------|
| `SUBJECT_FAMILY_MIN_PLEASED` | Pleased or better (positive) |
| `SUBJECT_FAMILY_MIN_CAUTIOUS` | Cautious or better (neutral+) |
| `SUBJECT_FAMILY_MAX_CAUTIOUS` | Cautious or worse (neutral-) |
| `SUBJECT_FAMILY_MIN_FRIENDLY` | Friendly or better |

### Subjects and Relations

Use `<Relations>` inside a Subject to link it to another subject. Useful for linking a family to a specific character:

```xml
<Subjects>
    <Subject alias="candidate1">
        <Type>SUBJECT_FAMILY_HEAD_US</Type>
    </Subject>
    <Subject alias="family1">
        <Type>SUBJECT_FAMILY_US</Type>
        <Relations>
            <Relation>
                <Type>SUBJECTRELATION_FAMILY_SAME</Type>
                <Target>candidate1</Target>
            </Relation>
        </Relations>
    </Subject>
</Subjects>
```

This ensures `family1` is always the same family as `candidate1`.

### Ensuring Different Subjects (SubjectNotRelations)

To ensure multiple subjects come from different families, use `<SubjectNotRelations>` with `<Triple>`:

```xml
<SubjectNotRelations>
    <Triple><First>2</First><Second>SUBJECTRELATION_FAMILY_SAME</Second><Third>3</Third></Triple>
    <Triple><First>2</First><Second>SUBJECTRELATION_FAMILY_SAME</Second><Third>4</Third></Triple>
    <Triple><First>3</First><Second>SUBJECTRELATION_FAMILY_SAME</Second><Third>4</Third></Triple>
</SubjectNotRelations>
```

This prevents subjects at indices 2, 3, and 4 from being in the same family.

### Inline vs Separate Event Options

When using inline `<EventOptions>` with `<SubjectBonuses>` in `eventStory-add.xml`, do **not** also define the same options in a separate `eventOption-add.xml` file. They can conflict.

- **Inline format** (recommended): Uses aliases like `<First>candidate</First>`
- **Separate file format** (old): Uses positional `<zValue>` elements where position = subject index

### Shared Cooldowns

To make multiple events share a cooldown, use `aeEventStoryRepeatTurns` with **bidirectional linking** — each event must list all other events (excluding itself):

```xml
<!-- In EVENTSTORY_A -->
<aeEventStoryRepeatTurns>
    <zValue>EVENTSTORY_B</zValue>
    <zValue>EVENTSTORY_C</zValue>
</aeEventStoryRepeatTurns>

<!-- In EVENTSTORY_B -->
<aeEventStoryRepeatTurns>
    <zValue>EVENTSTORY_A</zValue>
    <zValue>EVENTSTORY_C</zValue>
</aeEventStoryRepeatTurns>

<!-- In EVENTSTORY_C -->
<aeEventStoryRepeatTurns>
    <zValue>EVENTSTORY_A</zValue>
    <zValue>EVENTSTORY_B</zValue>
</aeEventStoryRepeatTurns>
```

One-way linking does **not** work. Every event must list every other event.

---

## Bonuses

### Leader Succession (iSeizeThroneSubject)

To make a character become the new leader via an event bonus:

1. Add `SUBJECT_PLAYER_US` as a subject (e.g., at index 0)
2. Create a bonus with `<iSeizeThroneSubject>0</iSeizeThroneSubject>` pointing to that player subject
3. Apply the bonus TO the character who should become leader (via `<SubjectBonuses>`)

```xml
<!-- In eventStory-add.xml -->
<Subjects>
    <Subject alias="player">
        <Type>SUBJECT_PLAYER_US</Type>
    </Subject>
    <Subject alias="candidate">
        <Type>SUBJECT_FAMILY_HEAD_US</Type>
    </Subject>
</Subjects>
<EventOptions>
    <EventOption>
        <SubjectBonuses>
            <Pair>
                <First>candidate</First>
                <Second>BONUS_SEIZE_THRONE</Second>
            </Pair>
        </SubjectBonuses>
    </EventOption>
</EventOptions>

<!-- In bonus-event-add.xml -->
<Entry>
    <zType>BONUS_SEIZE_THRONE</zType>
    <iSeizeThroneSubject>0</iSeizeThroneSubject>
</Entry>
```

**Key insight**: The bonus is applied to the Character (who becomes leader), while `iSeizeThroneSubject` points to the Player (whose throne is seized).

---

## Family Memory System

To change family opinions via events, use the memory system. Create memories with preset levels, then apply them through bonuses.

**Step 1:** Define memories in `memory-family-add.xml`:
```xml
<Entry>
    <zType>MEMORYFAMILY_ELEVATED</zType>
    <MemoryLevel>MEMORYLEVEL_POS_MEDIUM_SHORT</MemoryLevel>
</Entry>
<Entry>
    <zType>MEMORYFAMILY_PASSED_OVER</zType>
    <MemoryLevel>MEMORYLEVEL_NEG_LOW_SHORT</MemoryLevel>
</Entry>
```

**Step 2:** Apply in a bonus in `bonus-event-add.xml`:
```xml
<Entry>
    <zType>BONUS_ELECT</zType>
    <Memory>MEMORYFAMILY_ELEVATED</Memory>
    <MemoryAllFamilies>MEMORYFAMILY_PASSED_OVER</MemoryAllFamilies>
</Entry>
```

- `<Memory>` applies to the character's family only
- `<MemoryAllFamilies>` applies to **all** families

Net effect: the character's family gets both (+X - Y), other families get only (-Y).

**Common memory levels:**

| Level | Value | Duration |
|-------|-------|----------|
| `MEMORYLEVEL_POS_LOW_SHORT` | +20 | 20 turns |
| `MEMORYLEVEL_POS_MEDIUM_SHORT` | +40 | 20 turns |
| `MEMORYLEVEL_NEG_LOW_SHORT` | -20 | 20 turns |
| `MEMORYLEVEL_NEG_MEDIUM_SHORT` | -40 | 20 turns |
| `MEMORYLEVEL_POS_LOW_NORMAL` | +20 | 40 turns |
| `MEMORYLEVEL_POS_HIGH_FOREVER` | +80 | Permanent |

See [memory-levels.md](memory-levels.md) for the full reference table.

---

## Game Options

Mods can add toggle options to the game setup screen using XML only. These appear as checkboxes under the category you specify.

### Defining a Game Option

Create `Infos/gameOption-add.xml`:

```xml
<?xml version="1.0"?>
<Root>
  <Entry>
    <zType>GAMEOPTION_MY_FEATURE</zType>
    <zName>TEXT_GAMEOPTION_MY_FEATURE</zName>
    <zHelp>TEXT_GAMEOPTION_MY_FEATURE_HELP</zHelp>
    <Category>RULES</Category>
  </Entry>
</Root>
```

**Fields:**

| Field | Description |
|-------|-------------|
| `zType` | Unique identifier (must start with `GAMEOPTION_`) |
| `zName` | Text key for display name |
| `zHelp` | Text key for tooltip description |
| `Category` | Where it appears: `RULES`, `PLAYER`, `OPPONENTS`, or `CHARACTERS` |
| `bDefaultSinglePlayer` | Default ON in single-player if set to `1` (default: OFF) |
| `bDefaultMultiPlayer` | Default ON in multiplayer if set to `1` (default: OFF) |

### Text Entries

Each game option needs two text entries in a `text-*-add.xml` file (must have UTF-8 BOM):

```xml
<Entry>
  <zType>TEXT_GAMEOPTION_MY_FEATURE</zType>
  <en-US>My Feature</en-US>
</Entry>
<Entry>
  <zType>TEXT_GAMEOPTION_MY_FEATURE_HELP</zType>
  <en-US>Enables the custom feature. Changes X and Y behavior.</en-US>
</Entry>
```

### Mutual Exclusivity (`abDisableWhenActive`)

To grey out other options in the UI when one is checked, use `abDisableWhenActive`. This must be **bidirectional** — each option lists the others:

```xml
<Entry>
  <zType>GAMEOPTION_MODE_EASY</zType>
  <zName>TEXT_GAMEOPTION_MODE_EASY</zName>
  <zHelp>TEXT_GAMEOPTION_MODE_EASY_HELP</zHelp>
  <Category>RULES</Category>
  <abDisableWhenActive>
    <Pair>
      <zIndex>GAMEOPTION_MODE_HARD</zIndex>
      <bValue>1</bValue>
    </Pair>
  </abDisableWhenActive>
</Entry>
<Entry>
  <zType>GAMEOPTION_MODE_HARD</zType>
  <zName>TEXT_GAMEOPTION_MODE_HARD</zName>
  <zHelp>TEXT_GAMEOPTION_MODE_HARD_HELP</zHelp>
  <Category>RULES</Category>
  <abDisableWhenActive>
    <Pair>
      <zIndex>GAMEOPTION_MODE_EASY</zIndex>
      <bValue>1</bValue>
    </Pair>
  </abDisableWhenActive>
</Entry>
```

Note: `abDisableWhenActive` is **UI-only**. It greys out the other option but does not force-uncheck it. If a player manually enables both (e.g., via save editing), both will be active.

### Gating Events on Game Options (`aeGameOptionInvalid`)

The **only** way XML events can react to game options at runtime is `aeGameOptionInvalid`. This field lists game options that **block** the event from firing:

```xml
<Entry>
  <zType>EVENTSTORY_MY_DEFAULT_EVENT</zType>
  <!-- ... other event fields ... -->
  <aeGameOptionInvalid>
    <zValue>GAMEOPTION_MODE_HARD</zValue>
  </aeGameOptionInvalid>
</Entry>
```

Key behavior:
- Uses **OR logic**: if **any** listed option is active, the event is blocked
- There is **no `aeGameOptionRequired`** — you can only block events, not require an option to be on
- This is the same mechanism vanilla uses (e.g., `GAMEOPTION_COMPETITIVE_EVENTS` blocks certain events)

### Pattern: Priority Cascade for Preset Selection

When you want mutually exclusive event sets controlled by game options — but can only block, not require — use the **priority cascade** pattern.

**Problem:** You have three presets (Default, Alt1, Alt2). You want exactly one set of events to fire based on which option is checked. But `aeGameOptionInvalid` can only block, so you can't say "require Alt1 to be ON."

**Solution:** Give the default set the highest priority, block higher-priority sets when alternatives are enabled, and use shared cooldowns to prevent lower-priority fallbacks from also firing.

```
Default events:  iPriority=20, aeGameOptionInvalid=[ALT1, ALT2]
Alt1 events:     iPriority=15, aeGameOptionInvalid=[ALT2]
Alt2 events:     iPriority=10, (no aeGameOptionInvalid)
```

| Options checked | Default (pri 20) | Alt1 (pri 15) | Alt2 (pri 10) | Fires |
|-----------------|-------------------|----------------|----------------|-------|
| Neither (default) | eligible | eligible | eligible | **Default** (highest pri) |
| ALT1 ON | BLOCKED | eligible | eligible | **Alt1** (higher pri) |
| ALT2 ON | BLOCKED | BLOCKED | eligible | **Alt2** (only one) |

All event variants must share a cooldown via `aeEventStoryRepeatTurns` (bidirectional — each event lists all others, excluding itself) to prevent lower-priority events from also firing on the same turn.

### Limitations

- **No custom dropdowns.** The `gameOptionPreset` system (used by Forced March, Event Level, etc.) selects from hardcoded enums. Mods cannot create new dropdown UI elements in XML.
- **No `aeGameOptionRequired`.** Events can only be blocked by options, not required. Use the priority cascade pattern above as a workaround.
- **`abDisableWhenActive` is UI-only.** It greys out options but doesn't enforce mutual exclusivity at the data level.

---

## Debugging

1. **Check logs:** `~/Library/Logs/MohawkGames/OldWorld/Player.log` (macOS), `%USERPROFILE%\AppData\LocalLow\Mohawk Games\Old World\Player.log` (Windows)
2. **Verify mod loads:** Look for `[ModPath] Setting ModPath: .../YourMod/` in the log
3. **No errors doesn't mean success:** The game silently ignores malformed XML
4. **Compare to working mods:** Vanilla events in `Reference/XML/Infos/eventStory.xml` are a good reference
5. **Test incrementally:** Start with a minimal event, add complexity gradually

## Common Pitfalls

1. **Missing BOM on text file** — Events silently fail to fire
2. **Using `<English>` instead of `<en-US>`** — Text won't load
3. **Wrong text file name** — `text-add.xml` works but `text-new-add.xml` is safer
4. **Missing explicit trigger** — Event fires randomly instead of reliably
5. **Using alias names in text** — Use numeric indices like `{CHARACTER-0}`
6. **Extra directories in mod** — Can cause loading errors (keep only `Infos/`, `ModInfo.xml`, images)
7. **Mixing inline and separate event options** — Can cause bonuses to apply to wrong subjects
8. **One-way cooldown linking** — Must be bidirectional for shared cooldowns to work
9. **Clean deploys prevent stale file bugs** — Always `rm -rf` the target mod directory before copying

---

## Further Resources

- **[dales.world](https://dales.world)** — Authoritative Old World modding tutorials
- **Old World Discord** — Official modding support channel
- **[Pinacotheca](https://becked.github.io/pinacotheca/)** — Browsable gallery of all in-game art assets (portraits, icons, illustrations), useful for picking `ImageName` values for events and UI
- **Reference Data** — `Reference/XML/Infos/` in the game folder contains all vanilla XML definitions
- **Vanilla Events** — `Reference/XML/Infos/eventStory.xml` for examples of event structure, triggers, and options
- **[Event Lottery Weight System](event-lottery-weight-system.md)** — How the game selects which events fire
- **[Memory Levels Reference](memory-levels.md)** — Full table of vanilla memory levels
