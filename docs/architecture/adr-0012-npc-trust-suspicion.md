# ADR-0012: NPC Trust/Suspicion

## Status

Accepted

## Date

2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Gameplay / AI |
| **Knowledge Risk** | LOW — uses standard GDScript signals, Resource, and float arithmetic. No post-cutoff APIs required. |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, docs/engine-reference/godot/breaking-changes.md, docs/engine-reference/godot/deprecated-apis.md |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Test trust/suspicion delta application for all input types. Test threshold crossing signals. Test cross-loop persistence via propose_delta(). Test reset behavior on loop restart. Test graceful behavior when NPCManager is not yet loaded. Test serialization round-trip. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (loop-state-management — propose_delta(), register_state_paths(), DeltaAccumulator), ADR-0006 (interaction-event-bus — interaction_detected signal for trust event triggers), ADR-0009 (npc-state-machine — NPCManager.get_emotional_state() as input, npc_state_changed signal as trigger) |
| **Enables** | System #14 (Conditional Dialogue Trees — reads trust_level/suspicion_level for branching), System #15 (Guest Interrogation — trust/suspicion drive interrogation availability and NPC reactions), System #9 (Event Scheduler — schedules events based on trust thresholds) |
| **Blocks** | System #14, System #15 |
| **Ordering Note** | Must be Accepted before Conditional Dialogue Trees ADR (ADR-0013). All dependency ADRs (0004, 0006, 0009) are already Accepted. |

## Context

### Problem Statement

七夜的 5 位 NPC 住客（Pillar 4: 每个住客都有要守护的秘密）不是信息自动售货机。玩家如何对待他们——展示知识、反复追问、说谎被发现——应该累积影响 NPC 的信任和警惕。信任和警觉不是简单的一维关系：NPC 可以高度信任玩家同时也高度警觉（例如，信任你是善意的人但怀疑你知道的比说的多）。这两个值驱动对话分支、审问可用性和事件调度。

### Current State

NPCManager（ADR-0009）定义了 6 种情绪状态（NEUTRAL, FRIENDLY, SUSPICIOUS, HOSTILE, SECRETIVE, REVEALING），但情绪状态和信任/警觉是独立的概念。情绪是 NPC 当前的心情，信任/警觉是跨循环积累的长期关系值。ADR-0009 明确将信任/警觉排除在其范围之外，留给本 ADR。

InteractionBus（ADR-0006）提供交互事件。LoopStateManager（ADR-0004）提供 propose_delta() 用于持久化。KnowledgeManager（ADR-0002）提供每 NPC 颜色饱和度值。

### Constraints

- 5 NPC guests, each with unique trust/suspicion evolution curves
- Trust and suspicion are INDEPENDENT axes — not inverses. An NPC can be high-trust AND high-suspicion simultaneously
- Trust/suspicion values persist across nights within a loop via LoopStateManager.propose_delta()
- Whether values reset on loop restart is configurable per NPC (some NPCs remember cross-loop behavior)
- TrustManager reads NPC emotional state as input but NEVER writes to it (state ownership: npc-manager owns npc_emotional_state)
- All trust/suspicion mutations MUST go through LoopStateManager.propose_delta() — direct mutation forbidden
- TrustManager must register its state paths at startup via LoopStateManager.register_state_paths()
- Must emit signals for downstream consumers (dialogue, events, UI)

### Requirements

- Per-NPC trust_level (float 0.0–100.0) and suspicion_level (float 0.0–100.0)
- Trust increases from: showing relevant knowledge, making NPC-friendly choices, protecting NPC secrets
- Suspicion increases from: caught lying, asking about sensitive topics repeatedly, demonstrating knowledge that "shouldn't" be known
- Threshold-based reactions at configurable breakpoints (e.g., trust ≥ 60 unlocks new dialogue; suspicion ≥ 80 triggers defensive behavior)
- Input events: dialogue choice consequences, item presentation results, interaction patterns
- Output: trust_level and suspicion_level values for downstream systems
- NPC emotional state changes can trigger trust/suspicion adjustments (e.g., NPC becoming HOSTILE increases suspicion)

