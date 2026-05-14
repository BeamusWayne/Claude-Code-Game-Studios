# ADR-0009: NPC State Machine

## Status
Accepted (enum unified with GDD 2026-05-15; see Amendment below)

## Date
2026-05-14

## Amendment (2026-05-15)

NPCEmotionalState enum unified with GDD `design/gdd/npc-state-machine.md`. Old values (FRIENDLY, SUSPICIOUS, SECRETIVE, REVEALING) replaced with GDD values (TRUSTING, ANXIOUS, CURIOUS, FRIGHTENED). Transition table updated to match GDD formulas section. Code (`src/core/npc_manager.gd`) already used the correct GDD enum; this change brings the ADR documentation into alignment.

## Last Verified
2026-05-14

## Decision Makers
godot-specialist (author), technical-director (review pending)

## Summary

The 5 NPC guests in 七夜 need individual emotional states that change based on player actions and cross-loop knowledge, while their template state (position, dialogue availability) resets each night. This ADR defines an enum-based finite state machine per NPC, backed by NPCTemplate resources for per-night initial state, with all mutations routed through LoopStateManager's propose_delta() pipeline. Trust/suspicion is explicitly excluded as a separate future system (System #13).

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Gameplay / AI |
| **Knowledge Risk** | LOW -- uses standard Godot Resource, enum, and signal patterns. No post-cutoff APIs required. |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, docs/engine-reference/godot/breaking-changes.md, docs/engine-reference/godot/deprecated-apis.md |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Test state transitions for all 6 emotional states. Test propose_delta() integration with LoopStateManager. Test night reset restores template state. Test NPC registration of state paths. Test serialization round-trip of NPC state. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (Loop State Management) -- NPC registers state paths, uses propose_delta() for mutations, listens to night_advanced/night_ready signals. ADR-0006 (Interaction Event Bus) -- NPC click events arrive via InteractionBus. |
| **Enables** | System #13 (NPC Trust/Suspicion -- reads NPC emotional state), System #14 (Conditional Dialogue Trees -- queries NPC state for dialogue branching), System #15 (Guest Interrogation / 住客审问 -- drives interrogation availability and NPC reactions), System #9 (Event Scheduler -- schedules events based on NPC state) |
| **Blocks** | System #13, System #14, System #15, System #9 |
| **Ordering Note** | Must be Accepted before NPC Trust/Suspicion ADR and Conditional Dialogue Trees ADR. Can be designed in parallel with Countdown Timer (ADR-0008). |

## Context

### Problem Statement

七夜 has 5 NPC guests (住客), each with secrets, motives, and lies (Pillar 4: 每个住客都有要守护的秘密). NPCs are not information vending machines -- they have emotional states that change based on how the player approaches them, what knowledge the player demonstrates, and what consequences have accumulated across loops. The NPC state machine must: (1) track each NPC's emotional disposition, (2) reset template properties each night while preserving cross-loop mutations, (3) provide a query interface for downstream systems (dialogue, trust, events), and (4) integrate with LoopStateManager's propose_delta() pipeline for all state changes.

### Current State

No NPC system exists yet. This is a greenfield design. The LoopStateManager (ADR-0004) is Accepted and provides the propose_delta() / register_state_paths() interface that NPC state must use. The InteractionBus (ADR-0006) is Accepted and will deliver NPC click events.

### Constraints

- 5 NPC guests, each with a unique character color from the art bible (靛蓝, 赭石, 朱砂, 青瓷, 梅紫)
- NPC state is split between Template State (resets each night) and Persistent Mutations (accumulates cross-loop), per ADR-0004's three-layer model
- All NPC state mutations MUST go through LoopStateManager.propose_delta() -- direct mutation is forbidden
- NPC must register its state paths at startup via LoopStateManager.register_state_paths()
- current_night and current_phase are READ-ONLY for NPC -- owned by loop-state-system
- InteractionBus delivers click events with target_type "npc" -- NPC must not contain game logic in the bus handler (forbidden pattern: interaction_bus_game_logic)
- Trust/suspicion is NOT part of this system -- it will be designed separately as System #13
- MVP: static NPC positions (no movement/scheduling), 3-5 emotional states per NPC
- Future: per-night NPC schedules, movement between rooms, location-based state changes

### Requirements

