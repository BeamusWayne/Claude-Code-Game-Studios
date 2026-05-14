# System #18: 水墨视觉风格 (Ink Wash Visual Style)

> **Status**: GDD Complete
> **Priority**: MVP
> **Layer**: Presentation
> **Depends On**: #16 (色彩积累 / Color Accumulation)
> **Assigned Agent**: godot-shader-specialist
> **Effort**: M (2-3 sessions)
> **ADR**: ADR-0001 (Ink Wash Shader Pipeline), ADR-0002 (Knowledge Color Accumulation)

---

## 1. Overview

水墨视觉风格系统是一个场景级视觉编排器 (VisualStyleManager)，负责根据游戏状态将水墨着色器管线（ADR-0001）、色彩积累系统（#16）和场景上下文协调为连贯的视觉体验。它不重复渲染逻辑——着色器和 ColorAccumulationManager 已实现核心渲染——而是管理视觉状态转换、房间特定参数、发现时刻动画和夜晚过渡序列。本系统将分散的渲染参数统一为七个离散视觉状态，确保游戏的每个时刻都表达正确的水墨氛围。

---

## 2. Player Fantasy

玩家感受到世界是一幅活的水墨画——安静时墨色沉淀、边缘清晰、世界可读；压力时墨色流淌、晕染、失去边界；发现真相时色彩从墨色瀑布般涌出，短暂超出边界然后沉淀。每次走进不同房间，温度和住客色的微妙变化让空间具有性格。夜晚结束时深墨淹没一切，但玩家已赚取的色彩在白纸上依然可见——进度被视觉化。玩家不需要看 HUD 来感受游戏节奏，因为墨色就是节奏。

---

## 3. Detailed Rules

### 3.1 视觉状态机

系统定义七个视觉状态，每个状态对应一组着色器参数目标值。状态转换通过 lerp 实现平滑过渡，不使用瞬间切换。

| 状态 | 触发条件 | 核心视觉特征 |
|------|---------|------------|
| **EXPLORATION** | 默认状态；玩家在房间内自由移动 | 墨色沉淀，边缘锐利，中性温度，低对比度 |
| **DIALOGUE** | 进入 NPC 对话 | 背景墨色减密度，NPC 颜色渗入，温度向 NPC 色偏移 |
| **CLUE_CONNECTION** | 打开线索连接/笔记本 | 场景墨色"拉开"，纯纸纹背景，墨色边缘最锐利 |
| **WHISPER** | 倒计时进入低语阶段 | 墨色略微颤抖，边缘失锐，偏冷温度，雨强度+1 |
| **ROAR** | 倒计时进入咆哮阶段 | 墨色剧烈流动，大量出血，强偏冷，可视区域缩小 |
| **NIGHT_END** | 夜晚倒计时归零 | 墨色完全占据 2-3s，然后排去露出白纸+保留色彩 |
| **DISCOVERY** | 生成洞察/发现线索 | 墨色从特定元素瞬间退去，色彩溢出 1-1.5s |

状态优先级（高→低）：DISCOVERY > NIGHT_END > ROAR > WHISPER > DIALOGUE > CLUE_CONNECTION > EXPLORATION

高优先级状态可以中断低优先级状态的过渡。DISCOVERY 和 NIGHT_END 是瞬态——播放完毕后自动恢复到之前的持续状态。

### 3.2 状态转换时长

| 过渡 | 持续时间 | 视觉机制 |
|------|---------|---------|
| EXPLORATION → WHISPER | 3.0-5.0s | 墨色边缘渐失锐度，雨强度渐增 |
| WHISPER → ROAR | 1.0-2.0s | 墨色出血突增，全屏墨色闪光标志阈值 |
| ROAR → NIGHT_END | 0.3s | 墨色完全占据 |
| NIGHT_END → EXPLORATION | 2.0-3.0s | 墨色排去，露出白纸和保留色彩 |
| EXPLORATION → DIALOGUE | 1.0s | 背景墨色减密度，NPC 颜色绽放 |
| EXPLORATION → CLUE_CONNECTION | 1.0s | 场景墨色"拉开"，露出笔记本 |
| 任何 → DISCOVERY | 即时 + 1.5s 保持 | 发现源处墨色瀑布 + 色彩溢出 |
| DISCOVERY → 之前状态 | 0.5s | 色彩收回至正常饱和度 |