## Decision

TrustManager Autoload singleton that owns trust_level and suspicion_level per NPC, reading NPC emotional state as input and producing trust/suspicion values consumed by dialogue, events, and UI.

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                 TrustManager (Autoload)                               │
│                                                                      │
│  State owned (via LoopStateManager.propose_delta):                   │
│    trust_level[npc_id]: float (0.0–100.0)                            │
│    suspicion_level[npc_id]: float (0.0–100.0)                        │
│                                                                      │
│  Configuration (TrustConfig Resource per NPC):                       │
│    trust_thresholds: Dictionary (threshold → reaction)               │
│    suspicion_thresholds: Dictionary (threshold → reaction)           │
│    reset_on_loop_restart: bool (per-NPC config)                      │
│    emotional_state_weights: Dictionary (emotion → delta modifier)    │
│                                                                      │
│  Signals:                                                            │
│    trust_changed(npc_id: StringName, old_trust: float, new_trust)   │
│    suspicion_changed(npc_id: StringName, old_susp: float, new_susp) │
│    trust_threshold_crossed(npc_id: StringName, threshold: float,     │
│                            direction: ThresholdDirection)             │
│    suspicion_threshold_crossed(npc_id: StringName, threshold: float, │
│                                 direction: ThresholdDirection)        │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Input Sources:                                              │    │
│  │    NPCManager.npc_state_changed → _on_npc_state_changed      │    │
│  │    DialogueManager.consequence → _on_dialogue_consequence     │    │
│  │    InteractionBus.interaction_detected → _on_interaction      │    │
│  │    KnowledgeManager.knowledge_level_changed → _on_knowledge   │    │
│  │    External: apply_delta(npc_id, trust_delta, susp_delta)     │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Query API (read-only for downstream systems):                │    │
│  │    get_trust(npc_id) -> float                                  │    │
│  │    get_suspicion(npc_id) -> float                              │    │
│  │    get_trust_tier(npc_id) -> TrustTier enum                    │    │
│  │    get_suspicion_tier(npc_id) -> SuspicionTier enum            │    │
│  │    is_threshold_crossed(npc_id, metric, threshold) -> bool     │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
         │              │              │
    ┌────▼────┐   ┌─────▼─────┐  ┌────▼────┐
    │LoopState│   │NPCManager │  │Dialogue │
    │Manager  │   │(emotional │  │Manager  │
    │propose_ │   │ state     │  │(branch  │
    │delta()  │   │ input)    │  │ cond.)  │
    └─────────┘   └───────────┘  └─────────┘
```

### Key Interfaces

**TrustManager (Autoload Singleton)**:
```gdscript
class_name TrustManager
extends Node

enum TrustTier { NONE, LOW, MEDIUM, HIGH, MAXIMUM }
enum SuspicionTier { CALM, WATCHFUL, WARY, ALARMED, HOSTILE }
enum ThresholdDirection { CROSSED_ABOVE, CROSSED_BELOW }

signal trust_changed(npc_id: StringName, old_trust: float, new_trust: float)
signal suspicion_changed(npc_id: StringName, old_susp: float, new_susp: float)
signal trust_threshold_crossed(npc_id: StringName, threshold: float, direction: ThresholdDirection)
signal suspicion_threshold_crossed(npc_id: StringName, threshold: float, direction: ThresholdDirection)

var _trust: Dictionary = {}       # StringName -> float
var _suspicion: Dictionary = {}   # StringName -> float
var _configs: Dictionary = {}     # StringName -> TrustConfig

func _ready() -> void:
    NPCManager.npc_state_changed.connect(_on_npc_state_changed)
    LoopStateManager.night_advanced.connect(_on_night_advanced)
    _register_state_paths()

## --- State Registration ---

func _register_state_paths() -> void:
    for npc_id: StringName in _configs:
        LoopStateManager.register_state_paths([
            "trust.%s.trust_level" % npc_id,
            "trust.%s.suspicion_level" % npc_id,
        ])

## --- Public Query API ---

func get_trust(npc_id: StringName) -> float:
    return _trust.get(npc_id, 50.0)

