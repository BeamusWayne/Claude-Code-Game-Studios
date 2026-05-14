# ADR-0014: Event Scheduler

## Status

Accepted

## Date

2026-05-14

## Accepted

2026-05-15

## Last Verified

2026-05-14

## Decision Makers

systems-designer, game-designer

## Summary

EventScheduler Autoload 单例 + ScriptedEvent Resource 数据驱动。每夜从 .tres 文件加载事件列表，支持三种触发器（TIME/CONDITION/COMPOUND），执行四种动作（move_npc/start_dialogue/change_room_state/emit_custom_signal）。事件每夜最多触发一次，夜晚过渡时重置。

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Gameplay / Scripting |
| **Knowledge Risk** | LOW — uses standard Resource system, signals, and _process() |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, design/gdd/event-scheduler.md, design/gdd/countdown-timer.md, design/gdd/npc-state-machine.md, design/gdd/night-transition-controller.md |
| **Post-Cutoff APIs Used** | None — Resource, Array[CustomResource], signals exist since Godot 4.0 |
| **Verification Required** | Test TIME trigger fires within 1 frame of threshold. Test CONDITION trigger fires on signal reception. Test COMPOUND trigger requires both conditions. Test fired_events prevents re-trigger. Test night_advanced clears state. Test load_night_events with missing .tres returns empty list. Test MAX_EVENTS_PER_FRAME cap. Test serialize/deserialize round-trip preserves fired_events. Test force_trigger skips already-fired events. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (Loop State Management — reads current_night, listens to night_ready/night_advanced), ADR-0008 (Countdown Timer — reads remaining_time/total_duration/current_phase, listens to phase_changed), ADR-0007 (Room/Location Management — reads room state, executes change_room_state), ADR-0009 (NPC State Machine — reads NPC position/state, executes move_npc), ADR-0011 (Night Transition Controller — listens to transition_complete) |
| **Enables** | System #14 (Conditional Dialogue Trees — start_dialogue action target), System #24 (Audio System — emit_custom_signal for audio triggers), System #23 (Ending Trigger Logic — event-driven ending conditions) |
| **Blocks** | System #24 (Audio System), narrative event-driven content in Feature Layer |
| **Ordering Note** | Should be Accepted after ADR-0004, ADR-0008, ADR-0009 (NPC State Machine). Can be designed in parallel with dialogue and trust systems. Implementation should follow TimerService, NPCManager, and RoomManager. |

## Context

### Problem Statement

七夜是一款时间循环冒险游戏，每夜有有限的时间。NPC 需要在特定时间移动到不同房间，环境需要随时间变化，对话需要在特定条件下解锁。这些"世界运转"的事件需要一个统一的调度机制。目前没有系统负责在正确的时间触发正确的脚本事件——NPC 位置是静态的，环境不会变化，对话解锁是手动触发的。

### Constraints

- 事件定义必须是数据驱动的（Resource .tres），设计师可在编辑器中配置
- MVP 不包含可视化脚本编辑器或嵌套条件——保持简单
- 事件触发必须精确到帧级别（TIME 触发器不能遗漏）
- 事件每夜最多触发一次（防止重复）
- 夜晚过渡必须完全重置事件状态
- 事件动作的执行委托给目标系统——EventScheduler 不包含游戏逻辑

### Requirements

- 三种触发器类型：TIME（时间阈值）、CONDITION（状态匹配）、COMPOUND（两者兼需）
- 四种动作类型：move_npc、start_dialogue、change_room_state、emit_custom_signal
- 每夜从 Resource 文件加载事件列表
- fired_events 集合防止重复触发
- 夜晚过渡时重置并加载新夜事件
- 序列化支持（保存已触发事件集合）
- 同帧多事件的优先级排序

## Decision