### 3.3 房间视觉配置

每个房间有独立的视觉参数配置，由 VisualStyleManager 在玩家切换房间时应用。

| 房间 | 温度偏移 | 住客色渗入 | 默认雨强度 | 墨色密度基数 |
|------|---------|-----------|----------|-----------|
| 大堂 | 暖 (+0.1) | 五色均低饱和 (0.1) | 0.4 | 0.5 |
| 餐厅 | 暖 (+0.15) | 梅紫主导(0.3) + 青瓷次之(0.2) | 0.3 | 0.4 |
| 客房 A（观察者） | 中性 (0.0) | 仅靛蓝 (0.1) | 0.5 | 0.6 |
| 客房 B（倾听者+幼者） | 暖 (+0.1) | 青瓷主导(0.3) + 藤黄(0.15) | 0.5 | 0.5 |
| 守门人书房 | 冷 (-0.1) | 赭石主导(0.3) + 朱砂(0.15) | 0.3 | 0.7 |
| 走廊 | 冷 (-0.05) | 最近对话住客色 3s 褪去 | 0.6 | 0.6 |
| 地下室 | 寒 (-0.2) | 全部住客色高饱和 (0.4) | 0.2 | 0.8 |
| 阁楼 | 寒 (-0.15) | 梅紫(0.2) + 藤黄(0.2) | 0.7 | 0.5 |

温度偏移范围：-0.3（寒）到 +0.3（暖）。影响 shader 的 vignette 色温和墨色透明度。

### 3.4 发现时刻动画

当洞察生成时触发发现时刻动画序列：

1. **T=0.0s**：墨色从发现源（NPC/物品）位置径向退去，半径在 0.3s 内从 0 扩展到全屏
2. **T=0.3s**：发现对应颜色的全饱和色彩从中心向外溢出，超出目标边界 10-20px
3. **T=1.0s**：色彩开始收回至正常饱和度边界
4. **T=1.5s**：色彩稳定在 knowledge_level 对应的饱和度，过渡完成

MVP 实现：不使用径向遮罩（需要额外 shader uniform），改为全局 knowledge_level 瞬时提升然后回落至实际值，配合 vignette 临时变暖。色彩溢出通过 vignette 半径临时扩大实现。

### 3.5 夜晚过渡视觉序列

当 NightTransitionController 触发夜晚结束时：

1. **淹没阶段 (0-2.0s)**：knowledge_level 被 lerp 至 0.0，pressure_level 被 lerp 至 1.0，vignette 收紧至中心。深黑墨色从屏幕边缘向中心蔓延。
2. **保持阶段 (2.0-3.0s)**：全屏深墨，仅 vignette 中心微弱可见。
3. **排去阶段 (3.0-5.0s)**：knowledge_level 恢复至实际值（保留已赚取的色彩），pressure_level 降至 0.0。墨色从中心向边缘退去，露出白纸底色和色彩。

### 3.6 咆哮状态覆盖

ROAR 状态下的视觉规则覆盖房间配置：
- 所有房间温度强制为寒（-0.2）
- 墨色密度基数 +0.3（上限 1.0）
- Vignette 收紧 40%
- 色彩饱和度即使 knowledge_level 高也降 20%（压力覆盖色彩以强化紧迫感）
- 雨强度固定为 1.0

### 3.7 VisualStyleManager 接口

```gdscript
class_name VisualStyleManager
extends Node

signal visual_state_changed(old_state: int, new_state: int)

enum VisualState {
    EXPLORATION,
    DIALOGUE,
    CLUE_CONNECTION,
    WHISPER,
    ROAR,
    NIGHT_END,
    DISCOVERY,
}

# 当前视觉状态
var current_state: VisualState = VisualState.EXPLORATION
# 当前房间配置
var current_room_id: StringName = &""
# 发现动画进行中
var is_discovery_animating: bool = false

func request_state(new_state: VisualState) -> void
func set_room(room_id: StringName) -> void
func trigger_discovery(color_hex: String, source_position: Vector2) -> void
func trigger_night_end_sequence() -> void
func get_target_params() -> VisualParams
```

### 3.8 VisualParams 数据结构

