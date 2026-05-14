# 住客审问 (Guest Interrogation)

**System ID**: #15
**Category**: Gameplay, MVP, Feature Layer
**Status**: GDD Complete
**Date**: 2026-05-14
**Source ADR**: ADR-0013 (extends conditional dialogue trees)

---

## 1. Overview

住客审问是条件性对话树的特殊模式，允许玩家对 NPC 施压以获取隐藏信息。审问模式由 InterrogationManager（Autoload）协调——它在普通对话的基础上叠加压力机制、NPC 情绪状态追踪和线索展示质证。审问中的信任/怀疑增量是普通对话的 interrogation_multiplier 倍（默认 1.5x），使审问成为高风险高回报的信息获取手段。NPC 在审问中会经历情绪状态转移（CALM → ANXIOUS → HOSTILE），情绪状态决定可获取信息的深度。过度施压会导致 NPC 闭口不言或提供虚假信息。

## 2. Player Fantasy

你把靛蓝叫到走廊角落。她看起来很平静——至少现在是。你掏出那块破碎的灯笼碎片，质问她为什么声称从没来过走廊。她的表情变了。焦虑爬上她的眉头，但她还在抵抗。你加大力度，展示她在第三夜的秘密行动记录。她的嘴唇颤抖——她知道自己被逼到墙角了。就在她快要崩溃、准备说出真相的那一刻，你的追问过了火。她的焦虑变成了愤怒，嘴唇紧抿，再也不肯说一个字。

你得到了一条重要信息，但你永远不知道如果你再温柔一点，她会不会说出更多。

## 3. Detailed Rules

### 3.1 审问触发条件

审问是普通对话的升级模式。触发条件：

- NPC 当前处于可交互状态（NPCManager.dialogue_available == true）
- 玩家已发现至少 1 条与该 NPC 关联的线索（ClueDatabase 中 npc_affinity 匹配）
- NPC 的怀疑值低于 HOSTILE 阈值（suspicion < 80.0）
- 当前没有其他对话或审问正在进行（DialogueManager.is_active == false）

触发方式：在普通对话中选择"施压"类型的选项，或在 NPC 交互菜单中选择"审问"。进入审问模式后，DialogueManager.is_active 保持 true，TimerService 时间缩放保持 0.5x（与普通对话一致）。

### 3.2 审问会话结构

审问会话由 InterrogationManager 管理，包含以下阶段：

1. **开放阶段**：NPC 从当前情绪状态开始，提供初始对话选项
2. **质询阶段**：玩家选择追问方向或展示线索
3. **反应阶段**：NPC 根据压力和情绪做出反应，可能揭示信息或抵抗
4. **结束阶段**：审问以三种方式之一结束——NPC 崩溃（信息释放）、NPC 愤怒退出、玩家主动结束

### 3.3 审问对话数据

审问使用与普通对话相同的 DialogueTree Resource 格式（ADR-0013），但通过 metadata 标记为审问专用：

```
DialogueTree:
  tree_id: &"interrogation_indigo_night3"
  npc_id: &"guest_indigo"
  is_interrogation: true                    ← 审问标记
  interrogation_config: InterrogationConfig  ← 审问专用配置
```

**InterrogationConfig**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `pressure_success_threshold` | float | 累计压力值达到此阈值时 NPC 崩溃（释放关键信息） |
| `pressure_fail_threshold` | float | 累计压力值超过此阈值时 NPC 愤怒退出 |
| `opening_emotional_state` | NPCEmotionalState | 审问开始时强制的初始情绪状态 |
| `pressure_decay_per_turn` | float | 每回合压力自然衰减量 |
| `clue_bonus` | float | 展示相关线索时的压力加成 |

### 3.4 压力机制

审问的核心是累计压力值（pressure），代表 NPC 心理防线的承受程度：

