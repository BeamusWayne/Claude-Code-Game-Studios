# ADR-0007: Room/Location Management

## Status
Accepted

## Date
2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Scene Management |
| **Knowledge Risk** | LOW — uses standard Godot PackedScene, Node2D, and CanvasLayer APIs |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, design/gdd/game-concept.md, design/gdd/systems-index.md |
| **Post-Cutoff APIs Used** | None — PackedScene.instantiate(), Node.add_child/remove_child are stable since Godot 3.x |
| **Verification Required** | Test room transition with 5 sequential loads (no memory leak). Test template reset restores all room state. Test interactable registration/unregistration on transition. Test fade overlay hides unload/load artifacts. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (loop-state-management) — RoomManager listens to night_advanced for template resets. ADR-0006 (interaction-event-bus) — exit interactables emit navigation events via InteractionBus. |
| **Enables** | System #3 (交互系统 — depends on room structure), System #9 (事件调度器 — schedules by room), System #17 (房间导航 UI) |
| **Blocks** | System #7 (交互系统), System #9 (事件调度器), System #17 (房间导航 UI), all room-dependent gameplay |
| **Ordering Note** | Must be Accepted before interaction system GDD. Can be designed in parallel with countdown-timer ADR. |

## Context

### Problem Statement

七夜的核心体验是在山间旅馆中探索。旅馆有 8 个房间（MVP 3 个），玩家通过点击出口在房间间移动。需要决定：(1) 房间场景如何加载和卸载？(2) 房间状态如何与循环状态架构（ADR-0004）集成？(3) 房间内的可交互物如何注册到 InteractionBus（ADR-0006）？(4) 房间切换的视觉过渡如何处理？

### Constraints

- 旅馆固定 8 房间，MVP 3 房间（大厅、走廊、客房 A）
- 同时只有一个房间可见（单房间视图）
- 房间切换需要视觉过渡（淡入淡出），不能突然切换
- 房间状态属于 ADR-0004 的 Template State 层——每夜重置
- 房间内可交互物必须在进入时注册、离开时注销（ADR-0006）
- 80% 的游戏时间在当前房间内——房间加载性能影响整体体验

### Requirements

- 按需加载/卸载房间场景
- 房间状态与 Template State 层集成——advance_night() 重置房间状态
- 可交互物生命周期管理——注册/注销与房间切换绑定
- 过渡动画——淡出/淡入掩盖场景切换
- 房间状态查询接口——供其他系统读取当前房间属性

## Decision

按需 PackedScene 加载/卸载模式。RoomManager autoload 单例管理房间生命周期。

### Architecture Diagram

```
┌───────────────────────────────────────────────────────┐
│                RoomManager (Autoload)                  │
│                                                       │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │Room Registry │  │Active Room   │  │Room Cache   │  │
│  │(room_id →   │  │(current      │  │(loaded       │  │
│  │ PackedScene │  │ scene inst.) │  │ PackedScenes)│  │
│  │ path)       │  │              │  │              │  │
│  └─────────────┘  └──────────────┘  └─────────────┘  │
│                                                       │
│  request_transition(room_id)                          │
│    → fade-out → unload → load → apply state →         │
│      register interactables → fade-in → emit          │
│                                                       │
│  apply_template_reset() ← night_advanced signal       │
│  register_room_interactables() / unregister...()      │
│       ↕ ADR-0006 InteractionBus                       │
└───────────────────────────────────────────────────────┘
         │                           │
    ┌────▼─────┐              ┌──────▼──────┐
    │RoomScene │              │InteractionBus│
    │(.tscn)   │              │(ADR-0006)   │
    │          │              └─────────────┘
    │ Background│
    │ Interact. │    ┌──────────────────┐
    │ NPCs      │    │LoopStateManager  │
    │ Exits     │    │(ADR-0004)        │
    └───────────┘    └──────────────────┘
```

### Room Scene Structure Convention

每个房间场景 (.tscn) 遵循固定节点层级：

```
Room_[id] (Node2D) — root
├── Background (Node2D, z:-10) — 背景美术层
├── Interactables (Node2D, z:0) — 可交互物体（带 Area2D 子节点）
├── NPCs (Node2D, z:1) — NPC 节点
├── Exits (Node2D, z:2) — 出口区域（带 Area2D 子节点 + Exit 组件）
└── NavigationRegions — 可选：NavigationRegion2D 节点
```

