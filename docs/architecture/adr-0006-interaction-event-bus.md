# ADR-0006: Interaction Event Bus

## Status
Accepted

## Date
2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Input |
| **Knowledge Risk** | LOW — uses standard Godot Area2D signals and GDScript |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, design/gdd/game-concept.md, design/gdd/systems-index.md |
| **Post-Cutoff APIs Used** | None — Area2D input_event signal exists since Godot 3.x |
| **Verification Required** | Test event dispatch with 10+ interactables in scene. Test long-press detection timing. Test touch vs mouse input_method tagging. Test long-press cancellation on touch/mouse exit. Test deferred priority resolution with overlapping interactables. **CRITICAL: Test on actual touch hardware** -- Area2D requires `input_pickable = true` AND at least one CollisionShape2D child for `input_event` to fire. Touch events (InputEventScreenTouch) must be verified to propagate to Area2D nodes in the scene tree, especially for interactables nested inside SubViewports or CanvasLayers with `follow_viewport_enabled = false`. Mouse emulation in editor is NOT sufficient for touch validation. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None — foundational core system |
| **Enables** | System #6 (点击交互), System #7 (长按交互), System #9 (线索发现 — receives interaction events), System #12 (NPC 对话触发), System #13 (房间导航) |
| **Blocks** | All Gameplay-layer interaction systems (#6, #7, #9, #12, #13) |
| **Ordering Note** | Should be Accepted before ADR-0004 and ADR-0005 in implementation order, as gameplay systems consume events first. Can be designed in parallel. |

## Context

### Problem Statement

七夜是点击式冒险游戏。玩家通过点击/长按与场景中的物体交互——检查物品、与NPC对话、发现线索、在房间间移动。需要一个统一的交互检测和分发机制，将输入事件路由到正确的游戏系统，同时支持鼠标和触摸输入。

### Constraints

- 所有交互同时支持鼠标和触摸
- 无 hover-only 交互（移动端兼容）
- 点击检测（检查/拾取）和长按检测（深入检查）必须区分
- 交互目标是场景中的 Area2D 节点
- 触摸目标最小 44px（移动端规范）
- 必须支持场景中多个可交互物体重叠时的优先级

### Requirements

- 统一的交互事件分发——所有点击/长按通过一个通道
- 事件包含：类型、目标、位置、输入方式、时间戳
- Interactable 组件可附加到任何 Area2D
- 消费者按 target_type 过滤事件
- 事件总线不包含任何游戏逻辑——纯检测和分发
- 桢缓冲优先级解析——同帧多个交互事件只分发最高优先级

## Decision

事件总线模式——InteractionBus 自动加载 + Interactable 可重用组件。分发采用桢缓冲延迟模式：同帧收集的事件在 _process 末尾统一解析，按优先级只分发最高优先级事件。

Interactable component is scoped to scene-world objects (Area2D) only. UI controls (Button, TextureButton on CanvasLayer 30+) use Godot's built-in signal system (pressed, toggled) and call UIManager directly, bypassing the InteractionBus.

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────┐
│                    InteractionBus (Autoload)               │
│                                                           │
│  signal interaction_detected(event: InteractionEvent)     │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Registered Interactables:                          │ │
│  │  Dictionary[StringName, InteractableInfo]           │ │
│  │  { target_id → { node, target_type, priority } }   │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │  Frame Buffer (deferred dispatch):                  │ │
│  │  _frame_buffer: Array[Dictionary]                   │ │
│  │  → _process resolves by priority                    │ │
│  │  → only highest-priority event emitted per frame    │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                           │
│  Event Flow:                                             │
│  Input (click/long-press)                                │
│    → Area2D input_event signal                           │
│    → Interactable component detects type                 │
│    → InteractionBus.emit_interaction() buffers event     │
│    → _process: _resolve_by_priority() picks best         │
│    → interaction_detected.emit(resolved_event)           │
│    → Consumers filter by target_type                     │
└───────────┬──────────────┬──────────────┬───────────────┘
            │              │              │
   ┌────────▼───────┐ ┌───▼────────┐ ┌───▼──────────┐
   │ ClueDiscovery  │ │NPCManager  │ │RoomManager   │
   │ (target_type:  │ │(target_type:│ │(target_type:  │
   │  "item")       │ │ "npc")     │ │ "exit")       │
   └────────────────┘ └────────────┘ └────────────────┘
```

### Key Interfaces

**InteractionBus (Autoload Singleton)**:
```gdscript
class_name InteractionBus
extends Node

signal interaction_detected(event: Dictionary)

var _frame_buffer: Array[Dictionary] = []

func register_interactable(id: StringName, info: Dictionary) -> void
func unregister_interactable(id: StringName) -> void

func emit_interaction(event: Dictionary) -> void:
    _frame_buffer.append(event)

func _process(_delta: float) -> void:
    if _frame_buffer.is_empty(): return
    var resolved := _resolve_by_priority(_frame_buffer)
    interaction_detected.emit(resolved)
    _frame_buffer.clear()

func _resolve_by_priority(events: Array[Dictionary]) -> Dictionary:
    # Return highest-priority event from the buffer
    var best := events[0]
    for event in events:
        if event["priority"] > best["priority"]:
            best = event
    return best
```

**InteractionEvent**:
```gdscript
# Event dictionary emitted by InteractionBus
{
    "type": int,                    # InteractionType.CLICK or LONG_PRESS
    "target_id": StringName,        # unique interactable identifier
    "target_type": StringName,      # "item", "npc", "exit", "environment"
    "position": Vector2,            # world position of interaction
    "input_method": int,            # InputMethod.MOUSE or TOUCH
    "timestamp": float,             # Time.get_ticks_msec() at detection
    "metadata": Dictionary          # extensible per-interactable data
}

enum InteractionType { CLICK, LONG_PRESS }
enum InputMethod { MOUSE, TOUCH }
```

**Interactable Component**:
```gdscript
# Attach to any Area2D to make it interactable
extends Area2D

@export var target_id: StringName
@export var target_type: StringName  # "item", "npc", "exit", "environment"
@export var long_press_duration: float = 0.5  # seconds
@export var priority: int = 0  # higher = processed first when overlapping

var _press_timer: float = 0.0
var _is_pressed: bool = false
var _input_method: int = 0

func _ready() -> void:
    input_pickable = true  # guard against designer unchecking in editor
    InteractionBus.register_interactable(target_id, {
        "node": self,
        "target_type": target_type,
        "priority": priority
    })
    input_event.connect(_on_input_event)
    mouse_exited.connect(_on_mouse_exit)  # cancel long-press on cursor leave

# IMPORTANT: Area2D.input_event requires both input_pickable = true AND
# at least one CollisionShape2D/CollisionPolygon2D child defining the clickable
# region. Without a collision shape, the signal will never fire.
# For touch (InputEventScreenTouch): verify that touch events propagate
# correctly to Area2D nodes in the game scene tree, especially if interactables
# are nested inside SubViewports or CanvasLayers with follow_viewport_enabled = false.
# Test on actual touch hardware, not just mouse emulation.

func _process(delta: float) -> void:
    if not _is_pressed: return
    _press_timer += delta
    if _press_timer >= long_press_duration:
        _is_pressed = false
        InteractionBus.emit_interaction({
            "type": InteractionType.LONG_PRESS,
            "target_id": target_id,
            "target_type": target_type,
            "position": global_position,
            "input_method": _input_method,
            "timestamp": Time.get_ticks_msec(),
            "priority": priority,
            "metadata": {}
        })

func _on_mouse_exit() -> void:
    # Cancel long-press if cursor leaves Area2D during hold
    _is_pressed = false
    _press_timer = 0.0

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
    if event is InputEventScreenTouch:
        if event.canceled:
            _is_pressed = false
            _press_timer = 0.0
            return
        if event.pressed:
            _is_pressed = true
            _press_timer = 0.0
            _input_method = InputMethod.TOUCH
        else:
            if _is_pressed and _press_timer < long_press_duration:
                InteractionBus.emit_interaction({
                    "type": InteractionType.CLICK,
                    "target_id": target_id,
                    "target_type": target_type,
                    "position": event.position,
                    "input_method": _input_method,
                    "timestamp": Time.get_ticks_msec(),
                    "priority": priority,
                    "metadata": {}
                })
            _is_pressed = false
            _press_timer = 0.0
    elif event is InputEventMouseButton:
        if event.pressed:
            _is_pressed = true
            _press_timer = 0.0
            _input_method = InputMethod.MOUSE
        else:
            if _is_pressed and _press_timer < long_press_duration:
                InteractionBus.emit_interaction({
                    "type": InteractionType.CLICK,
                    "target_id": target_id,
                    "target_type": target_type,
                    "position": event.position,
                    "input_method": _input_method,
                    "timestamp": Time.get_ticks_msec(),
                    "priority": priority,
                    "metadata": {}
                })
            _is_pressed = false
            _press_timer = 0.0

func _exit_tree() -> void:
    InteractionBus.unregister_interactable(target_id)
```

## Alternatives Considered

### Alternative 1: Direct Signal Per Interactable

- **Description**: Each interactable emits its own signal; consumers connect directly
- **Pros**: No central bus; simpler for small number of interactables
- **Cons**: Consumers must connect/disconnect for every interactable added/removed; no unified filtering; hard to debug event flow
- **Rejection Reason**: Central bus provides unified logging, filtering, and debug overlay. Point-and-click game has many interactables — direct connections would be unmanageable.

### Alternative 2: Godot Input Map

- **Description**: Use Godot's built-in InputMap for interaction actions
- **Pros**: Engine-native; supports input rebinding
- **Cons**: InputMap is for global actions (jump, shoot), not per-object interactions; cannot distinguish which Area2D was clicked; no target_type filtering
- **Rejection Reason**: InputMap solves a different problem. Interactions are spatial (what did I click?) not action-based (what button did I press?).

### Alternative 3: Raycast-Based Detection

- **Description**: Cast physics ray from click position; determine interactable from collision
- **Pros**: No Area2D signal overhead; works with any collision shape
- **Cons**: Requires physics processing every frame; priority resolution more complex; Area2D input_event is already the idiomatic Godot pattern for 2D
- **Rejection Reason**: Area2D.input_event is designed exactly for this use case. Raycasting adds unnecessary physics overhead for a 2D point-and-click game.

## Consequences

### Positive

- Single event channel simplifies debugging and logging
- Interactable component is reusable — attach to any Area2D
- target_type filtering keeps consumers focused on their domain
- Input method tagging enables platform-specific feedback (hover for mouse, highlight for touch)
- Clean separation: detection (bus) vs consequence (consumers)
- Deferred dispatch resolves overlap priority deterministically — only one event emitted per frame
- Frame buffer prevents signal flood — multiple overlapping interactables produce a single resolved event

### Negative

- All interactions go through one signal — if many consumers don't filter early, unnecessary processing
- Interactable component must be added to every clickable object — authoring overhead
- Long-press detection adds frame-by-frame timer in _process
- Debug overlay needed to visualize interactable zones during development
- Deferred dispatch adds one frame of latency between detection and delivery — acceptable for adventure game pacing but would be unsuitable for action games

### Risks

- **Signal flood**: If player clicks rapidly, many events buffer. Mitigation: deferred dispatch already de-duplicates per frame; InteractionBus can throttle (debounce 100ms) if needed beyond frame-level.
- **Overlap priority**: When two Area2Ds overlap, both receive input_event. Mitigation: _resolve_by_priority picks highest-priority event from frame buffer.
- **Input latency**: Long-press detection adds 0.5s delay before event. Mitigation: show visual feedback during press to indicate detection in progress.
- **Metadata scope creep**: Consumers may be tempted to embed game logic in metadata. Mitigation: documented boundary rule (see Boundary Rules below).

### Boundary Rules

- **InteractionEvent.metadata must never carry game logic** (e.g., `should_trigger_cutscene`). The bus boundary is strict: detection + dispatch only. Game logic belongs in consumers. Metadata is reserved for context data that helps consumers identify *what* was interacted with, not *what to do about it*.

## Conventions

- **target_id naming**: `target_id` on Interactable scene objects matches `clue_id` in ClueDatabase for discoverable items. NPC targets use the same `npc_id` as the NPC state machine. This eliminates the need for a mapping layer between the interaction system and downstream consumers.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-concept.md | 点击式冒险游戏核心交互 | InteractionBus + Interactable component for all click/tap interactions |
| technical-preferences.md | 触摸 Full | All interactions tagged with input_method; no hover-only interactions |
| technical-preferences.md | No hover-only interactions | Only CLICK and LONG_PRESS event types; hover is visual feedback only |
| systems-index.md | System #6 (点击交互) | CLICK event type via Interactable |
| systems-index.md | System #7 (长按交互) | LONG_PRESS event type with configurable duration |
| systems-index.md | TD Concern #2 | Resolves: event bus pattern, not god object — bus only detects and dispatches |
| art-bible.md Sec 7 | 移动端湿光泽 | Interactable metadata can include wet-sheen cycling parameters |

## Performance Implications

- **CPU**: One signal emission per interaction. _process only active during press for long-press detection. Deferred dispatch adds one Dictionary comparison loop per frame when buffer is non-empty — O(n) where n is overlapping interactables (typically ≤ 5). Negligible.
- **Memory**: One Dictionary entry per registered interactable. Frame buffer holds at most one event per interactable per frame. Expected ≤ 30 per scene.
- **Load Time**: register_interactable() on each Area2D._ready() — O(n) per scene load.
- **Network**: N/A

## Migration Plan

New system. Implementation order: InteractionBus → Interactable component → Consumer systems (ClueDiscovery, NPCManager, RoomManager).

## Validation Criteria

1. CLICK event emitted on mouse click and touch tap
2. LONG_PRESS event emitted after 0.5s sustained press
3. LONG_PRESS canceled when finger/cursor leaves Area2D before threshold
4. InputEventScreenTouch.canceled resets press state (no spurious event emitted)
5. Input method correctly tagged (MOUSE vs TOUCH)
6. target_id and target_type correctly populated
7. Timestamp field populated with Time.get_ticks_msec() value
8. Overlapping interactables resolved by priority via deferred dispatch
9. Only one event emitted per frame when multiple interactables fire simultaneously
10. Unregister on _exit_tree prevents stale events
11. Debug overlay shows all interactable zones
12. Minimum touch target 44px enforced in Interactable setup
13. input_pickable forced true in _ready() regardless of editor setting
14. metadata field contains no game logic keys at emission time
15. Touch events verified on actual touch hardware (not mouse emulation) -- Area2D with input_pickable=true and CollisionShape2D child receives InputEventScreenTouch correctly

## Related Decisions

- ADR-0003: UI Visual Register — HUD seal buttons are interactables
- ADR-0004: Loop State Management — some interactions trigger consequence registration
- ADR-0005: Clue/Insight Unified Schema — clue discovery is a consumer of interaction events
- Technical Preferences: Input & Platform — touch support requirements
- UIManager: UI controls (CanvasLayer 30+) bypass InteractionBus entirely