- `pressure` 范围：0.0 -- `pressure_fail_threshold`（默认 100.0）
- 玩家的每个审问选项增加或减少 pressure
- 展示相关线索增加额外压力（clue_bonus）
- NPC 情绪状态随 pressure 阈值变化
- 每回合 pressure 自然衰减 `pressure_decay_per_turn`

**压力选项类型**：

| 选项类型 | pressure_delta | trust_delta_mult | suspicion_delta_mult | 说明 |
|----------|---------------|------------------|---------------------|------|
| `gentle_probe` | +5.0 | 0.8x | 0.8x | 温和追问——低压力、低信任/怀疑影响 |
| `direct_question` | +10.0 | 1.0x | 1.0x | 直接质问——标准压力 |
| `present_clue` | +15.0 + clue_bonus | 1.2x | 0.6x | 展示线索——高压力但降低怀疑（证据说话） |
| `threaten` | +20.0 | 0.5x | 2.0x | 威胁——高压力、高怀疑惩罚 |
| `comfort` | -5.0 | 1.5x | 0.5x | 安抚——降低压力、增加信任 |
| `observe` | 0.0 | 1.0x | 0.5x | 观察反应——无压力变化 |

trust_delta_mult 和 suspicion_delta_mult 是对基础后果的乘数。基础后果由 DialogueConsequence 定义（ADR-0013），乘数在 InterrogationManager 中应用。

### 3.5 NPC 情绪状态转移

审问中 NPC 情绪由 pressure 阈值驱动，而非直接由 NPC 状态机的常规转换规则控制：

| 压力范围 | 情绪状态 | NPC 行为 |
|---------|---------|---------|
| 0 -- 29 | NEUTRAL（平静） | 配合回答，提供基础信息 |
| 30 -- 59 | ANXIOUS（焦虑） | 紧张回答，可能无意中透露关键信息 |
| 60 -- 79 | FRIGHTENED（恐惧） | 可能崩溃释放关键信息（触发 pressure_success） |
| 80 -- 99 | HOSTILE（敌对） | 拒绝合作，可能撒谎 |
| >= 100 | EXIT（退出） | 强制结束审问，NPC 愤怒离去 |

情绪转移与 NPC 状态机的交互：
- 审问期间的情绪状态覆盖 NPC 状态机的常规状态
- 审问结束后，NPC 的情绪状态设为审问结束时的最终状态（通过 NPCManager.request_state_transition()）
- 如果审问以 HOSTILE 结束，NPC 状态机也设为 HOSTILE

### 3.6 线索展示机制

玩家在审问中可以展示已发现的线索来施压：

- 打开一个线索选择界面（从 ClueDatabase 获取所有已发现的 CLUE 条目）
- 玩家选择一条线索后，系统检查线索与当前 NPC 的关联性：
  - **强关联**：线索的 npc_affinity == 当前 NPC → clue_bonus = interrogation_config.clue_bonus（默认 +10.0）
  - **弱关联**：线索的 tags 包含当前 NPC 的 ID → clue_bonus × 0.5
  - **无关联**：线索与当前 NPC 无关 → clue_bonus = 0，且 trust_delta 额外 -5.0（展示无关线索降低信任）
- 展示线索触发 NPC 的特定反应对话节点（通过 DialogueCondition has_clue 条件匹配）

### 3.7 审问结果

审问以三种结果之一结束：

**崩溃（Breakdown）**：
- 触发条件：pressure >= pressure_success_threshold 且 NPC 当前情绪为 ANXIOUS 或 FRIGHTENED
- 效果：NPC 释放关键信息（自动 reveal_clue 后果），信任 +5.0，怀疑 -3.0
- NPC 情绪设为 FRIGHTENED（崩溃后）

**愤怒退出（Angry Exit）**：
- 触发条件：pressure >= pressure_fail_threshold
- 效果：审问强制结束，信任 -10.0，怀疑 +15.0
- NPC 情绪设为 HOSTILE，短时间内拒绝再次对话