EventScheduler Autoload 单例 + ScriptedEvent Resource 数据驱动。事件定义存储在 Godot Resource 文件中（每夜一个 .tres），由 EventScheduler 在 night_ready 时加载。TIME 和 COMPOUND 触发器在 _process() 中检查 TimerService.remaining_time。CONDITION 触发器通过监听上游系统信号（NPCManager、ClueDatabase、RoomManager、TimerService）进行评估。动作执行委托给目标系统的公共接口。

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│              EventScheduler (Autoload)                       │
│                                                              │
│  State:                                                      │
│    pending_events: Array[ScriptedEvent]                      │
│    fired_events: Set[StringName]                             │
│    loaded_night: int (-1 = not loaded)                       │
│    _events_processed_this_frame: int                         │
│                                                              │
│  Signals (emitted):                                          │
│    event_triggered(event_id: StringName, actions: Array)     │
│    night_events_loaded(night: int, event_count: int)         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Trigger Evaluation (_process + signal handlers):     │    │
│  │                                                       │    │
│  │  TIME:      elapsed >= trigger_time                   │    │
│  │  CONDITION: all cond.type checks pass                 │    │
│  │  COMPOUND:  TIME AND CONDITION                        │    │
│  │                                                       │    │
│  │  All: must NOT be in fired_events                     │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  Action Dispatch (after trigger):                     │    │
│  │                                                       │    │
│  │  move_npc         -> NPCManager.move_npc_to_room()    │    │
│  │  start_dialogue   -> UIManager.start_dialogue()       │    │
│  │  change_room_state -> RoomManager.set_room_state()    │    │
│  │  emit_custom_signal -> InteractionBus.dispatch()       │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  Lifecycle:                                                  │
│  night_ready -> load_night_events(night)                     │
│  _process -> check TIME/COMPOUND triggers                    │
│  signal handlers -> check CONDITION triggers                 │
│  night_advanced -> clear fired_events + pending_events       │
│  transition_complete -> load_night_events(new_night)         │
└──────┬───────────┬───────────┬──────────┬────────────────────┘
       │           │           │          │
  ┌────▼────┐ ┌────▼────┐ ┌───▼───┐ ┌───▼──────────┐
  │ Timer   │ │ NPC     │ │ Room  │ │ LoopState    │
  │ Service │ │ Manager │ │ Mgr   │ │ Manager      │
  │ (reads  │ │ (reads  │ │(reads │ │ (reads       │
  │ remain, │ │ npc     │ │ room  │ │ night, flags)│
  │ phase)  │ │ pos,    │ │ state)│ │              │
  │         │ │ emotion)│ │       │ │              │
  └─────────┘ └─────────┘ └───────┘ └──────────────┘
```

### Key Interfaces

**ScriptedEvent Resource**:
```gdscript
class_name ScriptedEvent
extends Resource

enum TriggerType { TIME, CONDITION, COMPOUND }

@export var event_id: StringName
@export var trigger_type: TriggerType
@export var trigger_time: float = 0.0
@export var trigger_conditions: Array[EventCondition] = []
@export var actions: Array[EventAction] = []
@export var priority: int = 0
```

**EventCondition Resource**:
```gdscript
class_name EventCondition
extends Resource

enum ConditionType {
    NPC_IN_ROOM,
    NPC_EMOTIONAL_STATE,
    CLUE_DISCOVERED,
    ROOM_STATE,
    CUSTOM_FLAG,
    PHASE_IS
}

@export var type: ConditionType
@export var npc_id: StringName
@export var room_id: StringName
@export var clue_id: StringName
@export var state: int               # NPC emotional state or PressurePhase
@export var state_key: StringName    # for ROOM_STATE
@export var value: Variant           # for ROOM_STATE expected value
@export var flag_path: String        # for CUSTOM_FLAG
```

**EventAction Resource**:
```gdscript
class_name EventAction
extends Resource

enum ActionType { MOVE_NPC, START_DIALOGUE, CHANGE_ROOM_STATE, EMIT_CUSTOM_SIGNAL }

@export var type: ActionType
@export var npc_id: StringName
@export var target_room: StringName
@export var dialogue_id: StringName
@export var room_id: StringName
@export var state_key: StringName
@export var value: Variant
@export var signal_name: StringName
@export var signal_args: Dictionary = {}
```

**EventScheduler (Autoload Singleton)**:
```gdscript
class_name EventScheduler
extends Node

signal event_triggered(event_id: StringName, actions: Array[EventAction])
signal night_events_loaded(night: int, event_count: int)

const MAX_EVENTS_PER_FRAME: int = 5

var pending_events: Array[ScriptedEvent] = []
var fired_events: Dictionary = {}  # StringName -> true (set emulation)
var loaded_night: int = -1

func _ready() -> void:
    LoopStateManager.night_ready.connect(_on_night_ready)
    LoopStateManager.night_advanced.connect(_on_night_advanced)
    NightTransitionController.transition_complete.connect(_on_transition_complete)
    # Connect to condition signal sources
    TimerService.phase_changed.connect(_on_condition_signal)
    # NPCManager, ClueDatabase, RoomManager signals connected similarly
    set_process(false)

func load_night_events(night: int) -> void:
    _clear_state()
    var path := "res://assets/data/events/night_{0}_events.tres".format([night])
    if ResourceLoader.exists(path):
        var night_events: NightEvents = load(path)
        if night_events:
            pending_events = night_events.events.duplicate()
            loaded_night = night
            set_process(true)
            night_events_loaded.emit(night, pending_events.size())
    else:
        loaded_night = night
        set_process(false)

