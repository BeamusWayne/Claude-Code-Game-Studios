# 房间/位置管理 (Room/Location Management)

> **Status**: GDD Complete
> **Author**: Katya + agents
> **Last Updated**: 2026-05-14
> **CD-GDD-ALIGN**: APPROVED 2026-05-14 — 4 支柱全部对齐，3 个非阻塞关注点已记录到 Open Questions
> **Implements Pillar**: 间接服务所有支柱——空间骨架（支柱 1：房间承载碎片；支柱 2：时间节奏的空间容器；支柱 3：连接在房间间发生；支柱 4：住客在房间中存在）

## Overview

房间/位置管理是七夜的空间骨架——负责旅馆房间的加载、卸载、状态管理和过渡动画。它维护一个 RoomManager 单例，按需从 PackedScene 实例化房间（同时只有一个房间在内存中），管理房间间的切换流程（9 步原子过渡：guard → pre-unload → fade-out → unload → load → apply_state → post-load → fade-in → complete），并在循环重置时通过重新实例化 PackedScene 恢复模板状态。

它不决定房间里的内容（那是叙事和美术的职责）、不处理房间内的交互检测（那是交互系统 #7 的职责）、不渲染房间（那是 Godot 渲染管的职责）。它是空间的容器——确保正确的房间在正确的时间加载、正确的状态应用、正确的过渡体验。

架构决策、接口签名和场景层级约定由 ADR-0007（Room/Location Management）定义。本 GDD 在 ADR-0007 基础上补充操作规则、状态公式、边界条件和验收标准——不重复 ADR 已定义的接口细节，而是引用它。

## Player Fantasy

每个房间是一幅独立的水墨画。在房间之间移动不是"加载关卡"——它是将目光从一幅画转向另一幅画。淡出是墨色从边缘涌入，像水填满一个盆；淡入是新的画面从宣纸中心浮现——先是建筑骨架，然后是家具，最后是房间的氛围呼吸而至。0.6 秒的过渡是一笔有意的画笔。

当夜晚重置，你再次站在同一个房间，感觉同又不同——昨夜打开的抽屉关上了，移动过的物品回到原位。房间是同一幅画，但重新绘制了。这种"相同但不同"让循环变得可触：空间记得它的模板状态，而你作为玩家记得更多。

**支柱对齐**：间接服务所有支柱。房间承载碎片（支柱 1）、过渡创造节奏性的低语停顿（支柱 2）、在房间间移动就是在连接点之间穿行（支柱 3）、每位住客的房间有其情绪和色彩（支柱 4）。

**可测试时刻**：玩家点击走廊出口，看到墨色从屏幕边缘涌入再退去，新房间从中心逐渐浮现时，是否感到"翻过了一页"而非"等了一次加载"？

## Detailed Design

### Core Rules

**规则 1：房间身份和注册表**

**规则 1.1**：每个房间有唯一 `StringName` 标识符（如 `&"lobby"`、`&"corridor"`、`&"guest_room_a"`）。RoomManager 在 `_ready()` 时从 `ROOM_PATHS` 常量字典注册所有 8 个房间。未注册的 room_id 在 GUARD 步骤导致 `request_transition()` 静默返回。

**规则 1.2**：MVP 房间集：`lobby`、`corridor`、`guest_room_a`。其余 5 个房间注册路径但 PackedScene 可不存在。若 LOAD 步骤加载失败，当前房间不卸载，过渡中止，记录警告。

**规则 1.3**：`current_room_id` 在首次成功过渡前为 `&""`。在 COMPLETE 步骤（第 9 步）原子更新——不在 LOAD 或 APPLY_STATE 期间更新。

**规则 2：房间场景结构（ADR-0007 约定）**

**规则 2.1**：每个房间 PackedScene 必须遵循固定层级：根 `Node2D` 包含四个必需子组——`Background`(z:-10)、`Interactables`(z:0)、`NPCs`(z:1)、`Exits`(z:2)。可选 `NavigationRegions`。

**规则 2.2**：RoomManager 在 LOAD 时验证场景结构。缺失必需子组记录警告但继续加载（该组视为空）。不因缺失 Background 阻塞加载。

