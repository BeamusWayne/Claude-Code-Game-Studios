# 房间导航 UI (Room Navigation UI)

**System ID**: #22
**Category**: Presentation, MVP, Presentation Layer
**Status**: GDD Complete
**Date**: 2026-05-15

---

## 1. Overview

房间导航 UI 是七夜游戏的方位感知层，在 CanvasLayer 20 上显示当前房间中文名称（顶部横条）和可用的出口按钮（底部横条）。顶部横条高 48px，显示 room_labels 字典映射的房间名称（如"大厅"、"走廊"、"客房 A"）。底部横条高 48px，根据当前房间的 room_connections 配置动态生成出口按钮，每个按钮使用朱砂红边框的印章风格样式。导航在两种情况下被禁用：房间过渡进行中（RoomManager.room_transition_started/completed 信号）和对话活跃期间（DialogueManager.dialogue_started/ended 信号）。禁用时出口按钮变灰（modulate.a = 0.4）且 disabled，顶部横条在对话期间变淡（modulate.a = 0.3）。点击出口按钮发出 `navigation_requested(room_id)` 信号并调用 RoomManager.request_transition()。

## 2. Player Fantasy

**"印章之路"** -- 你站在大厅里，屏幕底部有两个朱砂红色的印章按钮，上面写着"走廊"。你点击一个，按钮微微颤动确认，屏幕开始暗下来。你没有选择"加载"或"传送"--你选择了一条路，像是在纸上按下一个印章。过渡完成后，顶部横条的文字从"大厅"变成了"走廊"，底部的出口按钮也变了--现在有"大厅"和"客房 A"两个选项。但如果你正在和靛蓝对话，那些按钮会变暗变淡，告诉你现在不是移动的时候。专注于眼前的人，路不会消失。

## 3. Detailed Rules

### 3.1 CanvasLayer 层级

- RoomNavigationUI 位于 CanvasLayer 20，高于 HUD（Layer 10），低于对话面板（Layer 40）和笔记本（Layer 50）
- 层级分配遵循 ADR-0003（UI Visual Register System）
- 过渡期间导航禁用，对话期间导航禁用，但 UI 始终可见（仅改变交互状态和透明度）

### 3.2 布局结构

```
RoomNavigationUI (CanvasLayer 20)
  ├─ TopBar (Control, 全宽, 顶部 48px)
  │    ├─ Background (ColorRect, 半透明白色)
  │    └─ RoomNameLabel (Label, 居中, 14px, INK_TEXT_COLOR)
  └─ BottomBar (Control, 全宽, 底部 48px)
       ├─ Background (ColorRect, 半透明白色)
       └─ ExitBar (HBoxContainer, 居中对齐, 间距 8px, 边距 12px)
            ├─ ExitButton_lobby (Button, 44x44+, 印章风格)
            └─ ExitButton_corridor (Button, 44x44+, 印章风格)
```

### 3.3 房间显示名称

房间显示名称通过 `room_labels` 字典映射：

| room_id | 中文标签 |
|---------|---------|
| lobby | 大厅 |
| corridor | 走廊 |
| guest_room_a | 客房 A |

- 未在 room_labels 中注册的 room_id 直接显示 room_id 字符串（`String(_current_room)`）
- room_labels 是数据驱动字典，标注为"可提取到外部配置"

### 3.4 房间连接配置

房间出口连接通过 `room_connections` 字典定义，每个房间映射到出口数组：

```
lobby -> [{id: "corridor", label: "走廊"}]
corridor -> [{id: "lobby", label: "大厅"}, {id: "guest_room_a", label: "客房 A"}]
guest_room_a -> [{id: "corridor", label: "走廊"}]
```

- 数据结构：`room_connections[room_id] -> Array[{id: StringName, label: String}]`
- 未在 room_connections 中注册的房间显示空底栏（无出口按钮）
- room_connections 是数据驱动字典，标注为"可提取到外部配置"

