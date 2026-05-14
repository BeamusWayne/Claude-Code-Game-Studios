# ADR-0005: Clue/Insight Unified Schema

## Status
Accepted

## Date
2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Data |
| **Knowledge Risk** | LOW — uses standard GDScript Dictionary and Array |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, design/gdd/game-concept.md, design/gdd/systems-index.md |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Test clue-insight connection creation. Test contextual_unlocks cascade. Test serialization round-trip with 50+ entries. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (knowledge-color-accumulation) — KnowledgeManager reads from ClueDatabase. ADR-0004 (loop-state-management) — Player Knowledge layer is stored in ClueDatabase. |
| **Enables** | System #9 (线索发现), System #10 (线索连接/洞察), System #11 (笔记本/推理板), System #16 (色彩积累 — via KnowledgeManager) |
| **Blocks** | All Gameplay-layer knowledge systems (#9, #10, #11), Presentation-layer notebook (#21) |
| **Ordering Note** | Must be Accepted before GDD design of Systems #9, #10, #11. ADR-0004 should be Accepted first (dependency). |

## Context

### Problem Statement

七夜的笔记本系统需要统一管理线索（clues）和洞察（insights）。线索是玩家发现的原始事实；洞察是连接两条线索产生的新理解。需要决定：(1) 线索和洞察是同一数据结构还是分开？(2) 连接如何表示？(3) 洞察如何"重新解释"旧线索？(4) 数据库接口？

### Constraints

- 线索和洞察都需要：ID、标题、描述、来源、发现时间
- 洞察额外需要：产生它的两条线索的引用
- 连接是双向的（A-B 等同于 B-A）
- 洞察可以解锁旧线索的新解读（contextual_unlocks）
- 数据必须跨循环持久（ADR-0004 Player Knowledge 层）
- 序列化必须支持版本迁移

### Requirements

- 统一的数据结构覆盖线索和洞察
- 连接（Connection）作为独立数据结构
- contextual_unlocks 机制——洞察为旧线索添加新信息
- ClueDatabase 提供 CRUD、搜索、连接操作
- 完整序列化支持
- 与 ADR-0002 KnowledgeManager 集成

## Decision

统一 KnowledgeEntry 模式 + 独立 Connection 结构 + contextual_unlocks 机制。

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    ClueDatabase (Autoload)               │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  entries: Dictionary[StringName, KnowledgeEntry]  │  │
│  │                                                    │  │
│  │  KnowledgeEntry:                                  │  │
│  │  ├─ id: StringName                                │  │
│  │  ├─ entry_type: EntryType (CLUE | INSIGHT)        │  │
│  │  ├─ title: String                                 │  │
│  │  ├─ description: String                           │  │
│  │  ├─ source: StringName (room/NPC/event id)        │  │
│  │  ├─ discovered_at_night: int                       │  │
│  │  ├─ npc_affinity: StringName (guest color key)    │  │
│  │  ├─ tags: Array[StringName]                        │  │
│  │  ├─ contextual_unlocks: Array[StringName]  ←──┐   │  │
│  │  └─ metadata: Dictionary                      │   │  │
│  │                                                │   │  │
│  │  Insight-specific fields (when CLUE):          │   │  │
│  │  (none — insight fields below)                 │   │  │
│  │                                                │   │  │
│  │  Insight-specific fields (when INSIGHT):       │   │  │
│  │  ├─ source_clues: Array[StringName] (exactly 2)│   │  │
│  │  └─ reinterpretation: String (new reading)     │   │  │
│  └────────────────────────────────────────────────┘   │  │
│                                                        │  │
│  ┌──────────────────────────────────────────────────┐  │
│  │  connections: Array[Connection]                   │  │
│  │                                                    │  │
│  │  Connection:                                      │  │
│  │  ├─ clue_a: StringName                            │  │
│  │  ├─ clue_b: StringName                            │  │
│  │  ├─ made_at_night: int                            │  │
│  │  ├─ is_valid: bool                                │  │
│  │  └─ insight_id: StringName (if is_valid)          │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  contextual_unlocks cascade:                      │  │
│  │                                                    │  │
│  │  Triggered automatically inside add_entry()       │  │
│  │  when entry_type == INSIGHT:                      │  │
│  │  1. Validate both source_clues exist              │  │
│  │     (if not, add_entry returns false — atomic)    │  │
│  │  2. Add insight.id to BOTH clues'                 │  │
│  │     contextual_unlocks arrays                     │  │
│  │  3. Clue now shows reinterpretation text           │  │
│  │     in notebook when insight exists                │  │
│  │                                                    │  │
│  │  On remove_entry() for an insight:                │  │
│  │  → remove insight ID from both source clues'      │  │
│  │    contextual_unlocks arrays (cascade cleanup)    │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────────┬────────────────────────────────┘
                         │ reads from
                ┌────────▼────────┐
                │ KnowledgeManager│
                │ (ADR-0002)      │
                │ derives color   │
                │ from entries    │
                └─────────────────┘
```

### Key Interfaces

**ClueDatabase (Autoload Singleton)**:
```gdscript
class_name ClueDatabase
extends Node

signal clue_discovered(clue_id: StringName)
signal insight_generated(insight_id: StringName)
signal connection_made(clue_a: StringName, clue_b: StringName, is_valid: bool)

enum EntryType { CLUE, INSIGHT }

var entries: Dictionary = {}
var connections: Array[Dictionary] = []

# CRUD
func add_entry(entry: Dictionary) -> bool
func get_entry(id: StringName) -> Dictionary
func update_entry(id: StringName, updates: Dictionary) -> bool
func remove_entry(id: StringName) -> bool

# Search
func search_by_tag(tag: StringName) -> Array[StringName]
func search_by_source(source: StringName) -> Array[StringName]
func search_by_npc(npc_affinity: StringName) -> Array[StringName]
func get_all_clues() -> Array[StringName]
func get_all_insights() -> Array[StringName]
func get_undiscovered_clues() -> Array[StringName]

# Connections
# Returns Dictionary with keys:
#   ok: bool — true if connection was created
#   connection: Dictionary — the created Connection record (empty on failure)
#   reason: String — empty on success; "duplicate"/"clue_not_found"/"invalid_types" on failure
func connect_clues(clue_a: StringName, clue_b: StringName) -> Dictionary
func get_connections_for(clue_id: StringName) -> Array[Dictionary]
func get_valid_connections() -> Array[Dictionary]
func get_invalid_connections() -> Array[Dictionary]

# Contextual unlocks
func get_contextual_unlocks(clue_id: StringName) -> Array[StringName]
func has_insight_for(clue_id: StringName) -> bool

# Serialization
func serialize() -> Dictionary
func deserialize(data: Dictionary) -> bool
```

**KnowledgeEntry Schema**:
```gdscript
# Both CLUE and INSIGHT share these fields
{
    "id": StringName,                    # unique identifier
    "entry_type": int,                   # EntryType.CLUE or EntryType.INSIGHT
    "title": String,                     # display title
    "description": String,              # original description
    "source": StringName,               # room_id, npc_id, or event_id
    "discovered_at_night": int,          # night number when discovered
    "npc_affinity": StringName,          # which guest this relates to (for color)
    "tags": Array[StringName],           # searchable tags
    "contextual_unlocks": Array[StringName],  # insight IDs that reinterpret this
    "metadata": Dictionary               # extensible data
}

# INSIGHT entries additionally have:
{
    "source_clues": Array[StringName],   # exactly 2 clue IDs
    "reinterpretation": String           # new reading of the connected clues
}
```

**Connection Schema**:
```gdscript
{
    "clue_a": StringName,       # first clue (alphabetically smaller for consistency)
    "clue_b": StringName,       # second clue
    "made_at_night": int,       # when player made this connection
    "is_valid": bool,           # whether this connection produces an insight
    "insight_id": StringName    # the insight ID if is_valid, else &""
}
```

> **Connection entry_type validation**: `connect_clues()` only accepts CLUE
> entries as arguments, not INSIGHT entries. If either `clue_a` or `clue_b`
> resolves to an insight ID, the function returns
> `{"ok": false, "reason": "invalid_types"}`. Player connections are
> clue-to-clue only.

**Serialization Schema**:
```json
{
    "schema_version": 1,
    "entries": {
        "clue_broken_lantern": {
            "id": "clue_broken_lantern",
            "entry_type": 0,
            "title": "破碎的灯笼",
            "description": "走廊尽头的灯笼被摔碎，灯油洒了一地。",
            "source": "room_hallway",
            "discovered_at_night": 2,
            "npc_affinity": "red",
            "tags": ["object", "hallway", "broken"],
            "contextual_unlocks": [],
            "metadata": {}
        },
        "insight_red_guest_lie": {
            "id": "insight_red_guest_lie",
            "entry_type": 1,
            "title": "红色住客的谎言",
            "description": "红色住客声称从未去过走廊，但灯笼上的指纹证明她在那里。",
            "source": "connection",
            "discovered_at_night": 3,
            "npc_affinity": "red",
            "tags": ["deduction", "red", "contradiction"],
            "contextual_unlocks": [],
            "metadata": {},
            "source_clues": ["clue_broken_lantern", "clue_red_alibi"],
            "reinterpretation": "灯笼不仅是被打破的——它是被故意摔碎来制造黑暗掩护的。"
        }
    },
    "connections": [
        {
            "clue_a": "clue_broken_lantern",
            "clue_b": "clue_red_alibi",
            "made_at_night": 3,
            "is_valid": true,
            "insight_id": "insight_red_guest_lie"
        }
    ]
}
```

> The `entries` dictionary is keyed by entry id (StringName). The
> `connections` array stores all player-made connections. `schema_version`
> enables forward-compatible migration in `deserialize()`.

**Insight Validation Pipeline**:

When `connect_clues()` is called, ClueDatabase creates a Connection record
with `is_valid = false` initially. ClueDatabase then delegates validation to
a separate `InsightGenerator` system — not an autoload, but a utility class
(`class_name InsightGenerator extends RefCounted`) that encapsulates
validation logic. InsightGenerator checks a pre-authored lookup table (game
data loaded from a JSON or Resource) to determine whether `clue_a + clue_b`
is a valid combination. If valid, InsightGenerator creates the INSIGHT
KnowledgeEntry and updates the Connection's `is_valid = true` and
`insight_id`. This keeps ClueDatabase as data storage and InsightGenerator as
validation logic — single responsibility.

> **reinterpretation scope**: The `reinterpretation` field is a single text
> string per insight that applies to the insight as a whole, not per-source-
> clue. If per-clue reinterpretation is needed in the future, it can be added
> as an optional extension (e.g., a `reinterpretations: Dictionary` keyed by
> source clue ID) without breaking the current schema.

## Alternatives Considered

### Alternative 1: Separate Clue and Insight Tables

- **Description**: Two independent data structures for clues and insights
- **Pros**: Clear type separation; simpler individual schemas
- **Cons**: Duplicate CRUD code; unified search requires merging two collections; notebook must query both
- **Rejection Reason**: Unified schema with EntryType enum is simpler to maintain. Clues and insights share 90% of fields.

### Alternative 2: Graph Database Pattern

- **Description**: Nodes and edges as the primary data model
- **Pros**: Natural fit for connection-heavy data; graph traversal for finding chains
- **Cons**: Over-engineered for 7-night scope; GDScript lacks native graph support; serialization complexity
- **Rejection Reason**: Dictionary-based entries with a flat connections array is sufficient for ≤50 clues and ≤20 insights. Graph traversal is not a gameplay requirement.

### Alternative 3: Resource-Based (Godot Resource)

- **Description**: Each clue/insight is a Godot Resource (.tres file)
- **Pros**: Editor integration; visual editing; type safety
- **Cons**: File I/O per entry; merge conflicts in version control; dynamic entries (player-discovered) awkward as files
- **Rejection Reason**: Mix of pre-authored clues (could be Resources) and player-discovered insights (must be runtime data). Unified in-memory Dictionary is simpler.

## Consequences

### Positive

- Unified schema simplifies notebook UI — one query returns all knowledge entries
- contextual_unlocks enables the "re-read old clues with new understanding" mechanic
- Connection schema supports both valid and invalid player attempts (invalid connections stored for notebook history)
- Serialization is straightforward — Dictionary/Array map to JSON cleanly
- NPC affinity field enables ADR-0002 per-NPC color calculation

### Negative

- EntryType branching means some fields are unused per type (source_clues is empty for CLUE entries)
- contextual_unlocks cascade must be maintained when insights are created
- Flat connections array requires scanning for specific clue connections
- No built-in graph traversal — chain discovery must be implemented in consumer code

### Risks

- **Entry count**: 50 clues + 20 insights + 30 connections is manageable. If scope grows, connection queries may need indexing. Mitigation: add Dictionary index by clue_id if needed.
- **contextual_unlocks consistency**: If insight is removed, contextual_unlocks arrays must be cleaned. Mitigation: remove_entry() handles cascading cleanup.
- **Connection deduplication**: Player connecting same pair twice should not create duplicate. Mitigation: connect_clues() checks for existing connection before creating.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-concept.md | Pillar 3: 连接比线索更有力 | Connection schema + insight generation from valid connections. Gold ochre color reward (ADR-0002). |
| game-concept.md | 笔记本跨循环持久 | ClueDatabase is Player Knowledge layer (ADR-0004), never resets |
| game-concept.md | 每个住客有要守护的秘密 | npc_affinity field links entries to guests for color (ADR-0002) |
| art-bible.md Sec 4 | 六种知识色 | npc_affinity maps to color system; connection gold ochre for valid insights |
| systems-index.md | System #9 (线索发现) | add_entry() with EntryType.CLUE |
| systems-index.md | System #10 (线索连接/洞察) | connect_clues() + insight generation |
| systems-index.md | System #11 (笔记本/推理板) | Search, connection, and contextual_unlocks APIs |
| systems-index.md | TD Concern #1 | Resolves: unified schema for clues and insights |

## Performance Implications

- **CPU**: Dictionary lookup by ID is O(1). Connection scan is O(n) where n = connections. Expected n ≤ 30. Search by tag is O(entries) — acceptable for ≤70 entries.
- **Memory**: ~500 bytes per entry, ~100 bytes per connection. Total ≤ 50KB for full playthrough.
- **Load Time**: deserialize() rebuilds Dictionary from JSON — O(entries + connections). Fast.
- **Network**: N/A

## Migration Plan

New system. Implementation order: ClueDatabase schema → CRUD operations → Connection operations → contextual_unlocks → Serialization → KnowledgeManager integration (ADR-0002).

## Validation Criteria

1. add_entry() stores CLUE and INSIGHT entries correctly
2. connect_clues() creates valid connection for correct pair, invalid for incorrect
3. Duplicate connection rejected (no double-entry)
4. contextual_unlocks updated when insight is created
5. search_by_tag, search_by_source, search_by_npc return correct results
6. serialize()/deserialize() round-trip preserves all entries and connections
7. KnowledgeManager (ADR-0002) can read entry counts for color calculation
8. Invalid connections stored but marked is_valid = false

## Related Decisions

- ADR-0002: Knowledge Color Accumulation — reads ClueDatabase for per-NPC discovery counts and connection counts
- ADR-0004: Loop State Management — Player Knowledge layer is stored in ClueDatabase
- ADR-0003: UI Visual Register — Notebook UI (Register A) reads from ClueDatabase
- Art Bible Section 4: Color System — npc_affinity maps to six knowledge colors