func get_suspicion(npc_id: StringName) -> float:
    return _suspicion.get(npc_id, 0.0)

func get_trust_tier(npc_id: StringName) -> TrustTier:
    var t: float = get_trust(npc_id)
    if t >= 80.0: return TrustTier.HIGH
    if t >= 60.0: return TrustTier.MEDIUM
    if t >= 30.0: return TrustTier.LOW
    return TrustTier.NONE

func get_suspicion_tier(npc_id: StringName) -> SuspicionTier:
    var s: float = get_suspicion(npc_id)
    if s >= 80.0: return SuspicionTier.HOSTILE
    if s >= 60.0: return SuspicionTier.ALARMED
    if s >= 40.0: return SuspicionTier.WARY
    if s >= 20.0: return SuspicionTier.WATCHFUL
    return SuspicionTier.CALM

func is_threshold_crossed(npc_id: StringName, metric: StringName, threshold: float) -> bool:
    match metric:
        &"trust": return get_trust(npc_id) >= threshold
        &"suspicion": return get_suspicion(npc_id) >= threshold
    return false

## --- Mutation (routed through propose_delta) ---

func apply_delta(npc_id: StringName, trust_delta: float, suspicion_delta: float, reason: String = "") -> void:
    var old_trust: float = get_trust(npc_id)
    var old_susp: float = get_suspicion(npc_id)
    var new_trust: float = clampf(old_trust + trust_delta, 0.0, 100.0)
    var new_susp: float = clampf(old_susp + suspicion_delta, 0.0, 100.0)

    _trust[npc_id] = new_trust
    _suspicion[npc_id] = new_susp

    LoopStateManager.propose_delta({
        "source_night": LoopStateManager.current_night,
        "source_action": &"trust_delta",
        "target_path": "trust.%s.trust_level" % npc_id,
        "override_value": new_trust,
        "priority": 0,
    })
    LoopStateManager.propose_delta({
        "source_night": LoopStateManager.current_night,
        "source_action": &"suspicion_delta",
        "target_path": "trust.%s.suspicion_level" % npc_id,
        "override_value": new_susp,
        "priority": 0,
    })

    _check_threshold_crossing(npc_id, &"trust", old_trust, new_trust)
    _check_threshold_crossing(npc_id, &"suspicion", old_susp, new_susp)

    if not is_equal_approx(old_trust, new_trust):
        trust_changed.emit(npc_id, old_trust, new_trust)
    if not is_equal_approx(old_susp, new_susp):
        suspicion_changed.emit(npc_id, old_susp, new_susp)

## --- Input Handlers ---

func _on_npc_state_changed(npc_id: StringName, old_state: int, new_state: int) -> void:
    var config: TrustConfig = _configs.get(npc_id)
    if config == null: return

    var weights: Dictionary = config.emotional_state_weights
    var state_name: String = NPCEmotionalState.keys()[new_state].to_lower()

    if weights.has(state_name):
        var deltas: Dictionary = weights[state_name]
        apply_delta(npc_id, deltas.get("trust", 0.0), deltas.get("suspicion", 0.0),
            "emotional_state_change:%s" % state_name)

func _on_night_advanced(old_night: int, new_night: int) -> void:
    for npc_id: StringName in _configs:
        var config: TrustConfig = _configs[npc_id]
        var night_trust_decay: float = config.night_trust_decay
        var night_suspicion_decay: float = config.night_suspicion_decay
        if night_trust_decay != 0.0 or night_suspicion_decay != 0.0:
            apply_delta(npc_id, night_trust_decay, night_suspicion_decay,
                "night_advance:%d->%d" % [old_night, new_night])

## --- Threshold Detection ---

