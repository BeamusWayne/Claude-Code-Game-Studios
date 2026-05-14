# 结局触发逻辑 (Ending Trigger Logic)

**System ID**: #23
**Category**: Narrative, MVP, Feature Layer
**Status**: GDD Complete
**Date**: 2026-05-14

---

## 1. Overview

结局触发逻辑决定游戏何时以及如何基于玩家累积的知识和关系状态触发结局。EndingManager（Autoload）持续监听 ClueDatabase 的洞察生成信号、TrustManager 的信任阈值信号、以及 KnowledgeManager 的知识水平变化信号，判断是否满足结局条件。MVP 实现单一结局——当玩家发现"真相"洞察时触发。结局触发是充分条件而非必要条件的逻辑或：只要满足任一触发条件即进入结局。触发后系统冻结计时器、展示结局叙事序列、然后返回标题画面。结局条件对玩家不可见——没有进度条或"你离结局还有多远"的提示，直到即将触发时才出现叙事暗示。

## 2. Player Fantasy

你不知道结局在等你。七夜的真相不是一道解锁门——它是你一点一点拼出的理解。某个夜晚，你把最后两个碎片连在一起。一条洞察生成，忽然——屏幕边缘开始发光。不是色彩积累的那种缓慢渐变，而是一种脉冲，像是世界本身在回应你的发现。倒计时停止了。时间不再流动，因为真相已经不需要时间了。你看到的不是"游戏结束"，而是一段你亲手写就的叙事——因为你发现的每一条线索、你信任（或背叛）的每一个人，都塑造了这段结局。

## 3. Detailed Rules

### 3.1 EndingManager 职责边界

EndingManager 负责：
- 监听多个上游系统的状态变化信号
- 评估结局触发条件（每帧不执行——纯事件驱动）
- 管理结局序列的执行（冻结、叙事、返回标题）
- 防止结局在对话或笔记本打开时触发

EndingManager **不**负责：
- 定义结局叙事内容（由叙事设计提供，硬编码在 EndingNarrative Resource 中）
- 判断哪个多结局触发（MVP 单结局，多结局系统 #25 的职责）
- 渲染结局画面（UI 系统的职责）

### 3.2 MVP 结局：真相洞察

MVP 实现单一结局，触发条件为发现"真相"洞察。该洞察是游戏中所有有效连接定义中权重最高的洞察——需要玩家完成核心推理链。

**真相洞察标识**：

```
insight_id: &"insight_truth"
```

该洞察通过 ClueDatabase 的标准连接流程生成——没有特殊触发机制。当 InsightGenerator 验证出正确的线索对并生成 insight_truth 时，ClueDatabase 发出 `insight_generated("insight_truth")` 信号，EndingManager 监听到此信号后检查触发条件。

### 3.3 触发条件体系

结局触发采用"逻辑或"策略——满足以下任一条件即触发结局：

| 条件 ID | 类型 | 条件表达式 | 说明 |
|---------|------|-----------|------|
| `TRUTH_INSIGHT` | insight | ClueDatabase.has_entry(&"insight_truth") | 发现真相洞察 |
| `KNOWLEDGE_THRESHOLD` | knowledge | knowledge_level >= ending_knowledge_threshold | 知识水平达到阈值 |
| `TRUST_ALLY` | trust | 任一 NPC trust >= 80.0 AND suspicion < 20.0 | 与某位住客建立完全信任 |

**条件评估优先级**：TRUTH_INSIGHT > KNOWLEDGE_THRESHOLD > TRUST_ALLY。如果多个条件同时满足，使用优先级最高的条件作为触发原因。

**MVP 范围**：TRUTH_INSIGHT 是主要触发条件。KNOWLEDGE_THRESHOLD 和 TRUST_ALLY 作为备用条件存在，确保即使玩家没有找到特定的洞察组合，但通过系统性探索积累了足够知识或建立了足够信任，也能触发结局。

### 3.4 触发时机约束

结局不会在以下时机触发：

