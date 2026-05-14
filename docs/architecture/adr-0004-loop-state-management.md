# ADR-0004: Loop State Management

## Status
Accepted

## Date
2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — uses standard GDScript and Godot serialization |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, design/gdd/game-concept.md, design/gdd/systems-index.md |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Test atomic advance_night() with 5+ registered consequences. Test save/load round-trip preserves consequence order. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None — foundational core system |
| **Enables** | ADR-0005 (clue-insight-unified-schema) — ClueDatabase reads loop state for contextual unlocks. System #4 (时间循环), System #5 (住客记忆), System #8 (选择后果), System #15 (存档/读档) |
| **Blocks** | All Core-layer systems that depend on loop state (#4, #5, #8, #15), all Gameplay-layer systems |
| **Ordering Note** | Must be Accepted before ADR-0005 and all GDD design for loop-dependent systems. |

## Context

### Problem Statement

七夜的核心机制是7夜时间循环。每夜重置场景状态，但玩家知识和选择后果跨循环持久。需要决定：(1) 哪些状态重置、哪些持久？(2) 夜间推进如何原子化？(3) 选择后果如何注册和回放？(4) 序列化方案？

### Constraints

- 7夜循环，每夜有固定时长（低语/咆哮）
- 场景状态（NPC位置、物品、门锁）每夜重置
- 玩家知识（线索、洞察）永不重置
- 选择后果跨夜累积并改变模板
- 存档/读档必须支持循环中间保存
- 后果回放必须按注册顺序执行

### Requirements

- 三层状态分离：模板状态（重置）、持久变异（跨夜累积）、玩家知识（永不重置）
- 原子性 advance_night() 操作
- 后果注册和回放机制
- 完整序列化支持
- 后果顺序保证

## Decision

三层状态架构 + 后果注册/回放机制。

### Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│                 LoopStateManager (Autoload)           │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │Template State │  │Persistent    │  │Player      │ │
│  │(resets/night) │  │Mutations     │  │Knowledge   │ │
│  │              │  │(accumulates)  │  │(permanent)  │ │
│  │• NPC positions│  │• Consequences│  │• Clues     │ │
│  │• Item locations│ │• NPC memory  │  │• Insights  │ │
│  │• Door states │  │• Story flags │  │• Colors    │ │
│  │• Scene layout│  │• Trust deltas│  │• Connections│ │
│  └──────┬───────┘  └──────┬───────┘  └──────┬─────┘ │
│         │                 │                  │       │
│         │  advance_night() │                  │       │
│         │  ┌──────────────▼──────────────────┐       │
│         │  │ 1. VALIDATE  — assert night < 7,│       │
│         │  │    no pending writes, state ok   │       │
│         │  │ 2. SNAPSHOT — deep-copy active   │       │
│         │  │    state as rollback point       │       │
│         │  │ 3. COLLECT  — diff active vs     │       │
│         │  │    template, extract new deltas   │       │
│         │  │ 4. LOAD     — load night N+1     │       │
│         │  │    template (on fail: rollback)   │       │
│         │  │ 5. REBUILD  — template + all      │       │
│         │  │    deltas → new active state      │       │
│         │  │    (on fail: rollback to snapshot)│       │
│         │  │ 6. INCREMENT — night_counter += 1 │       │
│         │  │    (on fail: rollback to snapshot)│       │
│         │  │ 7. NOTIFY   — emit night_advanced │       │
│         │  └─────────────────────────────────┘       │
│         │                 │                  │       │
└─────────┼─────────────────┼──────────────────┼───────┘
          │                 │                  │
   ┌──────▼─────┐  ┌───────▼──────┐  ┌───────▼──────┐
   │RoomManager │  │NPCManager    │  │ClueDatabase  │
   │(scene load)│  │(memory trust)│  │(from ADR-0005│
   │            │  │              │  │ insights)    │
   └────────────┘  └──────────────┘  └──────────────┘
```

### State Layers

| Layer | Scope | Reset Behavior | Examples |
|-------|-------|---------------|----------|
| **Template State** | Per-night | Full reset each advance_night() | NPC positions, item locations, door locks, scene layout |
| **Persistent Mutations** | Cross-night | Accumulate; never reset | Consequences, NPC memory deltas, story flags, trust changes |
| **Player Knowledge** | Permanent | Never resets | Clues, insights, connections, colors (ADR-0002) |

### Dialogue vs. Transition Priority

If dialogue is active when `advance_night()` is called, the dialogue must complete first. ADR-0003 (dialogue state) and ADR-0004 (loop transition) both claim control during a night transition — dialogue has priority. `advance_night()` waits for the dialogue system to signal completion before executing the 7-step sequence. The night transition controller must not call `advance_night()` until ADR-0003's dialogue-in-progress flag is clear.

### Key Interfaces

**LoopStateManager (Autoload Singleton)**:
```gdscript
class_name LoopStateManager
extends Node

signal night_advanced(old_night: int, new_night: int)
signal night_advanced_failed(reason: String)
signal night_ready(night: int)
signal advance_failed(step: int, error: String)
signal consequence_registered(consequence_id: StringName)
signal consequence_replayed(consequence_id: StringName)

enum NightPhase { WHISPER, ROAR, TRANSITION }

const MAX_NIGHTS: int = 7

## Current night number (1–7). External code should read via
## get_current_night() and must NOT write to this variable directly.
var current_night: int = 1
var current_phase: NightPhase = NightPhase.WHISPER
var is_transitioning: bool = false

var _consequences: Array[Dictionary] = []
var _template_overrides: Dictionary = {}

func advance_night() -> void:
    # Step 2 (SNAPSHOT): uses duplicate_deep() for true recursive copy
    # var snapshot: Dictionary = _active_state.duplicate_deep()
    # NOT: _active_state.duplicate(true) — this only deep-copies sub-Resources,
    # not nested Dictionary/Array within those Resources.

func register_consequence(consequence_id: StringName, mutation: Dictionary) -> void:
func get_template_override(entity_id: StringName, property: String) -> Variant
func get_night_phase_duration() -> float
func get_current_night() -> int
func serialize() -> Dictionary
func deserialize(data: Dictionary) -> bool
```

**Consequence Registration**:
```gdscript
# Called by game systems when player makes a consequential choice
LoopStateManager.register_consequence("opened_secret_door", {
    "target": "room_3_secret_door",
    "property": "is_locked",
    "value": false,
    "affects_nights": [2, 3, 4, 5, 6, 7]  # which nights this applies to
})
```

**Serialization Schema**:
```json
{
    "schema_version": 1,
    "current_night": 3,
    "current_phase": "WHISPER",
    "consequences": [
        {
            "id": "opened_secret_door",
            "mutation": { "target": "...", "property": "...", "value": false, "affects_nights": [2,3,4,5,6,7] }
        }
    ],
    "template_overrides": {},
    "delta_accumulator": {
        "deltas": [
            {
                "source_night": 1,
                "source_action": "unlocked_door",
                "target_path": "rooms.basement.door_locked",
                "override_value": false,
                "priority": 0,
                "sequence_index": 1
            }
        ]
    }
}
```

> **Note:** Player Knowledge (ClueDatabase) is serialized separately per ADR-0005. The `delta_accumulator` field above shows the DeltaAccumulator state that must be persisted; see the GDD (`design/gdd/loop-state-management.md`) for the full StateDelta schema including all fields and conflict-resolution semantics.

## Alternatives Considered

### Alternative 1: Full State Snapshot

- **Description**: Save complete game state each night; reload snapshot on advance
- **Pros**: Simple mental model; perfect rollback
- **Cons**: Memory-heavy (7 full snapshots); hard to merge with persistent knowledge; snapshot size grows linearly
- **Rejection Reason**: Template + mutations is more memory-efficient. Knowledge layer is separate by design.

### Alternative 2: Event Sourcing

- **Description**: Record all player actions as events; replay to reconstruct state
- **Pros**: Complete audit trail; time-travel debugging
- **Cons**: Replay becomes expensive over 7 nights; event schema must cover every possible mutation; ordering sensitivity
- **Rejection Reason**: Consequence replay is a focused subset of event sourcing — only player choices are replayed, not every interaction. Sufficient for this game's needs.

### Alternative 3: Night-as-Scene

- **Description**: Each night is a separate Godot scene; load/unload on transition
- **Pros**: Clean separation; Godot-native
- **Cons**: Shared state (NPCs, items) must be synced across scenes; consequence system becomes inter-scene coordination; complex
- **Rejection Reason**: Single scene with state layers is simpler. Scene-per-night would duplicate shared assets and complicate NPC memory tracking.

## Consequences

### Positive

- Three layers match the game's core mechanic: reset what should reset, persist what should persist
- Atomic advance_night() prevents partial state corruption
- Consequence replay ensures deterministic behavior after save/load
- Clean separation between loop state and knowledge state (ADR-0005)

### Negative

- advance_night() is a blocking operation during transition
- Consequence replay cost grows linearly with accumulated consequences
- Template override system adds indirection for NPC/item queries
- Systems must register consequences explicitly — missing registration = lost consequence

### Risks

- **Replay ordering**: Consequences replayed in registration order. If order matters, registration must be sequential. Mitigation: document ordering guarantee; add consequence priority if needed.
- **Template override conflicts**: Two consequences modifying same property. Mitigation: last-write-wins with warning log; validate on registration.
- **Transition performance**: advance_night() with many consequences could cause frame hitch. Mitigation: profile after 20+ consequences; add async replay if needed.
- **Deep-copy integrity**: GDScript's `Dictionary.duplicate()` performs a shallow copy — nested dictionaries (e.g. room state containing sub-dictionaries of properties) share references with the original. A SNAPSHOT step that appears to save a rollback point may not actually isolate state if `duplicate()` is used naively on nested structures. Furthermore, `Resource.duplicate(true)` deep-copies sub-Resources but NOT nested Dictionary/Array properties within those Resources. Mitigation: use `duplicate_deep()` (available since Godot 4.5) which performs true recursive deep-copy of all nested structures. The GDD uses Resource-based modeling (NightTemplate, ActiveState, DeltaAccumulator) partly for structured state — `duplicate_deep()` should be used for the SNAPSHOT step specifically.
- **Rollback complexity**: The SNAPSHOT step in advance_night() introduces rollback semantics — if any step from LOAD through INCREMENT fails, the system must restore the pre-snapshot state. This requires the snapshot to be a true deep copy (see deep-copy risk above) and adds a failure path that must be tested. Mitigation: unit test each failure step individually; the VALIDATE step catches most precondition failures before snapshot is taken.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-concept.md | Pillar 2: 时间在低语与咆哮之间交替 | NightPhase enum (WHISPER/ROAR), phase duration query |
| game-concept.md | 时间循环：7夜重置场景 | Template State layer resets on advance_night() |
| game-concept.md | 选择后果跨循环 | Persistent Mutations layer + consequence registration |
| game-concept.md | 知识跨循环持久 | Player Knowledge layer never resets (separate from this system, owned by ADR-0005) |
| systems-index.md | System #4 (时间循环) | LoopStateManager owns night/phase state, advance operation |
| systems-index.md | System #8 (选择后果) | Consequence registration + replay mechanism |
| systems-index.md | System #15 (存档/读档) | serialize()/deserialize() with versioned schema |
| systems-index.md | TD Concern #6 | Resolves: atomic advance_night() with 7-step sequence including snapshot/rollback |

## Performance Implications

- **CPU**: advance_night() — template reset O(m) where m = template properties (still negligible for this scope), consequence replay O(n log n) due to sort_key ordering where n = registered consequences. Expected n ≤ 30 for full playthrough. Negligible.
- **Memory**: Consequences array ~200 bytes per consequence. Template overrides dictionary grows with consequence count. Snapshot adds one additional copy of active state during advance_night(), freed after completion.
- **Load Time**: deserialize() replays consequences on load — same O(n log n) as advance_night().
- **Network**: N/A

## Migration Plan

New system. Implementation order: LoopStateManager → Template State consumers (RoomManager) → Consequence consumers (NPC memory).

## Validation Criteria

1. advance_night() increments current_night from 1 to 7
2. advance_night() at night 7 triggers game end, not night 8
3. Template state resets on advance_night()
4. Registered consequences survive advance_night()
5. Consequences replay in registration order
6. serialize()/deserialize() round-trip preserves all state
7. is_transitioning blocks player input during advance_night()
8. NightPhase transitions correctly (WHISPER → ROAR → TRANSITION)
9. night_ready signal emitted after initialization and after each advance_night() completes
10. advance_failed signal emitted with step number and error on any step failure

## Related Decisions

- ADR-0002: Knowledge Color Accumulation — Player Knowledge layer feeds color system
- ADR-0005: Clue/Insight Unified Schema — ClueDatabase is the primary Player Knowledge store (serialized separately)
- ADR-0003: UI Visual Register — Night counter pillar reads current_night; dialogue has priority over night transition
- Art Bible Section 7: Night counter visual design
