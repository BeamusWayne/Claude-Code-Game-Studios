# ADR-0008: Countdown Timer System

## Status
Accepted

## Date
2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Gameplay / Time |
| **Knowledge Risk** | LOW — uses standard _process(), Curve resource, and signals |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, docs/engine-reference/godot/breaking-changes.md, docs/engine-reference/godot/deprecated-apis.md |
| **Post-Cutoff APIs Used** | None — Curve resource, maxf(), clampf() exist since Godot 4.0 |
| **Verification Required** | Test timer accuracy over 5-minute night. Test phase transitions at CALM/INTENSE/CRITICAL boundaries. Test pressure_curve.sample() with edge values (0.0, 1.0). Test time_scale = 0.5 during dialogue (conforms to ADR-0003). Test set_process(false) when inactive eliminates per-frame cost. Test Curve import from .tres file. Test serialize/deserialize preserves remaining_time and pressure_level. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (Loop State Management — reads current_night via interface, listens to night_ready/night_advanced signals) |
| **Enables** | ADR-0001 (produces pressure_level uniform value), System #9 (Event Scheduler — consumes phase changes), System #19 (Timer/HUD UI — reads pressure and remaining time), System #24 (Audio System — phase-driven music/ambient changes) |
| **Blocks** | System #9 (Event Scheduler), System #19 (Timer/HUD UI), System #24 (Audio System) |
| **Ordering Note** | Should be Accepted before event scheduler and timer/HUD UI ADRs. Can be designed in parallel with NPC state machine. |

## Context

### Problem Statement

七夜的核心机制支柱 2 是"时间在低语与咆哮之间交替"。每夜有有限的倒计时时长，随着时间流逝，压力（pressure_level）从 0.0 升至 1.0，驱动水墨着色器的视觉效果（ADR-0001）。目前 `pressure_level` uniform 在着色器中已定义，但没有任何系统生产这个值。需要一个倒计时系统：(1) 管理每夜的时长，(2) 计算并输出 pressure_level，(3) 在压力阶段变化时发出信号通知下游系统。

### Constraints

- 每夜时长由 BASE_DURATION 配置（未来可扩展 RHYTHM_TABLE）
- pressure_level 范围 0.0-1.0，作为着色器 uniform 每帧更新
- 三段压力阶段与 ADR-0001 着色器分段对齐
- 对话期间计时器以 50% 速度运行（ADR-0003 约束）
- 倒计时耗尽不直接触发 advance_night()——由夜晚过渡控制器决定
- 房间切换期间计时器不暂停（过渡 < 1秒，不影响游戏节奏）

### Requirements

- 拥有 pressure_level 状态（着色器 uniform 的唯一生产者）
- 使用 Godot Curve Resource 计算压力曲线（设计师可调整）
- 三段压力阶段（CALM/INTENSE/CRITICAL），阈值与 ADR-0001 对齐
- time_scale 机制支持变速（对话 0.5x，过渡 0.0x）
- 读取循环状态获取当夜编号和配置
- 每帧更新 pressure_level 供着色器驱动脚本读取
- 序列化支持（存档/读档保存剩余时间和压力状态）

## Decision

TimerService Autoload 单例 + Godot Curve Resource 压力曲线。TimerService 拥有 pressure_level 状态，通过 _process() 每帧计算更新。压力曲线使用 Godot 原生 Curve 资源，默认线性但设计师可直接在编辑器中调整节点创建非线性节奏。time_scale 变量替代 is_paused 布尔值，支持 ADR-0003 要求的对话 50% 减速。

### Architecture Diagram

