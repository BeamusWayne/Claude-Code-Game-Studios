# ADR-0010: Save/Load Persistence

## Status

Accepted

## Date

2026-05-14

## Last Verified

2026-05-14

## Decision Makers

godot-specialist (author), technical-director (review pending)

## Summary

七夜 requires save/load that captures mid-night game state across multiple systems (LoopStateManager, ClueDatabase, TimerService, RoomManager, NPCManager) with crash recovery guaranteeing the player never loses more than one action. This ADR defines a SaveManager Autoload that coordinates serialization by calling each system's serialize() method, aggregates results into a versioned JSON file, and uses atomic write (write-to-tmp-then-rename) with backup rotation for crash safety. Three independent save slots supported. The SaveManager owns NO game state -- it is a coordination layer only.

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Persistence / Core |
| **Knowledge Risk** | LOW -- FileAccess, JSON, OS.rename, user:// directory are stable since Godot 4.0 |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, docs/engine-reference/godot/breaking-changes.md, docs/engine-reference/godot/deprecated-apis.md |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Test atomic write + rename produces valid save after simulated crash (kill process during write). Test load of backup file when primary is corrupt. Test schema migration from version 1 to version 2. Test save/load round-trip with all systems populated (50+ clues, 10+ consequences, mid-night timer). Test 3-slot independence. Test auto-save after clue discovery, consequence registration, and room change. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (loop-state-management -- provides serialize()/deserialize()), ADR-0005 (clue-insight-unified-schema -- provides ClueDatabase.serialize()/deserialize()), ADR-0007 (room-location-management -- provides RoomManager state for serialization), ADR-0008 (countdown-timer -- provides TimerService.serialize()/deserialize()), ADR-0009 (npc-state-machine -- NPC state persisted via LoopStateManager pipeline) |
| **Enables** | System #8 (Night Transition Controller -- needs save before advance_night()), all mid-session persistence, crash recovery |
| **Blocks** | System #8 (Night Transition Controller), production release (no ship without save/load) |
| **Ordering Note** | Must be Accepted before Night Transition Controller ADR. All source system ADRs (0004, 0005, 0007, 0008) are already Accepted or Proposed. |

## Context

### Problem Statement

七夜 is a game about accumulating knowledge across 7 time loops. Play sessions last 30-90 minutes (2-4 loops per session). Players must be able to quit at any point and resume exactly where they left off -- not just between nights, but mid-night. Additionally, the game must survive crashes without losing more than one player action. The save system must coordinate serialization across 5+ independent systems, each owning their own state, without itself becoming a god object that owns any game state.

### Current State

No save/load system exists. The systems that own game state each define their own serialize()/deserialize() methods in their respective ADRs:

- **LoopStateManager.serialize()** -- returns Dictionary with current_night, current_phase, consequences, delta_accumulator, template_overrides (ADR-0004)
- **ClueDatabase.serialize()** -- returns Dictionary with entries, connections (ADR-0005)
- **TimerService.serialize()** -- returns Dictionary with remaining_time, total_duration, pressure_level, current_phase, time_scale, is_active (ADR-0008)
- **RoomManager** -- current_room_id is serializable; room template state resets on load from PackedScene re-instantiation (ADR-0007)
- **NPCManager** -- NPC state is persisted through LoopStateManager's propose_delta() pipeline, captured in LoopStateManager.serialize(). NPCManager re-initializes from templates + deltas on load (ADR-0009).

### Constraints

- Each system owns its own state and provides serialize()/deserialize() -- SaveManager must NOT bypass this ownership
- Save must capture ALL game state needed to restore a playable session
- Save file must be human-readable for debugging (JSON preferred)
- Crash recovery: player loses at most one action
- Minimum 3 save slots, each independent
- Mobile-compatible: save files in user:// directory (OS.get_user_data_dir())
- Godot 4.x FileAccess.open() returns null on failure (not error code) -- all file operations must null-check
- Godot 4.4+ FileAccess.store_*() returns bool -- must check return value
- Save file size budget: < 500 KB per slot (mobile-friendly)

### Requirements

- Coordinate serialization across all state-owning systems
- JSON save file format with schema versioning
- Atomic write (write to .tmp, then OS.rename to final name) for crash safety
- Backup of previous save file before overwriting
- 3 independent save slots
- Auto-save after every state-changing player action (clue discovery, consequence registration, room change)
- Manual save via save menu (blocked during night transition)
- Schema migration for forward compatibility
- SaveManager does NOT own any game state
- Load restores all systems to saved state via their deserialize() methods
- New game clears current slot and resets all systems