### Exit Interaction Convention

出口是特殊的 Interactable，在 ADR-0006 的 InteractionBus 中通过 `target_type: "exit"` 区分：

```gdscript
# Exit 组件附加到 Exits 下的 Area2D
@export var destination_room_id: StringName
@export var spawn_point_id: StringName  # 目标房间的出生位置

# 注册到 InteractionBus 时
Interactable.configure({
    "target_id": destination_room_id,
    "target_type": &"exit",
    "metadata": {"spawn_point": spawn_point_id}
})
```

### Transition Flow

```
玩家点击出口 → InteractionBus 分发事件 (target_type: "exit")
  → RoomManager.request_transition(room_id)
    1. GUARD — if _is_transitioning: return
    2. PRE_UNLOAD — unregister_room_interactables()
    3. FADE_OUT — emit room_transition_started, animate fade overlay
    4. UNLOAD — current_room.queue_free()
    5. LOAD — _room_registry[room_id].instantiate()
    6. APPLY_STATE — apply template + persistent mutations
    7. POST_LOAD — register_room_interactables()
    8. FADE_IN — animate fade overlay
    9. COMPLETE — emit room_transition_completed, room_changed
```

### State Ownership (ADR-0004 Integration)

房间状态遵循 ADR-0004 的三层分离：

| State Type | Owner | Write Path | Reset Behavior |
|------------|-------|------------|----------------|
| Template State (night-local) | RoomManager | `set_room_state()` | Resets on advance_night via PackedScene re-instantiation |
| Persistent Mutations (cross-night) | LoopStateManager | `register_consequence()` only | Never resets; applied during APPLY_STATE step |
| Player Knowledge | ClueDatabase | ADR-0005 interfaces | Never resets; not room-level |

**关键规则**: `set_room_state()` 只修改当夜模板状态（如"打开了一扇门"），这些变更在 advance_night 后丢失。跨夜持久变更（如"用钥匙永久打开了密道"）必须通过 `LoopStateManager.register_consequence()` 注册。RoomManager 的 APPLY_STATE 步骤从 `LoopStateManager.get_template_override()` 读取持久变异并应用到新实例化的场景上。

### Template Reset Integration

RoomManager 监听两个信号：`night_ready`（初始加载）和 `night_advanced`（循环重置）：

```gdscript
func _ready() -> void:
    LoopStateManager.night_ready.connect(_on_night_ready)
    LoopStateManager.night_advanced.connect(_on_night_advanced)

func _on_night_ready(night: int) -> void:
    # 初始房间加载——游戏启动或 deserialize 后
    request_transition(&"lobby")

func _on_night_advanced(_old_night: int, _new_night: int) -> void:
    apply_template_reset()

func apply_template_reset() -> void:
    # GUARD: 如果正在过渡中，排队等待过渡完成后执行
    if _is_transitioning:
        _pending_reset = true
        return
    if current_room_id == &"":
        return  # 游戏启动前，night_ready 会处理
    # Re-instantiate current room from PackedScene (fresh template)
    var room_id := current_room_id
    _unload_current_room()
    _load_room(room_id)
    register_room_interactables()

var _pending_reset: bool = false

# 在 request_transition 的 COMPLETE 步骤中检查
# if _pending_reset:
#     _pending_reset = false
#     apply_template_reset()
```

### Key Interfaces

**RoomManager (Autoload Singleton)**:
```gdscript
class_name RoomManager
extends Node

signal room_changed(room_id: StringName)
signal room_transition_started(from: StringName, to: StringName)
signal room_transition_completed(room_id: StringName)

var current_room_id: StringName = &""

var _room_container: Node2D
var _room_registry: Dictionary = {}
var _room_cache: Dictionary = {}
var _is_transitioning: bool = false

func request_transition(room_id: StringName) -> void
func get_current_room_id() -> StringName
func get_room_state(room_id: StringName) -> Dictionary
func set_room_state(room_id: StringName, property: String, value: Variant) -> void  # Template-only; persistent mutations use LoopStateManager.register_consequence()
func apply_template_reset() -> void
func register_room_interactables() -> void
func unregister_room_interactables() -> void
```

