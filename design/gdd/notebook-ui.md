# 笔记本 UI (Notebook UI)

**System ID**: #21
**Category**: Presentation, MVP, Presentation Layer
**Status**: GDD Complete
**Date**: 2026-05-15

---

## 1. Overview

笔记本 UI 是七夜游戏的全屏知识可视化界面，在 CanvasLayer 50 上以暗色遮罩覆盖游戏世界，提供三种视图模式：板视图（Board，自定义绘制的节点/边关系网络）、列表视图（List，可滚动的条目按钮列表）、详情视图（Detail，单条目完整信息展示）。板视图支持缩放（0.3x--3.0x）、平移、节点拖拽、节点选择（最多 2 个 CLUE 节点），选中两个 CLUE 节点时底部出现连接操作栏。列表视图支持搜索栏筛选。详情视图展示条目标题、描述、contextual_unlocks 重新解读（藤黄色）、以及关联连接列表。面板打开/关闭有 Tween 动画，打开时通知 NotebookManager，关闭时清除所有选择状态。

## 2. Player Fantasy

**"翻开你的推理画板"** -- 你按下一个键，世界缓缓暗下来，像墨色从四周涌入。一个全屏的面板浮现，这是你的思维画板。板视图上，线索是散落的墨点，洞察是菱形的印章。你把"碎灯笼"和"靛蓝的不在场证明"拖到一起，选中它们，底部的连接栏亮起来。你按下"连接"，一条灰色的线出现了--错的。但那条线留在那里，不让你忘记。后来你找到正确的连接，金色实线替代了灰色虚线，一个新的菱形节点浮现：洞察。你切换到列表视图，搜索"灯笼"，打开详情。下面多了一段藤黄色的文字，是你在发现洞察后才看到的重新解读。这是你的笔记本，也是你思维的镜子。

## 3. Detailed Rules

### 3.1 CanvasLayer 层级

- NotebookPanel 位于 CanvasLayer 50，高于对话面板（Layer 40）、房间导航 UI（Layer 20）和 HUD（Layer 10）
- 层级分配遵循 ADR-0003（UI Visual Register System）
- 打开时：全屏暗色遮罩（ColorRect, alpha 0.8）阻挡下层交互

### 3.2 布局结构

```
NotebookPanel (CanvasLayer 50)
  ├─ Dimmer (ColorRect, 全屏, alpha 0.0->0.8 动画)
  └─ MainContainer (Control, 全屏)
       ├─ Toolbar (HBoxContainer, 顶部 48px, 左右边距 16px)
       │    ├─ SearchBar (LineEdit, 200x44px, 最小触摸目标)
       │    ├─ BoardButton (Button, 44x44px)
       │    ├─ ListButton (Button, 44x44px)
       │    └─ CloseButton (Button, 44x44px)
       ├─ ContentArea (Control, 顶部=工具栏底部, 底部=88%视口高度)
       │    ├─ BoardView (Control, 自定义 _draw 渲染)
       │    ├─ EmptyLabel (Label, 居中, "探索世界，发现线索。")
       │    ├─ ListView (ScrollContainer, 含 VBoxContainer)
       │    └─ DetailView (VBoxContainer, 左右边距 24px)
       └─ ConnectionBar (HBoxContainer, 88%--100% 视口高度, 边距 24px)
            ├─ SelectionLabel (Label, 显示选中节点)
            └─ ConnectButton (Button, 88x44px)
```

### 3.3 视图模式

笔记本支持三种互斥视图模式（ViewMode 枚举）：

| 模式 | 枚举值 | 说明 |
|------|--------|------|
| BOARD | 0 | 核心视图，线索板关系网络 |
| LIST | 1 | 可滚动条目列表 + 搜索 |
| DETAIL | 2 | 单条目详情展示 |

切换视图时，非活跃视图设为 `visible = false`，活跃视图设为 `visible = true`。工具栏按钮状态同步：当前模式的按钮设为 disabled。

### 3.4 板视图（Board View）

板视图使用 Godot 的 `_draw()` 自定义渲染，通过 `_board_view.draw_*()` 调用绘制节点和边。