```gdscript
class_name VisualParams
extends RefCounted

var knowledge_multiplier: float = 1.0      # 乘以 ColorAccumulationManager.knowledge_level
var pressure_multiplier: float = 1.0       # 乘以 TimerService.pressure_level
var vignette_radius: float = 1.4           # 基础 vignette 半径
var vignette_tightness: float = 0.7        # vignette 收紧程度
var temperature_offset: float = 0.0        # -0.3 寒 → +0.3 暖
var rain_intensity: float = 0.5            # 雨覆盖强度
var ink_density_base: float = 0.5          # 墨色密度基数
var saturation_penalty: float = 0.0        # 0-0.3 色彩饱和度惩罚
var edge_softness: float = 0.0             # 0 锐利 → 1 柔软
var transition_duration: float = 1.0       # 过渡时长（秒）
```

---

## 4. Formulas

### 4.1 参数插值公式

状态转换期间，所有 VisualParams 字段使用 ease-in-out 插值：

```
current_value = lerp(from_value, to_value, ease(progress, -2.0))
```

其中 `progress = elapsed_time / transition_duration`，`ease(x, -2.0)` 提供 ease-in-out 曲线。

### 4.2 温度偏移着色器应用

温度偏移不直接修改 shader uniform，而是通过调整 vignette 的冷暖色混合：

```
vignette_warm = vec3(0.96, 0.94, 0.89)  # 宣纸白偏暖
vignette_cold = vec3(0.86, 0.88, 0.92)  # 宣纸白偏冷
vignette_color = mix(vignette_cold, vignette_warm, 0.5 + temperature_offset)
```

MVP 实现：temperature_offset 通过 InkWashDriver 新增的 `set_temperature_offset()` 方法传递。

### 4.3 发现时刻动画公式

```
discovery_knowledge_boost = 1.0  # 临时提升至最大
discovery_eased_progress = ease(elapsed / 1.5, -2.0)
effective_knowledge = max(
    actual_knowledge,
    lerp(1.0, actual_knowledge, discovery_eased_progress)
)
```

### 4.4 房间切换过渡

房间切换在 1.0 秒内完成，使用交叉淡入：
- 前 0.5s：当前房间参数向中性值 lerp
- 后 0.5s：中性值向新房间参数 lerp

---

## 5. Edge Cases

### 5.1 状态中断

**情况**：WHISPER 状态正在过渡中（progress=0.4），ROAR 被触发。
**处理**：记录 WHISPER 的当前插值位置作为新起点，直接从当前位置向 ROAR 目标 lerp。过渡时长使用 ROAR 的 1.0s，不是 WHISPER 剩余时间。

### 5.2 快速连续发现

**情况**：两个洞察在 0.5s 内连续生成。
**处理**：第二个发现重置发现动画计时器。knowledge_boost 不叠加（已经是 1.0），但颜色切换到第二个发现的颜色。总动画时长不延长。

### 5.3 对话中触发低语

**情况**：玩家在 DIALOGUE 状态下倒计时进入 WHISPER。
**处理**：WHISPER 的温度和压力效果叠加在 DIALOGUE 的 NPC 颜色渗入之上。NPC 颜色保持但背景墨色开始颤抖。使用较高优先级状态的参数叠加较低优先级的部分参数。

### 5.4 夜晚结束期间发现

**情况**：NIGHT_END 序列播放中（墨色淹没阶段），玩家发现了最后一个洞察。
**处理**：NIGHT_END 优先级高于 DISCOVERY。发现被记录但动画延迟到 NIGHT_END 排去阶段完成后再播放。排去后先显示正常状态 0.5s，再播放发现动画。

### 5.5 色彩积累为零时的排去

**情况**：玩家整个夜晚没有获得任何洞察（knowledge_level=0.0），夜晚结束排去后。
**处理**：排去后显示纯单色白纸+墨色世界，无保留色彩。视觉上强调"无进展"。

### 5.6 无 ColorAccumulationManager / TimerService

**情况**：测试环境或未注册 autoloads 时。
**处理**：使用默认值（knowledge=0.0, pressure=0.0）。VisualStyleManager 不崩溃，仅以默认 EXPLORATION 参数运行。

### 5.7 未知房间 ID

**情况**：`set_room()` 接收未在配置中定义的 room_id。
**处理**：使用中性默认配置（temperature=0.0, 无住客色渗入, rain=0.5, density=0.5）。打印警告。