**Room Registry Configuration**:
```gdscript
# Pre-configured in _ready() or via exported resource
const ROOM_PATHS: Dictionary = {
    &"lobby": "res://scenes/rooms/lobby.tscn",
    &"corridor": "res://scenes/rooms/corridor.tscn",
    &"guest_room_a": "res://scenes/rooms/guest_room_a.tscn",
    &"guest_room_b": "res://scenes/rooms/guest_room_b.tscn",
    &"guest_room_c": "res://scenes/rooms/guest_room_c.tscn",
    &"kitchen": "res://scenes/rooms/kitchen.tscn",
    &"basement": "res://scenes/rooms/basement.tscn",
    &"garden": "res://scenes/rooms/garden.tscn",
}
```

**Interactable Registration**:
```gdscript
func register_room_interactables() -> void:
    var interactables := _get_active_interactables()
    for interactable in interactables:
        InteractionBus.register_interactable(interactable)

func unregister_room_interactables() -> void:
    var interactables := _get_active_interactables()
    for interactable in interactables:
        InteractionBus.unregister_interactable(interactable)

func _get_active_interactables() -> Array[Node]:
    if _room_container.get_child_count() == 0:
        return []
    var room_node := _room_container.get_child(0)
    return room_node.find_children("*", "Interactable")  # requires class_name Interactable in ADR-0006
```

### Fade Overlay

过渡使用独立的 CanvasLayer（layer 100，高于所有 UI）和一个 ColorRect 实现：

```gdscript
# Fade overlay on CanvasLayer 100 (above HUD at 60)
# ColorRect: full screen, color black, modulate.a animated 0→1 (out) / 1→0 (in)
# Duration: 0.3s fade-out, 0.3s fade-in (tunable)
```

CanvasLayer 100 位于 UI 层（30-60）之上，确保淡入淡出覆盖所有视觉内容。

## Alternatives Considered

### Alternative 1: All Rooms Preloaded

- **Description**: 在游戏启动时加载所有 8 个房间场景，切换时只切换可见性
- **Pros**: 切换零延迟；房间间数据共享简单
- **Cons**: 8 个房间常驻内存（每个约 5-15MB），总计 40-120MB；对移动端不友好；违反按需加载原则
- **Rejection Reason**: MVP 3 房间可接受，但完整版 8 房间会显著增加内存压力。移动端移植是明确目标（technical-preferences.md: Touch Support: Full）。

### Alternative 2: Multi-Scene (Godot change_scene)

- **Description**: 使用 Godot 的 SceneTree.change_scene_to_file() 切换房间
- **Pros**: Godot 原生方式；自动清理旧场景
- **Cons**: Autoload 单例以外的所有节点被销毁和重建；无法共享房间间状态；过渡控制受限（无法自定义 fade）；全场景重建开销大
- **Rejection Reason**: Autoload 间协调足够（ADR-0004/0005/0006 都是 Autoload），但 destroy-all-then-rebuild 的开销和过渡控制限制不如手动管理灵活。PackedScene.instantiate() + add_child 提供同等功能但更可控。

### Alternative 3: Single Scene with TileMap

- **Description**: 所有房间绘制在同一个 TileMap 上，通过移动摄像机"切换"房间
- **Pros**: 无加载延迟；连续空间感强
- **Cons**: 所有房间同时存在内存中；可交互物需要额外的 enabled/disabled 管理；摄像机移动可能穿过墙壁露出未完成区域；不适合房间间有独立状态管理的需求
- **Rejection Reason**: 七夜的房间是独立空间（旅馆各房间有门隔离），不是连续开放世界。单房间加载更符合游戏概念。TileMap 方式的 enabled/disabled 管理复杂度超过按需加载。

## Consequences

### Positive

- 按需加载——只有当前房间在内存中，适合移动端
- 与 ADR-0004 无缝集成——template reset = 重新实例化 PackedScene
- 与 ADR-0006 无缝集成——进入注册、离开注销，交互生命周期清晰
- 场景层级约定确保所有房间结构一致
- Room Cache 可选保留最近访问的 1-2 个场景（可选优化）

### Negative