**规则 2.3**：Interactable 发现使用 `find_children("*", "Interactable")`。需要 ADR-0006 的 Interactable 组件声明 `class_name Interactable`。搜索范围覆盖整个房间根节点（包括 Interactables、NPCs、Exits 层）。

**规则 3：过渡协议（9 步原子）**

`request_transition(target_room_id: StringName)` 执行以下 9 步，不可并发：

| 步骤 | 名称 | 操作 | 失败行为 |
|------|------|------|---------|
| 1 | GUARD | 断言 `_is_transitioning == false`、target 在 ROOM_PATHS 中、target ≠ current_room_id | 静默返回（no-op 不报错；未知 room 记录警告） |
| 2 | PRE_UNLOAD | 调用 `unregister_room_interactables()`。发信号 `room_leaving(current_room_id)` | 继续（零 interactables 合法） |
| 3 | FADE_OUT | 设 `_is_transitioning = true`。设 fade overlay `mouse_filter = STOP`。发信号 `room_transition_started`。Tween 动画 fade alpha 0→1，时长 FADE_OUT_DURATION | 不会失败 |
| 4 | UNLOAD | 当前房间 `queue_free()`。清空内部引用 | 继续（null = 首次加载） |
| 5 | LOAD | 实例化 PackedScene，add_child 到 `_room_container` | 失败时尝试回退到前一个房间；回退也失败则进入错误状态 |
| 6 | APPLY_STATE | 查询 `LoopStateManager.get_template_override()` 应用持久变异 | 无 override = 纯模板状态。属性不存在则记录警告跳过 |
| 7 | POST_LOAD | 调用 `register_room_interactables()` | 继续（零 interactables 合法） |
| 8 | FADE_IN | Tween 动画 fade alpha 1→0，时长 FADE_IN_DURATION | 不会失败 |
| 9 | COMPLETE | 设 `_is_transitioning = false`。设 fade overlay `mouse_filter = IGNORE`。更新 `current_room_id`。发信号 `room_changed(target_room_id, spawn_point_id)` 和 `room_transition_completed`。检查 `_pending_reset` | 不会失败 |

**规则 3.2**：步骤 3-8 期间不处理玩家输入。fade overlay 的 `mouse_filter = STOP` 阻止所有点击。

**规则 3.3**：LOAD 和 APPLY_STATE 在全黑屏期间执行（alpha=1），必须在 FADE_OUT_DURATION 内完成。

**规则 4：状态管理——模板与持久分离**

**规则 4.1**：房间实例化后处于纯模板状态（PackedScene 原样）。当夜修改（打开抽屉、移动物品）通过 `set_room_state()` 应用于运行时实例，不自动持久。

**规则 4.2**：`set_room_state()` 只修改当夜模板状态——变更在 `advance_night()` 后丢失。持久变更必须通过 `LoopStateManager.register_consequence()` 注册（RoomManager 是消费者，不是生产者）。

**规则 4.3**：APPLY_STATE 步骤查询 `LoopStateManager.get_template_override("room_" + room_id, property)` 获取持久变异。无 override = 纯模板。

**规则 4.4**：持久 override 目标属性在房间实例上不存在时（如场景重新设计），记录警告跳过，不失败过渡。

**规则 5：Interactable 注册生命周期**

**规则 5.1**：RoomManager 拥有注册所有权。Interactable 组件**不自注册**（不在 `_ready()` 中调用 InteractionBus）。Interactable 暴露 `get_registration_info() -> Dictionary` 方法，RoomManager 在 POST_LOAD 调用此方法获取注册信息。

**规则 5.2**：`unregister_room_interactables()` 在 `queue_free()` **之前**调用，确保 InteractionBus 无悬空引用。

**规则 5.3**：`apply_template_reset()` 执行完整的注销-重注册周期：旧实例注销 → PackedScene 重新实例化 → 新实例注册。

**规则 6：出口处理**

**规则 6.1**：出口 Interactable 以 `target_type: &"exit"` 区分，位于 Exits(z:2) 子组。每个出口有两个导出属性：`destination_room_id: StringName` 和 `spawn_point_id: StringName`。