---

## 6. Dependencies

### 上游依赖（本系统消费）

| 系统 | 消费内容 | 接口 |
|------|---------|------|
| #16 色彩积累 | knowledge_level, npc_saturations, connection_intensity | ColorAccumulationManager (autoload) |
| #5 倒计时 | pressure_level, current_phase | TimerService (autoload) |
| #3 房间管理 | 当前房间 ID, 房间切换事件 | RoomManager (autoload) |
| #8 夜晚过渡 | 夜晚结束事件 | NightTransitionController (autoload) |
| #12 洞察生成 | 洞察生成事件, 关联 NPC | InsightGenerator signal via ClueDatabase |
| ADR-0001 | ink_wash.gdshader, rain.gdshader | InkWashDriver (autoload) |

### 下游依赖（本系统供给）

| 系统 | 供给内容 |
|------|---------|
| #19 计时器/HUD UI | visual_state 用于 HUD 元素动画同步 |
| #20 对话 UI | DIALOGUE 状态参数用于对话面板渲染 |
| #21 笔记本 UI | CLUE_CONNECTION 状态参数用于笔记本背景 |
| #24 音频系统 | visual_state 用于音乐/环境音切换 |

---

## 7. Tuning Knobs

| 参数 | 默认值 | 范围 | 影响的游戏方面 |
|------|-------|------|-------------|
| `transition_ease_curve` | -2.0 | -4.0 ~ 0.0 | 状态切换平滑度。更负 = 更明显的 ease-in-out |
| `discovery_duration` | 1.5s | 0.5 ~ 3.0s | 发现动画持续时长 |
| `discovery_knowledge_boost` | 1.0 | 0.5 ~ 1.0 | 发现时临时色彩恢复上限 |
| `night_end_flood_duration` | 2.0s | 1.0 ~ 4.0s | 夜晚淹没阶段时长 |
| `night_end_drain_duration` | 2.0s | 1.0 ~ 4.0s | 夜晚排去阶段时长 |
| `roar_saturation_penalty` | 0.2 | 0.0 ~ 0.4 | 咆哮时色彩惩罚力度 |
| `roar_vignette_tighten` | 0.4 | 0.1 ~ 0.6 | 咆哮时 vignette 收紧幅度 |
| `room_transition_duration` | 1.0s | 0.3 ~ 2.0s | 房间切换过渡时长 |
| `dialogue_bg_desaturation` | 0.3 | 0.0 ~ 0.5 | 对话时背景减墨密度 |
| `corridor_guest_color_linger` | 3.0s | 1.0 ~ 5.0s | 走廊住客色残留时间 |

---

## 8. Acceptance Criteria

1. **状态切换平滑**：七个视觉状态之间切换无瞬间跳变。所有参数通过 lerp 过渡，ease-in-out 曲线。测试验证任意相邻状态对的过渡时长符合规格。

2. **发现动画**：洞察生成时触发 knowledge_level 临时提升至 1.0 然后在 1.5s 内回落至实际值。vignette 临时变暖。测试验证动画计时和参数值序列。

3. **夜晚过渡序列**：NIGHT_END 状态触发三阶段动画（淹没→保持→排去），总时长 4.5-6.0s。排去后保留色彩正确恢复。测试验证阶段时长和 knowledge_level 恢复。

4. **房间视觉差异**：8 个房间各有独立视觉配置。切换房间时参数在 1.0s 内过渡。测试验证每个房间的配置值和切换过渡。

5. **咆哮覆盖**：ROAR 状态强制温度寒、墨色密度+0.3、色彩惩罚 0.2、雨强度 1.0，覆盖房间配置。测试验证覆盖参数值。

6. **优雅降级**：当 ColorAccumulationManager、TimerService、InkWashDriver 任一 autoload 不可用时，VisualStyleManager 以默认参数运行，无崩溃。测试验证缺失 autoload 场景。

7. **测试覆盖率**：单元测试 ≥80%，覆盖状态机转换、房间配置、发现动画、夜晚序列、降级场景。

8. **性能**：VisualStyleManager._process() 每帧执行 ≤5 次 lerp 计算 + ≤3 次 shader uniform 写入。无 GC 压力（无每帧分配）。