- 对话进行中（DialogueManager.is_active == true）
- 笔记本打开中（NotebookManager.is_open == true）
- 审问进行中（InterrogationManager.is_active == true）
- 夜间过渡动画中（NightTransitionController.is_transitioning == true）
- 倒计时处于 CRITICAL 阶段（不允许在最高压力时突然切到结局）

当触发条件满足但时机不合适时，EndingManager 将触发标记为 pending。当阻塞条件清除后，在下一帧检查并执行触发。

### 3.5 反剧透设计

结局条件对玩家不可见：

- 没有"进度条"或"你已发现 X% 的真相"提示
- knowledge_level 不直接显示给玩家（通过色彩变化间接体现）
- 没有成就系统追踪结局进度
- 结局触发前没有"你即将揭开真相"的弹窗

唯一的暗示是叙事层面的：
- 当 knowledge_level >= soft_hint_threshold（默认 0.6）时，NPC 对话中可能暗示"你似乎快要弄清楚了"
- 当 knowledge_level >= hard_hint_threshold（默认 0.8）时，夜晚梦境序列中出现更强烈的暗示
- 这些暗示由 DialogueTree 的 DialogueCondition 条件控制，不是 EndingManager 的职责

### 3.6 结局序列

结局触发后执行以下序列：

**阶段 1：冻结（Freeze）**：
- TimerService.set_time_scale(0.0)（倒计时完全停止）
- InteractionBus.set_accepting(false)（禁用所有交互）
- NPCManager 暂停所有 NPC 状态更新
- 画面效果：knowledge_level 色彩快速提升至 1.0（真相揭示，世界完全着色）
- 持续时间：2.0 秒

**阶段 2：叙事展示（Narrative）**：
- 显示结局叙事面板（CanvasLayer 60，最高层）
- 叙事内容为预定义文本序列（EndingNarrative Resource）
- 每段文字有打字机效果（与对话系统一致，30 字/秒）
- 文字内容基于触发条件动态选择：
  - TRUTH_INSIGHT：强调"你发现了真相"
  - KNOWLEDGE_THRESHOLD：强调"你拼凑出了完整的图景"
  - TRUST_ALLY：强调"[NPC 名]选择信任你"
- 持续时间：由叙事文本长度决定（自动推进 + 玩家可跳过）

**阶段 3：总结（Summary）**：
- 显示游戏统计面板：
  - 总游戏时长
  - 经历的循环数
  - 发现的线索数 / 总线索数
  - 生成的洞察数 / 总洞察数
  - 每位 NPC 的最终信任/怀疑值
  - 结局触发原因（条件 ID）
- 玩家点击"返回标题"按钮结束

**阶段 4：清理（Cleanup）**：
- 保存最终游戏状态（存档槽标记为 completed）
- 返回标题画面
- 不自动重置游戏状态——玩家可从标题选择"继续"回到触发前状态

### 3.7 信号流

```
上游信号 → EndingManager._on_*()
    │
    ├─ ClueDatabase.insight_generated(id)
    │   └─ 检查 id == "insight_truth"
    │
    ├─ KnowledgeManager.knowledge_level_changed(level)
    │   └─ 检查 level >= ending_knowledge_threshold
    │
    ├─ TrustManager.trust_threshold_crossed(npc_id, threshold, direction)
    │   └─ 检查 threshold == 80.0 AND direction == CROSSED_ABOVE
    │       AND get_suspicion(npc_id) < 20.0
    │
    ▼ 任一条件满足
    │
    ├─ 检查触发时机约束
    │   ├─ [阻塞] → pending = true，等待阻塞清除
    │   └─ [允许] → 执行结局序列
    │
    ▼ 结局序列
    │
    ├─ Phase 1: Freeze（2 秒）
    │   ├─ TimerService.set_time_scale(0.0)
    │   ├─ InteractionBus.set_accepting(false)
    │   ├─ KnowledgeManager.knowledge_level → 1.0（视觉：完全着色）
    │   └─ 等待 2.0 秒
    │
    ├─ Phase 2: Narrative
    │   ├─ 显示 CanvasLayer 60 叙事面板
    │   ├─ 根据触发条件选择叙事文本
    │   └─ 打字机效果显示（可跳过）
    │
    ├─ Phase 3: Summary
    │   ├─ 显示统计数据
    │   └─ 等待玩家点击"返回标题"
    │
    └─ Phase 4: Cleanup
        ├─ 保存最终状态（标记 completed）
        └─ 返回标题画面
```