**规则 6.2**：RoomManager 监听 `InteractionBus.interaction_detected`，过滤 `target_type == &"exit"` 事件，调用 `request_transition(event.target_id)`。

**规则 6.3**：`spawn_point_id` 从事件 `metadata.spawn_point` 提取，包含在 `room_changed` 信号 payload 中。NPC State Machine 和 Player Position 系统消费此信息放置角色。

**规则 7：夜晚重置集成**

**规则 7.1**：RoomManager 连接两个 LoopStateManager 信号：
- `night_ready(night)` → 初始加载，读取 PlayerState.current_room（新游戏默认 `&"lobby"`）
- `night_advanced(old, new)` → 调用 `apply_template_reset()`

**规则 7.2**：`apply_template_reset()` 重新实例化当前房间 PackedScene → 应用持久变异 → 重注册 interactables。room_id 不变。

**规则 7.3**：若 `night_advanced` 在 `_is_transitioning == true` 时触发，设 `_pending_reset = true`。在 COMPLETE 步骤检查并执行。

**规则 7.4**：`_pending_reset` 为 true 时，重置应用于新加载的房间（如果过渡刚完成）。正确——`night_advanced` 意味着"重置所有房间"。

**规则 8：Fade Overlay**

**规则 8.1**：Fade overlay 是 CanvasLayer(100) 上的全屏黑色 ColorRect（`anchors_preset = PRESET_FULL_RECT`）。Layer 100 高于所有 UI 层（ADR-0003）。

**规则 8.2**：初始状态 `self_modulate.a = 1.0`（全黑），覆盖初始加载。bootstrap FADE_IN 后变为 0。

**规则 8.3**：动画使用 `create_tween()`。FADE_OUT 用 `Tween.EASE_IN`，FADE_IN 用 `Tween.EASE_OUT`——创造"墨色涌入/退去"的节奏感。

**规则 8.4**：过渡期间 `mouse_filter = STOP`（阻塞输入），COMPLETE 后恢复 `IGNORE`。确保玩家不能在过渡中点击。

**规则 9：错误状态**

**规则 9.1**：LOAD 失败且回退也失败时，`_is_transitioning` 保持 true，黑屏，发信号 `room_load_failed`。致命错误——仅在缺场景文件时发生。

**规则 9.2**：`apply_template_reset()` 在 `current_room_id == &""` 时为 no-op。

### States and Transitions

RoomManager 有单一状态维度——过渡状态：

| 状态 | 入口条件 | 行为 | 退出条件 |
|------|---------|------|---------|
| IDLE | 启动时 / COMPLETE 步骤后 | 接受新 transition 请求和 night_advanced | request_transition() GUARD 通过 |
| TRANSITIONING | GUARD 通过后 | 阻塞新请求，执行 9 步流程 | COMPLETE 步骤 → IDLE |
| ERROR | LOAD + 回退都失败 | 黑屏，发 room_load_failed | 不可恢复（仅开发期） |

**状态不变量**：
- `_is_transitioning == false` → 可响应新请求
- `_is_transitioning == true` → GUARD 已通过，InteractionBus 出口事件被忽略
- `_pending_reset` 只在 `_is_transitioning == true` 时可为 true
- `current_room_id == &""` → 首次加载前有效

### Interactions with Other Systems

