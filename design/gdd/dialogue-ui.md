# 对话 UI (Dialogue UI)

## 1. Overview

对话 UI 系统是七夜游戏的对话呈现层，负责将 DialogueManager 的对话数据渲染为水墨风格的交互界面。DialoguePanel 位于 CanvasLayer 40，占据屏幕底部 30%，包含 NPC 说话者名称（住客颜色）、打字机效果的文本显示、最多 5 个印章风格选项按钮，以及始终可见的"结束对话"按钮。对话期间场景暗化 70%，NPC 颜色绽放，计时器减速至 50%。面板同时支持鼠标点击和触摸操作，所有交互元素最小 44px。

## 2. Player Fantasy

**"文字如墨迹晕开，每个选择都是一个印章"** — 你走近靛蓝住客，点击她。画面缓缓暗下来，像夜幕加深。底部浮现宣纸质感的面板，住客的名字以她的专属颜色书写。她的话语逐字显现，仿佛毛笔在纸上缓缓书写。两个选择浮现——不是普通按钮，而是朱砂印章风格的标记。你按下其中一个，印章微微颤动确认。她回应了，信任值改变了。但对话还没结束——还有一个隐藏选项只在拥有特定线索时才显示，那是真正的突破口。

## 3. Detailed Rules

### 3.1 面板布局

**DialoguePanel（CanvasLayer 40）**：
- 全屏覆盖，场景暗化 70%（ColorRect，color = Color(0, 0, 0, 0.7)）
- 底部 30% 为宣纸风格面板（Control，anchor_bottom = 1.0，anchor_top = 0.7）
- 面板背景：半透明白色 + 宣纸纹理（可后续替换为实际纹理）
- 面板内容从上到下：
  1. 说话者名称标签（Label）
  2. 对话文本区域（RichTextLabel）
  3. 选项按钮容器（VBoxContainer）
  4. "结束对话"按钮（始终可见，底部右对齐）

### 3.2 说话者名称

- NPC 说话时：显示 NPC 的显示名称，颜色为该 NPC 的住客颜色
- 玩家说话时：显示"你"，颜色为白色
- 名称标签字体：仿宋（FangSong），14px，加粗
- 名称标签背景：无背景，仅文字

### 3.3 文本显示（打字机效果）

- 使用 RichTextLabel 显示对话文本
- 打字机效果：逐字显示，速度可配置（默认 30 字符/秒）
- 打字机期间：选项按钮隐藏（防止跳读）
- 打字机完成后：选项按钮淡入（0.2s）
- 点击/触摸文本区域：跳过打字机，立即显示完整文本
- 文本字体：仿宋（FangSong），16px，颜色 #2C2C2C（深灰）
- NPC 文本：开头可包含 NPC 颜色标记（可选）

### 3.4 选项按钮