```
┌──────────────────────────────────────────────────────┐
│                TimerService (Autoload)                 │
│                                                       │
│  ┌────────────────────────────────────────────────┐   │
│  │  Pressure Curve (Curve Resource)               │   │
│  │  • Default: linear (0,0)→(1,1)                 │   │
│  │  • Editable in editor per project              │   │
│  │  • input: progress (0.0-1.0 = time elapsed)    │   │
│  │  • output: pressure_level (0.0-1.0)            │   │
│  └────────────────────────────────────────────────┘   │
│                                                       │
│  ┌────────────────────────────────────────────────┐   │
│  │  Phase State Machine:                          │   │
│  │  CALM (0.0-0.3) → INTENSE (0.3-0.7)          │   │
│  │  → CRITICAL (0.7-1.0)                          │   │
│  │  Thresholds aligned with ADR-0001 shader:      │   │
│  │    CALM      ↔ shader Whisper (0.0-0.3)       │   │
│  │    INTENSE   ↔ shader Transition (0.3-0.7)    │   │
│  │    CRITICAL  ↔ shader Roar (0.7-1.0)          │   │
│  └────────────────────────────────────────────────┘   │
│                                                       │
│  ┌────────────────────────────────────────────────┐   │
│  │  Time Scale Control:                           │   │
│  │  time_scale: float (0.0-1.0)                   │   │
│  │  1.0 = normal, 0.5 = dialogue (ADR-0003),     │   │
│  │  0.0 = paused (advance_night / menu)           │   │
│  └────────────────────────────────────────────────┘   │
│                                                       │
│  State:                                               │
│    pressure_level: float (0.0-1.0) [OWNED]           │
│    current_phase: PressurePhase enum                  │
│    remaining_time: float (seconds)                    │
│    total_duration: float (seconds)                    │
│    time_scale: float (0.0-1.0)                        │
│    is_active: bool                                    │
│                                                       │
│  Signals:                                             │
│    night_timer_started(night: int, duration: float)   │
│    night_timer_ended(night: int)                      │
│    phase_changed(old_phase: int, new_phase: int)      │
│    pressure_updated(pressure_level: float)            │
│                                                       │
│  Event Flow:                                          │
│  LoopStateManager.night_ready                         │
│    → TimerService.start_night_timer()                 │
│    → _process: countdown * time_scale                 │
│    → curve.sample(progress) → pressure_level          │
│    → pressure_updated → InkWashPostProcess            │
│    → phase_changed → EventScheduler (future)          │
│    → remaining_time <= 0                              │
│    → night_timer_ended → NightTransitionController    │
└──────────────┬───────────┬─────────────┬─────────────┘
               │           │             │
    ┌──────────▼──┐ ┌──────▼──────┐ ┌────▼──────────┐
    │ Ink Wash    │ │ Event       │ │ Timer/HUD UI  │
    │ PostProcess │ │ Scheduler   │ │ (reads        │
    │ (writes     │ │ (future:    │ │  pressure +   │
    │  pressure   │ │  phase-     │ │  remaining)   │
    │  uniform)   │ │  driven     │ │               │
    │             │ │  events)    │ │               │
    └─────────────┘ └─────────────┘ └───────────────┘
```

### Key Interfaces