### 3.8 持久化

- 结局触发状态不持久化——每次加载存档后重新评估
- 标记为 completed 的存档在标题画面显示特殊图标
- 玩家可以从 completed 存档继续游戏（回到结局触发前的状态），探索未发现的内容
- 结局序列本身不保存——一旦触发即完整执行

## 4. Formulas

### 4.1 知识阈值判定

**Named Expression**:

```
knowledge_trigger = knowledge_level >= ending_knowledge_threshold
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `knowledge_level` | float | 0.0 -- 1.0 | 当前全局知识水平（来自 KnowledgeManager） |
| `ending_knowledge_threshold` | float | 0.7 -- 0.95 | 触发结局的知识阈值 |
| `knowledge_trigger` | bool | true/false | 知识条件是否满足 |

**Output Range**: Boolean.

**Worked Example**:
- `knowledge_level = 0.72`, `ending_knowledge_threshold = 0.85`
- `0.72 >= 0.85` = false -- not yet
- Player generates more insights, `knowledge_level = 0.88`
- `0.88 >= 0.85` = true -- condition met

### 4.2 信任盟友判定

**Named Expression**:

```
trust_ally_trigger = exists(npc_id) such that
    (trust >= trust_ally_trust_threshold) AND (suspicion < trust_ally_suspicion_cap)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `trust` | float | 0.0 -- 100.0 | NPC 信任值（来自 TrustManager） |
| `suspicion` | float | 0.0 -- 100.0 | NPC 怀疑值（来自 TrustManager） |
| `trust_ally_trust_threshold` | float | 60.0 -- 90.0 | 盟友触发的信任阈值（可配） |
| `trust_ally_suspicion_cap` | float | 0.0 -- 40.0 | 盟友触发的怀疑上限（可配） |
| `trust_ally_trigger` | bool | true/false | 是否存在满足条件的 NPC |

**Output Range**: Boolean. Scans all registered NPCs.

**Worked Example**:
- guest_indigo: trust=82.0, suspicion=15.0 -> condition met (trust >= 80 AND suspicion < 20)
- guest_umber: trust=45.0, suspicion=30.0 -> condition not met
- `trust_ally_trigger = true` (at least one NPC qualifies)

### 4.3 触发时机检查

**Named Expression**:

```
can_trigger = NOT (DialogueManager.is_active
    OR NotebookManager.is_open
    OR InterrogationManager.is_active
    OR NightTransitionController.is_transitioning
    OR TimerService.is_critical)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `DialogueManager.is_active` | bool | true/false | 对话是否正在进行 |
| `NotebookManager.is_open` | bool | true/false | 笔记本是否打开 |
| `InterrogationManager.is_active` | bool | true/false | 审问是否正在进行 |
| `NightTransitionController.is_transitioning` | bool | true/false | 是否在夜间过渡中 |
| `TimerService.is_critical` | bool | true/false | 倒计时是否在 CRITICAL 阶段 |
| `can_trigger` | bool | true/false | 当前是否允许触发结局 |

**Output Range**: Boolean. All blockers must be false for can_trigger to be true.

**Worked Example**:
- Dialogue active, all others clear: `NOT (true OR false OR false OR false OR false) = false` -- blocked
- All clear: `NOT (false OR false OR false OR false OR false) = true` -- proceed

### 4.4 结局叙事选择

**Named Expression**:

```
narrative_variant = {
    "truth"      if trigger_reason == TRUTH_INSIGHT
    "knowledge"  if trigger_reason == KNOWLEDGE_THRESHOLD
    "ally"       if trigger_reason == TRUST_ALLY
}
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `trigger_reason` | enum | TRUTH_INSIGHT / KNOWLEDGE_THRESHOLD / TRUST_ALLY | 触发结局的条件 |
| `narrative_variant` | String | "truth" / "knowledge" / "ally" | 使用的叙事变体 |