- 印章风格按钮（Button，自定义主题覆盖）
- 最多 5 个选项同时显示（由 DialogueManager.get_available_choices() 过滤）
- 按钮最小尺寸：44x44px（触摸安全）
- 按钮间距：8px
- 按钮外观：
  - 正常状态：朱砂色边框 (#8B0000)，白色半透明背景
  - 悬停/聚焦：朱砂色背景，白色文字
  - 按下：缩放 0.95
- 按钮排列：垂直排列，居中
- 选项文本：仿宋，14px

### 3.5 "结束对话"按钮

- 始终可见（不受条件过滤影响）
- 位于面板底部右下角
- 印章风格，较小尺寸（文字按钮）
- 文本："告辞"
- 点击后调用 DialogueManager.end_dialogue()

### 3.6 场景暗化

- 对话开始时：ColorRect alpha 从 0 淡入到 0.7（0.5s）
- 对话结束时：ColorRect alpha 从 0.7 淡出到 0（0.3s）
- 暗化层位于面板下方（panel z_index > dimmer z_index）

### 3.7 面板进入/退出动画

- 对话开始：面板从屏幕底部滑入（0.5s，ease-out）
- 对话结束：面板向屏幕底部滑出（0.3s，ease-in）
- 动画期间禁止交互

### 3.8 信号连接

DialoguePanel 监听 DialogueManager 的信号：
- `dialogue_started(npc_id)` → 显示面板，开始动画
- `node_displayed(node_id, text)` → 更新文本和选项
- `dialogue_ended(npc_id)` → 隐藏面板，结束动画

DialoguePanel 通知 DialogueManager：
- 选项按钮按下 → `DialogueManager.select_choice(choice_id)`
- "结束对话"按钮 → `DialogueManager.end_dialogue()`
- 文本区域点击 → 跳过打字机效果

### 3.9 NPC 颜色系统

- 从 ADR-0002（色彩积累）获取 NPC 的住客颜色
- 颜色用于：说话者名称、选项高亮（可选）
- 颜色查询：`ColorAccumulation.get_npc_color(npc_id)`
- 颜色不可用时：使用白色 (#FFFFFF)

### 3.10 移动端适配

- 所有按钮最小触摸目标 44x44px
- 无 hover-only 交互（所有反馈同时支持 focus 和 hover）
- 面板占据底部 40%（而非 30%），确保选项不被手指遮挡
- 打字机跳过：触摸文本区域即可

## 4. Formulas

### 打字机速度
```
typewriter_interval = 1.0 / characters_per_second
total_duration = text.length() * typewriter_interval
```
默认：characters_per_second = 30.0，typewriter_interval = 0.033s

### 暗化动画
```
dialogue_enter_duration = 0.5s  (ease-out)
dialogue_exit_duration = 0.3s   (ease-in)
dimmer_target_alpha = 0.7
```

### 面板布局
```
panel_top_anchor = 0.7  (PC) / 0.6  (mobile)
panel_bottom_anchor = 1.0
panel_width = viewport_width
```

### 选项淡入
```
choice_fade_in_duration = 0.2s
choice_fade_delay_per_item = 0.05s  (级联效果)
```

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 对话树为空（无节点） | 面板不显示，DialogueManager.start_dialogue() 返回 false |
| 当前节点无选项且无 next_node_id | 自动结束对话（DialogueManager 处理） |
| 选项超过 5 个 | 只显示前 5 个已过滤的选项 |
| 打字机未完成时点击选项 | 先跳过打字机，再处理选项 |
| 打字机未完成时点击结束对话 | 先跳过打字机，立即结束 |
| 对话期间切换全屏/窗口 | 面板锚点自动适配（Godot anchor 系统） |
| NPC 颜色系统不可用 | 名称标签使用白色 |
| 快速连续点击选项 | DialogueManager.is_active 检查防止重复触发 |
| 打字机 Tween 被中断（面板隐藏） | hide_panel() 中 kill 所有 Tween |
| 文本为空字符串 | 打字机立即完成，显示空文本 |
| 选项文本为空 | 仍显示按钮（空白按钮），但不推荐在数据中如此设计 |

## 6. Dependencies

### 上游依赖
- **条件性对话树 (#14)** — DialogueManager 提供对话数据、选项过滤、信号
- **水墨视觉风格 (#18)** — 宣纸纹理、水墨美学（可选，MVP 可用纯色）
- **色彩积累 (#16)** — NPC 住客颜色（可选，降级为白色）

### 下游被依赖
- **住客审问 (#15)** — 审问对话使用同一 DialoguePanel

### ADR 引用
- **ADR-0003** — CanvasLayer 40 层级，UI 架构
- **ADR-0013** — DialogueManager 接口，DialoguePanel 骨架
- **ADR-0002** — NPC 住客颜色系统

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| characters_per_second | float | 30.0 | 10-60 | 打字机显示速度 |
| max_visible_choices | int | 5 | 2-6 | 同时显示的最大选项数 |
| dimmer_alpha | float | 0.7 | 0.3-0.9 | 场景暗化程度 |
| enter_duration | float | 0.5 | 0.2-1.0 | 面板进入动画时长（秒） |
| exit_duration | float | 0.3 | 0.1-0.5 | 面板退出动画时长（秒） |
| choice_fade_duration | float | 0.2 | 0.1-0.5 | 单个选项淡入时长 |
| choice_fade_delay | float | 0.05 | 0.0-0.15 | 选项级联延迟 |
| min_touch_target | int | 44 | 44-64 | 按钮最小触摸尺寸（px） |
| panel_height_ratio | float | 0.3 | 0.25-0.45 | 面板占屏幕高度比例 |
| text_font_size | int | 16 | 12-24 | 对话文本字号 |
| name_font_size | int | 14 | 10-18 | 说话者名称字号 |

## 8. Acceptance Criteria

1. 对话开始时面板从底部滑入（0.5s），场景暗化 70%
2. 打字机效果逐字显示文本，默认 30 字符/秒
3. 点击文本区域跳过打字机，立即显示完整文本
4. 选项按钮在打字机完成后淡入显示
5. 最多 5 个选项同时显示，条件不满足的选项不显示
6. 所有按钮最小尺寸 44x44px
7. "告辞"按钮始终可见
8. NPC 说话者名称使用该 NPC 的住客颜色
9. 玩家说话时名称为"你"，白色
10. 选项按钮点击触发 DialogueManager.select_choice()
11. "告辞"按钮点击触发 DialogueManager.end_dialogue()
12. 对话结束时面板滑出（0.3s），暗化消退
13. NPC 颜色系统不可用时名称使用白色，不崩溃
14. 空对话树不显示面板
15. 面板位于 CanvasLayer 40
16. 动画期间禁止重复交互
17. 移动端面板可适配不同屏幕比例