**TimerService (Autoload Singleton)**:
```gdscript
class_name TimerService
extends Node

signal night_timer_started(night: int, duration: float)
signal night_timer_ended(night: int)
signal phase_changed(old_phase: PressurePhase, new_phase: PressurePhase)
signal pressure_updated(pressure_level: float)

enum PressurePhase { CALM, INTENSE, CRITICAL }

## Phase thresholds aligned with ADR-0001 shader pressure ranges.
const CALM_MAX: float = 0.3
const INTENSE_MAX: float = 0.7

@export var pressure_curve: Curve
@export var base_duration: float = 300.0
@export var min_night_duration: float = 60.0

var pressure_level: float = 0.0
var current_phase: PressurePhase = PressurePhase.CALM
var remaining_time: float = 0.0
var total_duration: float = 0.0
var time_scale: float = 1.0
var is_active: bool = false

func _ready() -> void:
    LoopStateManager.night_ready.connect(_on_night_ready)
    set_process(false)
    if pressure_curve == null:
        pressure_curve = _create_default_curve()

func start_night_timer() -> void:
    var night := LoopStateManager.get_current_night()
    var duration := _calculate_night_duration(night)
    remaining_time = duration
    total_duration = duration
    pressure_level = 0.0
    current_phase = PressurePhase.CALM
    time_scale = 1.0
    is_active = true
    set_process(true)
    night_timer_started.emit(night, duration)

func stop_timer() -> void:
    is_active = false
    set_process(false)

func set_time_scale(scale: float) -> void:
    time_scale = clampf(scale, 0.0, 1.0)

func _process(delta: float) -> void:
    if not is_active: return
    var scaled_delta := delta * time_scale
    remaining_time = maxf(0.0, remaining_time - scaled_delta)

    var progress := 1.0 - (remaining_time / total_duration)
    var new_pressure := pressure_curve.sample(clampf(progress, 0.0, 1.0))
    new_pressure = clampf(new_pressure, 0.0, 1.0)

    if not is_equal_approx(new_pressure, pressure_level):
        pressure_level = new_pressure
        pressure_updated.emit(pressure_level)

    var new_phase := _determine_phase(pressure_level)
    if new_phase != current_phase:
        var old := current_phase
        current_phase = new_phase
        phase_changed.emit(old, new_phase)

    if remaining_time <= 0.0 and is_active:
        is_active = false
        set_process(false)
        night_timer_ended.emit(LoopStateManager.get_current_night())

func _calculate_night_duration(night: int) -> float:
    return maxf(min_night_duration, base_duration)

func _determine_phase(pressure: float) -> PressurePhase:
    if pressure >= INTENSE_MAX:
        return PressurePhase.CRITICAL
    if pressure >= CALM_MAX:
        return PressurePhase.INTENSE
    return PressurePhase.CALM

func _on_night_ready(night: int) -> void:
    start_night_timer()

func _create_default_curve() -> Curve:
    var curve := Curve.new()
    curve.add_point(Vector2(0.0, 0.0))
    curve.add_point(Vector2(1.0, 1.0))
    return curve

func serialize() -> Dictionary:
    return {
        "remaining_time": remaining_time,
        "total_duration": total_duration,
        "pressure_level": pressure_level,
        "current_phase": current_phase,
        "time_scale": time_scale,
        "is_active": is_active
    }

func deserialize(data: Dictionary) -> void:
    remaining_time = data.get("remaining_time", 0.0)
    total_duration = data.get("total_duration", 0.0)
    pressure_level = data.get("pressure_level", 0.0)
    current_phase = data.get("current_phase", PressurePhase.CALM) as PressurePhase
    time_scale = data.get("time_scale", 1.0)
    is_active = data.get("is_active", false)
    set_process(is_active)
```

**InkWashPostProcess Consumer Update** (ADR-0001 补充):
```gdscript
func _process(delta: float) -> void:
    ink_material["shader_parameter/knowledge_level"] = KnowledgeManager.knowledge_level
    ink_material["shader_parameter/pressure_level"] = TimerService.pressure_level
    ink_material["shader_parameter/time_value"] = time_elapsed
```

**Time Scale Consumers**:
```gdscript
# UIManager sets during dialogue (ADR-0003 compliance):
TimerService.set_time_scale(0.5)   # dialogue starts
TimerService.set_time_scale(1.0)   # dialogue ends

# Night Transition Controller sets during advance_night():
TimerService.set_time_scale(0.0)   # transition starts
TimerService.set_time_scale(1.0)   # after night_ready
```

**TimerService Configuration (per-night rhythm, future)**:
```gdscript
# Future enhancement: per-night duration variation
# When RHYTHM_TABLE is populated:

func _calculate_night_duration(night: int) -> float:
    var duration := base_duration
    if night - 1 < _rhythm_table.size():
        duration += _rhythm_table[night - 1]
    return maxf(min_night_duration, duration)
```

## Alternatives Considered

### Alternative 1: Extend LoopStateManager

- **Description**: Add timer methods to LoopStateManager instead of separate Autoload
- **Pros**: Fewer Autoloads; direct access to night state
- **Cons**: Violates loop-state-management GDD's "neutral keeper" principle — loop state stores and manages state lifecycle, not gameplay logic. Timer interpreting time pressure and driving visual effects is interpreting state meaning — a different responsibility.
- **Rejection Reason**: Loop state management's design principle is "只负责状态的存储、分离和生命周期管理。它不解释状态含义。" Timer interpreting time pressure and driving visual effects is interpreting state meaning — a different responsibility.

### Alternative 2: Per-Scene Timer Node

