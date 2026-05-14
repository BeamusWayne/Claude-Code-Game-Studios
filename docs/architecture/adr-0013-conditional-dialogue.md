# ADR-0013: Conditional Dialogue Trees

## Status

Accepted

## Date

2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI / Gameplay |
| **Knowledge Risk** | LOW — uses standard Godot Resource, Control nodes, Tween, and signals. No post-cutoff APIs required. |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, docs/engine-reference/godot/breaking-changes.md, docs/engine-reference/godot/deprecated-apis.md |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Test condition evaluation for all condition types. Test dialogue flow with branching paths. Test graceful degradation when TrustManager unavailable. Test timer slow-down during dialogue. Test dialogue blocking of night transition. Test serialization of dialogue state. Test typewriter effect timing. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 (UI Visual Register — CanvasLayer 40 for dialogue, UIManager.is_dialogue_active), ADR-0004 (loop-state-management — LoopStateManager.get_active_state_value() for condition evaluation), ADR-0005 (clue-insight-unified-schema — ClueDatabase.has_clue()/has_insight() for knowledge conditions), ADR-0008 (countdown-timer — TimerService.set_time_scale(0.5) during dialogue), ADR-0009 (npc-state-machine — NPCManager.get_emotional_state() for NPC conditions, npc_interaction_requested signal), ADR-0011 (night-transition-controller — NightTransitionController blocks during active dialogue) |
| **Enables** | System #15 (Guest Interrogation — dialogue drives interrogation mechanic), narrative content authoring (designers author DialogueTree resources), System #9 (Event Scheduler — dialogue consequences can schedule events) |
| **Blocks** | System #15, narrative content integration |
| **Ordering Note** | ADR-0012 (NPC Trust/Suspicion) is a soft dependency — DialogueManager queries TrustManager if available, graceful degradation if not. This ADR can be Accepted before ADR-0012 without blocking. |

## Context

### Problem Statement

七夜是点击式冒险游戏，对话是核心交互。玩家通过对话了解 NPC 的秘密、展示已获取的知识、做出选择影响 NPC 关系。对话系统需要：(1) 数据驱动的对话树（策划在编辑器中编写，不是代码），(2) 条件分支（基于 NPC 状态、信任/警觉、玩家知识、循环状态），(3) 后果触发（对话选择可以改变 NPC 情绪、信任值、触发线索发现），(4) UI 呈现（水墨风格的对话面板 + 打字机效果）。

### Current State

NPCManager（ADR-0009）提供 npc_interaction_requested 信号和 is_dialogue_available() 查询。UIManager（ADR-0003）定义 CanvasLayer 40 用于对话。TimerService（ADR-0008）支持 set_time_scale() 用于对话时减速。NightTransitionController（ADR-0011）检查 UIManager.is_dialogue_active 来阻止夜间过渡。但没有任何系统实际管理对话内容、条件和流程。

### Constraints

- 对话数据必须数据驱动（DialogueTree Resource 在编辑器中编写）
- 条件类型：NPC 情绪状态、信任/警觉值、玩家知识（线索/洞察）、循环状态、当前夜晚
- 对话面板在 CanvasLayer 40（ADR-0003）
- 对话期间计时器减速到 50%（ADR-0008）
- 对话必须完成才能进行夜间过渡（ADR-0011）
- 信任/警觉系统（ADR-0012）可能尚未加载 — 需要优雅降级
- 对话选择可以触发后果：NPC 状态变更、信任变更、线索发现、后果注册
- 最多 5 个对话选项同时显示

### Requirements

- 数据驱动对话树（.tres Resource）
- 条件评估器查询多个系统
- 对话流程管理（开始、推进、选择、结束）
- 后果系统（对话选择触发游戏状态变更）
- UI 面板（水墨风格、打字机效果、选项高亮）
- 计时器减速（对话期间 0.5x）
- 信号通知（下游系统可以响应对话事件）
- 优雅降级（TrustManager 不可用时使用默认值）

## Decision