func force_trigger(event_id: StringName) -> void:
    if fired_events.has(event_id):
        return
    var event := _find_pending_event(event_id)
    if event == null:
        return
    _execute_event(event)

func _process(delta: float) -> void:
    if pending_events.is_empty():
        return
    var events_this_frame := 0
    var elapsed := TimerService.total_duration - TimerService.remaining_time

    # Sort by priority descending
    pending_events.sort_custom(func(a, b): return a.priority > b.priority)

    var to_fire: Array[ScriptedEvent] = []
    for event in pending_events:
        if events_this_frame >= MAX_EVENTS_PER_FRAME:
            break
        if fired_events.has(event.event_id):
            continue
        if _should_fire(event, elapsed):
            to_fire.append(event)
            events_this_frame += 1

    for event in to_fire:
        _execute_event(event)

func _should_fire(event: ScriptedEvent, elapsed: float) -> bool:
    match event.trigger_type:
        ScriptedEvent.TriggerType.TIME:
            return elapsed >= event.trigger_time
        ScriptedEvent.TriggerType.CONDITION:
            return _evaluate_all_conditions(event.trigger_conditions)
        ScriptedEvent.TriggerType.COMPOUND:
            return (elapsed >= event.trigger_time
                and _evaluate_all_conditions(event.trigger_conditions))
    return false

func _evaluate_all_conditions(conditions: Array[EventCondition]) -> bool:
    for cond in conditions:
        if not _evaluate_condition(cond):
            return false
    return true

func _evaluate_condition(cond: EventCondition) -> bool:
    match cond.type:
        EventCondition.ConditionType.NPC_IN_ROOM:
            return NPCManager.get_npc_position(cond.npc_id) == cond.room_id
        EventCondition.ConditionType.NPC_EMOTIONAL_STATE:
            return NPCManager.get_npc_state(cond.npc_id) == cond.state
        EventCondition.ConditionType.CLUE_DISCOVERED:
            return ClueDatabase.has_clue(cond.clue_id)
        EventCondition.ConditionType.ROOM_STATE:
            return RoomManager.get_room_state(cond.room_id, cond.state_key) == cond.value
        EventCondition.ConditionType.CUSTOM_FLAG:
            return LoopStateManager.get_state(cond.flag_path) == true
        EventCondition.ConditionType.PHASE_IS:
            return TimerService.current_phase == cond.phase
    return false

func _execute_event(event: ScriptedEvent) -> void:
    fired_events[event.event_id] = true
    for action in event.actions:
        _execute_action(action)
    event_triggered.emit(event.event_id, event.actions)

func _execute_action(action: EventAction) -> void:
    match action.type:
        EventAction.ActionType.MOVE_NPC:
            NPCManager.move_npc_to_room(action.npc_id, action.target_room)
        EventAction.ActionType.START_DIALOGUE:
            UIManager.start_dialogue(action.dialogue_id, action.npc_id)
        EventAction.ActionType.CHANGE_ROOM_STATE:
            RoomManager.set_room_state(action.room_id, action.state_key, action.value)
        EventAction.ActionType.EMIT_CUSTOM_SIGNAL:
            InteractionBus.dispatch_custom(action.signal_name, action.signal_args)

func _on_condition_signal(_args = null) -> void:
    # Re-evaluate all CONDITION events
    for event in pending_events:
        if event.trigger_type in [ScriptedEvent.TriggerType.CONDITION,
                                   ScriptedEvent.TriggerType.COMPOUND]:
            if not fired_events.has(event.event_id):
                if _should_fire(event,
                    TimerService.total_duration - TimerService.remaining_time):
                    _execute_event(event)

func _on_night_ready(night: int) -> void:
    load_night_events(night)

func _on_night_advanced(_night: int) -> void:
    _clear_state()

func _on_transition_complete(night: int) -> void:
    load_night_events(night)

func _clear_state() -> void:
    pending_events.clear()
    fired_events.clear()
    loaded_night = -1
    set_process(false)

func _find_pending_event(event_id: StringName) -> ScriptedEvent:
    for event in pending_events:
        if event.event_id == event_id:
            return event
    return null

func serialize() -> Dictionary:
    return {
        "fired_events": fired_events.keys(),
        "loaded_night": loaded_night
    }

func deserialize(data: Dictionary) -> void:
    fired_events.clear()
    for event_id in data.get("fired_events", []):
        fired_events[event_id] = true
    var night: int = data.get("loaded_night", -1)
    if night >= 1:
        load_night_events(night)
        # Re-mark fired events after loading (load_night_events clears them)
        for event_id in data.get("fired_events", []):
            fired_events[event_id] = true