- 首次进入房间有 PackedScene 加载延迟（预估 < 100ms，仍需 fade 遮盖）
- 房间间不能直接共享 Node 引用——只能通过 RoomManager 接口查询状态
- 每次过渡有 0.6s 的不可操作时间（fade-out 0.3s + fade-in 0.3s）
- RoomManager 成为房间相关的所有操作的中心节点

### Risks

- **加载延迟**: 大房间场景可能导致 >100ms 加载时间。缓解: fade 动画自然遮盖 0.3s；房间场景保持轻量（2D 节点，无物理模拟）。
- **状态同步**: 房间内 NPC 位置需要在 template reset 后由 NPCManager 重新放置。缓解: NPCManager 监听 room_changed 信号，独立管理 NPC 放置。
- **Cache 策略**: 保留最近 N 个 PackedScene 可能增加内存。缓解: MVP 不实现缓存，仅在 profiling 发现需要时添加。
- **Interactable 遗漏注销**: 如果 transition 失败，interactables 可能残留注册。缓解: unregister 在 unload 之前执行；transition 失败时 guard 阻止后续请求。
- **Template reset 与 transition 竞态**: advance_night() 可能在房间过渡进行中触发。缓解: `_pending_reset` 标志延迟重置到过渡完成后。
- **房间状态双写路径**: 如果系统直接修改房间节点属性而不通过 RoomManager 或 LoopStateManager。缓解: 明确文档化 set_room_state() 为 Template-only，持久变异必须通过 register_consequence()。
- **Interactable 发现依赖 class_name**: `find_children("*", "Interactable")` 要求 ADR-0006 的 Interactable 组件声明 `class_name Interactable`。缓解: 在 ADR-0006 审查中确认此声明。

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-concept.md | 时间循环探索——每夜旅馆大部分状态重置 | Template reset via PackedScene re-instantiation on night_advanced |
| game-concept.md | 山间旅馆——8 房间探索 | Room registry with 8 rooms, on-demand loading |
| systems-index.md | System #3 (房间/位置管理) | RoomManager autoload with transition lifecycle |
| systems-index.md | System #7 (交互系统) — depends on #3 | Room scene structure convention (Interactables layer z:0) |
| systems-index.md | System #17 (房间导航 UI) | room_changed signal for UI updates, current_room_id query |
| systems-index.md | TD Concern #6 — 夜晚重置原子性 | apply_template_reset() triggered by night_advanced signal |
| loop-state-management.md | Template State layer resets on advance_night() | Room state is Template State — re-instantiated from PackedScene |
| interaction-event-bus.md | Interactable lifecycle management | register/unregister bound to room transition flow |

## Performance Implications

- **CPU**: PackedScene.instantiate() — O(n) where n = nodes in room scene. Expected < 50 nodes per room → < 5ms. Fade animation adds 0.3s × 2 user-perceived delay.
- **Memory**: Only active room in memory. ~5-15 MB per room (2D sprites, no physics). Total room memory capped at ~15 MB.
- **Load Time**: First load loads PackedScene resource from disk (~10-50ms). Subsequent loads of same room load from resource cache (near-instant). Room cache optional.
- **Network**: N/A

## Migration Plan

New system. Implementation order: RoomManager autoload → room scene convention → exit interactables → fade overlay → integration with LoopStateManager + InteractionBus.

## Validation Criteria

1. request_transition() loads correct room and emits room_changed
2. _is_transitioning guard blocks concurrent transitions
3. unregister_room_interactables() called before unload
4. register_room_interactables() called after load
5. apply_template_reset() restores room to PackedScene default state
6. Fade overlay covers transition completely (no visible frame of unload/load)
7. Room scene structure follows Background(z:-10) / Interactables(z:0) / NPCs(z:1) / Exits(z:2)
8. Exit interactables emit target_type "exit" via InteractionBus
9. current_room_id returns correct value after transition
10. room_transition_started fires before unload, room_transition_completed after fade-in

## Related Decisions

- ADR-0004: Loop State Management — night_advanced triggers template reset
- ADR-0006: Interaction Event Bus — exit interactions trigger navigation, interactable lifecycle
- ADR-0003: UI Visual Register — CanvasLayer 100 for fade overlay above all UI
- Art Bible Section 5: Room visual design and environmental storytelling
