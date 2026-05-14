# 计时器/HUD UI (Timer/HUD UI)

**System ID**: #19
**Category**: Presentation, MVP, Presentation Layer
**Status**: GDD Complete
**Date**: 2026-05-15

---

## 1. Overview

计时器/HUD UI 是七夜游戏的倒计时可视化层，在 CanvasLayer 10 上显示当前夜晚剩余时间（M:SS 格式）、压力条（pressure_level 驱动的水平填充条）、以及压力阶段文本（平静/紧张/危急）。HUD 位于屏幕顶部中央，监听 TimerService 的 pressure_updated、phase_changed、night_timer_started/ended 信号和 ColorAccumulationManager 的 knowledge_level_changed 信号，实时更新时间文本、条形填充量和颜色。压力条颜色根据当前阶段（灰/朱砂红/墨黑）混合知识色彩（藤黄 GOLD_OCHRE），使玩家的知识积累在视觉压力中显现。HUD 在对话活跃或笔记本打开时自动淡出，对话结束或笔记本关闭时淡入，使用 0.2 秒 Tween 过渡。

## 2. Player Fantasy

**"时间如墨，知识如金"** -- 屏幕顶部一行小小的文字和一条细长的色带。你刚开始第一个夜晚，倒计时显示 3:00，压力条是浅灰色，几乎看不到。但随着时间流逝，条形逐渐填满，颜色从灰变红，再从红变黑。文字从"平静"变成"紧张"，然后是"危急"--每个字像是在提醒你时间不多了。但你发现，随着你揭开更多真相，那条压力条的颜色被一层温暖的金色渗透了。知识没有消除压力，但它改变了你看到压力的方式。当你在对话中，HUD 悄然消失，让你专注于眼前的人；对话结束，它又悄然回来，告诉你还剩多少时间。

## 3. Detailed Rules

### 3.1 CanvasLayer 层级

- TimerHUDUI 位于 CanvasLayer 10，低于房间导航 UI（Layer 20）、对话面板（Layer 40）和笔记本（Layer 50）
- 层级分配遵循 ADR-0003（UI Visual Register System）
- HUD 不阻挡下层交互--所有 Control 节点设置 `mouse_filter = MOUSE_FILTER_IGNORE`

### 3.2 布局结构

HUD 由一个居中的容器构成：

```
HUDContainer (Control, 200x52px, 居中偏移, top=8px)
  └─ VBox (separation=4)
       ├─ TimeLabel (居中, 18px, 显示 "M:SS")
       ├─ BarContainer (200x12px)
       │    ├─ BarBackground (全尺寸 ColorRect, 白色半透明)
       │    └─ BarFill (ColorRect, anchor_right = pressure_level, 上下各 2px 边距)
       └─ PhaseLabel (居中, 12px, 显示阶段文本)
```

- HUDContainer 的 anchor_left/anchor_right = 0.5（水平居中），offset_left/right = +/-BAR_WIDTH/2
- BarFill 的 anchor_right 值由 pressure_level (0.0-1.0) 直接驱动，clamp 到 [0.0, 1.0] 范围

### 3.3 时间显示

- 格式：`M:SS`，如 `0:00`、`1:30`、`10:05`
- 格式化算法：`total_secs = int(seconds); mins = total_secs / 60; secs = total_secs % 60; "%d:%02d" % [mins, secs]`
- 文本颜色：INK_TEXT_COLOR (0.172, 0.172, 0.172)，水墨深灰色
- 更新时机：TimerService 的 pressure_updated 和 night_timer_started 信号触发

### 3.4 压力条填充

- BarFill.anchor_right = clampf(pressure_level, 0.0, 1.0)
- 填充从左到右，pressure_level = 0.0 时不可见，= 1.0 时填满整个宽度
- 背景色：BAR_BG_COLOR = Color(1.0, 1.0, 1.0, 0.6)，半透明白色
- 更新时机：pressure_updated 信号

### 3.5 压力条颜色

压力条颜色由两个因素决定：

1. **阶段基础色**：