func reset() -> void:
    _clear_state()
```

### NightEvents Resource (Container):
```gdscript
class_name NightEvents
extends Resource

@export var events: Array[ScriptedEvent] = []
```

### Implementation Guidelines

1. EventScheduler must NOT contain game logic — it schedules and dispatches only.
2. All condition evaluations must fail gracefully (return false) for missing entities.
3. The _process() check must sort a copy of pending_events, not mutate the original order.
4. Signal connections to upstream systems should be established in _ready(), not dynamically.
5. force_trigger() is the only public API for external code to trigger events — use it sparingly.

## Alternatives Considered

### Alternative 1: Timer-Based Individual Nodes

- **Description**: Attach Timer nodes to each event, fire individually
- **Pros**: No central scheduler; events are self-contained scene elements
- **Cons**: Cannot express CONDITION or COMPOUND triggers; no global priority ordering; night reset requires finding and resetting all Timer nodes; no serialization of fired state in one place
- **Rejection Reason**: TIME-only triggers are insufficient for the game's needs (NPC movements depend on game state, not just time). Central scheduling provides unified lifecycle management and serialization.

### Alternative 2: Hardcoded Script Events

- **Description**: Write events directly in GDScript per-night scripts
- **Pros**: Maximum flexibility; no data format design needed
- **Cons**: Non-data-driven; designers cannot edit in editor; requires programmer for every event change; no separation between event definition and execution
- **Rejection Reason**: Violates the project's data-driven design principle (coding-standards.md: "Gameplay values must be data-driven"). Resource-based definition allows designer iteration without code changes.

### Alternative 3: Event Graph / Visual Scripting

- **Description**: Visual node-based event editor
- **Pros**: Very designer-friendly; supports complex logic chains
- **Cons**: Scope too large for MVP; requires custom editor plugin; testing complexity; Godot's VisualShader is rendering-only
- **Rejection Reason**: User explicitly requested MVP simplicity ("no visual scripting, no nested conditions"). Can be evaluated for Vertical Slice or Polish phase.

## Consequences

### Positive

- Data-driven event definition allows designers to iterate on NPC schedules, timed dialogue, and environmental changes without code changes
- Three trigger types cover all identified use cases (timed NPC movements, state-driven dialogue unlocks, combined conditions)
- Unified lifecycle management (load/trigger/reset) prevents scattered event state across systems
- EventScheduler is a pure dispatcher — it does not own game state, consistent with InteractionBus boundary pattern (ADR-0006)
- Serialization is minimal (just fired_events set + loaded_night), reducing save/load complexity
- Resource-based definition is testable offline (load .tres, verify trigger/action fields)

### Negative

- One more Autoload in the project (total: InteractionBus, LoopStateManager, TimerService, NPCManager, RoomManager, NightTransitionController, EventScheduler)
- CONDITION triggers require signal connections to multiple upstream systems — new condition types require code changes to EventScheduler
- _process() runs every frame during active night — iterating all pending TIME/COMPOUND events adds per-frame cost
- Action execution is fire-and-forget — if NPCManager.move_npc_to_room() fails, the event is still marked as fired

### Risks

- **Event explosion**: Each night could define dozens of events, increasing _process() iteration cost. Mitigation: MAX_EVENTS_PER_FRAME cap. For MVP (3 rooms, 3-5 NPCs), expected 5-15 events per night.
- **Condition signal frequency**: If NPCManager emits state change signals frequently, _on_condition_signal could re-evaluate many events per frame. Mitigation: CONDITION_RECHECK_INTERVAL throttle (default 0.0 for MVP, tunable if needed).
- **Action failure propagation**: move_npc on a non-existent NPC ID silently fails but event is marked fired. Mitigation: _execute_action should validate target existence before dispatching; log warnings on failure.
- **Night transition ordering**: If night_advanced fires before transition_complete, events could be loaded twice. Mitigation: night_advanced clears state; transition_complete loads new night. The order is guaranteed by NightTransitionController's 8-step sequence (ADVANCE_NIGHT is step 4, COMPLETE is step 8).

## Boundary Rules

- **EventScheduler must not modify game state directly**. All state changes go through target system interfaces (NPCManager.move_npc_to_room, RoomManager.set_room_state, etc.). EventScheduler only manages its own fired_events tracking.
- **Events are dispatch-only**. EventScheduler does not interpret what actions mean — it maps action types to system calls. Business logic (can this NPC move right now?) is the target system's responsibility.
- **Event resources are read-only at runtime**. EventScheduler loads .tres files but never modifies them. All runtime state (fired_events) is in EventScheduler's own variables.

## Conventions

- Event IDs follow format `night{N}_{descriptor}` (e.g., `night1_indigo_to_garden`, `night3_study_light_off`). This namespace makes debugging and save file inspection easier.
- NightEvents resources are stored in `assets/data/events/` to separate data from code.
- EventAction enum values (MOVE_NPC, START_DIALOGUE, CHANGE_ROOM_STATE, EMIT_CUSTOM_SIGNAL) are intentionally distinct from InteractionBus event types to prevent confusion.

## Performance Implications

| Metric | Before | Expected After | Budget |
|--------|--------|---------------|--------|
| CPU (frame time) | 0ms | <0.05ms | 16.6ms total |
| Memory | 0KB | ~2KB per night | 512MB ceiling |
| Load Time | 0ms | ~1ms per .tres | - |

- _process() iterates pending_events array (O(n) per frame, n = 5-15 for MVP). With sort_custom, this is O(n log n) but n is tiny.
- Signal-driven CONDITION evaluation runs only when upstream signals fire, not every frame.
- set_process(false) when no events are loaded eliminates all per-frame cost.

## Migration Plan

新系统。实现顺序：EventScheduler -> 创建 ScriptedEvent/EventCondition/EventAction/NightEvents Resource 类 -> 创建 night_1_events.tres 测试数据 -> 集成 NightTransitionController.transition_complete 信号。

GDD 更新：systems-index.md 将 System #9 状态更新为 "GDD Complete"。countdown-timer.md、npc-state-machine.md、night-transition-controller.md 的下游依赖已列出 EventScheduler。

## Validation Criteria

- [ ] TIME trigger fires within 1 frame of elapsed_time crossing trigger_time threshold
- [ ] CONDITION trigger fires within 1 frame of signal reception
- [ ] COMPOUND trigger fires only when both TIME and CONDITION are met
- [ ] fired_events prevents duplicate triggering within a night
- [ ] night_advanced clears all event state
- [ ] load_night_events with missing .tres returns empty list without errors
- [ ] force_trigger works for pending events, skips fired events
- [ ] serialize/deserialize preserves fired_events across save/load
- [ ] MAX_EVENTS_PER_FRAME cap prevents frame spikes
- [ ] Action dispatch calls correct target system methods
- [ ] Condition evaluation returns false for missing entities (no crash)
- [ ] set_process(false) when no events are loaded

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| design/gdd/event-scheduler.md | Event Scheduler #9 | 三种触发器 (TIME/CONDITION/COMPOUND) | TriggerType enum + _should_fire() dispatcher |
| design/gdd/event-scheduler.md | Event Scheduler #9 | 四种动作 (move_npc/start_dialogue/change_room_state/emit_custom_signal) | EventAction resource + _execute_action() dispatcher |
| design/gdd/event-scheduler.md | Event Scheduler #9 | 每夜事件从 Resource 加载 | load_night_events() loads from night_{N}_events.tres |
| design/gdd/event-scheduler.md | Event Scheduler #9 | 事件每夜触发一次 | fired_events set + membership check in _should_fire() |
| design/gdd/event-scheduler.md | Event Scheduler #9 | 夜晚过渡重置 | night_advanced signal -> _clear_state() |
| design/gdd/countdown-timer.md | Countdown Timer #5 | 事件调度器消费 phase_changed | EventScheduler listens to TimerService.phase_changed |
| design/gdd/npc-state-machine.md | NPC State Machine #6 | 事件调度器基于 NPC 状态调度 | EventCondition.NPC_IN_ROOM + NPC_EMOTIONAL_STATE |
| design/gdd/night-transition-controller.md | Night Transition #8 | transition_complete -> reload events | EventScheduler listens to transition_complete signal |
| design/gdd/systems-index.md | CD Concern #1 | 节奏规则 | PHASE_IS condition type + TIME triggers for scheduled moments |
| game-concept.md | Pillar 2 | 时间在低语与咆哮之间交替 | Events driven by TimerService phases and remaining time |

## Related

- ADR-0004: Loop State Management — provides night_ready/night_advanced signals, current_night, custom_flag state
- ADR-0006: Interaction Event Bus — same boundary pattern (dispatch-only, no game logic)
- ADR-0007: Room/Location Management — target for change_room_state actions, source for room_state conditions
- ADR-0008: Countdown Timer — source for remaining_time/total_duration/current_phase, phase_changed signal
- ADR-0009: NPC State Machine — target for move_npc actions, source for NPC position/state conditions
- ADR-0011: Night Transition Controller — provides transition_complete signal for event reload