**主动结束（Voluntary End）**：
- 触发条件：玩家选择"结束审问"选项
- 效果：无额外信任/怀疑变化（仅累计已发生的后果）
- NPC 情绪保持当前状态

### 3.8 信任/怀疑放大

审问中的所有信任/怀疑后果使用 interrogation_multiplier 放大：

- 默认 interrogation_multiplier = 1.5
- 放大应用于 DialogueConsequence 中的 modify_trust 和 modify_suspicion
- 展示线索带来的信任/怀疑变化也受放大影响
- 放大后的最终值通过 TrustManager.apply_delta() 应用（TrustManager 自身的钳位逻辑处理溢出）

### 3.9 跨夜持久化

审问结果跨夜持久化：

- 信任/怀疑变化通过 TrustManager 的 LoopStateManager.propose_delta() 持久化（与普通对话一致）
- NPC 情绪状态变化通过 NPCManager 持久化
- 审问中释放的线索通过 ClueDatabase 持久化
- 审问历史记录（pressure 变化轨迹）不持久化——每夜重新开始

### 3.10 信号流

```
玩家选择"审问" → InterrogationManager.start_interrogation(npc_id)
    │
    ├─ DialogueManager.is_active = true
    ├─ 加载审问专用 DialogueTree
    ├─ 初始化 pressure = 0.0
    ├─ 强制 NPC 情绪为 opening_emotional_state
    │
    ▼ 审问回合循环
    │
    ├─ 玩家选择审问选项（gentle_probe / direct_question / present_clue / threaten / comfort / observe）
    │   ├─ 应用 pressure_delta
    │   ├─ 应用 pressure_decay
    │   ├─ 检查情绪状态转移
    │   ├─ 应用信任/怀疑后果（× interrogation_multiplier）
    │   ├─ 若 present_clue：计算 clue_bonus 并应用
    │   ├─ 检查崩溃条件
    │   ├─ 检查愤怒退出条件
    │   └─ 显示 NPC 反应对话节点
    │
    ▼ 审问结束
    │
    ├─ [崩溃] → reveal_clue + trust +5 / suspicion -3
    ├─ [愤怒] → trust -10 / suspicion +15 + 拒绝对话冷却
    ├─ [主动] → 无额外后果
    │
    ├─ NPCManager.request_state_transition(npc_id, final_emotional_state)
    ├─ DialogueManager.is_active = false
    └─ interrogation_ended.emit(npc_id, result)
```

## 4. Formulas

### 4.1 压力累计

**Named Expression**:

```
pressure = clampf(pressure + pressure_delta - pressure_decay_per_turn, 0.0, pressure_fail_threshold)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `pressure` | float | 0.0 -- pressure_fail_threshold | 当前累计压力值 |
| `pressure_delta` | float | -20.0 -- +35.0 | 本次选项的压力增量（含 clue_bonus） |
| `pressure_decay_per_turn` | float | 0.0 -- 5.0 | 每回合压力自然衰减 |
| `pressure_fail_threshold` | float | 50.0 -- 150.0 | NPC 愤怒退出的压力阈值 |

**Output Range**: Clamped to [0.0, pressure_fail_threshold].

**Worked Example**: Player presents a relevant clue to guest_indigo.
- `pressure = 45.0`, `pressure_delta = +15.0 + 10.0(clue_bonus) = +25.0`, `pressure_decay_per_turn = 2.0`
- `pressure = clampf(45.0 + 25.0 - 2.0, 0.0, 100.0) = 68.0`
- NPC shifts from ANXIOUS to FRIGHTENED (crossed threshold 60)

### 4.2 情绪状态判定

**Named Expression**:

```
interrogation_emotional_state = {
    EXIT        if pressure >= pressure_fail_threshold
    HOSTILE     if pressure >= 80.0
    FRIGHTENED  if pressure >= 60.0
    ANXIOUS     if pressure >= 30.0
    NEUTRAL     otherwise
}
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `pressure` | float | 0.0 -- pressure_fail_threshold | 当前累计压力值 |
| `pressure_fail_threshold` | float | 50.0 -- 150.0 | NPC 愤怒退出阈值 |
| `interrogation_emotional_state` | enum | NEUTRAL/ANXIOUS/FRIGHTENED/HOSTILE/EXIT | 审问中 NPC 情绪 |