| 系统 | 数据流方向 | 接口拥有者 | 接口细节 |
|------|----------|----------|---------|
| LoopStateManager (#1) | LS → RM | LS | `night_ready` 触发 bootstrap，`night_advanced` 触发 template reset，`get_template_override()` 用于 APPLY_STATE |
| LoopStateManager (#1) | RM → LS（只读） | LS | RM 读取 PlayerState.current_room 确定起始房间 |
| InteractionBus (ADR-0006) | Bus → RM | Bus | `interaction_detected` 信号，RM 过滤 exit 类型事件 |
| InteractionBus (ADR-0006) | RM → Bus | RM | `register/unregister_room_interactables()` 管理 Interactable 生命周期 |
| NPC State Machine (#6) | RM → NPC | RM | `room_changed` 信号 + spawn_point 信息，NPC 据此放置 |
| Event Scheduler (#9) | RM → ES | RM | `room_changed` + `current_room_id` 查询，ES 用于房间绑定事件 |
| Room Navigation UI (#22) | RM → UI | RM | `room_changed` + `room_transition_started/completed` 信号，UI 显示当前房间名 |
| Save/Load (#4) | SL → RM | RM | deserialize 后 `night_ready` 触发房间加载，无直接序列化接口 |
| Player Position | RM → PP | RM | spawn_point 通过 `room_changed` 信号 payload 传递 |

## Formulas

### F1: Room Memory Footprint

`M_room = N_nodes * m_node + N_interactables * m_interactable + m_textures + m_audio + m_overhead`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 节点数 | `N_nodes` | int | 20–50 | 房间 PackedScene 中的节点数 |
| 节点内存 | `m_node` | float | 0.002–0.005 MB | 每个 Node2D 开销 |
| 可交互物数 | `N_interactables` | int | 0–30 | 房间内 Interactable 组件数 |
| 可交互物内存 | `m_interactable` | float | 0.005–0.01 MB | 每个 Interactable 开销 |
| 纹理内存 | `m_textures` | float | 2–30 MB | 背景和精灵纹理 |
| 音频内存 | `m_audio` | float | 0–5 MB | 房间环境音 |
| 场景开销 | `m_overhead` | float | 0.5 MB (固定) | Godot 场景实例化开销 |

**Output Range**: 3–60 MB per room。典型值：10–25 MB。
**Example**: `35*0.004 + 20*0.008 + 15 + 1 + 0.5 = 16.8 MB` per active room。MVP 3 房间 ~32 MB，Full 8 房间 ~57 MB（占 512 MB 天花板的 11%）。

### F2: Transition Time Budget

`T_during_blackout = T_unload + T_load + T_apply_state`

`T_load = N_nodes * t_instantiate + N_interactables * t_component_init`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 卸载时间 | `T_unload` | float | 1–5 ms | queue_free() 调用 |
| 加载时间 | `T_load` | float | 5–50 ms | PackedScene 实例化 |
| 状态应用 | `T_apply_state` | float | 0.5–5 ms | 持久 override 应用 |
| 黑屏窗口 | `FADE_OUT_DURATION` | float | 300 ms (固定) | 淡出持续时间 |

**Output Range**: `T_during_blackout` = 25–65 ms。Margin = 300 - 65 = 235 ms（79% 空闲）。
**Example**: 50 节点 + 30 interactables + 10 overrides → T = 63.5 ms，margin 236.5 ms。

### F3: Interactable Scan Cost

`T_scan = N_children * t_per_child`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 子节点总数 | `N_children` | int | 20–80 | 房间场景树中的所有节点 |
| 每节点开销 | `t_per_child` | float | ~0.00002 s | 树遍历 + 类型检查 |

**Output Range**: 0.4–1.6 ms per scan（每次过渡 2 次扫描 = 0.8–3.2 ms）。
**Example**: 50 节点 → 1 ms per scan，2 次扫描 = 2 ms total。

### F4: Max Rooms Before Memory Ceiling

`N_max = floor((M_ceiling - M_engine - M_systems) / M_packed)`

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 内存天花板 | `M_ceiling` | float | 512 MB (固定) | 平台内存限制 |
| 引擎基础 | `M_engine` | float | 80–120 MB | Godot 4.6 基础内存 |
| 系统开销 | `M_systems` | float | 30–60 MB | 音频、UI、着色器、游戏状态 |
| 单房间缓存 | `M_packed` | float | 3–20 MB | 单个 PackedScene 资源内存 |

**Output Range**: 8–70 rooms（远超实际需求 8 房间）。
**Example**: `(512 - 100 - 45) / 5 = 73` rooms theoretical max。8 房间使用 ~15% 可用内存。

## Edge Cases

### 过渡操作边界

- **如果 `request_transition()` 在 `_is_transitioning == true` 时被调用**：GUARD 步骤静默返回。不排队、不报错。玩家可能需要再次点击出口。
- **如果 `request_transition()` 的 target 等于 `current_room_id`**：GUARD 步骤静默返回（no-op）。玩家已在目标房间。
- **如果 `request_transition()` 的 target 不在 `ROOM_PATHS` 中**：GUARD 步骤记录警告后返回。玩家留在当前房间。
- **如果 LOAD 步骤 PackedScene 加载失败**：尝试重新加载前一个房间（回退）。回退成功则玩家留在旧房间；回退也失败则进入 ERROR 状态（黑屏 + room_load_failed 信号）。

### 状态管理边界

- **如果 APPLY_STATE 步骤的 override 目标属性在房间实例上不存在**：记录警告，跳过该 override，不失败过渡。
- **如果 `set_room_state()` 在无加载房间时被调用**（`current_room_id == &""`）：静默返回。无房间可修改。
- **如果 `set_room_state()` 尝试修改不存在的属性**：`set()` 调用返回 null（Godot 行为），记录警告。不崩溃。
- **如果 `get_room_state()` 查询未加载的房间**：返回空字典 `{}`。调用者用 `.is_empty()` 判断。

### 夜晚重置边界

- **如果 `night_advanced` 在过渡进行中触发**：设 `_pending_reset = true`，不中断当前过渡。COMPLETE 步骤检查并执行重置。
- **如果 `night_advanced` 连续触发两次**（理论上不可能）：第二次覆盖 `_pending_reset = true`（已是 true），无额外影响。
- **如果 `apply_template_reset()` 在 `current_room_id == &""` 时被调用**：no-op。bootstrap load 会处理。
- **如果 `_pending_reset` 在 COMPLETE 步骤为 true 但过渡目标房间与之前不同**：重置应用于新房间。正确——`night_advanced` 意味着"重置所有房间"。

### Interactable 生命周期边界

- **如果房间中有零个 Interactable**：`find_children` 返回空数组，register/unregister 调用遍历零次。合法。
- **如果 Interactable 组件未声明 `class_name Interactable`**：`find_children("*", "Interactable")` 返回空数组。所有 interactable 不被发现——房间功能降级但不崩溃。开发期应通过场景验证捕获。
- **如果 `unregister_room_interactables()` 在 `queue_free()` 之后被调用**（违反规则 5.2）：InteractionBus 持有已释放节点的引用。Godot 会将已释放节点转为 null——InteractionBus 应在调用前检查引用有效性。防御性编程要求必须在 queue_free 前注销。

### 出口处理边界

- **如果出口的 `destination_room_id` 为 `&""`**：GUARD 步骤拒绝（room_id 为空）。出口不触发过渡。
- **如果出口的 `spawn_point_id` 为 `&""`**：过渡正常执行，但 `room_changed` 信号的 spawn_point 为空。Player Position 系统应使用默认位置。
- **如果 InteractionBus 在 `_is_transitioning == true` 时发出 exit 事件**：RoomManager 忽略该事件（过滤条件加上 `_is_transitioning` 检查）。

### Fade Overlay 边界

- **如果 fade 动画被中断**（如 `queue_free` 在动画完成前触发）：Tween 自动在节点释放时取消。不会产生悬空动画。但此情况不应发生——过渡流程保证步骤顺序。
- **如果两个过渡请求在同一帧内到达**：第一个通过 GUARD 设 `_is_transitioning = true`，第二个被 GUARD 拒绝。无竞态。

### 性能边界

- **如果房间节点增长到 200+**：LOAD 步骤可能需要 100+ ms，超出 FADE_OUT_DURATION (300ms) 的舒适区但仍可接受。应通过场景设计约束防止（每个房间 ≤50 节点）。
- **如果持久 override 增长到 50+**：APPLY_STATE 步骤线性增长但每条 override 仅一次 `set()` 调用（~0.05ms），50 条 = ~2.5ms。可忽略。

## Dependencies

### 上游依赖（本系统依赖的）

| 系统 | 依赖类型 | 接口 | 状态 |
|------|---------|------|------|
| LoopStateManager (#1) | 硬依赖——信号触发 + 状态查询 | `night_ready` 信号、`night_advanced` 信号、`get_template_override()` | GDD Complete |
| InteractionBus (ADR-0006) | 硬依赖——事件分发 + Interactable 注册 | `interaction_detected` 信号、`register/unregister_interactable()` | ADR Accepted，GDD 未设计 |
| PlayerState (LoopStateManager 内) | 软依赖——起始房间读取 | `current_room` 属性 | 随 LoopStateManager GDD 一起 |

### 下游依赖（依赖本系统的）

| 系统 | 依赖类型 | 接口 | 状态 |
|------|---------|------|------|
| 交互系统 (#7) | 硬依赖——房间结构承载 Interactable | 房间场景层级（Interactables z:0）、Interactable 生命周期 | 未设计 |
| 事件调度器 (#9) | 硬依赖——房间绑定事件 | `room_changed` 信号、`current_room_id` 查询 | 未设计 |
| NPC 状态机 (#6) | 硬依赖——NPC 放置位置 | `room_changed` 信号 + spawn_point、房间 NPCs(z:1) 子组 | 未设计 |
| 房间导航 UI (#22) | 硬依赖——导航信息 | `room_changed` 信号、`room_transition_started/completed` 信号 | 未设计 |
| 住客审问 (#15) | 软依赖——对话发生在房间中 | 通过 NPC State Machine 间接依赖 | 未设计 |
| Player Position (隐含) | 软依赖——角色放置 | `room_changed` 信号中的 spawn_point_id | 未设计 |

## Tuning Knobs

| Knob | Type | Default | Range | Affects |
|------|------|---------|-------|---------|
| `FADE_OUT_DURATION` | float | 0.3 s | 0.1–1.0 s | 过渡黑屏出现速度。低于 0.2 s 可能在低端硬件上露出加载闪烁 |
| `FADE_IN_DURATION` | float | 0.3 s | 0.1–1.0 s | 新房间显现速度。低于 0.2 s 感觉突兀 |
| `FADE_EASE_OUT` | int | `Tween.EASE_IN` | Godot Tween ease 常量 | 淡出曲线——影响"墨色涌入"的加速感 |
| `FADE_EASE_IN` | int | `Tween.EASE_OUT` | Godot Tween ease 常量 | 淡入曲线——影响"画面浮现"的减速感 |
| `ROOM_PATHS` | Dictionary | 8 条路径映射 | — | 房间注册表——添加/移除房间 |
| `DEFAULT_START_ROOM` | StringName | `&"lobby"` | 任何已注册 room_id | 新游戏的起始房间 |
| `MAX_NODES_PER_ROOM` | int | 50 | 20–200 | 场景复杂度约束——用于 LOAD 时验证 |

**Knob 交互**：`FADE_OUT_DURATION` 和 `FADE_IN_DURATION` 的总和决定玩家每次房间切换的不可操作时间。0.6 s 是冒险游戏的舒适区间。减少总和提升响应感但增加闪烁风险。

## Visual/Audio Requirements

- **Fade overlay**：黑色 ColorRect，CanvasLayer 100。淡出使用 `Tween.EASE_IN`（加速墨色涌入），淡入使用 `Tween.EASE_OUT`（减速画面浮现）。美术团队可考虑在 fade 过程中叠加纸张纹理或水墨扩散效果，但这是表现层优化，不影响 RoomManager 接口。
- **房间切换**：无音频需求。过渡音效（如关门声、脚步声）由音频系统独立触发，不通过 RoomManager。

## UI Requirements

- 房间导航 UI (#22) 消费 `room_changed` 和 `room_transition_started/completed` 信号。RoomManager 不直接管理 UI 元素。
- 过渡期间 UI 应禁用（fade overlay 的 `mouse_filter = STOP` 已处理点击阻断，但 UI 系统应额外响应 `room_transition_started` 禁用交互反馈）。

## Acceptance Criteria

### 过渡生命周期

- AC-T1-01: Given current_room_id = "lobby", When request_transition("corridor") called, Then 9 步顺序执行，current_room_id 更新为 "corridor"，room_changed 信号发射
- AC-T1-02: Given _is_transitioning = true, When request_transition("guest_room_a") called, Then 静默返回，current_room_id 不变
- AC-T1-03: Given current_room_id = "lobby", When request_transition("lobby") called, Then no-op 返回
- AC-T1-04: Given request_transition("nonexistent"), Then GUARD 记录警告后返回
- AC-T1-05: Given 正常过渡, When 步骤 3-8 执行中, Then 玩家输入被 fade overlay mouse_filter=STOP 阻断

### 状态管理

- AC-S1-01: Given 房间已加载, When set_room_state("lobby", "door_open", true), Then 房间实例对应属性被修改
- AC-S1-02: Given advance_night() 触发, When apply_template_reset() 执行, Then 房间重新实例化为 PackedScene 默认状态（当夜修改丢失）
- AC-S1-03: Given 持久 override 存在, When APPLY_STATE 步骤执行, Then override 正确应用到新房间实例
- AC-S1-04: Given 持久 override 目标属性不存在, When APPLY_STATE 执行, Then 记录警告跳过，不失败过渡

### Interactable 生命周期

- AC-I1-01: Given 房间有 20 个 Interactable, When POST_LOAD 执行, Then InteractionBus.register_interactable() 被调用 20 次
- AC-I1-02: Given 房间有 20 个 Interactable, When PRE_UNLOAD 执行, Then InteractionBus.unregister_interactable() 在 queue_free() 之前被调用 20 次
- AC-I1-03: Given Interactable 未声明 class_name, When find_children 执行, Then 返回空数组（不崩溃）
- AC-I1-04: Given apply_template_reset() 执行, Then 旧实例注销 → 重新实例化 → 新实例注册的完整周期完成

### 夜晚重置集成

- AC-N1-01: Given night_ready 信号, When 游戏启动, Then request_transition(DEFAULT_START_ROOM) 被调用
- AC-N1-02: Given night_advanced 信号, When _is_transitioning = false, Then apply_template_reset() 立即执行
- AC-N1-03: Given night_advanced 信号, When _is_transitioning = true, Then _pending_reset 设为 true，在 COMPLETE 步骤执行
- AC-N1-04: Given current_room_id = "", When apply_template_reset() 被调用, Then no-op（不崩溃）

### Fade Overlay

- AC-F1-01: Given 过渡开始, When FADE_OUT 执行, Then self_modulate.a 从 0 动画到 1，时长 FADE_OUT_DURATION
- AC-F1-02: Given FADE_IN 完成, When COMPLETE 步骤执行, Then mouse_filter 恢复为 IGNORE
- AC-F1-03: Given 游戏启动, When 首次 FADE_IN 完成, Then 初始黑屏变为可见的第一个房间

### 错误处理

- AC-E1-01: Given PackedScene 加载失败, When 回退房间也加载失败, Then _is_transitioning 保持 true，room_load_failed 信号发射
- AC-E1-02: Given 正常过渡, When 步骤顺序执行, Then room_transition_started 在 UNLOAD 前发射，room_transition_completed 在 FADE_IN 后发射

### 性能

- AC-P1-01: Given 典型房间（50 节点，20 interactables）, When 过渡执行, Then LOAD + APPLY_STATE 在 100 ms 内完成（黑屏窗口 300 ms 的 1/3）
- AC-P1-02: Given 8 房间注册, When 游戏运行, Then 总房间内存 < 60 MB（512 MB 天花板的 12%）

## Open Questions

1. **Interactable 自注册 vs RoomManager 注册**：本 GDD 决定 RoomManager 拥有注册权（规则 5.1），但 ADR-0006 显示 Interactable 在 `_ready()` 中自注册。需在交互系统 GDD (#7) 中确认最终方案，并更新 ADR-0006 或 ADR-0007 中的矛盾描述。
2. **Spawn point 传递机制**：`room_changed` 信号包含 spawn_point_id，但 Player Position 系统尚未设计。确认信号 payload 是否足够，还是需要独立信号。
3. **Room cache 策略**：当前无缓存（每次重新实例化）。若 profiling 发现频繁回访的房间加载有 hitch，可添加 LRU-1 缓存（保留最近 1 个已卸载房间实例）。
4. **房间场景验证工具**：规则 2.2 的验证逻辑是否应作为编辑器插件（debug build 自动检查所有房间场景结构）？对开发效率有帮助但不影响运行时。