**Output Range**: One of three strings. MVP 只有 truth 变体有完整叙事，knowledge 和 ally 使用简短文本。

**Worked Example**:
- Player discovers `insight_truth` -> `trigger_reason = TRUTH_INSIGHT` -> `narrative_variant = "truth"`
- Player reaches knowledge_level 0.88 without truth insight -> `trigger_reason = KNOWLEDGE_THRESHOLD` -> `narrative_variant = "knowledge"`

### 4.5 结局色彩脉冲

**Named Expression**:

```
pulse_knowledge_level = lerp(current_knowledge, 1.0, pulse_progress)
pulse_progress = clampf(elapsed_time / pulse_duration, 0.0, 1.0)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `current_knowledge` | float | 0.0 -- 1.0 | 触发前的知识水平 |
| `pulse_duration` | float | 1.0 -- 3.0 | 色彩脉冲持续时间（秒） |
| `elapsed_time` | float | 0.0 -- pulse_duration | 脉冲已进行的时间 |
| `pulse_progress` | float | 0.0 -- 1.0 | 脉冲进度 |
| `pulse_knowledge_level` | float | current -- 1.0 | 当前脉冲中的知识水平值 |

**Output Range**: current_knowledge to 1.0. Linear interpolation over pulse_duration.

**Worked Example**:
- `current_knowledge = 0.65`, `pulse_duration = 2.0`, `elapsed_time = 0.5`
- `pulse_progress = clampf(0.5 / 2.0, 0.0, 1.0) = 0.25`
- `pulse_knowledge_level = lerp(0.65, 1.0, 0.25) = 0.7375`

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 多个触发条件在同一帧满足 | 按优先级选择：TRUTH_INSIGHT > KNOWLEDGE_THRESHOLD > TRUST_ALLY |
| 结局触发时对话正在进行 | 设为 pending，对话结束后触发 |
| 结局触发时笔记本打开 | 设为 pending，笔记本关闭后触发 |
| 结局触发时倒计时为 CRITICAL | 设为 pending，CRITICAL 结束后触发（或倒计时归零导致夜间过渡） |
| pending 期间新条件满足 | 不改变 pending 状态——已有触发原因保留 |
| 结局序列执行中游戏崩溃 | 不保存结局进度——下次加载存档回到触发前，重新评估条件 |
| insight_truth 在第一夜就被发现 | 正常触发结局——不做最低夜数限制（除非 allow_ending_on_night_1 = false） |
| knowledge_level 因洞察删除降到阈值以下 | 不撤销已满足的触发——一旦条件满足过就锁定（one-shot） |
| trust 降到 80 以下但触发已 pending | 不撤销 pending——触发条件一旦满足即锁定 |
| 所有 NPC 都不满足 trust_ally 条件 | TRUST_ALLY 条件不满足，检查其他条件 |
| ClueDatabase 中没有 insight_truth 定义 | TRUTH_INSIGHT 条件永远不满足，依赖其他触发条件 |
| knowledge_level 为 1.0 但没有 truth 洞察 | KNOWLEDGE_THRESHOLD 满足，正常触发 |
| 玩家从 completed 存档继续并再次触发结局 | 允许——结局可重复触发，不阻止继续游戏 |
| EndingManager 加载时条件已满足 | 在 _ready() 中评估一次，立即触发或设为 pending |
| 存档中标记了 completed 但条件不满足 | completed 标记仅影响标题画面显示，不影响触发逻辑 |

## 6. Dependencies

### 上游依赖

| System | ADR | Relationship | Nature |
|--------|-----|-------------|--------|
| Notebook System | — | 知识状态查询 | 查询 knowledge_level（通过 KnowledgeManager 代理） |
| NPC State Machine | ADR-0009 | NPC 情绪状态 | 检查 NPC 是否可交互（间接触发约束） |
| Clue Connection/Deduction | — | 洞察生成 | 监听 insight_generated 信号检查 insight_truth |
| Clue Database | ADR-0005 | 条目查询 | has_entry() 检查特定洞察是否存在 |
| Trust/Suspicion | ADR-0012 | 信任/怀疑值 | 监听 trust_threshold_crossed 信号 |
| KnowledgeManager | ADR-0002 | 知识水平 | 监听 knowledge_level_changed 信号 |
| Timer Service | ADR-0008 | 时间控制 | 冻结倒计时；检查 is_critical 约束 |
| Dialogue Manager | ADR-0013 | 对话状态 | 检查 is_active 约束 |
| Night Transition | ADR-0011 | 过渡状态 | 检查 is_transitioning 约束 |

### 下游被依赖

| System | Relationship | Nature |
|--------|-------------|--------|
| Multiple Endings (#25) | 多结局扩展 | 使用 EndingManager 的触发框架，添加多条件分支 |
| Save/Load (#4) | 存档标记 | 结局完成后标记存档为 completed |

### ADR 引用

- **ADR-0002** — knowledge_level 计算、色彩脉冲机制
- **ADR-0012** — trust_threshold_crossed 信号
- **ADR-0005** — insight_generated 信号
- **ADR-0003** — CanvasLayer 层级（结局叙事面板在 Layer 60）

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| ending_knowledge_threshold | float | 0.85 | 0.7--0.95 | 触发结局的知识水平阈值 |
| trust_ally_trust_threshold | float | 80.0 | 60.0--90.0 | 盟友触发的信任阈值 |
| trust_ally_suspicion_cap | float | 20.0 | 0.0--40.0 | 盟友触发的怀疑上限 |
| freeze_duration | float | 2.0 | 1.0--5.0 | 冻结阶段持续时间（秒） |
| pulse_duration | float | 2.0 | 1.0--3.0 | 色彩脉冲持续时间（秒） |
| narrative_typewriter_speed | float | 30.0 | 10.0--60.0 | 结局叙事打字机速度（字/秒） |
| soft_hint_threshold | float | 0.6 | 0.4--0.7 | NPC 暗示接近真相的知识阈值 |
| hard_hint_threshold | float | 0.8 | 0.7--0.9 | 强烈暗示的知识阈值 |
| allow_ending_on_night_1 | bool | false | true/false | 是否允许在第一夜触发结局（调试用） |

> **平衡说明**：ending_knowledge_threshold = 0.85 意味着玩家需要发现约 85% 的洞察才能通过知识路径触发。这确保了知识路径不会过早触发，但也为无法找到特定洞察的玩家提供了替代结局路径。

## 8. Acceptance Criteria

1. EndingManager 正确监听 ClueDatabase.insight_generated 信号
2. 当 insight_truth 被生成时，TRUTH_INSIGHT 条件触发
3. EndingManager 正确监听 KnowledgeManager.knowledge_level_changed 信号
4. 当 knowledge_level >= ending_knowledge_threshold 时，KNOWLEDGE_THRESHOLD 条件触发
5. EndingManager 正确监听 TrustManager.trust_threshold_crossed 信号
6. 当任一 NPC trust >= 80.0 且 suspicion < 20.0 时，TRUST_ALLY 条件触发
7. 多个条件同时满足时按优先级选择触发原因
8. 触发条件满足后锁定（one-shot），不因后续状态变化撤销
9. 对话期间结局触发被阻止，对话结束后自动执行
10. 笔记本打开时结局触发被阻止，关闭后自动执行
11. CRITICAL 阶段结局触发被阻止，阶段结束后自动执行
12. 夜间过渡期间结局触发被阻止
13. 冻结阶段正确调用 TimerService.set_time_scale(0.0)
14. 冻结阶段正确禁用 InteractionBus
15. 色彩脉冲在 freeze_duration 内从当前值线性插值到 1.0
16. 叙事面板显示正确的变体文本（基于触发原因）
17. 总结面板显示正确的统计数据（游戏时长、循环数、线索数、洞察数、NPC 信任值）
18. 结局完成后存档标记为 completed
19. EndingManager._ready() 加载时检查条件是否已满足
20. 从 completed 存档继续时结局可重复触发
21. 没有结局条件的进度提示或进度条显示给玩家
22. insight_truth 不存在时 TRUTH_INSIGHT 条件永远不满足，其他条件正常工作