**缩放和平移**：

- 缩放范围：MIN_ZOOM (0.3) 到 MAX_ZOOM (3.0)，步进 ZOOM_STEP (0.1)
- 缩放输入：鼠标滚轮（WHEEL_UP 放大，WHEEL_DOWN 缩小）
- 平移输入：鼠标右键拖拽 / 触摸空白区域拖拽 / 触控板 PanGesture
- 平移速度：PAN_SPEED (8.0) 用于 PanGesture 乘数
- 绘制变换：`_board_view.draw_set_transform(_board_offset, 0.0, Vector2(_board_zoom, _board_zoom))`

**节点渲染**：

| 类型 | entry_type | 形状 | 大小 | 选中高亮 |
|------|-----------|------|------|---------|
| CLUE | 0 | 圆形 | 32px 直径 | 金色圆环 (radius+2, 2px 宽) |
| INSIGHT | 1 | 菱形 | 40px 直径 | 金色菱形轮廓 (size+4, 2px 宽) |

- 选中状态：颜色 RGB 各通道 +0.2（加亮）
- 节点数据来源：NotebookManager.get_board_nodes() 返回 Dictionary 数组
- 每个节点 Dictionary 包含：position (Vector2), color (Color), size (float), state (String), entry_type (int), entry_id (StringName)

**边渲染**：

| 连接类型 | 样式 | 颜色 | 宽度 |
|---------|------|------|------|
| 有效连接 | 实线 | edge.color（通常金色） | edge.width |
| 无效连接 | 虚线（6px dash, 4px gap） | INVALID_EDGE_COLOR (灰色 30% 透明) | edge.width |

- 边数据来源：NotebookManager.get_board_edges() 返回 Dictionary 数组
- 每条边 Dictionary 包含：clue_a (StringName), clue_b (StringName), color (Color), width (float), is_valid (bool)

**节点交互**：

- 左键/触摸点击节点：切换选中状态（toggle selection）
- 左键/触摸点击空白：取消所有选中
- 左键拖拽节点：更新节点位置（同步到 NotebookManager.update_node_position()）
- 右键拖拽空白：平移画板
- 鼠标滚轮：缩放
- 触控板手势：平移

**命中检测**：

- 遍历节点数组（从末尾到开头，支持上层节点优先）
- 点击距离 <= size * 0.5 + 4.0（4px 容差用于触摸友好）
- 返回匹配的 entry_id 或空 StringName

### 3.5 列表视图（List View）

- 条目按钮最小高度 44px（MIN_TOUCH_TARGET），宽度填充容器
- 按钮文本为条目标题（entry_data.title）
- 点击按钮：切换到详情视图，_detail_entry_id 设为该条目 ID
- 列表每次刷新时清除并重建所有按钮（queue_free 子节点）

**搜索**：

- SearchBar 实时筛选：text_changed 信号触发 _refresh_list_view()
- 搜索查询为空时显示所有可见条目（get_all_visible()）
- 搜索查询非空时调用 NotebookManager.search_entries(query)
- 无结果时显示 "没有找到相关条目" 文本
- 搜索提交（Enter 键）自动切换到列表视图

### 3.6 详情视图（Detail View）

详情视图为选中条目展示完整信息，每次打开时清除并重建所有子节点：

1. **标题**：Label, 20px 字号
2. **描述**：RichTextLabel (纯文本, fit_content), 14px 字号
3. **Contextual Unlocks**（重新解读）：每条 unlock 为一个 RichTextLabel
   - 使用 BBCode 斜体：`[i]reinterpretation_text[/i]`
   - 12px 字号，藤黄色（GOLD_OCHRE）文本
4. **连接列表**（如果存在连接）：
   - 标题 "连接" (14px)
   - 每个连接：前缀圆点 + 对方条目 ID
     - 有效连接：实心圆 "● "，藤黄色
     - 无效连接：空心圆 "○ "，灰色 (0.5, 0.5, 0.5)
   - 12px 字号
5. **返回按钮**：最小 44x44px，点击切换回列表视图