func _check_threshold_crossing(npc_id: StringName, metric: StringName, old_val: float, new_val: float) -> void:
    var config: TrustConfig = _configs.get(npc_id)
    if config == null: return

    var thresholds: Array[float] = []
    match metric:
        &"trust": thresholds = config.trust_thresholds
        &"suspicion": thresholds = config.suspicion_thresholds

    for threshold: float in thresholds:
        if old_val < threshold and new_val >= threshold:
            if metric == &"trust":
                trust_threshold_crossed.emit(npc_id, threshold, ThresholdDirection.CROSSED_ABOVE)
            else:
                suspicion_threshold_crossed.emit(npc_id, threshold, ThresholdDirection.CROSSED_ABOVE)
        elif old_val >= threshold and new_val < threshold:
            if metric == &"trust":
                trust_threshold_crossed.emit(npc_id, threshold, ThresholdDirection.CROSSED_BELOW)
            else:
                suspicion_threshold_crossed.emit(npc_id, threshold, ThresholdDirection.CROSSED_BELOW)
```

**TrustConfig (Resource)**:
```gdscript
class_name TrustConfig
extends Resource

@export var initial_trust: float = 50.0
@export var initial_suspicion: float = 0.0
@export var reset_on_loop_restart: bool = false

@export var trust_thresholds: Array[float] = [20.0, 40.0, 60.0, 80.0]
@export var suspicion_thresholds: Array[float] = [20.0, 40.0, 60.0, 80.0]

@export var night_trust_decay: float = -2.0
@export var night_suspicion_decay: float = -1.0