**Output Range**: Always one of five states. Threshold boundaries are inclusive at the lower bound.

**Worked Example**:
- `pressure = 59.9` -> `ANXIOUS`
- `pressure = 60.0` -> `FRIGHTENED`
- `pressure = 100.0` with `pressure_fail_threshold = 100.0` -> `EXIT`

### 4.3 放大后信任/怀疑增量

**Named Expression**:

```
amplified_trust_delta = base_trust_delta * trust_delta_mult * interrogation_multiplier
amplified_suspicion_delta = base_suspicion_delta * suspicion_delta_mult * interrogation_multiplier
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `base_trust_delta` | float | -30.0 -- +30.0 | DialogueConsequence 中定义的信任增量 |
| `base_suspicion_delta` | float | -30.0 -- +30.0 | DialogueConsequence 中定义的怀疑增量 |
| `trust_delta_mult` | float | 0.5 -- 2.0 | 选项类型的信任乘数 |
| `suspicion_delta_mult` | float | 0.5 -- 2.0 | 选项类型的怀疑乘数 |
| `interrogation_multiplier` | float | 1.0 -- 3.0 | 审问全局放大倍数 |
| `amplified_trust_delta` | float | unbounded (clamped by TrustManager) | 最终信任增量 |
| `amplified_suspicion_delta` | float | unbounded (clamped by TrustManager) | 最终怀疑增量 |

**Output Range**: Unbounded, but TrustManager.apply_delta() clamps final values to [0.0, 100.0].

**Worked Example**: Player threatens guest_indigo (threaten option).
- `base_trust_delta = -8.0` (from threaten consequence), `trust_delta_mult = 0.5`, `interrogation_multiplier = 1.5`
- `amplified_trust_delta = -8.0 * 0.5 * 1.5 = -6.0`
- `base_suspicion_delta = +10.0`, `suspicion_delta_mult = 2.0`, `interrogation_multiplier = 1.5`
- `amplified_suspicion_delta = 10.0 * 2.0 * 1.5 = +30.0`
- TrustManager.apply_delta("guest_indigo", -6.0, +30.0) -- heavy suspicion spike

### 4.4 线索关联性加成

**Named Expression**:

```
effective_clue_bonus = {
    interrogation_config.clue_bonus          if clue.npc_affinity == current_npc_id
    interrogation_config.clue_bonus * 0.5    if current_npc_id in clue.tags
    0.0                                      otherwise
}
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `clue.npc_affinity` | StringName | any NPC ID or &"" | 线索的主要关联住客 |
| `current_npc_id` | StringName | valid NPC ID | 当前被审问的 NPC |
| `clue.tags` | Array[StringName] | — | 线索的标签列表 |
| `interrogation_config.clue_bonus` | float | 5.0 -- 20.0 | 展示相关线索的压力加成 |
| `effective_clue_bonus` | float | 0.0 -- 20.0 | 实际获得的加成 |

**Output Range**: 0.0 to clue_bonus. For unrelated clues, 0.0 with an additional trust penalty.

**Worked Example**:
- Clue `clue_broken_lantern` has `npc_affinity = &"guest_indigo"` and `tags: [&"npc_indigo", &"object"]`
- Player presents it while interrogating `guest_indigo`
- `clue.npc_affinity == guest_indigo` -> `effective_clue_bonus = 10.0`

### 4.5 崩溃判定

**Named Expression**:

```
is_breakdown = (pressure >= pressure_success_threshold)
    AND (interrogation_emotional_state in {ANXIOUS, FRIGHTENED})
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `pressure` | float | 0.0 -- pressure_fail_threshold | 当前累计压力值 |
| `pressure_success_threshold` | float | 30.0 -- 80.0 | NPC 崩溃的压力阈值 |
| `interrogation_emotional_state` | enum | — | NPC 当前审问情绪状态 |
| `is_breakdown` | bool | true/false | 是否触发崩溃 |

**Output Range**: Boolean. Both conditions must be true simultaneously.

**Worked Example**:
- `pressure = 65.0`, `pressure_success_threshold = 60.0`, `interrogation_emotional_state = FRIGHTENED`
- `65.0 >= 60.0` = true, `FRIGHTENED in {ANXIOUS, FRIGHTENED}` = true
- `is_breakdown = true` -- NPC releases critical information

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 审问期间 NPC 情绪达到 HOSTILE 但未到 EXIT | NPC 拒绝回答当前问题，可能撒谎，审问继续 |
| 审问期间触发夜间过渡 | NightTransitionController 检测 DialogueManager.is_active == true，阻止过渡 |
| 审问中展示未发现的线索 | 不可能——线索选择界面只显示 ClueDatabase 中已发现的条目 |
| 审问中展示无关线索 | pressure 无 clue_bonus 加成，且 trust 额外 -5.0（展示者缺乏准备） |
| 压力恰好等于崩溃阈值 | 触发崩溃（阈值包含边界） |
| 压力恰好等于愤怒阈值 | 触发愤怒退出（阈值包含边界） |
| 崩溃和愤怒同时满足 | 愤怒优先（上限保护先触发）——pressure_fail_threshold < pressure_success_threshold 时不会发生 |
| 同一夜对同一 NPC 多次审问 | 允许，但 NPC 的信任/怀疑已受前次影响，可能更难或更容易 |
| 审问期间 TrustManager 不可用 | 使用默认信任/怀疑值（50.0/0.0），后果静默跳过（push_warning） |
| 审问期间 ClueDatabase 不可用 | 线索展示功能不可用，其他审问选项正常工作 |
| NPC 的 suspicion >= 80.0（HOSTILE 怀疑等级）时尝试审问 | 审问触发条件不满足——NPC 拒绝进入审问 |
| pressure_decay 使 pressure 降到 0 以下 | clampf 保证 pressure 不低于 0.0 |
| 审问对话树无审问专用节点 | 使用默认审问对话模板（通用反应） |
| InterrogationConfig 中 pressure_success_threshold >= pressure_fail_threshold | 加载时验证拒绝，使用默认值（success=60, fail=100） |
| 玩家在审问中选择 observe（观察）连续 10 次 | pressure 持续衰减但不增加，NPC 保持当前情绪，无信息获得——浪费回合但允许 |
| NPC 在审问中释放的线索已被发现 | reveal_clue 后果通过 ClueDatabase 处理——已存在的条目不重复添加 |

## 6. Dependencies

### 上游依赖

| System | ADR | Relationship | Nature |
|--------|-----|-------------|--------|
| Conditional Dialogue Trees | ADR-0013 | 审问基于对话系统 | 使用 DialogueTree 格式、DialogueCondition 评估、DialogueConsequence 执行 |
| NPC Trust/Suspicion | ADR-0012 | 审问驱动信任/怀疑变化 | 调用 TrustManager.apply_delta() 查询 get_trust()/get_suspicion() |
| Interaction System | ADR-0006 | NPC 交互触发审问 | 监听 InteractionBus.interaction_detected 信号 |
| NPC State Machine | ADR-0009 | 审问影响 NPC 情绪 | 调用 NPCManager.request_state_transition() |
| Clue Database | ADR-0005 | 线索展示和释放 | 查询 ClueDatabase 获取可展示线索；接收 reveal_clue 后果 |
| Loop State Management | ADR-0004 | 审问结果持久化 | 审问触发的状态变更通过 propose_delta() 持久化 |

### 下游被依赖

| System | Relationship | Nature |
|--------|-------------|--------|
| Ending Trigger Logic (#23) | NPC 信任/怀疑阈值影响结局条件 | 审问导致的信任/怀疑变化可能触发或阻止结局 |
| Dialogue UI (#20) | 展示审问界面 | 审问使用增强版对话面板（含压力指示器和线索选择器） |

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| interrogation_multiplier | float | 1.5 | 1.0--3.0 | 审问中信任/怀疑后果的放大倍数 |
| pressure_fail_threshold | float | 100.0 | 50.0--150.0 | NPC 愤怒退出的压力上限 |
| pressure_success_threshold | float | 60.0 | 30.0--80.0 | NPC 崩溃释放信息的压力阈值 |
| pressure_decay_per_turn | float | 2.0 | 0.0--5.0 | 每回合压力自然衰减量 |
| clue_bonus | float | 10.0 | 5.0--20.0 | 展示相关线索的压力加成 |
| angry_exit_trust_penalty | float | -10.0 | -30.0--0.0 | 愤怒退出的信任惩罚 |
| angry_exit_suspicion_penalty | float | +15.0 | 0.0--+30.0 | 愤怒退出的怀疑增加 |
| breakdown_trust_bonus | float | +5.0 | 0.0--+15.0 | NPC 崩溃的信任奖励 |
| breakdown_suspicion_reduction | float | -3.0 | -10.0--0.0 | NPC 崩溃的怀疑降低 |
| unrelated_clue_trust_penalty | float | -5.0 | -15.0--0.0 | 展示无关线索的额外信任惩罚 |
| dialogue_cooldown_after_anger | float | 120.0 | 30.0--300.0 | 愤怒退出后 NPC 拒绝对话的冷却时间（秒，游戏内） |

> **约束**：pressure_success_threshold 必须 < pressure_fail_threshold。加载时验证，不满足则使用默认值。

## 8. Acceptance Criteria

1. InterrogationManager.start_interrogation() 在满足触发条件时正确初始化审问会话（pressure=0.0, 加载审问 DialogueTree, 强制 NPC 初始情绪）
2. 审问触发条件检查：NPC 可交互 + 至少 1 条关联线索 + suspicion < 80.0 + 无活跃对话
3. 审问触发条件不满足时拒绝启动，返回明确的失败原因
4. 每个审问选项正确应用 pressure_delta 和 pressure_decay_per_turn
5. NPC 情绪状态随 pressure 阈值正确转移（NEUTRAL -> ANXIOUS -> FRIGHTENED -> HOSTILE -> EXIT）
6. 展示相关线索（npc_affinity 匹配）获得完整 clue_bonus
7. 展示弱关联线索（tags 匹配）获得 clue_bonus x 0.5
8. 展示无关线索获得 0 clue_bonus 且额外 trust -5.0
9. 信任/怀疑后果正确应用 interrogation_multiplier 和选项类型乘数
10. pressure >= pressure_success_threshold 且情绪为 ANXIOUS/FRIGHTENED 时触发崩溃
11. pressure >= pressure_fail_threshold 时触发愤怒退出
12. 崩溃结果：reveal_clue + trust +5.0 / suspicion -3.0
13. 愤怒退出结果：trust -10.0 / suspicion +15.0 / NPC 设为 HOSTILE / 冷却计时开始
14. 主动结束审问无额外后果
15. 审问结束后 NPCManager.request_state_transition() 正确设为最终情绪状态
16. 审问期间 DialogueManager.is_active == true，阻止新对话和夜间过渡
17. InterrogationManager 在 TrustManager 不可用时使用默认值（50.0/0.0），不崩溃
18. InterrogationManager 在 ClueDatabase 不可用时禁用线索展示，其他选项正常
19. interrogation_ended 信号携带正确的 npc_id 和结果类型
20. 同一夜多次审问同一 NPC 时信任/怀疑变化正确累计