### 3.5 出口按钮样式

出口按钮使用 StyleBoxFlat 实现印章风格：

| 状态 | 背景色 | 边框色 | 边框宽度 | 圆角 | 内边距 | 文字颜色 |
|------|--------|--------|---------|------|--------|---------|
| Normal | 白色半透明 (1,1,1,0.6) | 朱砂红 (0.545,0,0) | 2px all | 4px all | 8px all | 默认 |
| Hover | 朱砂红 (0.545,0,0) | 朱砂红 (0.545,0,0) | 2px all | 4px all | 8px all | 白色 |
| Pressed | 朱砂红半透明 (0.545,0,0,0.8) | 朱砂红 (0.545,0,0) | 2px all | 4px all | 8px all | 白色 |
| Focus | 同 Hover | 同 Hover | 同 Hover | 同 Hover | 同 Hover | 白色 |

- 按钮最小尺寸：44x44px（MIN_TOUCH_TARGET）
- 按钮文本：exit_info.label（如"走廊"、"大厅"）
- 按钮字号：14px（EXIT_FONT_SIZE）
- 按钮水平对齐：SIZE_SHRINK_CENTER（居中收缩）
- 按钮命名："ExitButton_" + room_id（用于调试）

### 3.6 导航状态控制

导航按钮在以下情况下禁用：

| 条件 | 来源 | 效果 |
|------|------|------|
| 房间过渡进行中 | RoomManager.room_transition_started/completed | _is_transitioning = true/false，底栏 modulate.a = 0.4，按钮 disabled = true |
| 对话活跃 | DialogueManager.dialogue_started/ended | _is_dialogue_active = true/false，底栏 modulate.a = 0.4 + disabled，顶栏 modulate.a = 0.3 |

**is_navigation_enabled()** 返回：`not _is_transitioning and not _is_dialogue_active`

**视觉反馈**：
- 导航启用时：底栏 modulate.a = 1.0，按钮 enabled
- 导航禁用时：底栏 modulate.a = 0.4，按钮 disabled
- 对话期间顶栏额外变淡：modulate.a = 0.3

### 3.7 房间切换流程

当 RoomManager 发出 `room_changed(room_id)` 信号时：

1. `_is_transitioning` 设为 false
2. 调用 `update_for_room(room_id)`
3. update_for_room 更新 _current_room
4. `_update_room_name()` 根据 room_labels 设置顶栏文本
5. `_update_exit_buttons()` 清除旧按钮，根据 room_connections 创建新按钮

### 3.8 导航请求

点击出口按钮时：

1. 发出 `navigation_requested(target_id)` 信号
2. 调用 `_request_room_transition(target_id)`
3. 如果 `is_navigation_enabled()` 返回 false，提前返回（不发起过渡）
4. 如果 RoomManager 存在且有 `request_transition` 方法，调用 `RoomManager.request_transition(target_id)`

### 3.9 信号连接

RoomNavigationUI 连接以下信号：

**RoomManager**（/root/RoomManager）：
- `room_changed(room_id: StringName)` -> 更新房间名和出口按钮
- `room_transition_started(from: StringName, to: StringName)` -> 设 _is_transitioning = true，禁用导航
- `room_transition_completed(room_id: StringName)` -> 设 _is_transitioning = false，启用导航

**DialogueManager**（/root/DialogueManager）：
- `dialogue_started(npc_id: StringName)` -> 设 _is_dialogue_active = true，禁用导航
- `dialogue_ended(npc_id: StringName)` -> 设 _is_dialogue_active = false，启用导航

### 3.10 依赖注入

RoomManager 和 DialogueManager 通过 `get_node_or_null()` 获取。测试可通过 `set_room_manager()` 和 `set_dialogue_manager()` 注入 mock 对象。

## 4. Formulas

### 4.1 导航启用判定

**Named Expression**:

```
is_navigation_enabled = (not _is_transitioning) and (not _is_dialogue_active)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `_is_transitioning` | bool | true/false | 房间过渡进行中 |
| `_is_dialogue_active` | bool | true/false | 对话活跃中 |
| `is_navigation_enabled` | bool | true/false | 导航是否可用 |

**Worked Example**: 对话中 + 无过渡
- is_navigation_enabled = (not false) and (not true) = true and false = false（禁用）

### 4.2 房间名称查找

**Named Expression**:

```
display_name = room_labels.get(current_room, String(current_room))
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `current_room` | StringName | 已注册 room_id | 当前房间标识符 |
| `room_labels` | Dictionary | 3 entries (MVP) | room_id -> 中文名称映射 |
| `display_name` | String | -- | 顶栏显示的房间名称 |

**Worked Example**: current_room = "corridor"
- display_name = room_labels.get("corridor", "corridor") = "走廊"

### 4.3 出口按钮数量

**Named Expression**:

```
button_count = room_connections.get(current_room, []).size()
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `current_room` | StringName | 已注册 room_id | 当前房间标识符 |
| `room_connections` | Dictionary | 3 entries (MVP) | room_id -> 出口数组映射 |
| `button_count` | int | 0--N | 底栏显示的按钮数量 |

**Worked Example**: current_room = "corridor"
- exits = [{id: "lobby", label: "大厅"}, {id: "guest_room_a", label: "客房 A"}]
- button_count = 2

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| RoomManager 为 null | 信号不连接，update_for_room 不被自动触发；手动调用 update_for_room 仍可工作 |
| DialogueManager 为 null | 对话信号不连接，_is_dialogue_active 保持 false |
| update_for_room 传入未注册的 room_id | 顶栏显示 room_id 字符串（String(room_id)），底栏无按钮 |
| room_connections 中当前房间无出口 | 底栏显示空 ExitBar（无按钮） |
| room_labels 中当前房间无映射 | 顶栏显示 room_id 字符串（get 的默认值） |
| 过渡期间点击出口按钮 | is_navigation_enabled() 返回 false，_request_room_transition 提前返回 |
| 对话期间点击出口按钮 | is_navigation_enabled() 返回 false，_request_room_transition 提前返回 |
| 同时过渡进行中且对话活跃 | 两者都导致禁用，任一恢复后如果另一个仍活跃则保持禁用 |
| 导航请求时 RoomManager 为 null | _request_room_transition 的 null 检查阻止调用 |
| 导航请求时 RoomManager 无 request_transition 方法 | has_method 检查阻止调用 |
| _current_room 初始为空 StringName | 顶栏显示空字符串，底栏无按钮；直到首次 room_changed 信号 |
| room_changed 信号在 _is_transitioning=true 时到达 | _is_transitioning 先设为 false，然后更新 UI |
| room_transition_started 后无对应的 completed 信号 | 导航永久禁用；RoomManager 的过渡协议保证 completed 一定会到达 |
| 出口按钮在禁用状态下被点击 | Godot Button.disabled = true 阻止 pressed 信号 |

## 6. Dependencies

### 上游依赖

| System | ADR | Relationship | Nature |
|--------|-----|-------------|--------|
| RoomManager (#3) | ADR-0007 | 数据源和导航执行 | 监听 room_changed、room_transition_started/completed 信号；调用 request_transition() |
| DialogueManager (#14) | -- | 导航封锁 | 监听 dialogue_started/ended 信号 |

### 下游被依赖

| System | Relationship | Nature |
|--------|-------------|--------|
| RoomManager (#3) | 双向--UI 消费 RoomManager 信号，也向其发送导航请求 | navigation_requested 信号和 request_transition() 调用 |

### ADR 引用

- **ADR-0003** -- CanvasLayer 层级分配（导航 UI 在 Layer 20）
- **ADR-0007** -- Room/Location Management，定义房间注册表、过渡协议、出口处理规则

### 与房间管理 GDD 的关系

本 GDD 是 `design/gdd/room-location-management.md` 的下游 UI 文档。房间管理 GDD 的规则 6（出口处理）和 UI Requirements 部分定义了导航 UI 的接口契约。本 GDD 补充具体的 UI 行为、样式、状态管理和边界条件。

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 类别 | 影响 |
|------|------|--------|------|------|------|
| BAR_HEIGHT | float | 48.0 | 40.0--64.0 | feel | 顶部和底部横条高度 |
| BAR_PADDING | float | 12.0 | 8.0--24.0 | feel | 横条内容水平边距 |
| ROOM_NAME_FONT_SIZE | int | 14 | 12--20 | feel | 房间名称字号 |
| EXIT_FONT_SIZE | int | 14 | 12--20 | feel | 出口按钮字号 |
| MIN_TOUCH_TARGET | int | 44 | 44--64 | gate | 按钮最小尺寸（触摸友好） |
| NAV_LAYER | int | 20 | -- | gate | CanvasLayer 层级 |
| SEAL_BORDER_COLOR | Color | (0.545, 0.0, 0.0) | -- | gate | 朱砂红边框颜色 |
| INK_TEXT_COLOR | Color | (0.172, 0.172, 0.172) | -- | gate | 水墨深灰文本颜色 |
| BAR_BG_COLOR | Color | (1.0, 1.0, 1.0, 0.75) | -- | gate | 横条背景色 |
| DISABLED_ALPHA | float | 0.4 | 0.2--0.6 | feel | 禁用时底栏透明度 |
| DIALOGUE_TOP_ALPHA | float | 0.3 | 0.1--0.5 | feel | 对话期间顶栏透明度 |
| room_labels | Dictionary | 3 entries | -- | gate | 房间 ID 到显示名称映射（可外部化到配置） |
| room_connections | Dictionary | 3 entries | -- | gate | 房间 ID 到出口列表映射（可外部化到配置） |

## 8. Acceptance Criteria

### 房间显示

1. update_for_room("lobby") 后顶栏显示"大厅"，底栏有 1 个"走廊"按钮
2. update_for_room("corridor") 后顶栏显示"走廊"，底栏有 2 个按钮："大厅"和"客房 A"
3. update_for_room("guest_room_a") 后顶栏显示"客房 A"，底栏有 1 个"走廊"按钮
4. update_for_room 传入未注册的 room_id 时顶栏显示 room_id 字符串，底栏无按钮
5. 切换房间时旧按钮被清除（queue_free），新按钮正确生成

### 导航请求

6. 点击出口按钮发出 navigation_requested(target_id) 信号
7. 点击出口按钮调用 RoomManager.request_transition(target_id)
8. RoomManager 为 null 时点击按钮不崩溃

### 导航封锁

9. room_transition_started 信号后 is_navigation_enabled() 返回 false
10. room_transition_completed 信号后 is_navigation_enabled() 恢复 true（如果对话不活跃）
11. dialogue_started 信号后 is_navigation_enabled() 返回 false
12. dialogue_ended 信号后 is_navigation_enabled() 恢复 true（如果不过渡中）
13. 导航禁用时出口按钮 disabled = true，modulate.a = 0.4
14. 对话期间顶栏 modulate.a = 0.3
15. 导航启用时出口按钮 disabled = false，modulate.a = 1.0

### 按钮样式

16. 出口按钮最小尺寸 44x44px
17. Normal 状态有朱砂红边框（2px）
18. Hover/Pressed 状态背景变为朱砂红，文字变白
19. 所有按钮水平居中排列

### 层级

20. CanvasLayer.layer = 20（高于 HUD Layer 10，低于对话 Layer 40）

### 依赖注入

21. set_room_manager() 正确覆盖默认 RoomManager 引用
22. set_dialogue_manager() 正确覆盖默认 DialogueManager 引用
23. 两个外部依赖任一为 null 时系统不崩溃