### 3.7 连接操作栏

连接操作栏在板视图底部显示，条件：

1. 当前视图为 BOARD
2. 恰好选中 2 个节点
3. 两个选中节点都是 CLUE 类型（entry_type == 0）

连接栏内容：
- SelectionLabel：显示 "已选择: {id_a} + {id_b}"
- ConnectButton：88x44px，文本 "连接"

点击连接按钮时：
1. 发出 `connection_requested(clue_a, clue_b)` 信号
2. 调用 NotebookManager.request_connection(clue_a, clue_b)
3. 清除所有选中状态
4. 刷新数据并重绘板视图

### 3.8 面板打开/关闭动画

**打开（show_panel）**：

1. 如果正在动画中或 NotebookManager 为 null，返回
2. 调用 NotebookManager.open_notebook()
3. 刷新数据（_refresh_data）
4. 设 Dimmer 和 MainContainer 为 visible，设 CanvasLayer visible
5. 重置视图为 BOARD，清除选中状态
6. Tween 动画：Dimmer alpha 0.0 -> DIMMER_ALPHA (0.8)，持续 ENTER_DURATION (0.3s)
7. 动画完成后设 _animating = false，渲染当前视图

**关闭（hide_panel）**：

1. 如果正在动画中，返回
2. 设 _animating = true
3. 调用 NotebookManager.close_notebook()
4. Tween 动画：Dimmer alpha DIMMER_ALPHA -> 0.0，持续 EXIT_DURATION (0.2s)
5. 动画完成后调用 hide_panel_immediate()

**立即关闭（hide_panel_immediate）**：

- 设 CanvasLayer visible = false
- Dimmer visible = false, alpha = 0.0
- MainContainer visible = false
- 清除 _animating, _selected_node_ids, _dragging_node_id, _is_panning, _detail_entry_id

### 3.9 信号连接

NotebookPanel 连接 NotebookManager 的以下信号：

- `notebook_opened()` -> 刷新数据，渲染当前视图
- `notebook_closed()` -> 无操作
- `board_updated()` -> 刷新数据，如果板视图活跃则重绘
- `entry_selected(entry_id: StringName)` -> 刷新数据，如果板视图活跃则重绘
- `connection_attempted(a: StringName, b: StringName, success: bool)` -> 刷新数据，如果板视图活跃则重绘

### 3.10 依赖注入

NotebookManager 通过 `get_node_or_null("/root/NotebookManager")` 获取。测试可通过 `set_notebook_manager()` 注入 mock 对象。

## 4. Formulas

### 4.1 屏幕坐标到板坐标转换

**Named Expression**:

```
board_pos = (screen_local - board_offset) / board_zoom
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `screen_local` | Vector2 | 视口尺寸 | 屏幕坐标减去 BoardView 的 global_position |
| `board_offset` | Vector2 | 任意 | 当前板平移偏移量 |
| `board_zoom` | float | 0.3 -- 3.0 | 当前缩放级别 |
| `board_pos` | Vector2 | 任意 | 板坐标系中的位置 |

**Worked Example**: 点击屏幕位置 (640, 360)，BoardView.global_position = (0, 48)，offset = (100, -50)，zoom = 1.5
- screen_local = (640, 360) - (0, 48) = (640, 312)
- board_pos = ((640, 312) - (100, -50)) / 1.5 = (540, 362) / 1.5 = (360, 241.3)

### 4.2 节点命中检测

**Named Expression**:

```
is_hit = (distance <= size * 0.5 + HIT_TOLERANCE)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `distance` | float | 0+ | 点击位置到节点中心的距离 |
| `size` | float | 32.0 or 40.0 | 节点直径（CLUE 或 INSIGHT） |
| `HIT_TOLERANCE` | float | 4.0 (固定) | 触摸友好容差 |
| `is_hit` | bool | -- | 是否命中该节点 |

**Worked Example**: 点击位置距 CLUE 节点中心 18px
- threshold = 32 * 0.5 + 4 = 20
- 18 <= 20 -> is_hit = true

### 4.3 虚线绘制

**Named Expression**:

```
while drawn < length:
    draw segment from (from + dir * drawn) to (from + dir * min(drawn + dash_len, length))
    drawn += dash_len + gap_len
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `dash_len` | float | 6.0 (固定) | 每段虚线长度 |
| `gap_len` | float | 4.0 (固定) | 虚线间隔长度 |
| `length` | float | 1+ | 两节点间总距离 |
| `drawn` | float | 0 -- length | 已绘制距离 |

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| NotebookManager 为 null | show_panel() 提前返回；数据刷新方法跳过；不崩溃 |
| 板视图中没有节点 | 显示 EmptyLabel ("探索世界，发现线索。")，不绘制任何内容 |
| 选中一个 CLUE 节点和一个 INSIGHT 节点 | 连接栏不显示（_update_connection_bar 检查 both_clues 条件） |
| 选中超过 2 个节点 | 连接栏不显示（只在 size() == 2 时显示） |
| 选中 2 个节点但其中一个不是 CLUE | 连接栏不显示 |
| 搜索查询为空字符串 | 列表显示所有可见条目（get_all_visible） |
| 搜索查询无匹配结果 | 列表显示 "没有找到相关条目" 文本 |
| 详情视图打开时 _detail_entry_id 为空 | 提前返回，不渲染任何内容 |
| get_entry_detail 返回空 entry_data | 提前返回，不渲染详情 |
| 面板动画进行中时调用 show_panel 或 hide_panel | 提前返回（_animating == true 检查） |
| 节点被拖拽到板视图可视范围外 | 位置更新但不可见，需要平移或缩小才能找到 |
| 缩放达到极限值（0.3 或 3.0） | minf/maxf 约束阻止超出范围 |
| 多个边连接同一个节点 | 所有边正常绘制，可能重叠 |
| 点击节点后再次点击同一节点 | 取消选中（toggle 行为） |
| 点击空白区域但已有选中节点 | 清除所有选中，隐藏连接栏 |
| 立即关闭后重新打开 | 重置为 BOARD 视图，清除选中状态 |
| connection_attempted 信号中 success = false | 仍然刷新数据（灰色边可能被添加到板视图） |
| 视口尺寸变化（窗口缩放） | ContentArea 使用 anchor 定位自动适应 |

## 6. Dependencies

### 上游依赖

| System | ADR | Relationship | Nature |
|--------|-----|-------------|--------|
| NotebookManager (#17) | ADR-0005 | 数据源和控制 | 读取 get_board_nodes/edges、get_all_visible、search_entries、get_entry_detail；调用 open/close_notebook、request_connection、update_node_position、select_entry、deselect_all；监听 notebook_opened/closed、board_updated、entry_selected、connection_attempted 信号 |

### 下游被依赖

| System | Relationship | Nature |
|--------|-------------|--------|
| ClueConnectionManager (#11) | 间接--通过 NotebookManager 委托 | connection_requested 信号通知外部系统，NotebookManager 内部也调用 request_connection |
| Timer/HUD UI (#19) | 可见性联动 | 笔记本打开时 HUD 隐藏（通过 NotebookManager.notebook_opened 信号） |

### ADR 引用

- **ADR-0003** -- CanvasLayer 层级分配（笔记本在 Layer 50）
- **ADR-0005** -- KnowledgeEntry 统一 schema、Connection 结构、contextual_unlocks 机制
- **ADR-0002** -- 六种知识颜色、藤黄（GOLD_OCHRE）作为有效连接和洞察色

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 类别 | 影响 |
|------|------|--------|------|------|------|
| LAYER_DEPTH | int | 50 | -- | gate | CanvasLayer 层级 |
| DIMMER_ALPHA | float | 0.8 | 0.5--1.0 | feel | 暗色遮罩不透明度 |
| ENTER_DURATION | float | 0.3 | 0.1--0.5 | feel | 打开动画时长（秒） |
| EXIT_DURATION | float | 0.2 | 0.1--0.3 | feel | 关闭动画时长（秒） |
| TOOLBAR_HEIGHT | float | 48.0 | 40.0--64.0 | feel | 工具栏高度 |
| CLUE_NODE_SIZE | float | 32.0 | 20.0--60.0 | feel | CLUE 节点直径 |
| INSIGHT_NODE_SIZE | float | 40.0 | 24.0--72.0 | feel | INSIGHT 节点直径（比 CLUE 大） |
| MIN_ZOOM | float | 0.3 | 0.1--0.5 | curve | 最小缩放级别 |
| MAX_ZOOM | float | 3.0 | 2.0--5.0 | curve | 最大缩放级别 |
| ZOOM_STEP | float | 0.1 | 0.05--0.25 | feel | 每次滚轮缩放步进 |
| PAN_SPEED | float | 8.0 | 4.0--16.0 | feel | 触控板平移速度乘数 |
| FONT_SIZE_TITLE | int | 20 | 16--28 | feel | 详情标题字号 |
| FONT_SIZE_NORMAL | int | 14 | 12--18 | feel | 正文和按钮字号 |
| FONT_SIZE_SMALL | int | 12 | 10--14 | feel | 辅助信息字号 |
| DASH_LENGTH | float | 6.0 | 4.0--12.0 | feel | 虚线段长度 |
| GAP_LENGTH | float | 4.0 | 2.0--8.0 | feel | 虚线间隔长度 |
| HIT_TOLERANCE | float | 4.0 | 0.0--10.0 | feel | 命中检测额外容差（触摸友好） |

## 8. Acceptance Criteria

### 面板生命周期

1. show_panel() 在 NotebookManager 存在时正确打开面板，Dimmer alpha 从 0 动画到 0.8
2. hide_panel() 正确关闭面板，Dimmer alpha 从 0.8 动画到 0
3. hide_panel_immediate() 立即隐藏所有元素，清除选中状态
4. 动画进行中时 show_panel/hide_panel 被忽略（不重复触发）
5. is_panel_open 属性在面板可见且不动画时返回 true

### 板视图渲染

6. CLUE 节点渲染为圆形，INSIGHT 节点渲染为菱形
7. 选中节点显示金色轮廓高亮
8. 有效连接渲染为实线，无效连接渲染为虚线（6px dash, 4px gap）
9. 空板视图显示引导文字 "探索世界，发现线索。"
10. 缩放和平移正确应用于板视图的 draw_set_transform

### 板视图交互

11. 左键点击节点正确切换选中状态
12. 左键点击空白区域清除所有选中
13. 选中 2 个 CLUE 节点时连接栏可见
14. 选中包含非 CLUE 节点时连接栏不可见
15. 选中 1 或 3+ 个节点时连接栏不可见
16. 拖拽节点更新位置并同步到 NotebookManager
17. 鼠标滚轮缩放在 0.3 到 3.0 范围内
18. 右键拖拽和触控板手势正确平移板视图

### 连接操作

19. 连接按钮点击发出 connection_requested(clue_a, clue_b) 信号
20. 连接后选中状态被清除，连接栏隐藏
21. 连接后数据刷新并重绘板视图

### 列表视图

22. 列表正确显示所有可见条目为可点击按钮
23. 点击条目按钮切换到详情视图并设置 _detail_entry_id
24. 搜索查询为空时显示所有条目
25. 搜索查询非空时调用 NotebookManager.search_entries
26. 搜索无结果时显示 "没有找到相关条目"

### 详情视图

27. 详情视图正确显示标题、描述、contextual_unlocks 和连接列表
28. contextual_unlocks 使用藤黄色和斜体
29. 有效连接显示实心圆，无效连接显示空心圆
30. 返回按钮切换回列表视图
31. _detail_entry_id 为空时不渲染任何内容

### 视图切换

32. 切换视图时非活跃视图不可见，活跃视图可见
33. 当前视图的工具栏按钮为 disabled 状态

### CanvasLayer 与层级

34. CanvasLayer.layer = 50（高于对话 Layer 40）
35. 所有交互元素最小尺寸 44x44px

### 依赖注入

36. set_notebook_manager() 正确覆盖默认引用
37. NotebookManager 为 null 时所有操作安全跳过