- **Description**: Attach a Timer node to each night's scene root
- **Pros**: Scene-scoped lifecycle; no Autoload
- **Cons**: Timer state must survive scene transitions; pressure_level must persist across rooms within a night; no single source of truth for pressure during transitions
- **Rejection Reason**: The countdown spans the entire night, not a single scene. Per-scene timers would need complex synchronization and could produce pressure discontinuities during room transitions.

### Alternative 3: Timer via Tween/AnimationPlayer

- **Description**: Use Tween or AnimationPlayer to animate pressure_level from 0 to 1
- **Pros**: Smooth interpolation built-in; no _process needed
- **Cons**: Can't easily change curve at runtime; pause/resume requires Tween manipulation; no phase detection; no signal on arbitrary thresholds
- **Rejection Reason**: Curve Resource in _process provides same smoothness with explicit phase detection and signal emission. Tween is better suited for animations than gameplay systems.

## Consequences

### Positive

- TimerService is the single authority for pressure_level — no other system should write to the ink wash shader's pressure uniform
- Curve Resource enables designers to tune pressure feel without code changes — adjust curve in editor, see results in real-time
- Three-phase model (CALM/INTENSE/CRITICAL) aligns directly with ADR-0001's shader pressure ranges (Whisper/Transition/Roar)
- time_scale mechanism supports ADR-0003's dialogue 50% speed requirement and enables future variable-rate scenarios
- set_process(false) when inactive eliminates per-frame cost during non-countdown periods
- Clean signal interface allows future consumers (event scheduler, audio) without modifying TimerService
- Serialization support ensures save/load mid-night preserves timer state

### Negative

- One more Autoload in the project (total: InteractionBus, LoopStateManager, TimerService)
- Curve Resource is an additional asset to manage and version
- _process runs every frame during active countdown — negligible cost (~0.01ms) but not zero
- Timer accuracy depends on frame rate — low FPS could cause slight drift (acceptable for adventure game pacing)
- time_scale is a global modifier — any system can call set_time_scale(), creating potential for conflicting time scale requests

### Risks

- **Curve design complexity**: Designers may create curves with pressure that decreases over time, producing phase transitions from CRITICAL back to CALM. Mitigation: document recommended curve shapes; validate in editor that phase transitions are generally monotonic. Non-monotonic curves are not forbidden — they could create deliberate tension/release rhythm.
- **Pause accumulation**: If dialogue pauses are frequent and long, effective play time per night may exceed intended duration. Mitigation: ADR-0003 specifies 50% speed (not pause), which limits time dilation. Track and optionally display "active play time" separately.
- **Timer and advance_night() ordering**: If night_timer_ended fires and the night transition controller calls advance_night() in the same frame, LoopStateManager's _pending_write could block. Mitigation: TimerService emits night_timer_ended at end of _process; transition controller should defer advance_night() to next frame via call_deferred().
- **Curve.sample() edge cases**: Godot's Curve.sample() clamps input to [0,1] but the curve's output range depends on point values. If a designer sets a point to >1.0, pressure_level could exceed the shader's expected range. Mitigation: clamp output to [0.0, 1.0] after sampling (already implemented).
- **Conflicting time_scale requests**: If dialogue and a narrative event both try to set time_scale simultaneously, last-write-wins. Mitigation: UIManager is the designated time_scale authority; other systems should request changes through UIManager rather than setting time_scale directly.

## Boundary Rules