- Each NPC has an emotional state from a defined enum (NEUTRAL, CURIOUS, ANXIOUS, HOSTILE, TRUSTING, FRIGHTENED)
- State transitions triggered by: player dialogue choices, item presentation, cross-loop knowledge demonstration, time pressure (TimerService phases)
- NPC initial state per night comes from NPCTemplate (part of NightTemplate)
- NPC state persists across nights via LoopStateManager's DeltaAccumulator
- NPCManager coordinates all 5 NPCs and provides a query interface
- NPC state changes emit signals for downstream consumers (dialogue, trust, events, UI)
- Dialogue availability is an NPC state property (can be unavailable due to emotional state or narrative conditions)
- NPC current_location is part of template state (MVP: static per night)

## Decision

Enum-based finite state machine per NPC, coordinated by an NPCManager (Autoload). Each NPC's state lives in the LoopStateManager's active state under registered paths. NPCManager owns the transition logic and validation, but delegates persistence to LoopStateManager via propose_delta().

Trust/suspicion values are explicitly NOT stored in NPC state. The future NPC Trust/Suspicion system (System #13) will own trust_level and suspicion_level, reading NPC emotional state as an input to its own calculations.

### Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     NPCManager (Autoload)                        │
│                                                                  │
│  signal npc_state_changed(npc_id: StringName, old_state, new)   │
│  signal npc_dialogue_availability_changed(npc_id: StringName,   │
│      available: bool)                                            │
│  signal npc_interaction_requested(npc_id: StringName, event)    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  _npc_registry: Dictionary[StringName, NPCInstance]         │ │
│  │  {                                                          │ │
│  │    "guest_indigo":  { template, current_state, node_ref },  │ │
│  │    "guest_ochre":   { template, current_state, node_ref },  │ │
│  │    "guest_vermilion": { template, current_state, node_ref },│ │
│  │    "guest_celadon": { template, current_state, node_ref },  │ │
│  │    "guest_plum":    { template, current_state, node_ref },  │ │
│  │  }                                                          │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  State Flow:                                                     │
│  1. _ready() → register_state_paths() with LoopStateManager     │
│  2. night_ready → _initialize_npcs_from_template(night)         │
│  3. InteractionBus "npc" event → _handle_npc_interaction()      │
│  4. Transition request → validate → propose_delta()             │
│  5. propose_delta accepted → update cache → emit signal         │
│  6. night_advanced → _initialize_npcs_from_template(night + 1)  │
└───────────────┬────────────────────┬─────────────────────────────┘
                │                    │
     ┌──────────▼──────┐  ┌─────────▼──────────┐
     │ LoopStateManager│  │ InteractionBus      │
     │ (propose_delta) │  │ (npc click events)  │
     └─────────────────┘  └────────────────────┘
                │                    │
     ┌──────────▼──────┐  ┌─────────▼──────────┐
     │ Downstream:     │  │ NPC Node (scene)    │
     │ - Dialogue (#14)│  │ - Sprite + color    │
     │ - Trust (#13)   │  │ - Interactable      │
     │ - Events (#9)   │  │ - Area2D            │
     │ - UI (#19,#20)  │  └────────────────────┘
     └─────────────────┘
```

### Key Interfaces

**NPCEmotionalState Enum**:
```gdscript
enum NPCEmotionalState {
    NEUTRAL,      ## Default calm state. Standard dialogue options.
    CURIOUS,      ## Attracted by player's new clues. Extra dialogue branches.
    ANXIOUS,      ## Feels threatened or uneasy. Avoids sensitive topics.
    HOSTILE,      ## Actively confrontational, refuses to cooperate. Limited dialogue.
    TRUSTING,     ## Has developed trust toward player. Shares hints proactively.
    FRIGHTENED,   ## Extreme fear. Short responses, may reveal critical info.
}
```

**NPCTemplate Resource** (per-night initial state, authored in editor):
```gdscript
class_name NPCTemplate
extends Resource

@export var npc_id: StringName
@export var initial_emotional_state: NPCEmotionalState = NPCEmotionalState.NEUTRAL
@export var location: StringName                      ## room_id where NPC starts this night
@export var dialogue_available: bool = true
@export var dialogue_id: StringName                   ## root dialogue node for this night
@export var portrait: Texture2D                       ## NPC portrait for dialogue UI
@export var conditions: Dictionary = {}               ## night-specific override conditions
```

**NPCInstance** (runtime state cache in NPCManager):
```gdscript
## Internal runtime representation. Not a Resource -- cached from LoopStateManager.
## NPCManager holds the authoritative cache; LoopStateManager holds the persistent truth.
class NPCInstance:
    var npc_id: StringName
    var template: NPCTemplate
    var current_emotional_state: NPCEmotionalState
    var current_location: StringName
    var dialogue_available: bool
    var dialogue_id: StringName
    var node_ref: Node2D  ## reference to the NPC scene node, set when scene loads
```

**NPCManager (Autoload Singleton)**:
```gdscript
class_name NPCManager
extends Node

signal npc_state_changed(npc_id: StringName, old_state: NPCEmotionalState, new_state: NPCEmotionalState)
signal npc_dialogue_availability_changed(npc_id: StringName, available: bool)
signal npc_interaction_requested(npc_id: StringName, event: Dictionary)

const NPC_STATE_PATH_PREFIX: StringName = &"npcs"

var _npc_registry: Dictionary[StringName, NPCInstance] = {}

func _ready() -> void:
    _register_state_paths()
    LoopStateManager.night_ready.connect(_on_night_ready)
    LoopStateManager.night_advanced.connect(_on_night_advanced)
    InteractionBus.interaction_detected.connect(_on_interaction_detected)

func _register_state_paths() -> void:
    ## Register all NPC state paths with LoopStateManager.
    ## Each NPC gets paths for emotional_state, location, dialogue_available.
    var paths: Array[StringName] = []
    for npc_id: StringName in _get_all_npc_ids():
        paths.append(&"npcs.%s.emotional_state" % npc_id)
        paths.append(&"npcs.%s.location" % npc_id)
        paths.append(&"npcs.%s.dialogue_available" % npc_id)
    LoopStateManager.register_state_paths(paths)

func get_emotional_state(npc_id: StringName) -> NPCEmotionalState:
    if not _npc_registry.has(npc_id):
        push_warning("NPCManager: unknown npc_id '%s'" % npc_id)
        return NPCEmotionalState.NEUTRAL
    return _npc_registry[npc_id].current_emotional_state

func get_location(npc_id: StringName) -> StringName:
    if not _npc_registry.has(npc_id):
        return &""
    return _npc_registry[npc_id].current_location

func is_dialogue_available(npc_id: StringName) -> bool:
    if not _npc_registry.has(npc_id):
        return false
    return _npc_registry[npc_id].dialogue_available

func request_state_transition(npc_id: StringName, new_state: NPCEmotionalState) -> bool:
    ## Validates and attempts a state transition via LoopStateManager.
    ## Returns true if the delta was accepted.
    if not _npc_registry.has(npc_id):
        push_warning("NPCManager: transition requested for unknown npc_id '%s'" % npc_id)
        return false

    var instance: NPCInstance = _npc_registry[npc_id]
    if instance.current_emotional_state == new_state:
        return false  ## no-op, not an error

    if not _is_valid_transition(instance.current_emotional_state, new_state):
        push_warning("NPCManager: invalid transition %s -> %s for '%s'" % [
            NPCEmotionalState.keys()[instance.current_emotional_state],
            NPCEmotionalState.keys()[new_state],
            npc_id
        ])
        return false

    var path: StringName = &"npcs.%s.emotional_state" % npc_id
    var accepted: bool = LoopStateManager.propose_delta({
        "source_night": LoopStateManager.current_night,
        "source_action": &"npc_state_transition",
        "target_path": path,
        "override_value": new_state,
        "priority": 0,
    })

    if accepted:
        var old_state: NPCEmotionalState = instance.current_emotional_state
        instance.current_emotional_state = new_state
        npc_state_changed.emit(npc_id, old_state, new_state)

    return accepted

func force_state_transition(npc_id: StringName, new_state: NPCEmotionalState, narrative_priority: int = 10) -> bool:
    ## Bypasses transition validation for narrative overrides.
    ## Uses elevated priority so narrative deltas win during REBUILD.
    ## Log all forced transitions for design review.
    if not _npc_registry.has(npc_id):
        return false

    var path: StringName = &"npcs.%s.emotional_state" % npc_id
    var accepted: bool = LoopStateManager.propose_delta({
        "source_night": LoopStateManager.current_night,
        "source_action": &"npc_narrative_override",
        "target_path": path,
        "override_value": new_state,
        "priority": narrative_priority,
    })

    if accepted:
        var old_state: NPCEmotionalState = _npc_registry[npc_id].current_emotional_state
        _npc_registry[npc_id].current_emotional_state = new_state
        npc_state_changed.emit(npc_id, old_state, new_state)

    return accepted

func set_dialogue_availability(npc_id: StringName, available: bool) -> bool:
    ## Changes dialogue availability via propose_delta.
    var path: StringName = &"npcs.%s.dialogue_available" % npc_id
    var accepted: bool = LoopStateManager.propose_delta({
        "source_night": LoopStateManager.current_night,
        "source_action": &"npc_dialogue_toggle",
        "target_path": path,
        "override_value": available,
        "priority": 0,
    })
    if accepted:
        _npc_registry[npc_id].dialogue_available = available
        npc_dialogue_availability_changed.emit(npc_id, available)
    return accepted

func get_npc_ids_in_room(room_id: StringName) -> Array[StringName]:
    ## Returns all NPC IDs whose current_location matches room_id.
    var result: Array[StringName] = []
    for npc_id: StringName in _npc_registry:
        if _npc_registry[npc_id].current_location == room_id:
            result.append(npc_id)
    return result

func get_all_npc_ids() -> Array[StringName]:
    return _npc_registry.keys()

var _is_initialized: bool = false

func _initialize_npcs_from_template(night: int) -> void:
    ## Load NPCTemplate for each NPC for the given night.
    ## Template state provides the baseline; DeltaAccumulator overlays
    ## cross-loop mutations during LoopStateManager's REBUILD step.
    ##
    ## Emotional state: query LoopStateManager's active state first.
    ## If a delta exists (from DeltaAccumulator REBUILD), that value
    ## takes precedence over the template baseline. This preserves
    ## cross-loop emotional mutations across night transitions.
    for npc_id: StringName in _get_all_npc_ids():
        var template: NPCTemplate = _load_npc_template(npc_id, night)
        var instance: NPCInstance = _npc_registry[npc_id]
        instance.template = template
        instance.current_location = template.location
        instance.dialogue_available = template.dialogue_available
        instance.dialogue_id = template.dialogue_id
        # Query LoopStateManager for persisted emotional state.
        # Active state = template + DeltaAccumulator rebuild.
        # get_active_state_value() is a read-only accessor on LoopStateManager's
        # active state Dictionary -- an extension of ADR-0004's interface,
        # to be added alongside register_state_paths() and propose_delta().
        var state_path: StringName = &"npcs.%s.emotional_state" % npc_id
        var persisted: Variant = LoopStateManager.get_active_state_value(state_path)
        if persisted != null:
            instance.current_emotional_state = persisted as NPCEmotionalState
        else:
            instance.current_emotional_state = template.initial_emotional_state
    _is_initialized = true

func _is_valid_transition(from: NPCEmotionalState, to: NPCEmotionalState) -> bool:
    ## Transition validation table.
    ## Not all transitions are valid -- e.g., NEUTRAL -> FRIGHTENED requires
    ## intermediate steps. This prevents jarring NPC behavior.
    match from:
        NPCEmotionalState.NEUTRAL:
            return to in [NPCEmotionalState.CURIOUS, NPCEmotionalState.ANXIOUS,
                          NPCEmotionalState.TRUSTING]
        NPCEmotionalState.CURIOUS:
            return to in [NPCEmotionalState.NEUTRAL, NPCEmotionalState.TRUSTING,
                          NPCEmotionalState.ANXIOUS]
        NPCEmotionalState.ANXIOUS:
            return to in [NPCEmotionalState.HOSTILE, NPCEmotionalState.FRIGHTENED,
                          NPCEmotionalState.NEUTRAL]
        NPCEmotionalState.HOSTILE:
            return to in [NPCEmotionalState.ANXIOUS, NPCEmotionalState.NEUTRAL]
        NPCEmotionalState.TRUSTING:
            return to in [NPCEmotionalState.NEUTRAL, NPCEmotionalState.CURIOUS,
                          NPCEmotionalState.ANXIOUS]
        NPCEmotionalState.FRIGHTENED:
            return to in [NPCEmotionalState.ANXIOUS, NPCEmotionalState.HOSTILE,
                          NPCEmotionalState.NEUTRAL]
        _:
            return false

func _on_interaction_detected(event: Dictionary) -> void:
    ## Filter InteractionBus events for NPC targets.
    ## Does NOT contain game logic (forbidden pattern: interaction_bus_game_logic).
    if event.get("target_type", &"") != &"npc":
        return
    var npc_id: StringName = event["target_id"]
    if not _npc_registry.has(npc_id):
        return
    npc_interaction_requested.emit(npc_id, event)

func _on_night_ready(night: int) -> void:
    if _is_initialized:
        return  ## Guard: avoid double-init if night_ready and night_advanced both fire
    _initialize_npcs_from_template(night)

func _on_night_advanced(old_night: int, new_night: int) -> void:
    ## Template state resets are handled by LoopStateManager's REBUILD step.
    ## NPCManager re-initializes its cache from the rebuilt active state.
    _is_initialized = false
    _initialize_npcs_from_template(new_night)

func _get_all_npc_ids() -> Array[StringName]:
    return [&"guest_indigo", &"guest_ochre", &"guest_vermilion",
            &"guest_celadon", &"guest_plum"]

func _load_npc_template(npc_id: StringName, night: int) -> NPCTemplate:
    ## Load the NPCTemplate resource for this NPC on this night.
    ## Path convention: assets/data/npcs/{npc_id}/night_{n}.tres
    var path: String = "res://assets/data/npcs/%s/night_%d.tres" % [npc_id, night]
    if ResourceLoader.exists(path):
        return load(path) as NPCTemplate
    ## Fallback: load night_1 template (guests default to their initial disposition)
    var fallback_path: String = "res://assets/data/npcs/%s/night_1.tres" % npc_id
    if ResourceLoader.exists(fallback_path):
        return load(fallback_path) as NPCTemplate
    ## Last resort: create a default template
    push_warning("NPCManager: no template found for '%s' night %d, using default" % [npc_id, night])
    var default_template := NPCTemplate.new()
    default_template.npc_id = npc_id
    default_template.initial_emotional_state = NPCEmotionalState.NEUTRAL
    default_template.dialogue_available = true
    return default_template
```

**State Transition Diagram**:
```
                    ┌──────────────┐
                    │   NEUTRAL    │◄─── ANXIOUS, HOSTILE, TRUSTING, FRIGHTENED
                    └──┬─┬─┬───────┘
                       │ │ │
          ┌────────────┘ │ └──────────────┐
          ▼              │                ▼
   ┌─────────────┐      │         ┌──────────────┐
   │  TRUSTING   │◄─────┼─────────│   ANXIOUS    │──┐
   └──┬─┬────────┘      │         └──────┬───────┘  │
      │ │               │                │          │
      │ └──────────┐    │                ▼          │
      │            ▼    │         ┌──────────────┐  │
      │    ┌────────────┤         │   HOSTILE    │──┤
      │    │  CURIOUS   │         └──────────────┘  │
      │    └──┬─┬───────┘                           │
      │       │ │                                   │
      │       │ └──────────────┐                    │
      │       ▼                │                    │
      │  ┌──────────────┐     │                    │
      │  │ FRIGHTENED   │─────┼────────────────────┘
      │  └──────────────┘     │
      │                       │
      └───────────────────────┘
  (NEUTRAL reachable from: CURIOUS, ANXIOUS, HOSTILE, TRUSTING, FRIGHTENED)
```

### Implementation Guidelines

1. **NPCTemplate resources** are authored per NPC per night in the Godot editor. Path convention: `assets/data/npcs/{npc_id}/night_{n}.tres`. If a night has no specific template, fall back to night_1, then to a programmatic default.

2. **Transition validation** uses a match-block allowlist, not a transition matrix Resource. This keeps the validation logic visible and auditable in code. If designers need to customize transitions per NPC, this can be promoted to a Resource in a future iteration.

3. **NPCManager is the sole authority** for NPC state queries. Downstream systems (dialogue, trust, events) call NPCManager methods, never LoopStateManager directly for NPC-specific queries.

4. **NPC scene nodes** (CharacterBody2D with sprite, Interactable component) are instantiated per room and register with NPCManager. The node_ref in NPCInstance enables visual updates (sprite state changes) when emotional state changes.

5. **Signal flow**: NPCManager emits npc_state_changed. Downstream systems connect to this signal. The NPCManager does NOT call downstream systems directly -- decoupled communication via signals.

6. **force_state_transition()** bypasses transition validation for narrative overrides. It uses elevated priority (default 10, matching ADR-0004's NARRATIVE_DELTA_PRIORITY) so narrative deltas survive cross-night REBUILD. All forced transitions are logged for design review. Use sparingly -- the normal transition path should be preferred.

7. **Autoload load order**: NPCManager must be registered below LoopStateManager in Project Settings > Autoload. Godot fires `_ready()` in registration order; NPCManager's `_ready()` calls `LoopStateManager.register_state_paths()`, which requires LoopStateManager to be initialized first. This ordering constraint matches the existing pattern (InteractionBus, RoomManager also depend on LoopStateManager and must be registered after it).

8. **Programmatic NPCTemplate fallback** (from `_load_npc_template()` last-resort path) creates an ephemeral Resource with no `resource_path`. LoopStateManager serializes NPC state values (enum ints) via `propose_delta()`, not template references, so the missing resource_path does not affect serialization. The fallback template is not persisted and is rebuilt from code on each initialization.

9. **Post-deserialize cache rebuild**: After `LoopStateManager.deserialize()` fires `night_ready`, NPCManager's `_on_night_ready()` handler re-initializes the NPC cache from templates + LoopStateManager's restored active state (which includes DeltaAccumulator entries). The `_is_initialized` guard prevents double-init if both `night_ready` and `night_advanced` fire during deserialization.

## Alternatives Considered

### Alternative 1: Behavior Tree

- **Description**: Each NPC runs a Behavior Tree that evaluates conditions and selects actions each frame, producing emergent emotional state.
- **Pros**: Richer AI behavior; NPC can autonomously react to environment changes; supports complex priority-based decision making.
- **Cons**: Significantly more complex to implement and debug; requires a Behavior Tree library or custom implementation; 5 NPCs with no movement or autonomous behavior in MVP means the tree is mostly idle; overkill for a narrative adventure game where NPC reactions are scripted, not emergent.
- **Rejection Reason**: 七夜's NPCs are narrative-driven, not simulation-driven. Their state changes come from player actions and scripted story beats, not autonomous decision-making. A finite state machine is the simplest mechanism that captures the needed behavior. Behavior Trees are appropriate for games where NPCs have complex autonomous routines; this is not that game.

### Alternative 2: Dictionary-Based State with No Enum

- **Description**: NPC state is a free-form Dictionary of string keys to arbitrary values, with no enum constraint. State names are defined in data files.
- **Pros**: Maximum flexibility; designers can add new states without code changes; no enum maintenance.
- **Cons**: No compile-time validation of state names; typos in state strings cause silent failures; transition validation must be data-driven (more complex); IDE autocomplete and type safety lost; debugging requires string matching.
- **Rejection Reason**: With only 6 emotional states and a fixed set of 5 NPCs, an enum provides type safety, compile-time checking, and clear documentation. The flexibility cost (maintaining transition validation data) outweighs the benefit for this scope. If the state set grows significantly post-MVP, this decision can be revisited.

### Alternative 3: Resource-Per-State Pattern

- **Description**: Each possible NPC state (NEUTRAL on night 1, TRUSTING on night 3, etc.) is a separate Resource instance with all properties embedded. State transitions load a new Resource.
- **Pros**: Full editor control over every state; each state is a complete snapshot; easy to preview in editor.
- **Cons**: Resource explosion (5 NPCs x 7 nights x 6 states = 210 Resources); merge conflicts in team editing; difficult to track incremental changes; duplicative data when most properties stay the same between states.
- **Rejection Reason**: NPCTemplate per night (5 x 7 = 35 Resources maximum) is manageable. Per-state Resources would multiply this by the number of possible states, creating a combinatorial explosion that is hard to author and maintain. The enum + template approach keeps authoring burden proportional to nights, not nights x states.

## Consequences

### Positive

- Enum-based states are type-safe, self-documenting, and easy to debug -- the Godot debugger shows enum names, not magic numbers
- Integration with LoopStateManager's propose_delta() ensures NPC state mutations follow the same persistence and conflict-resolution rules as all other game state
- NPCManager provides a clean query interface for downstream systems, preventing direct coupling to LoopStateManager internals
- NPCTemplate resources allow per-night NPC configuration without code changes
- Transition validation prevents jarring emotional shifts (e.g., NEUTRAL directly to FRIGHTENED), supporting Pillar 4's requirement that NPCs feel like characters with guard and agency
- Signal-based communication keeps NPCManager decoupled from dialogue, trust, and event systems
- Static positions in MVP keep implementation simple; the architecture supports future scheduling without restructuring
- force_state_transition() provides an escape valve for narrative designers without undermining the normal transition rules

### Negative

- Adding new emotional states requires code changes (enum + transition validation + all templates that reference the enum). This is acceptable for 6 states but would be burdensome at 15+.
- NPCManager is an Autoload, introducing a global dependency. Systems that query NPC state depend on NPCManager being loaded. Mitigated by: NPCManager has no scene-specific state and follows the same autoload discipline as LoopStateManager.
- Transition validation is code-based, not data-driven. Designers cannot modify transition rules without a programmer. Acceptable for MVP; can be promoted to a Resource if needed.
- NPCManager caches state locally and must stay synchronized with LoopStateManager's active state. If LoopStateManager's REBUILD changes NPC state without going through NPCManager, the cache becomes stale. Mitigated by: NPCManager re-initializes from templates on night_ready and night_advanced.

### Neutral

- NPC node_ref in NPCInstance creates a bidirectional reference (NPCManager knows about scene nodes, scene nodes register with NPCManager). This is standard for manager patterns in Godot.
- The path convention for NPCTemplate resources (`assets/data/npcs/{id}/night_{n}.tres`) is a project convention, not an engine requirement.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-----------|
| Cache desync between NPCManager and LoopStateManager active state | Low | High -- wrong NPC state shown to player | NPCManager re-initializes from active state on night_ready and night_advanced. Unit test cache consistency after propose_delta and after REBUILD. |
| Transition validation too restrictive -- designers need paths that are blocked | Medium | Medium -- design workarounds | force_state_transition() bypasses validation for narrative overrides with elevated priority. Log all forced transitions for design review. |
| NPCTemplate resource loading fails at runtime | Low | Medium -- NPC appears with wrong state | Fallback chain: night_N -> night_1 -> programmatic default. Warning logged for missing templates. |
| NPC state becomes a dumping ground for unrelated data | Medium | High -- scope creep, coupling | Boundary rule: NPC state owns emotional_state, location, dialogue_availability only. Trust, suspicion, dialogue content are owned by other systems. Enforced in code review. |
| 5 NPCs x per-frame queries becomes a performance concern | Very Low | Low | NPC queries are O(1) Dictionary lookups. No _process() in NPCManager. |

## Boundary Rules

1. **NPC state machine owns**: current_emotional_state, current_location, dialogue_availability, dialogue_id (pointer to dialogue root, not dialogue content).
2. **NPC state machine does NOT own**: trust_level (owned by System #13 NPC Trust/Suspicion), suspicion_level (owned by System #13), dialogue content/trees (owned by System #14 Conditional Dialogue Trees), NPC visual rendering (owned by NPC scene node).
3. **No game logic in InteractionBus handler**: The _on_interaction_detected() method only filters and re-emits. All consequence logic lives in the systems that consume npc_interaction_requested.
4. **No direct state mutation**: All changes to NPC emotional state must go through NPCManager.request_state_transition() or force_state_transition() (which call propose_delta()). Direct assignment to NPCInstance.current_emotional_state outside NPCManager is forbidden.
5. **NPC ID convention**: All NPC IDs use the format `guest_{color}` (guest_indigo, guest_ochre, guest_vermilion, guest_celadon, guest_plum). These IDs are shared across InteractionBus target_id, NPCManager registry, ClueDatabase references, and KnowledgeManager npc_id parameters.

## Conventions

- **NPC ID naming**: `guest_{english_color_name}` in snake_case. Matches the art bible's five guest colors. The same ID is used in InteractionBus (target_id), ClueDatabase (metadata), KnowledgeManager (npc_saturation queries), and dialogue system (npc_id parameter).
- **Template resource naming**: `night_{n}.tres` inside `assets/data/npcs/{npc_id}/`. Night 1 template is the fallback for any night without a specific template.
- **State path convention**: `npcs.{npc_id}.{property}` registered with LoopStateManager. Example: `npcs.guest_indigo.emotional_state`.
- **Signal naming**: NPCManager signals use the `npc_` prefix to distinguish from LoopStateManager signals. Downstream systems connect to NPCManager signals, not LoopStateManager.state_changed, for NPC-related logic.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| game-concept.md | Pillar 4 | 每个住客都有要守护的秘密 -- NPC不是信息贩卖机 | Emotional state enum models NPC disposition; state transitions require player effort; CURIOUS and HOSTILE states gate information |
| game-concept.md | Pillar 4 | 住客审问 -- NPC对话根据跨循环状态变化 | NPC state persists cross-loop via DeltaAccumulator; dialogue_availability is queryable; dialogue_id changes per night |
| game-concept.md | Core Mechanics #4 | 5个NPC有独立的动机、恐惧和谎言 | Per-NPC NPCTemplate resources allow individual configuration; NPCManager provides per-NPC queries |
| loop-state-management.md | Dependencies | NPC状态机注册路径 + propose_delta() | NPCManager.register_state_paths() registers all NPC paths; request_state_transition() uses propose_delta() |
| loop-state-management.md | Interactions | NPC状态属于模板状态层 -- 每夜重置 | NPCTemplate provides per-night baseline; LoopStateManager REBUILD resets template properties |
| systems-index.md | System #6 | NPC状态机 (NPC State Machine) -- depends on #1 | This ADR defines the complete NPC state machine |
| systems-index.md | System #13 | NPC信任/怀疑 -- depends on #6, #7 | NPC emotional state is an input to trust system; trust is NOT in this ADR's scope |
| systems-index.md | System #14 | 条件性对话树 -- depends on #6, #13 | get_emotional_state() and is_dialogue_available() provide query interface for dialogue branching |
| systems-index.md | System #9 | 事件调度器 -- depends on #5, #3, #6 | NPC state changes emit signals that event scheduler can consume |
| game-concept.md | Technical | NPC行为复杂度 -- MVP先做静态 | MVP uses static positions from NPCTemplate; architecture supports future scheduling via location property |

## Performance Implications

| Metric | Expected | Budget | Notes |
|--------|----------|--------|-------|
| CPU (frame time) | ~0.0ms idle, ~0.01ms per query | 0.1ms | No _process() in NPCManager. Queries are Dictionary lookups O(1). State transitions are propose_delta() calls (delegated to LoopStateManager). |
| Memory | ~2KB per NPC instance, ~10KB total for 5 NPCs | 512MB ceiling | NPCInstance is lightweight: enum + StringName + bool + Object ref. NPCTemplate resources are loaded on demand (~1KB each). |
| Load Time | 5 Resource loads per night change | Negligible | load() for 5 NPCTemplate .tres files. Small resources. Fallback path adds at most 1 extra load per NPC. |
| Network | N/A | N/A | Single-player game. |

## Migration Plan

New system. Implementation order:

1. **Define NPCEmotionalState enum and NPCTemplate Resource** -- no dependencies, can be authored immediately
2. **Implement NPCManager Autoload** -- requires LoopStateManager (ADR-0004) and InteractionBus (ADR-0006) to be Accepted and implementable
3. **Author NPCTemplate .tres files** -- for MVP: 3 NPCs x 3 nights = 9 template files
4. **Create NPC scene nodes** -- CharacterBody2D with Interactable component (target_type "npc"), sprite, and Area2D collision
5. **Wire NPCManager signals to downstream consumers** -- dialogue system, trust system, event scheduler (as those systems come online)

**Rollback plan**: NPCManager is an Autoload that can be removed from project settings without affecting LoopStateManager or InteractionBus. NPC scene nodes degrade to static sprites if NPCManager is absent.

## Validation Criteria

1. NPCManager registers state paths for all 5 NPCs on _ready()
2. night_ready signal triggers NPC initialization from NPCTemplate
3. get_emotional_state() returns NEUTRAL for unknown npc_id (no crash)
4. request_state_transition() accepts valid transitions and rejects invalid ones
5. State transitions call LoopStateManager.propose_delta() with correct target_path
6. propose_delta() rejection (returns false) does not change cached state or emit signal
7. npc_state_changed signal emitted only on accepted transitions with correct old/new values
8. npc_dialogue_availability_changed signal emitted when dialogue availability changes
9. _on_interaction_detected() filters for target_type "npc" only, ignores other types
10. npc_interaction_requested signal emitted with correct npc_id and event data
11. get_npc_ids_in_room() returns only NPCs whose location matches the queried room
12. NPCTemplate fallback chain works: night_N -> night_1 -> programmatic default
13. _is_valid_transition() blocks NEUTRAL -> FRIGHTENED (requires intermediate steps)
14. _is_valid_transition() allows ANXIOUS -> FRIGHTENED (valid path to extreme fear)
15. force_state_transition() bypasses validation and uses elevated priority
16. Serialization round-trip: NPC state restored correctly after save/load cycle
17. night_advanced re-initializes NPC cache from templates + DeltaAccumulator
18. No game logic in _on_interaction_detected() handler (boundary rule)
19. 5 NPCs x 3 state properties = 15 state paths registered with LoopStateManager

## Related Decisions

- ADR-0004: Loop State Management -- NPC state paths registered, propose_delta() for mutations, night_ready/night_advanced signals for lifecycle
- ADR-0006: Interaction Event Bus -- NPC click events delivered via interaction_detected signal
- ADR-0007: Room/Location Management -- NPC location is a room_id matching RoomManager's room registry
- ADR-0008: Countdown Timer -- TimerService pressure_level may influence NPC emotional state transitions (future integration point)
- System #13 (NPC Trust/Suspicion): Will read NPC emotional state via NPCManager.get_emotional_state() and produce trust/suspicion values that feed back into state transitions
- System #14 (Conditional Dialogue Trees): Will query NPCManager.get_emotional_state() and is_dialogue_available() for dialogue branching
- System #15 (Guest Interrogation / 住客审问): Will use npc_interaction_requested signal and request_state_transition() to drive interrogation mechanics