DialogueManager Autoload 负责对话会话协调，配合数据驱动的 DialogueTree Resource 系统。条件评估器查询多个系统并优雅降级。

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                 DialogueManager (Autoload)                            │
│                                                                      │
│  NO PERSISTENT STATE — session-only dialogue tracking                │
│                                                                      │
│  Session State (not persisted):                                      │
│    _active_tree: DialogueTree                                        │
│    _current_node: DialogueNode                                       │
│    _active_npc: StringName                                           │
│    _dialogue_panel: DialoguePanel (CanvasLayer 40)                   │
│                                                                      │
│  Signals:                                                            │
│    dialogue_started(npc_id: StringName)                              │
│    dialogue_ended(npc_id: StringName)                                │
│    dialogue_choice_made(npc_id: StringName, choice_id: StringName)   │
│    dialogue_consequence_triggered(npc_id: StringName,                │
│                                   consequence: DialogueConsequence)  │
│    node_displayed(node_id: StringName, text: String)                 │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Condition Evaluator:                                        │    │
│  │    evaluate(conditions: Array[DialogueCondition]) -> bool     │    │
│  │                                                              │    │
│  │  Query Sources (graceful degradation):                       │    │
│  │    NPCManager     → get_emotional_state()  (always available) │    │
│  │    TrustManager   → get_trust/get_suspicion (or default 50/0)│    │
│  │    ClueDatabase   → has_clue/has_insight     (always available)│    │
│  │    LoopStateManager→ get_active_state_value (always available)│    │
│  │    TimerService   → current phase check      (always available)│    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Dialogue Flow:                                               │    │
│  │    start_dialogue(npc_id, tree) → validate → show first node  │    │
│  │    advance() → show next node or end                          │    │
│  │    select_choice(choice_id) → evaluate → apply consequences   │    │
│  │    end_dialogue() → restore timer → emit dialogue_ended       │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
         │              │              │              │
    ┌────▼────┐   ┌─────▼─────┐  ┌────▼────┐  ┌─────▼─────┐
    │NPCManager│  │TrustManager│  │Clue     │  │TimerService│
    │(NPC      │  │(trust/    │  │Database │  │(time_scale │
    │ state)   │  │suspicion) │  │(clues)  │  │ 0.5x)      │
    └──────────┘  └───────────┘  └─────────┘  └────────────┘
         │              │
    ┌────▼────┐   ┌─────▼─────┐
    │UIManager│   │LoopState  │
    │(dialogue│   │Manager    │
    │ panel)  │   │(loop state│
    └──────────┘  └───────────┘
```

### Key Interfaces

**DialogueManager (Autoload Singleton)**:
```gdscript
class_name DialogueManager
extends Node

signal dialogue_started(npc_id: StringName)
signal dialogue_ended(npc_id: StringName)
signal dialogue_choice_made(npc_id: StringName, choice_id: StringName)
signal dialogue_consequence_triggered(npc_id: StringName, consequence: DialogueConsequence)
signal node_displayed(node_id: StringName, text: String)

var _active_tree: DialogueTree
var _current_node: DialogueNode
var _active_npc: StringName
var _dialogue_panel: DialoguePanel
var _is_active: bool = false

func _ready() -> void:
    NPCManager.npc_interaction_requested.connect(_on_npc_interaction_requested)
    UIManager.dialogue_ended.connect(_on_dialogue_ended_from_ui)
    _dialogue_panel = get_node_or_null("/root/DialoguePanel")

## --- Public API ---

var is_active: bool:
    get: return _is_active

func start_dialogue(npc_id: StringName, tree: DialogueTree) -> void:
    if _is_active: return
    if not NPCManager.is_dialogue_available(npc_id): return

    _active_npc = npc_id
    _active_tree = tree
    _is_active = true

    TimerService.set_time_scale(0.5)
    UIManager.set_dialogue_active(true)

    _current_node = tree.get_start_node()
    _display_node(_current_node)
    dialogue_started.emit(npc_id)

func select_choice(choice_id: StringName) -> void:
    if not _is_active: return
    assert(_current_node != null)

    var choice: DialogueChoice = _find_choice(choice_id)
    if choice == null: return

    dialogue_choice_made.emit(_active_npc, choice_id)

    for consequence: DialogueConsequence in choice.consequences:
        _apply_consequence(consequence)

    if choice.next_node_id == &"" or choice.next_node_id == &"END":
        end_dialogue()
    else:
        _current_node = _active_tree.get_node(choice.next_node_id)
        _display_node(_current_node)

func end_dialogue() -> void:
    if not _is_active: return

    var npc_id: StringName = _active_npc
    _is_active = false
    _active_tree = null
    _current_node = null
    _active_npc = &""

    TimerService.set_time_scale(1.0)
    UIManager.set_dialogue_active(false)
    _dialogue_panel.hide_panel()

    dialogue_ended.emit(npc_id)

func advance() -> void:
    if not _is_active: return
    if _current_node.choices.is_empty():
        if _current_node.next_node_id == &"" or _current_node.next_node_id == &"END":
            end_dialogue()
        else:
            _current_node = _active_tree.get_node(_current_node.next_node_id)
            _display_node(_current_node)

## --- Condition Evaluation ---

func _evaluate_conditions(conditions: Array[DialogueCondition]) -> bool:
    for condition: DialogueCondition in conditions:
        if not _evaluate_single(condition):
            return false
    return true

func _evaluate_single(condition: DialogueCondition) -> bool:
    var actual: Variant = _get_condition_value(condition)
    match condition.comparison:
        &"eq": return actual == condition.value
        &"neq": return actual != condition.value
        &"gte": return float(actual) >= float(condition.value)
        &"lte": return float(actual) <= float(condition.value)
        &"gt": return float(actual) > float(condition.value)
        &"lt": return float(actual) < float(condition.value)
        &"exists": return actual != null
        &"not_exists": return actual == null
    return false

func _get_condition_value(condition: DialogueCondition) -> Variant:
    match condition.source:
        &"npc_emotional_state":
            return NPCManager.get_emotional_state(condition.target_id)
        &"trust_level":
            return _safe_get_trust(condition.target_id)
        &"suspicion_level":
            return _safe_get_suspicion(condition.target_id)
        &"has_clue":
            return ClueDatabase.has_clue(condition.target_id)
        &"has_insight":
            return ClueDatabase.has_insight(condition.target_id)
        &"loop_state":
            return LoopStateManager.get_active_state_value(condition.target_id)
        &"current_night":
            return LoopStateManager.current_night
        &"current_phase":
            return LoopStateManager.current_phase
    return null

func _safe_get_trust(npc_id: StringName) -> float:
    var tm: Node = _get_trust_manager()
    if tm == null: return 50.0
    return tm.get_trust(npc_id)

func _safe_get_suspicion(npc_id: StringName) -> float:
    var tm: Node = _get_trust_manager()
    if tm == null: return 0.0
    return tm.get_suspicion(npc_id)

func _get_trust_manager() -> Node:
    ## Cached lookup for TrustManager Autoload.
    ## Returns null if not loaded (graceful degradation).
    return Engine.get_main_loop().root.get_node_or_null("TrustManager")

## --- Consequence Application ---

func _apply_consequence(consequence: DialogueConsequence) -> void:
    dialogue_consequence_triggered.emit(_active_npc, consequence)
    match consequence.type:
        &"npc_state_change":
            NPCManager.request_state_transition(
                consequence.target_id, consequence.value as int)
        &"trust_delta":
            var tm: Node = _get_trust_manager()
            if tm != null:
                tm.apply_delta(consequence.target_id, float(consequence.value), 0.0,
                    "dialogue_choice:%s" % consequence.description)
        &"suspicion_delta":
            var tm2: Node = _get_trust_manager()
            if tm2 != null:
                tm2.apply_delta(consequence.target_id, 0.0, float(consequence.value),
                    "dialogue_choice:%s" % consequence.description)
        &"discover_clue":
            ClueDatabase.discover_clue(consequence.target_id)
        &"register_consequence":
            LoopStateManager.register_consequence(
                consequence.target_id, consequence.value)

## --- Input Handlers ---

func _on_npc_interaction_requested(npc_id: StringName, event: Dictionary) -> void:
    var tree: DialogueTree = _resolve_dialogue_tree(npc_id)
    if tree == null: return
    start_dialogue(npc_id, tree)

func _resolve_dialogue_tree(npc_id: StringName) -> DialogueTree:
    var tree_path: String = "res://data/dialogue/dialogue_%s_default.tres" % npc_id
    if ResourceLoader.exists(tree_path):
        return load(tree_path) as DialogueTree
    return null

func _on_dialogue_ended_from_ui() -> void:
    end_dialogue()

## --- Display ---

func _display_node(node: DialogueNode) -> void:
    var available_choices: Array[DialogueChoice] = []
    for choice: DialogueChoice in node.choices:
        if _evaluate_conditions(choice.conditions):
            available_choices.append(choice)

    _dialogue_panel.display_node(node, available_choices)
    node_displayed.emit(node.id, node.text)

func _find_choice(choice_id: StringName) -> DialogueChoice:
    if _current_node == null: return null
    for choice: DialogueChoice in _current_node.choices:
        if choice.id == choice_id:
            return choice
    return null
```

**DialogueTree (Resource)**:
```gdscript
class_name DialogueTree
extends Resource

@export var id: StringName
@export var npc_id: StringName
@export var nodes: Array[DialogueNode] = []

func get_start_node() -> DialogueNode:
    for node: DialogueNode in nodes:
        if node.is_start: return node
    return nodes[0] if nodes.size() > 0 else null

func get_node(node_id: StringName) -> DialogueNode:
    for node: DialogueNode in nodes:
        if node.id == node_id: return node
    return null
```

**DialogueNode (Resource)**:
```gdscript
class_name DialogueNode
extends Resource

@export var id: StringName
@export var text: String
@export var speaker: StringName
@export var is_start: bool = false
@export var next_node_id: StringName = &""
@export var choices: Array[DialogueChoice] = []
@export var portrait_expression: String = "neutral"
@export var typewriter_speed: float = 0.03
```

**DialogueChoice (Resource)**:
```gdscript
class_name DialogueChoice
extends Resource

@export var id: StringName
@export var text: String
@export var next_node_id: StringName = &""
@export var conditions: Array[DialogueCondition] = []
@export var consequences: Array[DialogueConsequence] = []
@export var priority: int = 0
@export var is_default: bool = false
```

**DialogueCondition (Resource)**:
```gdscript
class_name DialogueCondition
extends Resource

@export var source: String = ""
@export var target_id: StringName = &""
@export var comparison: String = "eq"
@export var value: Variant = null
```

**DialogueConsequence (Resource)**:
```gdscript
class_name DialogueConsequence
extends Resource

@export var type: String = ""
@export var target_id: StringName = &""
@export var value: Variant = null
@export var description: String = ""
```

**DialoguePanel (Control — CanvasLayer 40)**:
```gdscript
class_name DialoguePanel
extends Control

var _text_label: RichTextLabel
var _choices_container: VBoxContainer
var _portrait: TextureRect
var _name_label: Label
var _typewriter_tween: Tween

func display_node(node: DialogueNode, choices: Array[DialogueChoice]) -> void:
    visible = true
    _name_label.text = _get_speaker_name(node.speaker)
    _set_portrait(node.speaker, node.portrait_expression)
    _typewriter_display(node.text, node.typewriter_speed)
    _display_choices(choices)

func hide_panel() -> void:
    visible = false
    if _typewriter_tween != null:
        _typewriter_tween.kill()
        _typewriter_tween = null

func _typewriter_display(text: String, speed: float) -> void:
    _text_label.text = ""
    _typewriter_tween = create_tween()
    for i: int in range(text.length()):
        _typewriter_tween.tween_callback(func() -> void:
            _text_label.text = text.substr(0, i + 1)
        )
        _typewriter_tween.tween_interval(speed)

func _display_choices(choices: Array[DialogueChoice]) -> void:
    for child: Node in _choices_container.get_children():
        child.queue_free()

    choices.sort_custom(func(a: DialogueChoice, b: DialogueChoice) -> bool:
        return a.priority > b.priority
    )

    for choice: DialogueChoice in choices:
        var button: Button = Button.new()
        button.text = choice.text
        button.pressed.connect(func() -> void:
            DialogueManager.select_choice(choice.id)
        )
        _choices_container.add_child(button)
```

## Alternatives Considered

### Alternative 1: Ink (Inkle) Integration

- **Description**: Use the Ink narrative scripting language (via GDExtension) for dialogue authoring.
- **Pros**: Battle-tested narrative engine. Rich scripting for complex branching.
- **Cons**: Requires GDExtension binding (C++ dependency conflicts with GDScript-only stack). Ink's variable model separate from Godot state management. Bridge complexity between Ink runtime and LoopStateManager/NPCManager/TrustManager.
- **Rejection Reason**: Project uses GDScript-only. The bridge complexity between Ink and Godot state systems outweighs authoring benefits. Godot-native Resources integrate directly with existing state management.

### Alternative 2: JSON-Based Dialogue Files

- **Description**: Dialogue trees stored as JSON files, parsed at runtime.
- **Pros**: Easy to edit in any text editor. Language-agnostic.
- **Cons**: No editor integration — no autocomplete, no type checking. String-based condition evaluation error-prone. Parser maintenance burden.
- **Rejection Reason**: Godot Resources provide editor integration that JSON lacks. Resource approach keeps everything within Godot's type system.

### Alternative 3: State Machine Dialogue

- **Description**: Each dialogue node is a state in a state machine with transitions.
- **Cons**: Over-engineered for mostly-linear dialogue with occasional branches.
- **Rejection Reason**: Tree-with-conditions model is simpler and maps directly to narrative structure.

## Consequences

### Positive

- Data-driven dialogue trees enable content authoring without code changes.
- Condition evaluator queries multiple systems through a unified interface.
- Graceful degradation ensures dialogue works even when TrustManager is not loaded.
- DialogueTree Resources integrate with Godot editor for visual authoring.
- TimerService.set_time_scale(0.5) creates time pressure while allowing dialogue.
- NightTransitionController blocking ensures dialogue completes before night transition.
- Consequence system enables rich NPC interaction without coupling to specific systems.

### Negative

- One more Autoload singleton (DialogueManager).
- DialogueTree Resources may become large for complex NPCs. No visual editor tool planned yet.
- Typewriter effect adds a Tween per displayed character — may impact mobile for long texts.
- Graceful degradation pattern adds conditional logic to every trust/suspicion query.
- Condition evaluator is string-based — no compile-time type checking on conditions.

### Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| DialogueTree Resources become unwieldy (50+ nodes) | Medium | Medium — authoring difficulty | Consider visual editor tool. For MVP, keep trees under 20 nodes per NPC. |
| Condition evaluation performance with many conditions | Low | Low — max 25 evaluations per node | Each evaluation is a single Dictionary lookup or method call. |
| Typewriter Tween accumulation for long texts | Low | Low — Tween GC'd after completion | Limit text per node (200 chars max recommended). |
| Graceful degradation hides missing TrustManager | Medium | Medium — conditions use defaults | Add debug-only warning when TrustManager not found. Integration tests require TrustManager. |
| Dialogue consequences create unintended state changes | Medium | Medium — designer error | Log all consequence applications. Unit test consequence types independently. |

## Boundary Rules

1. **DialogueManager MUST NOT own any persistent game state.** Session-only dialogue tracking. All persistent changes go through owning systems.

2. **DialogueManager MUST NOT contain narrative content.** All text, choices, conditions defined in DialogueTree Resources.

3. **DialogueManager MUST NOT bypass NPCManager.** Dialogue availability checked via NPCManager.is_dialogue_available().

4. **Dialogue MUST complete before night transition.** UIManager.is_dialogue_active returns true during dialogue.

5. **Condition evaluation is read-only.** _evaluate_conditions() only reads state. All modifications go through _apply_consequence().

## Conventions

1. **Autoload load order**: DialogueManager loads after NPCManager, ClueDatabase, LoopStateManager, TimerService, UIManager.

2. **DialogueTree naming**: `dialogue_{npc_id}_{context}.tres` (e.g., `dialogue_guest_01_night1_intro.tres`).

3. **Node ID convention**: snake_case with descriptive suffix (e.g., `intro_greeting`, `trust_high_secret`).

4. **Choice ID convention**: `{node_id}_choice_{index}` (e.g., `intro_greeting_choice_0`).

5. **Timer slow-down**: Always paired — set_time_scale(0.5) on start, set_time_scale(1.0) on end.

6. **CanvasLayer 40**: DialoguePanel on CanvasLayer 40, between HUD (30) and Notebook (50).

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| game-concept.md | Pillar 4 | Each NPC has secrets; player discovers through dialogue | Conditional dialogue trees with knowledge-based conditions enable secret discovery |
| game-concept.md | Pillar 2 | Time loop exploration — accumulated knowledge affects dialogue | Conditions check ClueDatabase for discovered knowledge, enabling knowledge-gated branches |
| systems-index.md | System #14 | Conditional Dialogue Trees — depends on #1, #4, #6, #12, #13 | This ADR defines the complete Conditional Dialogue system |
| systems-index.md | System #15 | Guest Interrogation — dialogue drives interrogation | DialogueManager provides dialogue infrastructure; interrogation is a specialized DialogueTree |
| ADR-0003 | CanvasLayer 40 | Dialogue renders on CanvasLayer 40 | DialoguePanel on CanvasLayer 40 per established layer ordering |
| ADR-0008 | Timer slow-down | Dialogue slows timer to 50% | TimerService.set_time_scale(0.5) on dialogue start, 1.0 on end |
| ADR-0011 | Dialogue blocking | Night transition waits for dialogue | UIManager.is_dialogue_active returns true during dialogue |

## Performance Implications

| Metric | Expected Value | Budget | Notes |
|--------|---------------|--------|-------|
| CPU (per node display) | < 0.1 ms | < 1 ms | Condition evaluation (max 25 checks) + UI update + typewriter start |
| CPU (per condition) | < 0.005 ms | < 0.05 ms | Single Dictionary lookup or method call |
| CPU (idle) | 0.0 ms | 0.0 ms | set_process(false). No per-frame cost when inactive. |
| Memory (per tree) | ~2-5 KB | < 10 KB per NPC | Resource instances with text + conditions. |
| GPU (dialogue panel) | 3-5 draw calls | ≤ 8 | Per ADR-0003: Dialogue 3-5 draw calls budget. |

## Migration Plan

New system. Implementation order:

1. Create DialogueTree, DialogueNode, DialogueChoice, DialogueCondition, DialogueConsequence Resources.
2. Create DialoguePanel Control (CanvasLayer 40) with typewriter effect and choice buttons.
3. Implement DialogueManager Autoload skeleton with flow management.
4. Implement condition evaluator with graceful degradation for TrustManager.
5. Implement consequence application.
6. Wire NPCManager.npc_interaction_requested → DialogueManager.start_dialogue().
7. Wire TimerService.set_time_scale() for dialogue slow-down.
8. Wire UIManager.is_dialogue_active for night transition blocking.
9. Create sample DialogueTree Resources for testing.
10. Write unit tests.

**Rollback plan**: DialogueManager is an Autoload that can be removed. Additive changes to UIManager and TimerService are non-breaking.

## Validation Criteria

1. start_dialogue() validates NPC availability via NPCManager.is_dialogue_available()
2. DialogueTree.get_start_node() returns correct start node
3. Condition evaluator handles all comparison types (eq, neq, gte, lte, gt, lt, exists, not_exists)
4. Condition evaluator queries all source types correctly
5. Graceful degradation: TrustManager queries return defaults when not loaded
6. Choices with failing conditions filtered out and not displayed
7. Consequence "npc_state_change" calls NPCManager.request_state_transition()
8. Consequence "trust_delta" calls TrustManager.apply_delta() when available
9. Consequence "discover_clue" calls ClueDatabase.discover_clue()
10. TimerService.set_time_scale(0.5) on dialogue start, 1.0 on end
11. UIManager.is_dialogue_active true during dialogue, false after end
12. Typewriter effect displays characters sequentially at configured speed
13. Dialogue ends on END node or empty next_node_id
14. Dialogue cannot start while already active (guard)
15. All signals emit correctly (dialogue_started, dialogue_ended, dialogue_choice_made)
16. DialoguePanel on CanvasLayer 40 (verified by layer check)
17. NightTransitionController blocked during active dialogue

## Related Decisions

- ADR-0003: UI Visual Register — CanvasLayer 40, UIManager.is_dialogue_active
- ADR-0004: Loop State Management — get_active_state_value() for conditions
- ADR-0005: Clue/Insight Unified Schema — ClueDatabase for knowledge conditions
- ADR-0008: Countdown Timer — TimerService.set_time_scale() for dialogue slow-down
- ADR-0009: NPC State Machine — NPCManager, npc_interaction_requested signal
- ADR-0011: Night Transition Controller — blocks during dialogue
- ADR-0012: NPC Trust/Suspicion — TrustManager for trust conditions (graceful degradation)
- architecture.yaml: DialogueManager owns no persistent state; all mutations delegated