- **TimerService must not call advance_night()**. Timer emits night_timer_ended. The Night Transition Controller (System #8) decides when and how to advance the night. This mirrors the InteractionBus boundary (ADR-0006): detect and dispatch, never apply game logic.
- **pressure_level is read-only for all consumers**. Only TimerService._process() writes to pressure_level. InkWashPostProcess reads it to set the shader uniform. HUD reads it for display. No other system writes to this value.
- **time_scale authority is UIManager**. During dialogue, UIManager sets 0.5. During night transition, the controller sets 0.0. Other systems should not set time_scale directly.

## Conventions

- **PressurePhase enum values** (CALM, INTENSE, CRITICAL) are intentionally distinct from LoopStateManager.NightPhase (WHISPER, ROAR, TRANSITION) to prevent signal cross-connection. TimerService phases describe moment-to-moment pressure intensity; NightPhase describes macro night lifecycle.
- **Phase thresholds** (CALM_MAX = 0.3, INTENSE_MAX = 0.7) must be updated in tandem if ADR-0001's shader pressure ranges change. These are paired constants across two ADRs.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-concept.md | Pillar 2: 时间在低语与咆哮之间交替 | TimerService drives pressure_level through CALM→INTENSE→CRITICAL phases via Curve Resource |
| game-concept.md | 倒计时压力系统—每夜时间限制 | start_night_timer() with configurable duration (BASE_DURATION) |
| game-concept.md | MVP: 恒定倒计时 | Default linear Curve + constant BASE_DURATION = constant pressure increase |
| game-concept.md | 节奏在低语与咆哮之间交替 | Three-phase state machine aligned with ADR-0001 shader ranges |
| systems-index.md | System #5 (倒计时系统) | TimerService Autoload |
| systems-index.md | CD Concern #1 | Resolves: rhythm rules — CALM/INTENSE/CRITICAL phases with Curve Resource |
| loop-state-management.md | BASE_DURATION tuning knob | @export base_duration on TimerService (migrated from loop-state GDD — this ADR takes ownership) |
| loop-state-management.md | NIGHT_RHYTHM_CONFIG | Future: per-night config exposed via tuning knobs on TimerService |
| ADR-0001 | pressure_level uniform producer | TimerService.pressure_level read each frame by InkWashPostProcess driver |
| ADR-0003 | Timer continues at 50% speed during dialogue | time_scale = 0.5 set by UIManager during dialogue state |

## Performance Implications

- **CPU**: One Curve.sample() call + float arithmetic + two float comparisons per frame during active countdown. Curve.sample() is O(n) where n = number of curve points (typically ≤ 10). Total: <0.01ms per frame. When inactive, set_process(false) eliminates all cost.
- **Memory**: One Curve Resource (~1KB). Timer state variables ~100 bytes.
- **GPU**: No direct GPU impact. pressure_level uniform update is already accounted for in ADR-0001's driver script.
- **Load Time**: Curve Resource loads with scene. Negligible.

## Migration Plan

新系统。实现顺序：TimerService → InkWashPostProcess 更新（添加 pressure_level 读取） → Timer/HUD UI。

GDD 迁移：loop-state-management.md 的 BASE_DURATION、MIN_NIGHT_DURATION、RHYTHM_TABLE、NIGHT_RHYTHM_CONFIG 旋钮应迁移到倒计时系统 GDD。循环状态管理不再负责计时器配置——它只提供 current_night 供倒计时系统查询当夜编号。

## Validation Criteria

1. pressure_level = 0.0 at start of each night
2. pressure_level = 1.0 when remaining_time = 0.0
3. Phase transitions: CALM→INTENSE at pressure 0.3, INTENSE→CRITICAL at pressure 0.7
4. pressure_curve.sample() produces values clamped to [0.0, 1.0] for inputs in [0.0, 1.0]
5. time_scale = 0.5 causes timer to tick at half speed (5 minute night takes ~10 minutes of wall-clock time)
6. time_scale = 0.0 fully pauses countdown
7. set_process(false) called when timer stops; set_process(true) when timer starts
8. night_timer_started emitted on night_ready signal
9. night_timer_ended emitted when remaining_time reaches 0.0
10. Timer restarts correctly on night_advanced → night_ready sequence
11. is_active = false after timer ends, prevents further pressure updates
12. Custom Curve Resource loads from .tres file and produces non-linear pressure curve
13. base_duration clamped by min_night_duration
14. serialize()/deserialize() round-trip preserves all timer state
15. Room transitions do not pause or affect the countdown

## Related Decisions

- ADR-0001: Ink Wash Shader Pipeline — consumes pressure_level uniform; phase thresholds must be updated in tandem
- ADR-0004: Loop State Management — provides night_ready/night_advanced signals, night counter; timer reads current_night via interface
- ADR-0003: UI Visual Register — dialogue state triggers time_scale = 0.5; HUD timer reads remaining_time; Timer Seal visual reads pressure
- ADR-0006: Interaction Event Bus — same boundary pattern: detect/dispatch only, never apply game logic