## Decision

SaveManager Autoload singleton coordinating JSON serialization. Each system serializes independently; SaveManager aggregates into a single versioned save file per slot. Atomic write with backup rotation for crash recovery.

### Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                    SaveManager (Autoload)                          │
│                                                                    │
│  NO GAME STATE OWNED -- coordination only                          │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │  Serialization Pipeline:                                    │   │
│  │                                                             │   │
│  │  save_game(slot_id)                                         │   │
│  │    1. Collect snapshots from each system:                   │   │
│  │       - LoopStateManager.serialize() -> "loop_state"        │   │
│  │       - ClueDatabase.serialize()      -> "clue_database"    │   │
│  │       - TimerService.serialize()      -> "timer_service"    │   │
│  │       - RoomManager.get_save_data()   -> "room_manager"     │   │
│  │    2. Build save envelope:                                  │   │
│  │       { schema_version, timestamp, slot_id, systems: {...} }│   │
│  │    3. Atomic write:                                         │   │
│  │       a. Rotate backup: save_N.json -> save_N.bak           │   │
│  │       b. Write to save_N.tmp                                │   │
│  │       c. OS.rename(save_N.tmp -> save_N.json)               │   │
│  │    4. Emit save_completed(slot_id)                          │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │  Deserialization Pipeline:                                  │   │
│  │                                                             │   │
│  │  load_game(slot_id)                                         │   │
│  │    1. Read save_N.json (fallback: save_N.bak)              │   │
│  │    2. Parse JSON -> Dictionary                              │   │
│  │    3. Check schema_version -> run migrations if needed      │   │
│  │    4. Distribute to each system:                            │   │
│  │       - LoopStateManager.deserialize(data["loop_state"])    │   │
│  │       - ClueDatabase.deserialize(data["clue_database"])     │   │
│  │       - TimerService.deserialize(data["timer_service"])     │   │
│  │       - RoomManager.restore_from_save(data["room_manager"]) │   │
│  │    5. Emit load_completed(slot_id)                          │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  ┌────────────────────────────────────────────────────────────┐   │
│  │  Auto-Save Triggers (via signal connections):               │   │
│  │                                                             │   │
│  │  ClueDatabase.clue_discovered    -> _auto_save()            │   │
│  │  ClueDatabase.insight_generated  -> _auto_save()            │   │
│  │  ClueDatabase.connection_made    -> _auto_save()            │   │
│  │  LoopStateManager.consequence_registered -> _auto_save()    │   │
│  │  NPCManager.npc_state_changed    -> _auto_save()            │   │
│  │  RoomManager.room_changed        -> _auto_save()            │   │
│  └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  State:                                                            │
│    current_slot: int (-1 = no active slot)                         │
│    _is_saving: bool (guards against concurrent writes)             │
│    _is_loading: bool (guards against concurrent loads)             │
│    SCHEMA_VERSION: int = 1                                         │
│                                                                    │
│  File Layout (user://):                                            │
│    save_1.json / save_1.bak                                        │
│    save_2.json / save_2.bak                                        │
│    save_3.json / save_3.bak                                        │
│    settings.json (future: audio/settings persistence)              │
└────────────────────────────────────────────────────────────────────┘
         │                    │                    │
    ┌────▼─────┐    ┌────────▼────────┐   ┌──────▼──────┐
    │LoopState │    │ClueDatabase     │   │TimerService │
    │Manager   │    │                 │   │             │
    │serialize │    │serialize()      │   │serialize()  │
    │deserialize│   │deserialize()    │   │deserialize()│
    └──────────┘    └─────────────────┘   └─────────────┘
         │
    ┌────▼──────┐
    │RoomManager│    ┌──────────────┐
    │get_save   │    │NPCManager    │
    │_data()    │    │(state stored │
    │restore    │    │ in LoopState │
    │_from_save │    │ serialize)   │
    └───────────┘    └──────────────┘
```

### Key Interfaces

**SaveManager (Autoload Singleton)**:
```gdscript
class_name SaveManager
extends Node

signal save_completed(slot_id: int)
signal save_failed(slot_id: int, reason: String)
signal load_completed(slot_id: int)
signal load_failed(slot_id: int, reason: String)
signal auto_save_completed()

const SCHEMA_VERSION: int = 1
const SAVE_FILE_PREFIX: String = "save_"
const SAVE_FILE_EXTENSION: String = ".json"
const BACKUP_EXTENSION: String = ".bak"
const TEMP_EXTENSION: String = ".tmp"
const NUM_SLOTS: int = 3

var current_slot: int = -1
var _is_saving: bool = false
var _is_loading: bool = false

func _ready() -> void:
    _connect_auto_save_signals()

## --- Public API ---

func save_game(slot_id: int) -> bool:
    ## Saves all game state to the specified slot.
    ## Returns true on success, false on failure.
    ## Blocked during night transition (LoopStateManager.is_transitioning).

func load_game(slot_id: int) -> bool:
    ## Loads all game state from the specified slot.
    ## Falls back to .bak if .json is missing or corrupt.
    ## Returns true on success, false on failure.

func new_game(slot_id: int) -> void:
    ## Starts a new game in the specified slot.
    ## Resets all systems to initial state and saves.

func delete_save(slot_id: int) -> bool:
    ## Deletes save file and backup for the specified slot.

func has_save(slot_id: int) -> bool:
    ## Returns true if a save file exists for the slot.

func get_save_metadata(slot_id: int) -> Dictionary:
    ## Returns metadata (night, timestamp, etc.) without full load.
    ## Returns empty Dictionary if no save exists.

func get_all_save_metadata() -> Array[Dictionary]:
    ## Returns metadata for all slots. Used by save/load UI.

## --- Auto-Save ---

func _auto_save() -> void:
    ## Called after state-changing events.
    ## Only saves if current_slot >= 0 and not already saving/loading.
    ## Debounced: no more than once per 2 seconds.

func _connect_auto_save_signals() -> void:
    ## Connect auto-save triggers from state-owning systems.
    ## Connections made in _ready() after all Autoloads are available.

## --- File Operations ---

func _get_save_path(slot_id: int) -> String:
    return "user://%s%d%s" % [SAVE_FILE_PREFIX, slot_id, SAVE_FILE_EXTENSION]

func _get_backup_path(slot_id: int) -> String:
    return "user://%s%d%s" % [SAVE_FILE_PREFIX, slot_id, BACKUP_EXTENSION]

func _get_temp_path(slot_id: int) -> String:
    return "user://%s%d%s" % [SAVE_FILE_PREFIX, slot_id, TEMP_EXTENSION]

func _atomic_write(slot_id: int, json_string: String) -> bool:
    ## Atomic write: write to .tmp, then rename to final path.
    ## 1. Rotate backup: rename current save -> .bak
    ## 2. Write new data to .tmp
    ## 3. Rename .tmp -> final save file
    ## Returns false if any step fails; previous backup preserved.

func _read_save_file(slot_id: int) -> Dictionary:
    ## Read save file. Falls back to backup if primary is missing/corrupt.
    ## Returns empty Dictionary if neither file is readable.

func _rotate_backup(slot_id: int) -> bool:
    ## Rename current save file to .bak (overwriting old backup).

## --- Schema Migration ---

func _migrate_save(data: Dictionary) -> Dictionary:
    ## Applies migration functions in order from data's schema_version
    ## to current SCHEMA_VERSION. Returns migrated data.
    ## Each migration function is a static method on SaveManager.
    var version: int = data.get("schema_version", 1)
    while version < SCHEMA_VERSION:
        var migrator_name: String = "_migrate_%d_to_%d" % [version, version + 1]
        if has_method(migrator_name):
            data = call(migrator_name, data)
        else:
            push_warning("SaveManager: no migration from schema %d to %d" % [version, version + 1])
            break
        version += 1
    data["schema_version"] = SCHEMA_VERSION
    return data

## Example migration (placeholder for future use):
# static func _migrate_1_to_2(data: Dictionary) -> Dictionary:
#     ## Schema 1 -> 2: add "npc_manager" section
#     if not data["systems"].has("npc_manager"):
#         data["systems"]["npc_manager"] = {}
#     return data

## --- Serialization Coordination ---

func _collect_snapshots() -> Dictionary:
    ## Calls serialize() on each state-owning system.
    ## Returns Dictionary keyed by system name.
    return {
        "loop_state": LoopStateManager.serialize(),
        "clue_database": ClueDatabase.serialize(),
        "timer_service": TimerService.serialize(),
        "room_manager": _serialize_room_manager(),
    }

func _distribute_snapshots(systems: Dictionary) -> void:
    ## Calls deserialize() on each state-owning system.
    ## Order matters: LoopStateManager first (other systems may read night state).
    if systems.has("loop_state"):
        LoopStateManager.deserialize(systems["loop_state"])
    if systems.has("clue_database"):
        ClueDatabase.deserialize(systems["clue_database"])
    if systems.has("timer_service"):
        TimerService.deserialize(systems["timer_service"])
    if systems.has("room_manager"):
        _restore_room_manager(systems["room_manager"])

func _serialize_room_manager() -> Dictionary:
    ## RoomManager doesn't have its own serialize() -- we extract
    ## the minimal data needed (current_room_id).
    return {
        "current_room_id": StringName(RoomManager.current_room_id),
    }

func _restore_room_manager(data: Dictionary) -> void:
    ## Restore room state. Room template state is rebuilt from
    ## PackedScene re-instantiation on room load.
    var room_id: StringName = data.get("current_room_id", &"lobby")
    # RoomManager.request_transition handles the full restore;
    # LoopStateManager.deserialize already restored night state,
    # so the correct template is available.
    RoomManager.request_transition(room_id)

func _build_save_envelope(slot_id: int, systems: Dictionary) -> Dictionary:
    ## Wraps system snapshots in metadata envelope.
    return {
        "schema_version": SCHEMA_VERSION,
        "timestamp": Time.get_datetime_string_from_system(),
        "unix_timestamp": Time.get_unix_time_from_system(),
        "slot_id": slot_id,
        "game_version": ProjectSettings.get_setting("application/config/version", "0.1.0"),
        "systems": systems,
    }
```

**Save File Structure (JSON)**:
```json
{
    "schema_version": 1,
    "timestamp": "2026-05-14T15:30:00",
    "unix_timestamp": 1747231200.0,
    "slot_id": 1,
    "game_version": "0.1.0",
    "systems": {
        "loop_state": {
            "schema_version": 1,
            "current_night": 3,
            "current_phase": "WHISPER",
            "consequences": [],
            "template_overrides": {},
            "delta_accumulator": {
                "deltas": []
            }
        },
        "clue_database": {
            "schema_version": 1,
            "entries": {},
            "connections": []
        },
        "timer_service": {
            "remaining_time": 245.3,
            "total_duration": 300.0,
            "pressure_level": 0.184,
            "current_phase": 0,
            "time_scale": 1.0,
            "is_active": true
        },
        "room_manager": {
            "current_room_id": "lobby"
        }
    }
}
```

**Save Slot UI Metadata (for save/load screen)**:
```gdscript
## get_save_metadata() returns only the envelope + summary for UI display.
## Does NOT deserialize full system state -- fast.
## {
##     "slot_id": 1,
##     "timestamp": "2026-05-14T15:30:00",
##     "game_version": "0.1.0",
##     "current_night": 3,
##     "current_room_id": "lobby",
##     "clue_count": 12,
##     "insight_count": 3,
##     "exists": true
## }
```

### Implementation Guidelines

1. **Deserialization order is critical**: LoopStateManager.deserialize() MUST run first because other systems read current_night and night phase during their own deserialization. ClueDatabase.deserialize() second (independent). TimerService.deserialize() third (reads night state). RoomManager.restore last (triggers scene load, which may query other systems).

2. **Auto-save debounce**: The `_auto_save()` method tracks the last auto-save timestamp and skips if less than 2 seconds have elapsed. This prevents rapid sequential auto-saves when multiple state changes happen in the same frame (e.g., clue discovery + consequence registration from the same interaction).

3. **Save blocking**: save_game() returns false and emits save_failed if LoopStateManager.is_transitioning is true. The Night Transition Controller should save BEFORE calling advance_night(), not after.

4. **File corruption handling**: If the primary save file fails to parse, SaveManager falls back to the .bak file. If both fail, the slot is treated as empty. The player is notified via UI that the save was corrupt.

5. **New game flow**: new_game(slot_id) calls reset methods on each system (LoopStateManager.reset(), ClueDatabase.reset(), TimerService.stop_timer()), then saves the initial state to the slot. This ensures the slot file always exists and is valid.

6. **System extensibility**: When a new state-owning system is added (e.g., NPC Trust/Suspicion with its own serialize/deserialize), add it to _collect_snapshots() and _distribute_snapshots(). The save file's "systems" Dictionary is open-ended -- missing keys are treated as empty state during deserialization (via Dictionary.get() with defaults). Old saves without the new system section load without error.

7. **StringName serialization**: Dictionary keys that are StringName must be converted to String for JSON compatibility. The `StringName()` constructor is used when reading back. Each system's serialize()/deserialize() handles this internally.

8. **Stale .tmp cleanup**: On startup, `_ready()` checks for leftover `.tmp` files from interrupted saves and deletes them. This prevents orphaned temp files from accumulating over multiple crash-recovery cycles.

9. **Android atomic rename caveat**: On some Android configurations, `OS.rename()` within `user://` may internally perform copy+delete rather than a true atomic rename. The backup rotation (.bak file preserved before every write) mitigates this -- even if rename is interrupted, the backup is intact. This is acceptable for the "lose at most one action" guarantee.

10. **Godot 4.x FileAccess pattern**: FileAccess.open() returns null on failure. All file operations follow this pattern:
```gdscript
var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
if file == null:
    push_error("SaveManager: failed to open '%s' for writing: %s" % [path, FileAccess.get_open_error()])
    return false
var store_ok: bool = file.store_string(json_string)
# store_string returns bool since Godot 4.4
if not store_ok:
    push_error("SaveManager: failed to write to '%s'" % path)
    return false
file.close()
```

## Alternatives Considered

### Alternative 1: Godot Resource Save (.tres)

- **Description**: Save game state as a custom Godot Resource serialized to .tres binary format
- **Pros**: Engine-native serialization; type-safe; editor previewable; handles Resource sub-objects natively
- **Cons**: Binary format -- not human-readable, not debuggable in text editor; version migration requires code changes to the Resource class rather than JSON transformation; Resource serialization can break when class_name fields are renamed; merge conflicts in version control are unresolvable for binary files; all game systems would need to convert their Dictionary-based state to Resource objects
- **Rejection Reason**: JSON is human-readable, debuggable, and supports schema migration via simple Dictionary transformation. The game's state systems already use Dictionary-based serialize() methods (ADR-0004, ADR-0005, ADR-0008). Adding a Resource wrapper would create unnecessary conversion layers. The architecture registry (architecture.yaml) already records the API decision: "knowledge_data_storage: In-memory Dictionary + JSON serialization" (ADR-0005).

### Alternative 2: Per-System Save Files

- **Description**: Each system writes its own save file independently (loop_state.json, clue_db.json, timer.json, etc.)
- **Pros**: Systems stay fully independent; no central coordinator; one corrupt file does not lose all state
- **Cons**: No atomic save across systems -- crash between system saves produces partially updated state; no consistent snapshot; load order becomes critical and complex; file management multiplies (3 slots x 4 files = 12 files); backup/rotation becomes complex per-file
- **Rejection Reason**: Crash recovery requires a consistent snapshot across all systems. Per-system files cannot guarantee atomicity without a write-ahead log, which adds complexity exceeding a single coordinated file. The single-file approach with atomic rename gives crash recovery by design.

### Alternative 3: Binary Save with Write-Ahead Log (WAL)

- **Description**: Custom binary format with a write-ahead log that records state mutations before applying them, enabling point-in-time recovery
- **Pros**: Maximum crash recovery granularity (single-action recovery); compact file size; can implement undo/redo
- **Cons**: Significantly more complex implementation; not human-readable; WAL management (truncation, compaction) adds maintenance burden; overkill for a 7-night adventure game with <500 KB state; each system would need to write WAL entries instead of simple serialize() calls
- **Rejection Reason**: The atomic write + backup rotation approach achieves "lose at most one action" with auto-save frequency. If auto-save fires after every state-changing action, the worst case is that the action immediately before a crash is lost -- the same guarantee WAL provides, with far simpler implementation. WAL is appropriate for databases and editors, not a single-player narrative game.

## Consequences

### Positive

- SaveManager owns zero game state -- purely a coordination layer, respecting the state ownership model in architecture.yaml
- JSON format is human-readable -- developers can inspect and manually fix save files during development and QA
- Atomic write + backup rotation provides crash safety without WAL complexity
- Schema versioning with migration functions supports forward-compatible save files across game updates
- Each system's serialize()/deserialize() remains its own responsibility -- SaveManager does not need to understand internal state structure
- Auto-save after state-changing actions means the player never explicitly needs to save (but can)
- 3 independent slots allow multiple playthroughs or experimentation
- Extensible: new systems are added by appending to _collect_snapshots()/_distribute_snapshots()

### Negative

- One more Autoload singleton (adds to InteractionBus, LoopStateManager, ClueDatabase, TimerService, RoomManager, NPCManager)
- Auto-save after every state-changing action means frequent disk writes -- mitigated by debounce (min 2 seconds between writes)
- JSON serialization of StringName requires String conversion; Dictionary keys must be string-compatible
- Save file grows with game progress -- but bounded by 7 nights x ~50 state paths x ~200 bytes = <100 KB for loop state, <200 KB for clue database with 50+ entries. Well within 500 KB budget
- Save/load is synchronous -- a large save file could cause a frame hitch. Mitigated by keeping save files small (<500 KB) and profiling during implementation

### Neutral

- SaveManager has a fixed list of systems it coordinates -- adding a new system requires code changes to SaveManager (not data-driven). This is acceptable for a project with a known, bounded set of state-owning systems
- Auto-save is triggered by signals, not polling. If a new state-changing action is added without connecting its signal, it will not trigger auto-save. This is a documentation and code review concern, not a runtime concern

## Boundary Rules

1. **SaveManager MUST NOT own any game state.** It reads state from other systems via their serialize() methods and writes state to other systems via their deserialize() methods. If SaveManager starts caching game state, it becomes a secondary source of truth and introduces sync bugs.

2. **SaveManager MUST NOT interpret save data.** It does not validate that current_night is in range 1-7 or that clue entries have the right fields. Each system's deserialize() is responsible for validating its own data. SaveManager's job is transport, not validation.

3. **SaveManager MUST NOT bypass state ownership.** It does not write to LoopStateManager.current_night directly. It calls LoopStateManager.deserialize(), which is the system's own authorized write path.

4. **Auto-save triggers MUST NOT cause feedback loops.** If deserialize() causes a system to emit a signal that triggers auto-save, SaveManager guards against re-entrant saves via the _is_saving flag.

## Conventions

1. **File naming**: `save_{slot_id}.json` for primary, `save_{slot_id}.bak` for backup, `save_{slot_id}.tmp` for in-progress write. Slot IDs are 1-indexed (1, 2, 3).

2. **System section keys**: The key in the "systems" Dictionary matches the system name: "loop_state", "clue_database", "timer_service", "room_manager". Future systems add their own key (e.g., "npc_trust", "dialogue_state").

3. **Schema version scope**: Each system's serialize() output has its own schema_version field (as defined in ADR-0004, ADR-0005, ADR-0008). The save file envelope also has a top-level schema_version. System-level migrations are handled by each system's deserialize(). Envelope-level migrations handle structural changes (renaming sections, adding new top-level fields).

4. **Metadata-only reads**: get_save_metadata() reads only the envelope and first-level system fields needed for display. It does NOT parse the full system state. This keeps the save/load menu fast regardless of save file size.

5. **Timestamp format**: ISO 8601 format (YYYY-MM-DDTHH:MM:SS) for human-readable timestamp, plus Unix timestamp as float for sorting and comparison.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| game-concept.md | Session Length | 30-90 min sessions (2-4 loops); must support quit/resume | SaveManager supports mid-night save/load; player can quit at any point and resume exactly where they left off |
| loop-state-management.md | AC-P1 through AC-P4 | Save/load integrity acceptance criteria | SaveManager coordinates LoopStateManager.serialize()/deserialize(); AC-P1 (mid-night save), AC-P2 (orphan deltas), AC-P3 (missing accumulator), AC-P4 (crash during advance_night) all supported |
| loop-state-management.md | Open Q1 | Multiple save slots: independent DeltaAccumulators or shared? | Independent. Each slot is a complete self-contained save file with its own loop state, clue database, timer state, etc. |
| systems-index.md | System #4 | 存档/读档持久化 (Save/Load Persistence) | SaveManager Autoload with JSON + atomic write + 3 slots |
| systems-index.md | System #8 | 夜晚过渡控制器 depends on #4 | Night Transition Controller can save before advance_night() via SaveManager.save_game() |
| game-concept.md | TR-concept-014 | Save/load persistence with crash recovery across sessions | Atomic write (write-to-tmp-then-rename) + backup rotation + auto-save after every state-changing action |

## Performance Implications

| Metric | Expected Value | Budget | Notes |
|--------|---------------|--------|-------|
| CPU (save) | < 5 ms | < 16 ms | JSON.stringify() on ~100 KB Dictionary. Runs on main thread. |
| CPU (load) | < 50 ms | < 500 ms | JSON.parse() + deserialize() across all systems + room scene load. Room PackedScene.instantiate() dominates (~10-50ms). |
| Memory (runtime) | ~0 KB additional | < 1 MB | SaveManager holds no persistent state. Temporary JSON string during save/load is GC'd. |
| Disk (per save) | 50-200 KB | < 500 KB | 2 copies per slot (.json + .bak) = 100-400 KB per slot. 3 slots = 300 KB - 1.2 MB total. |
| Disk I/O (save) | ~1-5 ms | < 16 ms | Single JSON write to user:// directory (SSD/NVMe on target platforms). |

- **Auto-save frequency**: At most once per 2 seconds (debounced). Typical gameplay produces ~1 state-changing action every 10-30 seconds. Auto-save is not a performance concern.
- **Network**: N/A (single-player, no cloud save in MVP)

## Migration Plan

New system. Implementation order:

1. SaveManager autoload skeleton with file I/O methods
2. Atomic write + backup rotation + read with fallback
3. _collect_snapshots() / _distribute_snapshots() wiring
4. Auto-save signal connections and debounce
5. Schema migration framework
6. new_game() / delete_save() / get_save_metadata()
7. Integration with Night Transition Controller (save before advance_night)
8. Save/load UI (future: System #21 area)

**Rollback plan**: If atomic write causes issues on a specific platform, the .tmp -> rename approach can be replaced with direct write (simpler but less crash-safe). If auto-save frequency causes performance issues on mobile, the debounce interval can be increased from 2s to 5s.

## Validation Criteria

1. save_game() writes a valid JSON file to user://save_{slot_id}.json
2. load_game() restores all systems to the exact state captured by save_game()
3. Atomic write: if process is killed during _atomic_write(), either the .tmp file exists (incomplete write) or the previous save is intact in .bak
4. Backup rotation: after successful save, the previous save exists as .bak
5. Corrupt primary falls back to .bak automatically during load
6. 3 save slots are fully independent -- saving to slot 2 does not affect slots 1 or 3
7. Auto-save triggers after clue_discovered, insight_generated, connection_made, consequence_registered, npc_state_changed, and room_changed signals
8. Auto-save debounce prevents more than one save per 2 seconds
9. Schema migration: a save file with schema_version=1 can be loaded after SCHEMA_VERSION is incremented to 2 (given a migration function)
10. Deserialization order: LoopStateManager.deserialize() runs before other systems
11. Save blocked during LoopStateManager.is_transitioning
12. get_save_metadata() returns correct night, timestamp, and slot info without full deserialization
13. new_game() resets all systems and creates a valid initial save file
14. Save file size stays under 500 KB with full playthrough data (7 nights, 50+ clues, 20+ consequences)
15. Save/load round-trip with TimerService active preserves remaining_time within 1.0 second accuracy
16. _is_saving / _is_loading flags prevent re-entrant save or load operations
17. NPCManager state is correctly restored via LoopStateManager's delta pipeline after load (NPCManager does not have its own serialize)

## Related

- ADR-0004: Loop State Management -- provides serialize()/deserialize(); owns current_night, consequences, delta_accumulator
- ADR-0005: Clue/Insight Unified Schema -- provides ClueDatabase.serialize()/deserialize(); owns entries, connections
- ADR-0007: Room/Location Management -- provides current_room_id; room state rebuilt from PackedScene on load
- ADR-0008: Countdown Timer -- provides TimerService.serialize()/deserialize(); owns pressure_level, remaining_time
- ADR-0009: NPC State Machine -- NPC state persisted through LoopStateManager pipeline; NPCManager re-initializes from templates + deltas on load
- ADR-0002: Knowledge Color Accumulation -- knowledge_level is derived from ClueDatabase state, not independently persisted
- ADR-0006: Interaction Event Bus -- boundary pattern reference (detect/dispatch only, no game logic)
- architecture.yaml: State ownership registry -- SaveManager does not register any state (owns none)
- design/gdd/loop-state-management.md: AC-P1 through AC-P4 (save/load integrity acceptance criteria)