| 阶段 | 枚举值 | 颜色 | RGB | 说明 |
|------|--------|------|-----|------|
| CALM | 0 | 灰色 | (0.6, 0.6, 0.6, 0.8) | 低语，水墨轻描 |
| INTENSE | 1 | 朱砂红 | (0.545, 0.0, 0.0, 0.9) | SEAL_BORDER_COLOR，紧张 |
| CRITICAL | 2 | 墨黑 | (0.0, 0.0, 0.0, 1.0) | 完全黑暗，危急 |

2. **知识色彩混合**：在阶段基础色上叠加藤黄（GOLD_OCHRE）的渐变
   - `tint_amount = knowledge_level * 0.3`（最大 30% 的藤黄混合）
   - 最终颜色 = phase_color.lerp(GOLD_OCHRE, tint_amount)
   - knowledge_level = 0.0 时不混合，= 1.0 时混合 30% 的藤黄

颜色在以下时机更新：
- pressure_updated（阶段可能改变）
- phase_changed（阶段明确改变）
- knowledge_level_changed（知识水平变化）

### 3.6 阶段文本

| 枚举值 | 中文标签 | 对应阶段 |
|--------|---------|---------|
| 0 | 平静 | CALM |
| 1 | 紧张 | INTENSE |
| 2 | 危急 | CRITICAL |

- 未知枚举值回退到 PHASE_LABELS[0]（平静）
- 文本颜色：INK_TEXT_COLOR，12px 字号

### 3.7 可见性控制

HUD 在以下条件同时满足时可见：

1. TimerService.is_active == true（计时器正在运行）
2. 对话未活跃（_is_dialogue_active == false）
3. 笔记本未打开（_is_notebook_open == false）

任何条件变化触发可见性重新计算。可见性变化使用 Tween 淡入/淡出：

- 淡入：modulate.a 0.0 -> 1.0，持续 FADE_DURATION (0.2s)
- 淡出：modulate.a 1.0 -> 0.0，持续 FADE_DURATION (0.2s)
- 新的可见性变化会终止正在进行的 Tween（kill 后重建）

可见性变化时发出 `hud_visibility_changed(is_visible: bool)` 信号。

### 3.8 信号连接

TimerHUDUI 连接以下信号：

**TimerService**（/root/TimerService）：
- `pressure_updated(pressure_level: float)` -> 更新条形填充和颜色
- `phase_changed(old_phase: int, new_phase: int)` -> 更新阶段标签和条形颜色
- `night_timer_started(night: int, duration: float)` -> 刷新全部显示
- `night_timer_ended(night: int)` -> 更新时间文本和可见性

**ColorAccumulationManager**（/root/ColorAccumulationManager）：
- `knowledge_level_changed(new_level: float)` -> 更新条形颜色

**DialogueManager**（/root/DialogueManager）：
- `dialogue_started(npc_id: StringName)` -> 设 _is_dialogue_active = true，更新可见性
- `dialogue_ended(npc_id: StringName)` -> 设 _is_dialogue_active = false，更新可见性

**NotebookManager**（/root/NotebookManager）：
- `notebook_opened()` -> 设 _is_notebook_open = true，更新可见性
- `notebook_closed()` -> 设 _is_notebook_open = false，更新可见性

### 3.9 依赖注入

所有四个外部依赖通过 `_get_*()` 虚方法获取，默认实现使用 `get_node_or_null("/root/...")`。测试可通过 `set_timer_service()`、`set_color_accumulation()`、`set_dialogue_manager()`、`set_notebook_manager()` 注入 mock 对象。

## 4. Formulas

### 4.1 时间格式化

**Named Expression**:

```
total_secs = int(seconds)
mins = total_secs / 60
secs = total_secs % 60
display_string = "%d:%02d" % [mins, secs]
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `seconds` | float | 0.0 -- 600.0+ | TimerService.remaining_time |
| `total_secs` | int | 0+ | 截断为整数的总秒数 |
| `mins` | int | 0+ | 分钟数 |
| `secs` | int | 0--59 | 剩余秒数 |
| `display_string` | String | "0:00" -- "99:59" | 显示文本 |

**Worked Example**: remaining_time = 183.7
- total_secs = 183, mins = 3, secs = 3
- display_string = "3:03"

### 4.2 压力条填充量

**Named Expression**:

```
bar_fill_anchor_right = clampf(pressure_level, 0.0, 1.0)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `pressure_level` | float | 0.0 -- 1.0 | TimerService.pressure_level |
| `bar_fill_anchor_right` | float | 0.0 -- 1.0 | BarFill 的右锚点值 |

**Worked Example**: pressure_level = 0.65
- bar_fill_anchor_right = 0.65（条形填充 65% 宽度）

### 4.3 压力条颜色混合

**Named Expression**:

```
tint_amount = knowledge_level * 0.3
bar_color = phase_color.lerp(GOLD_OCHRE, tint_amount)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `knowledge_level` | float | 0.0 -- 1.0 | 全局知识水平（ColorAccumulationManager） |
| `tint_amount` | float | 0.0 -- 0.3 | 藤黄混合比例（上限 30%） |
| `phase_color` | Color | 见 3.5 | 当前阶段基础色 |
| `GOLD_OCHRE` | Color | (0.8, 0.467, 0.133) | 藤黄知识色 |
| `bar_color` | Color | -- | 最终条形颜色 |

**Worked Example**: knowledge_level = 0.5, phase = INTENSE
- phase_color = (0.545, 0.0, 0.0, 0.9)
- tint_amount = 0.5 * 0.3 = 0.15
- bar_color = phase_color.lerp(GOLD_OCHRE, 0.15) = approximately (0.583, 0.070, 0.020, 0.915)
- 视觉效果：朱砂红偏暖的金色

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| TimerService 为 null | 所有显示方法提前返回（null 检查），不崩溃 |
| TimerService 不存在 remaining_time 属性 | `_update_time_text()` 通过 `"remaining_time" in _timer_service` 检查后提前返回 |
| TimerService 不存在 pressure_level 属性 | pressure 默认 0.0，条形不填充 |
| TimerService 不存在 current_phase 属性 | phase 默认 0（CALM），显示"平静" |
| TimerService 不存在 is_active 属性 | `_compute_should_be_visible()` 返回 false，HUD 隐藏 |
| knowledge_level > 1.0 | clampf 限制到 1.0，tint_amount 上限 0.3 |
| knowledge_level < 0.0 | clampf 限制到 0.0，不混合藤黄 |
| 同时对话活跃且笔记本打开 | 两者都导致隐藏，关闭任一后仍因另一个保持隐藏 |
| HUD 淡出期间新可见性变化 | 旧 Tween 被 kill，新 Tween 从当前 alpha 开始（或重建） |
| 夜晚计时器结束后 TimerService.is_active 变 false | `_update_visibility()` 触发淡出 |
| Phase 枚举值为 3 或更高 | `_get_phase_color()` 的 match 默认返回 PHASE_CALM_COLOR |
| PHASE_LABELS 中缺少某个枚举值 | `_update_phase_label()` 使用 `.get(phase, PHASE_LABELS[0])` 回退到"平静" |
| 首次 _ready() 时服务尚未加载 | `get_node_or_null` 返回 null，所有显示方法安全跳过 |

## 6. Dependencies

### 上游依赖

| System | ADR | Relationship | Nature |
|--------|-----|-------------|--------|
| TimerService (#5) | ADR-0008 | 数据源 | 读取 remaining_time、pressure_level、current_phase、is_active；监听 pressure_updated、phase_changed、night_timer_started/ended |
| ColorAccumulationManager (#16) | ADR-0002 | 色彩参数 | 监听 knowledge_level_changed 信号 |
| DialogueManager (#14) | -- | 可见性控制 | 监听 dialogue_started/ended 信号 |
| NotebookManager (#17) | ADR-0005 | 可见性控制 | 监听 notebook_opened/closed 信号 |

### 下游被依赖

| System | Relationship | Nature |
|--------|-------------|--------|
| Ending Trigger Logic (#23) | 可选--读取 HUD 状态 | 可通过 hud_visibility_changed 信号判断游戏状态 |

### ADR 引用

- **ADR-0001** -- 压力阶段颜色与 shader 压力分段对齐（CALM/INTENSE/CRITICAL 映射到 Whisper/Transition/Roar）
- **ADR-0003** -- CanvasLayer 层级分配（HUD 在 Layer 10）
- **ADR-0008** -- 倒计时系统接口定义

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 类别 | 影响 |
|------|------|--------|------|------|------|
| BAR_WIDTH | float | 200.0 | 120.0--400.0 | feel | 压力条和容器宽度 |
| BAR_HEIGHT | float | 8.0 | 4.0--16.0 | feel | 压力条高度 |
| TIME_FONT_SIZE | int | 18 | 14--28 | feel | 时间文本字号 |
| PHASE_FONT_SIZE | int | 12 | 10--18 | feel | 阶段文本字号 |
| FADE_DURATION | float | 0.2 | 0.05--0.5 | feel | 淡入/淡出动画时长（秒） |
| KNOWLEDGE_TINT_STRENGTH | float | 0.3 | 0.0--0.5 | curve | 知识色彩最大混合比例 |
| PHASE_CALM_COLOR | Color | (0.6, 0.6, 0.6, 0.8) | -- | gate | 低语阶段条形颜色 |
| PHASE_INTENSE_COLOR | Color | (0.545, 0.0, 0.0, 0.9) | -- | gate | 激昂阶段条形颜色（朱砂红） |
| PHASE_CRITICAL_COLOR | Color | (0.0, 0.0, 0.0, 1.0) | -- | gate | 危急阶段条形颜色（墨黑） |
| HUD_LAYER | int | 10 | -- | gate | CanvasLayer 层级 |

## 8. Acceptance Criteria

### 时间显示

1. 格式化函数正确转换浮点秒数为 "M:SS" 格式（0 秒 -> "0:00"，90 秒 -> "1:30"，600 秒 -> "10:00"）
2. 时间标签在 TimerService.remaining_time 变化时更新
3. 夜晚计时器开始时时间显示刷新为当前剩余时间

### 压力条

4. BarFill.anchor_right 等于 clampf(pressure_level, 0.0, 1.0)
5. pressure_level = 0.0 时条形不可见，= 1.0 时完全填充
6. 条形颜色根据阶段正确切换：CALM=灰、INTENSE=朱砂红、CRITICAL=墨黑

### 知识色彩混合

7. knowledge_level = 0.0 时条形颜色等于纯阶段色（无藤黄混合）
8. knowledge_level = 1.0 时条形颜色 = phase_color.lerp(GOLD_OCHRE, 0.3)
9. knowledge_level 变化时条形颜色立即更新

### 阶段显示

10. 阶段标签根据 current_phase 显示正确的中文文本（0="平静"、1="紧张"、2="危急"）
11. 未知阶段值回退到"平静"

### 可见性

12. TimerService.is_active = false 时 HUD 隐藏
13. TimerService.is_active = true 且无对话且无笔记本时 HUD 显示
14. 对话开始时 HUD 淡出，对话结束时 HUD 淡入
15. 笔记本打开时 HUD 淡出，笔记本关闭时 HUD 淡入
16. 可见性变化发出 hud_visibility_changed 信号
17. 淡入/淡出持续 FADE_DURATION 秒
18. 快速连续的可见性变化不产生动画冲突（旧 Tween 被终止）

### 层级与交互

19. CanvasLayer.layer = 10（低于房间导航 Layer 20 和对话 Layer 40）
20. 所有 HUD 节点的 mouse_filter = MOUSE_FILTER_IGNORE（不阻挡下层点击）

### 依赖注入

21. set_timer_service() 正确覆盖默认 TimerService 引用
22. set_color_accumulation() 正确覆盖默认 ColorAccumulationManager 引用
23. 四个外部依赖任一为 null 时系统不崩溃
