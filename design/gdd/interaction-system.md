# 交互系统 (Interaction System)

## 1. Overview

交互系统管理玩家与游戏世界中所有可交互对象之间的输入检测和事件分发。InteractionBus Autoload 单例作为中央事件总线，接收 Area2D 节点的输入信号，按优先级解决冲突（帧缓冲延迟一帧），将事件路由到目标处理器。Interactable 组件（附加到可交互节点上）负责注册/注销和配置交互参数。系统不包含任何游戏逻辑——仅处理输入检测、优先级排序和事件分发。

## 2. Player Fantasy

**"手指触碰世界的每一个角落"** — 玩家点击任何看起来有趣的东西，都能得到回应。书架上的书可以被翻阅，桌上的茶杯可以被打量，走廊尽头的门可以被推开。每一次点击都是一次探索，每一次交互都让世界变得更真实。交互系统是玩家与七夜客栈之间的触觉桥梁。

## 3. Detailed Rules

### 3.1 InteractionBus Autoload

- 全局单例，挂载为 Autoload
- 不持有游戏状态——仅负责事件路由
- 每帧收集所有待处理的交互请求，在 `_process()` 末尾按优先级排序后分发
- 提供 `register_interactable(interactable)` 和 `unregister_interactable(interactable_id)` 接口
- 提供 `get_interactables_in_group(group_name)` 批量查询

### 3.2 Interactable 组件

- RefCounted 资源，附加到可交互节点上
- 每个实例包含：
  - `interactable_id`: StringName 唯一标识
  - `display_name`: String 显示名称（用于 UI 提示）
  - `priority`: int 优先级（数值越高越优先处理）
  - `group`: StringName 分组标识（用于批量查询/禁用）
  - `input_methods`: Array[InputMethod] 支持的输入方式（MOUSE, TOUCH）
  - `click_detector`: ClickDetector 点击检测器引用
  - `handler_path`: NodePath 事件处理器节点路径
  - `enabled`: bool 是否启用
- 生命周期：跟随所在节点的 `_enter_tree()` / `_exit_tree()` 自动注册/注销

### 3.3 输入检测

- 使用 Area2D + input_event 信号检测点击
- 支持两种输入方式：
  - **鼠标点击**：左键单击触发
  - **触摸点击**：单指点击触发
- 每次输入事件附带 `input_method` 标签（`InputMethod.MOUSE` 或 `InputMethod.TOUCH`）
- 长按检测：按住超过 LONG_PRESS_THRESHOLD 秒触发长按事件（未来扩展）

### 3.4 优先级解决

- 当多个 Interactable 重叠时，按 priority 数值降序排序
- 同优先级按注册顺序（后注册的优先，即 z-index 更高的优先）
- 每帧最多分发一个交互事件（取优先级最高的）
- 使用帧缓冲：当前帧收集，下一帧分发（避免 Area2D 信号回调中的状态不一致）

### 3.5 事件分发

- InteractionBus 发出 `interaction_triggered(interactable_id: StringName, input_method: InputMethod)` 信号
- 处理器通过连接此信号并过滤 `interactable_id` 来响应
- 处理器可以是任何节点——Interactable 不假设处理器的类型
- 分发后清空帧缓冲区

### 3.6 分组管理

- Interactable 可属于一个或多个分组
- 支持批量操作：启用/禁用指定分组的所有 Interactable
- 典型用途：
  - `"room_exits"` — 房间出口交互
  - `"npc"` — NPC 交互
  - `"clue_objects"` — 可调查的线索物品
  - `"dialogue"` — 对话相关交互

### 3.7 房间切换集成

- 房间切换期间，InteractionBus 暂停事件分发（`is_accepting = false`）
- RoomManager 在切换开始时调用 `InteractionBus.set_accepting(false)`
- RoomManager 在切换完成后调用 `InteractionBus.set_accepting(true)` 并重新扫描当前房间的 Interactable
- 切换期间收到的输入事件被丢弃

## 4. Formulas

### 帧缓冲延迟

```
frame_delay = 1 frame
collection_phase: input_event → buffer
dispatch_phase: _process() → sort buffer → emit signal → clear buffer
```

### 优先级排序

```
sort_key = interactable.priority * 1000 + registration_order
// priority 越高越优先，同 priority 后注册的越优先
```

### 点击检测范围

```
interaction_area = Area2D collision shape
click_threshold: 任何在 collision shape 内的 input_event
```

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 多个重叠 Interactable 被同时点击 | 按优先级排序，只分发最高优先级的 |
| Interactable 在帧缓冲期间被注销 | 分发时跳过已注销的，不报错 |
| InteractionBus 未初始化时 Interactable 注册 | 静默忽略，下次 `_process` 时重新扫描 |
| 房间切换期间的点击事件 | 丢弃（is_accepting = false） |
| 重复注册同一 interactable_id | 更新而非报错（更新配置） |
| 注销不存在的 interactable_id | 静默忽略 |
| Interactable enabled = false 时收到点击 | 不加入帧缓冲区 |
| 所有 Interactable 都被禁用 | 点击无响应——正确行为 |
| 触摸和鼠标同时输入 | 分别标记 input_method，各自进入缓冲区 |
| 帧缓冲为空时 _process 调用 | 跳过分发——无开销 |

## 6. Dependencies

### 上游依赖
- **循环状态管理 (#1)** — 无直接依赖，但 Interactable 注册路径可能引用 LoopStateManager
- **房间/位置管理 (#3)** — RoomManager 控制 InteractionBus 的启用/禁用和 Interactable 扫描
- **ADR-0006 交互事件总线** — 本系统的架构决策基础

### 下游被依赖
- **NPC 状态机 (#6)** — NPC 点击事件通过 InteractionBus 路由
- **NPC 信任/怀疑 (#13)** — NPC 交互触发信任变化
- **条件性对话树 (#14)** — 对话由 NPC/物品交互触发
- **住客审问 (#15)** — 审问由 NPC 交互触发
- **线索发现 (#10)** — 线索物品交互触发发现
- **房间导航 UI (#22)** — 出口交互触发房间切换

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| LONG_PRESS_THRESHOLD | float | 0.5 | 0.2-1.0 | 长按判定时间（秒） |
| default_priority | int | 0 | 0-100 | Interactable 默认优先级 |
| npc_priority | int | 50 | 0-100 | NPC 交互优先级 |
| exit_priority | int | 30 | 0-100 | 房间出口优先级 |
| clue_object_priority | int | 10 | 0-100 | 线索物品优先级 |
| frame_buffer_enabled | bool | true | — | 是否启用帧缓冲 |

## 8. Acceptance Criteria

1. InteractionBus 注册/注销 Interactable，查询接口返回正确结果
2. 多个重叠 Interactable 点击时，按优先级排序只分发最高优先级的
3. 事件附带 input_method 标签（MOUSE 或 TOUCH）
4. 帧缓冲延迟一帧分发
5. Interactable enabled = false 时不响应点击
6. 房间切换期间（is_accepting = false）事件被丢弃
7. 分组批量查询 `get_interactables_in_group()` 返回正确子集
8. 重复注册同一 ID 更新配置而非报错
9. 注销不存在的 ID 静默忽略
10. 无 Interactable 时点击无响应且无错误
11. 信号 `interaction_triggered` 参数正确（interactable_id + input_method）
12. Interactable 跟随节点生命周期自动注册/注销

## Open Questions

- Interactable 是否需要支持"悬停"状态（鼠标悬停时显示名称提示）？移动端不支持悬停。
- 长按交互是否在 MVP 中实现，还是推迟到 Feature 层？
- Interactable 的 ClickDetector 是否应支持双击检测？