@export var emotional_state_weights: Dictionary = {
    "neutral": {"trust": 0.0, "suspicion": 0.0},
    "friendly": {"trust": 2.0, "suspicion": -1.0},
    "suspicious": {"trust": -3.0, "suspicion": 5.0},
    "hostile": {"trust": -5.0, "suspicion": 8.0},
    "secretive": {"trust": -1.0, "suspicion": 3.0},
    "revealing": {"trust": 5.0, "suspicion": -2.0},
}
```

### Trust/Suspicion Tier Mapping

| Tier | Trust Range | Suspicion Range | Narrative Meaning |
|------|-------------|-----------------|-------------------|
| NONE / CALM | 0–29 / 0–19 | NPC ignores player | Stranger |
| LOW / WATCHFUL | 30–59 / 20–39 | NPC is polite but distant | Acquaintance |
| MEDIUM / WARY | 60–79 / 40–59 | NPC shares some information | Confidant |
| HIGH / ALARMED | 80–100 / 60–79 | NPC reveals secrets | Trusted ally |
| MAXIMUM / HOSTILE | — / 80–100 | NPC actively obstructs | — / Threat detected |

## Alternatives Considered

### Alternative 1: Single Relationship Score

- **Description**: One relationship value per NPC (e.g., -100 to +100), where trust is the positive end and suspicion the negative.
- **Pros**: Simpler model; one value to track; easy to understand.
- **Cons**: Cannot represent "trusts you AND is suspicious of your knowledge" — a core narrative scenario (the NPC trusts your intentions but suspects you know too much). The game design explicitly requires independent axes.
- **Rejection Reason**: The single-axis model cannot express the narrative complexity the game requires. A trusted ally who becomes suspicious of your knowledge is a key dramatic beat that the two-axis model supports naturally.

### Alternative 2: Event-Log Approach (No Numeric Values)

- **Description**: Instead of numeric trust/suspicion, maintain a log of trust-relevant events per NPC. Downstream systems evaluate the log to determine behavior.
- **Pros**: Full auditability — every trust change has a cause. Designer can write complex conditions based on event history.
- **Cons**: Complex to evaluate at runtime — every dialogue choice would need to scan the event log. Serialization becomes large for long play sessions. Hard to display progress to the player.
- **Rejection Reason**: The numeric approach is simpler to implement, serialize, and query. Event-level detail can be captured in the `reason` parameter of apply_delta() for debugging without making the runtime model complex.

### Alternative 3: Trust as Derived View from NPC Emotional State

- **Description**: Trust/suspicion are derived values calculated from the NPC's emotional state history, not stored separately.
- **Pros**: No separate state to persist. Trust is always consistent with emotional state.
- **Cons**: Trust/suspicion can change for reasons unrelated to emotional state (item presentation, knowledge demonstration). Emotional state resets with template state each night; trust/suspicion should persist. Deriving trust from emotion history requires storing the full history, which is more complex than storing the derived values.
- **Rejection Reason**: Trust/suspicion have different lifecycle semantics than emotional state (cross-loop persistence vs nightly reset). Forcing trust to be derived from emotion creates coupling that makes both systems harder to evolve independently.

## Consequences

### Positive

- Two independent axes (trust + suspicion) support the narrative complexity of NPCs who trust the player but suspect their knowledge.
- Per-NPC TrustConfig resources allow designer-authorable curves without code changes.
- Threshold-crossing signals enable reactive behavior in downstream systems (dialogue branching, event triggers, UI indicators).
- propose_delta() integration provides automatic cross-loop persistence and serialization.
- TrustManager reads NPC emotional state but never writes it — clean state ownership boundary.
- Night decay creates natural narrative tension: trust erodes if the player doesn't maintain relationships.

### Negative

- One more Autoload singleton (adds to existing 9+ Autoloads).
- Trust/suspicion calibration requires playtesting — threshold values may need iteration.
- The two-axis model is harder to communicate to players visually than a single relationship meter.
- apply_delta() fires propose_delta() twice per call (trust + suspicion), doubling delta throughput for trust operations.

### Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Trust/suspicion values drift to extremes without meaningful gameplay impact | Medium | Low — designer calibration issue | Night decay provides natural regression toward center. Configurable per-NPC decay rates. |
| propose_delta() frequency too high during dialogue-heavy sequences | Low | Low — delta accumulation is lightweight | apply_delta() batches both trust and suspicion in one call. LoopStateManager batches deltas. |
| Trust thresholds feel arbitrary to players | Medium | Medium — player frustration | Playtest threshold visibility. Consider subtle UI indicators for trust tier changes. |
| Emotional state weights produce unintended trust/suspicion combinations | Low | Medium — narrative inconsistency | Designer-authorable via TrustConfig. Default weights are conservative (small deltas). |
| Cross-loop trust persistence makes late loops easier, reducing challenge | Medium | Medium — difficulty curve issue | reset_on_loop_restart per-NPC config. Some NPCs reset, creating fresh challenges each loop. |

## Boundary Rules

1. **TrustManager MUST NOT write to NPC emotional state.** It reads NPCManager.get_emotional_state() as input only. All emotional state mutations go through NPCManager.request_state_transition() → propose_delta().

2. **TrustManager MUST NOT contain dialogue logic.** It produces trust/suspicion values; dialogue branching is handled by DialogueManager (ADR-0013).

3. **TrustManager MUST NOT directly modify game state outside its domain.** All trust/suspicion mutations go through apply_delta() → propose_delta(). No direct ClueDatabase, NPCManager, or RoomManager mutations.

4. **Trust and suspicion are independent.** No code may assume trust + suspicion = 100 or that one increases when the other decreases.

5. **Trust/suspicion values are clamped to [0.0, 100.0].** No overflow or underflow. apply_delta() enforces clamping.

## Conventions

1. **Autoload load order**: TrustManager must load after LoopStateManager and NPCManager. It connects to signals from both and registers state paths during _ready().

2. **State path naming**: Trust state follows the pattern `trust.{npc_id}.trust_level` and `trust.{npc_id}.suspicion_level` in LoopStateManager's active state.

3. **Delta convention**: Positive trust_delta increases trust (good for player). Positive suspicion_delta increases suspicion (bad for player). This is the intuitive direction.

4. **Threshold arrays are sorted ascending**: TrustConfig.trust_thresholds and suspicion_thresholds must be sorted from lowest to highest for correct threshold crossing detection.

5. **Default values**: Trust defaults to 50.0 (neutral). Suspicion defaults to 0.0 (calm). Configs override these per NPC.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| game-concept.md | Pillar 4 | Each NPC has secrets to protect; NPCs react to player knowledge | Trust/suspicion track how player actions affect NPC disposition |
| game-concept.md | Pillar 2 | Time loop exploration — accumulated knowledge affects NPC relationships | Trust/suspicion persist across nights via propose_delta(); configurable cross-loop reset |
| systems-index.md | System #13 | NPC Trust/Suspicion — depends on #1, #4, #6 | This ADR defines the complete Trust/Suspicion system |
| systems-index.md | System #14 | Conditional Dialogue Trees — reads trust/suspicion for branching | TrustManager.get_trust() / get_suspicion() provide query API |
| systems-index.md | System #15 | Guest Interrogation — trust/suspicion drive interrogation | Trust tiers determine interrogation availability and NPC reactions |
| ADR-0009 | Trust exclusion | Trust/suspicion explicitly excluded from NPC state machine | TrustManager is the separate system owning trust/suspicion |

## Performance Implications

| Metric | Expected Value | Budget | Notes |
|--------|---------------|--------|-------|
| CPU (per delta) | < 0.01 ms | < 0.1 ms | Two float clamp + two propose_delta + threshold scan (4-5 comparisons). Negligible. |
| CPU (per query) | < 0.001 ms | < 0.01 ms | Dictionary lookup. No computation. |
| CPU (per frame) | 0.0 ms | 0.0 ms | set_process(false). No per-frame work. Event-driven only. |
| Memory (runtime) | ~1 KB | < 2 KB | 5 NPCs × 2 floats + 5 configs. Tiny. |
| Serialization | ~200 bytes per NPC | < 1 KB total | Two float values per NPC in JSON. |

- **Network**: N/A (single-player game)
- **Frame budget impact**: Zero per-frame cost. All operations are event-driven (signal handlers).

## Migration Plan

New system. Implementation order:

1. Create TrustConfig Resource with @export properties.
2. Implement TrustManager Autoload skeleton with state registration and query API.
3. Implement apply_delta() with propose_delta() integration and threshold crossing detection.
4. Implement _on_npc_state_changed() input handler.
5. Implement _on_night_advanced() for night decay.
6. Wire trust_changed/suspicion_changed signals for future DialogueManager integration.
7. Create default TrustConfig resources for 5 NPCs.
8. Write unit tests for: delta application, threshold crossing, clamping, night decay, cross-loop persistence, query API.

**Rollback plan**: TrustManager is an Autoload that can be removed without affecting NPCManager, LoopStateManager, or other systems. No existing code references TrustManager yet. Removing it only affects future dialogue branching that hasn't been implemented.

## Validation Criteria

1. apply_delta() correctly updates trust and suspicion values with clamping to [0.0, 100.0]
2. Trust thresholds at 20, 40, 60, 80 fire trust_threshold_crossed signals when crossed in either direction
3. Suspicion thresholds at 20, 40, 60, 80 fire suspicion_threshold_crossed signals when crossed in either direction
4. get_trust_tier() returns correct TrustTier enum for boundary values (29→NONE, 30→LOW, 59→LOW, 60→MEDIUM, etc.)
5. get_suspicion_tier() returns correct SuspicionTier enum for boundary values
6. NPC emotional state change triggers trust/suspicion delta per TrustConfig weights
7. Night advance triggers night decay per TrustConfig (negative deltas)
8. State paths registered correctly: trust.{npc_id}.trust_level and trust.{npc_id}.suspicion_level
9. propose_delta() called for every apply_delta() invocation
10. TrustManager never writes to NPCManager state (read-only access verified)
11. Default values: trust=50.0, suspicion=0.0 for unconfigured NPCs
12. Serialization round-trip: save with trust=73.5/suspicion=42.1 → load → values restored exactly

## Related Decisions

- ADR-0004: Loop State Management — provides propose_delta(), register_state_paths(), DeltaAccumulator for cross-loop persistence
- ADR-0009: NPC State Machine — provides NPCManager.get_emotional_state() as input, npc_state_changed signal
- ADR-0006: Interaction Event Bus — provides interaction_detected signal for trust event triggers
- ADR-0002: Knowledge Color Accumulation — KnowledgeManager per-NPC saturation values as potential trust input
- ADR-0013: Conditional Dialogue Trees — consumes trust_level/suspicion_level for dialogue branching
- architecture.yaml: State ownership — trust_level and suspicion_level are NEW state ownership claims from this ADR
