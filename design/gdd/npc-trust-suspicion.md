# NPC Trust/Suspicion System (NPC 信任/怀疑系统)

**System ID**: #13
**Status**: Design Complete
**Date**: 2026-05-14
**Source ADR**: ADR-0012

---

## 1. Overview

NPC Trust/Suspicion (System #13) manages per-NPC trust and suspicion values as two independent axes (0.0--100.0 each), driven by player actions such as presenting clues, making dialogue choices, and demonstrating cross-loop knowledge. TrustManager (Autoload) owns all trust/suspicion state, persists it across nights via LoopStateManager's `propose_delta()` pipeline, and exposes a query API for downstream systems including DialogueManager (conditional branching), EventScheduler (threshold-triggered events), and UI (relationship indicators). The system reads NPC emotional state from NPCManager as an input but never writes to it, maintaining strict state ownership boundaries.

---

## 2. Player Fantasy (玩家体验)

> 信任不是按按钮就能获得的。每一次展示线索、每一次追问、每一次被识破的谎言，都在悄然塑造住客对你的态度。
> 你可能同时赢得靛蓝的信赖却引起她的警觉——因为你"不该知道那些事"。
> 这种矛盾关系正是七夜的核心张力：**知己与疑人并存** (trust and suspicion coexisting)。
>
> 玩家应该感受到：NPC 不是信息自动售货机。信任需要经营，怀疑可以被化解也可以被激化。
> 同一循环中，你不可能让所有人都信任你——每次选择都有代价。
> 跨循环的知识积累是一把双刃剑：展示得太多太快会引起警觉，但恰到好处的揭示能打开关键对话。

---

## 3. Detailed Rules

### 3.1 双轴模型 (Dual-Axis Model)

每个 NPC 维护两个独立的浮点值：

- **信任值 (trust_level)**: `0.0`--`100.0`，默认 `50.0`
- **怀疑值 (suspicion_level)**: `0.0`--`100.0`，默认 `0.0`

两个轴完全独立。不存在 `trust + suspicion = 100` 的约束。一个 NPC 可以同时高信任且高怀疑——例如"我相信你是好意，但你似乎知道不该知道的事"。

### 3.2 等级划分 (Tier Classification)

**TrustTier**:

| Tier | Range | Narrative Meaning | Chinese |
|------|-------|-------------------|---------|
| NONE | 0--29 | NPC ignores player; minimal dialogue | 陌生人 |
| LOW | 30--59 | NPC is polite but guarded | 泛泛之交 |
| MEDIUM | 60--79 | NPC shares some information willingly | 知己 |
| HIGH | 80--100 | NPC reveals secrets and proactively helps | 盟友 |

**SuspicionTier**:

| Tier | Range | Narrative Meaning | Chinese |
|------|-------|-------------------|---------|
| CALM | 0--19 | NPC has no concerns about the player | 放松 |
| WATCHFUL | 20--39 | NPC notices something unusual | 留意 |
| WARY | 40--59 | NPC actively guards information | 警觉 |
| ALARMED | 60--79 | NPC refuses sensitive topics; may lie | 戒备 |
| HOSTILE | 80--100 | NPC actively obstructs; may sabotage | 敌意 |

### 3.3 行动表 (TrustAction Table)

玩家行为触发信任/怀疑变更。所有变更通过 `apply_delta()` 应用。每条行动定义在 `TrustAction` 数据表中（`.tres` Resource），支持策划在编辑器中调整。

| Action ID | Description | trust_delta | suspicion_delta | Chinese |
|-----------|-------------|-------------|-----------------|---------|
| `show_correct_clue` | Present a relevant, correct clue | +8.0 | -5.0 | 展示正确线索 |
| `show_wrong_clue` | Present an irrelevant clue | -3.0 | +4.0 | 展示无关线索 |
| `accuse_correct` | Correctly accuse NPC of hiding something | +3.0 | +6.0 | 正确指控 |
| `accuse_wrong` | Wrongly accuse NPC | -10.0 | +8.0 | 错误指控 |
| `share_insight` | Share a relevant insight (synthesized knowledge) | +12.0 | -3.0 | 分享洞察 |
| `threaten` | Use threatening dialogue choice | -8.0 | +10.0 | 威胁 |
| `lie_caught` | Player caught in a lie by NPC | -15.0 | +12.0 | 谎言被识破 |
| `gift_or_favor` | Perform a favor or give a gift | +6.0 | -2.0 | 帮忙或赠礼 |
| `demonstrate_loop_knowledge` | Show knowledge from a future night | +2.0 | +15.0 | 展示循环知识 |
| `protect_secret` | Choose to protect NPC's secret | +10.0 | -4.0 | 保护秘密 |
| `reveal_secret` | Expose NPC's secret to others | -20.0 | +8.0 | 泄露秘密 |
| `silent_observation` | Observe without interacting | +1.0 | +0.0 | 沉默观察 |

设计说明：
- `accuse_correct` 同时增加信任（你确实了解真相）和怀疑（你在追查他们）
- `demonstrate_loop_knowledge` 是高风险行动：轻微增加信任但大幅增加怀疑
- `protect_secret` 和 `reveal_secret` 是同一叙事节点的两个选择，形成明显的信任分歧点
- `silent_observation` 提供了一个"安全但缓慢"的信任建设路径

### 3.4 NPC 情绪状态反馈 (Emotional State Feedback)

当 NPC 的情绪状态（由 NPCManager 管理）发生变化时，TrustManager 自动应用情绪权重变更。权重在 `TrustConfig` 中定义，per-NPC 可配。

实际 NPC 情绪状态枚举（与实现一致）：

| NPCEmotionalState | trust_delta | suspicion_delta | Chinese |
|-------------------|-------------|-----------------|---------|
| NEUTRAL | 0.0 | 0.0 | 平静 |
| CURIOUS | +1.0 | 0.0 | 好奇 |
| ANXIOUS | -2.0 | +3.0 | 焦虑 |
| HOSTILE | -4.0 | +6.0 | 敌对 |
| TRUSTING | +3.0 | -1.0 | 信任 |
| FRIGHTENED | -1.0 | +5.0 | 恐惧 |

情绪状态变更触发信任/怀疑微调，模拟 NPC 情绪对长期关系的潜移默化影响。

### 3.5 夜间衰减 (Night Decay)

每当前进到下一夜时，信任和怀疑各自向中性方向衰减：

- `night_trust_decay`: -2.0（信任每夜自然下降 2 点）
- `night_suspicion_decay`: -1.0（怀疑每夜自然下降 1 点）

衰减模拟时间流逝对关系的淡化效应。如果玩家不持续维护关系，信任会逐渐降低；如果玩家停止可疑行为，怀疑也会自然消退。

### 3.6 跨循环持久化 (Cross-Night Persistence)

- 信任和怀疑值通过 `LoopStateManager.propose_delta()` 持久化
- 状态路径：`trust.{npc_id}.trust_level` 和 `trust.{npc_id}.suspicion_level`
- 跨夜持久：值在 `advance_night()` 后保留（通过 DeltaAccumulator）
- 循环重启行为：per-NPC 可配置 `reset_on_loop_restart`
  - `false`（默认）：值跨循环保留
  - `true`：循环重启时恢复到 `initial_trust` / `initial_suspicion`

### 3.7 阈值跨越信号 (Threshold Crossing Signals)

当信任或怀疑值跨越预设阈值时，TrustManager 发出信号供下游系统消费。

默认阈值：`[20.0, 40.0, 60.0, 80.0]`

信号：
- `trust_threshold_crossed(npc_id, threshold, direction)` -- 信任跨越阈值
- `suspicion_threshold_crossed(npc_id, threshold, direction)` -- 怀疑跨越阈值

`direction` 枚举：`CROSSED_ABOVE`（从下方穿过）或 `CROSSED_BELOW`（从上方回落）

下游系统（DialogueManager, EventScheduler）根据这些信号触发对话分支解锁、事件调度、UI 提示等。

### 3.8 对话可用性门控 (Dialogue Availability Gating)

信任和怀疑等级影响对话内容的可用性，但不直接控制对话是否可以开始（对话可用性由 NPCManager 的 `dialogue_available` 属性控制）。

| Condition | Effect |
|-----------|--------|
| `trust >= 60` AND `suspicion < 40` | 解锁 NPC 的秘密相关对话分支 |
| `trust >= 80` AND `suspicion < 20` | 解锁 NPC 的核心秘密揭示对话 |
| `suspicion >= 60` | NPC 在对话中开始撒谎或回避话题 |
| `suspicion >= 80` | NPC 拒绝某些对话选项，可能主动结束对话 |
| `trust < 20` AND `suspicion >= 60` | NPC 极度敌对，对话内容极其有限 |

具体对话分支条件在 DialogueTree Resource 中通过 `DialogueCondition` 配置（参见 ADR-0013），TrustManager 仅提供查询 API。

### 3.9 Per-NPC 配置差异 (Per-NPC Configuration)

每位 NPC 通过独立的 `TrustConfig` Resource 定义其信任/怀疑参数。这允许策划为不同性格的 NPC 设定不同的演变曲线。

示例（靛蓝 vs 赭石）：

| Property | guest_indigo (靛蓝) | guest_ochre (赭石) |
|----------|--------------------|--------------------|
| `initial_trust` | 60.0（较开放） | 30.0（较封闭） |
| `initial_suspicion` | 10.0 | 20.0 |
| `night_trust_decay` | -1.5（信任衰减慢） | -3.0（信任衰减快） |
| `night_suspicion_decay` | -0.5（怀疑消退慢） | -2.0（怀疑消退快） |
| `reset_on_loop_restart` | false（记仇） | true（不记仇） |

---

## 4. Formulas

### 4.1 Trust/Suspicion Delta Application

**Named Expression**:

```
new_trust = clampf(old_trust + trust_delta, 0.0, 100.0)
new_suspicion = clampf(old_suspicion + suspicion_delta, 0.0, 100.0)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `old_trust` | float | 0.0--100.0 | NPC 当前信任值 |
| `old_suspicion` | float | 0.0--100.0 | NPC 当前怀疑值 |
| `trust_delta` | float | unbounded (clamped by output) | 本次变更的信任增量（正为增，负为减） |
| `suspicion_delta` | float | unbounded (clamped by output) | 本次变更的怀疑增量（正为增，负为减） |
| `new_trust` | float | 0.0--100.0 | 变更后的信任值（clamp 后） |
| `new_suspicion` | float | 0.0--100.0 | 变更后的怀疑值（clamp 后） |

**Output Range**: Both `new_trust` and `new_suspicion` are clamped to [0.0, 100.0]. Overflow and underflow are absorbed by clamping.

**Worked Example**: Player presents a correct clue to guest_indigo.
- `old_trust = 52.0`, `old_suspicion = 18.0`
- `trust_delta = +8.0` (show_correct_clue), `suspicion_delta = -5.0`
- `new_trust = clampf(52.0 + 8.0, 0.0, 100.0) = 60.0` -- crosses threshold 60 (LOW -> MEDIUM)
- `new_suspicion = clampf(18.0 + (-5.0), 0.0, 100.0) = 13.0`
- Signal emitted: `trust_threshold_crossed("guest_indigo", 60.0, CROSSED_ABOVE)`

### 4.2 Trust Tier Classification

**Named Expression**:

```
trust_tier = {
    HIGH    if trust >= 80.0
    MEDIUM  if trust >= 60.0
    LOW     if trust >= 30.0
    NONE    otherwise
}
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `trust` | float | 0.0--100.0 | NPC 信任值 |
| `trust_tier` | enum | {NONE, LOW, MEDIUM, HIGH} | 信任等级 |

**Output Range**: Always one of four enum values. Boundary inclusive at lower bound (60.0 -> MEDIUM, 59.99 -> LOW).

**Worked Example**:
- `trust = 59.99` -> `trust_tier = LOW`
- `trust = 60.0` -> `trust_tier = MEDIUM`
- `trust = 100.0` -> `trust_tier = HIGH`

### 4.3 Suspicion Tier Classification

**Named Expression**:

```
suspicion_tier = {
    HOSTILE   if suspicion >= 80.0
    ALARMED   if suspicion >= 60.0
    WARY      if suspicion >= 40.0
    WATCHFUL  if suspicion >= 20.0
    CALM      otherwise
}
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `suspicion` | float | 0.0--100.0 | NPC 怀疑值 |
| `suspicion_tier` | enum | {CALM, WATCHFUL, WARY, ALARMED, HOSTILE} | 怀疑等级 |

**Output Range**: Always one of five enum values. Boundary inclusive at lower bound.

**Worked Example**:
- `suspicion = 0.0` -> `suspicion_tier = CALM`
- `suspicion = 20.0` -> `suspicion_tier = WATCHFUL`
- `suspicion = 80.0` -> `suspicion_tier = HOSTILE`

### 4.4 Night Decay

**Named Expression**:

```
decayed_trust = clampf(current_trust + night_trust_decay, 0.0, 100.0)
decayed_suspicion = clampf(current_suspicion + night_suspicion_decay, 0.0, 100.0)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `current_trust` | float | 0.0--100.0 | 当夜结束时的信任值 |
| `current_suspicion` | float | 0.0--100.0 | 当夜结束时的怀疑值 |
| `night_trust_decay` | float | typically -1.0 to -5.0 | 每夜信任衰减量（负值 = 下降） |
| `night_suspicion_decay` | float | typically -0.5 to -3.0 | 每夜怀疑衰减量（负值 = 下降） |
| `decayed_trust` | float | 0.0--100.0 | 衰减后的信任值 |
| `decayed_suspicion` | float | 0.0--100.0 | 衰减后的怀疑值 |

**Output Range**: Clamped to [0.0, 100.0].

**Worked Example**: Night advances from Night 3 to Night 4 for guest_ochre.
- `current_trust = 45.0`, `night_trust_decay = -3.0`
- `current_suspicion = 55.0`, `night_suspicion_decay = -2.0`
- `decayed_trust = clampf(45.0 + (-3.0), 0.0, 100.0) = 42.0`
- `decayed_suspicion = clampf(55.0 + (-2.0), 0.0, 100.0) = 53.0`

### 4.5 Emotional State Weight Application

**Named Expression**:

```
applied_trust_delta = emotional_state_weights[state_name].trust
applied_suspicion_delta = emotional_state_weights[state_name].suspicion
```

Then fed into formula 4.1.

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `state_name` | string | NPCEmotionalState enum key | NPC 新情绪状态名称 |
| `emotional_state_weights` | Dictionary | nested {trust, suspicion} | Per-NPC 情绪权重配置 |

**Output Range**: Small deltas (typically -5.0 to +5.0). Applied via formula 4.1 with clamping.

**Worked Example**: guest_indigo transitions from NEUTRAL to HOSTILE.
- `emotional_state_weights["hostile"] = {trust: -4.0, suspicion: +6.0}`
- `apply_delta("guest_indigo", -4.0, +6.0, "emotional_state_change:hostile")`

### 4.6 Threshold Crossing Detection

**Named Expression**:

```
crossed_above = (old_value < threshold) AND (new_value >= threshold)
crossed_below = (old_value >= threshold) AND (new_value < threshold)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `old_value` | float | 0.0--100.0 | 变更前的值 |
| `new_value` | float | 0.0--100.0 | 变更后的值 |
| `threshold` | float | one of [20.0, 40.0, 60.0, 80.0] | 检测阈值 |
| `crossed_above` | bool | true/false | 是否从下方穿过阈值 |
| `crossed_below` | bool | true/false | 是否从上方回落到阈值以下 |

**Output Range**: Boolean. At most one of `crossed_above` or `crossed_below` is true per threshold per delta application.

**Worked Example**:
- `old_trust = 58.0`, `new_trust = 62.0`, threshold = 60.0
- `58.0 < 60.0` is TRUE, `62.0 >= 60.0` is TRUE -> `crossed_above = TRUE`
- Signal: `trust_threshold_crossed("guest_indigo", 60.0, CROSSED_ABOVE)`

---

## 5. Edge Cases

### 5.1 TrustManager 加载前查询 (Queries Before TrustManager Loads)

如果下游系统（如 DialogueManager）在 TrustManager 尚未加载时查询信任/怀疑值，默认返回 `trust = 50.0`, `suspicion = 0.0`。DialogueManager 使用 `_safe_get_trust()` / `_safe_get_suspicion()` 实现优雅降级。

### 5.2 NPC 不在 TrustConfig 注册表中 (Unknown NPC ID)

`get_trust(npc_id)` 对未注册 NPC 返回 `50.0`（中性信任）。`get_suspicion(npc_id)` 返回 `0.0`（无怀疑）。`apply_delta()` 对未注册 NPC 仍然正常执行（内部 Dictionary 自动创建条目）。但 `_on_npc_state_changed()` 会跳过未配置的 NPC。

### 5.3 双重钳位场景 (Double Clamping)

如果 `trust_delta` 极大（如 +200.0），`clampf` 确保 `new_trust` 不超过 100.0。多余的增量被静默吸收。同理，`trust_delta = -200.0` 不会使信任低于 0.0。这避免了"越界惩罚"——NPC 不会因为你一次犯错就永久记恨（信任不会低于 0）。

### 5.4 同一帧多次 apply_delta (Multiple Deltas in Same Frame)

在同一次对话中，多个后果可能连续触发 `apply_delta()`。每次调用都是独立的：读取当前值、计算新值、钳位、发出信号。因此两次 `+60.0` 的信任增量不会导致信任超过 100.0（第一次 +60 -> 100，第二次 +60 -> 100，但第二次的 trust_changed 信号不会发出因为值没变）。

### 5.5 阈值边界精确值 (Exact Threshold Boundary)

当 `old_value == threshold` 时，`apply_delta` 的 delta 为 0 不会触发跨越信号（`is_equal_approx` 检查阻止重复信号）。当 `old_value == 60.0` 且 `new_value == 60.0` 时，无信号发出。仅当值真正穿过阈值时才发信号。

### 5.6 循环重启时的重置行为 (Loop Restart Reset)

对于 `reset_on_loop_restart = true` 的 NPC，循环重启后：
- 信任恢复到 `initial_trust`（而非 50.0）
- 怀疑恢复到 `initial_suspicion`（而非 0.0）
- 恢复操作通过 `apply_delta()` 执行（差值方式），确保信号正确发出

对于 `reset_on_loop_restart = false` 的 NPC，值跨循环保留，Night 1 的值等于上一循环 Night 7 的值。

### 5.7 Night 7 到 Night 1 的过渡 (Night 7 to Night 1 Transition)

当循环重启时，`advance_night()` 从 Night 7 到 Night 1 触发 `_on_night_advanced(7, 1)`。此时夜间衰减逻辑照常执行（Night 7 的值先衰减一次），然后检查 `reset_on_loop_restart` 决定是否重置。

### 5.8 TrustManager 与 NPCManager 同时加载 (Load Order Race)

TrustManager 在 `_ready()` 中连接 `NPCManager.npc_state_changed` 信号。如果 TrustManager 加载时 NPCManager 尚未注册某 NPC（如场景异步加载），后续的 NPC 注册不会触发 `_on_npc_state_changed`。TrustManager 在首次 `apply_delta()` 时自动创建内部条目。

### 5.9 零信任高怀疑组合 (Zero Trust + High Suspicion)

`trust = 0.0` 且 `suspicion = 100.0` 的极端组合表示 NPC 完全不信任且极度怀疑。此状态下：
- `trust_tier = NONE`
- `suspicion_tier = HOSTILE`
- 对话极度受限（DialogueManager 中对应条件分支生效）
- 需要多次正面互动才能恢复（信任每夜衰减 -2.0，怀疑每夜衰减 -1.0，自然恢复极慢）

### 5.10 高信任高怀疑组合 (High Trust + High Suspicion)

`trust = 80.0` 且 `suspicion = 70.0` 是叙事上最有趣的组合——NPC 认为你是个好人但知道太多秘密。此状态下：
- `trust_tier = HIGH`（可以触发秘密揭示对话）
- `suspicion_tier = ALARMED`（NPC 在对话中撒谎或回避）
- 玩家面临战略抉择：降低怀疑（通过保护秘密、赠礼）以解锁揭示路径，还是利用高信任获取信息但冒被识破的风险

---

## 6. Dependencies

### 6.1 Direct Dependencies

| System | ADR | Relationship | Nature |
|--------|-----|-------------|--------|
| LoopStateManager | ADR-0004 | TrustManager 依赖 | `propose_delta()` 用于所有状态变更持久化；`register_state_paths()` 注册状态路径；`night_advanced` 信号触发夜间衰减 |
| NPCManager | ADR-0009 | TrustManager 读取 | `npc_state_changed` 信号触发情绪权重应用；`get_emotional_state()` 读取 NPC 情绪（只读） |
| InteractionBus | ADR-0006 | TrustManager 消费 | `interaction_detected` 信号可触发信任变更（如展示物品） |

### 6.2 Downstream Consumers

| System | ADR | Relationship | Nature |
|--------|-----|-------------|--------|
| DialogueManager | ADR-0013 | 消费 TrustManager 数据 | `get_trust()` / `get_suspicion()` 用于对话条件分支；`apply_delta()` 通过对话后果触发 |
| EventScheduler | (TBD) | 消费 TrustManager 数据 | `trust_threshold_crossed` / `suspicion_threshold_crossed` 信号触发事件 |
| Guest Interrogation | (TBD) | 消费 TrustManager 数据 | 信任/怀疑值驱动审问可用性和 NPC 反应 |
| UI / HUD | (TBD) | 显示 TrustManager 数据 | 信任/怀疑等级指示器（如水墨浓度变化） |

### 6.3 Autoload Load Order

TrustManager 必须在 LoopStateManager 和 NPCManager 之后加载。加载顺序：

```
LoopStateManager -> NPCManager -> ... -> TrustManager -> DialogueManager
```

### 6.4 State Ownership Boundaries

| State | Owner | TrustManager Access |
|-------|-------|-------------------|
| `trust_level` per NPC | TrustManager | Read + Write |
| `suspicion_level` per NPC | TrustManager | Read + Write |
| `emotional_state` per NPC | NPCManager | Read-only |
| `dialogue_available` per NPC | NPCManager | None |
| `clue` / `insight` knowledge | ClueDatabase | None |

---

## 7. Tuning Knobs

### 7.1 Per-Action Deltas (TrustAction Table)

每个行动的 `trust_delta` 和 `suspicion_delta` 定义在 `TrustAction` Resource 中。

| Knob | File | Type | Range | Default | Impact |
|------|------|------|-------|---------|--------|
| `show_correct_clue.trust_delta` | `assets/data/trust/trust_actions.tres` | float | 0--30 | +8.0 | 正面互动的信任收益 |
| `show_correct_clue.suspicion_delta` | same | float | -20--0 | -5.0 | 正面互动的怀疑降低量 |
| `lie_caught.trust_delta` | same | float | -30--0 | -15.0 | 被识破谎言的信任惩罚 |
| `lie_caught.suspicion_delta` | same | float | 0--30 | +12.0 | 被识破谎言的怀疑增加量 |
| `demonstrate_loop_knowledge.suspicion_delta` | same | float | 0--40 | +15.0 | 展示未来知识的怀疑风险 |

**Safe Range**: Single action delta should not exceed +/-30.0 to prevent tier-jumping by more than one tier per action.

### 7.2 Per-NPC Configuration (TrustConfig Resource)

每个 NPC 的 `TrustConfig` Resource 定义以下可调参数。

| Knob | Type | Range | Default | Impact |
|------|------|-------|---------|--------|
| `initial_trust` | float | 0.0--100.0 | 50.0 | NPC 初始信任值；高值 = NPC 天生友善 |
| `initial_suspicion` | float | 0.0--100.0 | 0.0 | NPC 初始怀疑值；高值 = NPC 天生多疑 |
| `night_trust_decay` | float | -10.0--0.0 | -2.0 | 每夜信任衰减；更负 = 信任更难维持 |
| `night_suspicion_decay` | float | -10.0--0.0 | -1.0 | 每夜怀疑衰减；更负 = 怀疑消退更快 |
| `reset_on_loop_restart` | bool | true/false | false | 循环重启是否重置；true = NPC 不记仇 |
| `emotional_state_weights` | Dictionary | varies | see 3.4 | 情绪状态变更对信任/怀疑的微调 |

**Safe Range**: `night_trust_decay` should be between -1.0 and -5.0 (too fast = player can never build trust; too slow = trust accumulates passively).

### 7.3 Threshold Configuration

| Knob | Type | Range | Default | Impact |
|------|------|-------|---------|--------|
| `trust_thresholds` | Array[float] | 0.0--100.0 | [20.0, 40.0, 60.0, 80.0] | 触发信任跨越信号的阈值 |
| `suspicion_thresholds` | Array[float] | 0.0--100.0 | [20.0, 40.0, 60.0, 80.0] | 触发怀疑跨越信号的阈值 |

**Safe Range**: Thresholds must be sorted ascending. Must not contain duplicates. Gap between thresholds should be at least 10.0 to prevent rapid signal fire.

### 7.4 Tier Boundary Configuration

Tier boundary 值硬编码在 `get_trust_tier()` 和 `get_suspicion_tier()` 方法中。如果需要策划可配，可以提升到 `TrustConfig` 中。

| Knob | Current Value | Note |
|------|--------------|------|
| TrustTier.NONE -> LOW boundary | 30.0 | Hardcoded |
| TrustTier.LOW -> MEDIUM boundary | 60.0 | Hardcoded |
| TrustTier.MEDIUM -> HIGH boundary | 80.0 | Hardcoded |
| SuspicionTier.CALM -> WATCHFUL boundary | 20.0 | Hardcoded |
| SuspicionTier.WATCHFUL -> WARY boundary | 40.0 | Hardcoded |
| SuspicionTier.WARY -> ALARMED boundary | 60.0 | Hardcoded |
| SuspicionTier.ALARMED -> HOSTILE boundary | 80.0 | Hardcoded |

---

## 8. Acceptance Criteria

### 8.1 Core Functionality

- [ ] `apply_delta()` 正确更新信任和怀疑值，并钳位到 [0.0, 100.0]
- [ ] `get_trust()` 对已注册 NPC 返回正确值，对未注册 NPC 返回 50.0
- [ ] `get_suspicion()` 对已注册 NPC 返回正确值，对未注册 NPC 返回 0.0
- [ ] `get_trust_tier()` 对所有边界值返回正确的 TrustTier 枚举（29.99 -> NONE, 30.0 -> LOW, 59.99 -> LOW, 60.0 -> MEDIUM, 79.99 -> MEDIUM, 80.0 -> HIGH）
- [ ] `get_suspicion_tier()` 对所有边界值返回正确的 SuspicionTier 枚举

### 8.2 Signal Emission

- [ ] `trust_changed` 信号在信任值变更时发出，携带正确的 `old_trust` 和 `new_trust`
- [ ] `suspicion_changed` 信号在怀疑值变更时发出，携带正确的 `old_susp` 和 `new_susp`
- [ ] `trust_changed` 信号在值未变时（is_equal_approx）不发出
- [ ] `trust_threshold_crossed` 在阈值从下方穿过时发出（CROSSED_ABOVE）
- [ ] `trust_threshold_crossed` 在阈值从上方回落时发出（CROSSED_BELOW）
- [ ] `suspicion_threshold_crossed` 对所有阈值 [20, 40, 60, 80] 正确发出

### 8.3 Persistence

- [ ] 每次 `apply_delta()` 调用 `LoopStateManager.propose_delta()` 两次（trust + suspicion）
- [ ] 状态路径格式正确：`trust.{npc_id}.trust_level` 和 `trust.{npc_id}.suspicion_level`
- [ ] `_register_state_paths()` 在 `_ready()` 时为所有已配置 NPC 注册路径
- [ ] 跨夜持久化：Night 3 trust=73.5 -> advance_night() + decay -> Night 4 trust=71.5（正确衰减后值）
- [ ] 序列化往返：save trust=73.5/suspicion=42.1 -> load -> 值精确恢复

### 8.4 NPC Emotional State Integration

- [ ] NPC 情绪状态变更触发 `_on_npc_state_changed()`，应用 TrustConfig 中的权重
- [ ] TrustManager 从不调用 NPCManager.request_state_transition()（只读边界）
- [ ] 未在 TrustConfig 注册的 NPC 的状态变更被安全跳过

### 8.5 Night Decay

- [ ] `night_advanced` 信号触发每 NPC 的夜间衰减
- [ ] 衰减值来自 TrustConfig（per-NPC 可配）
- [ ] 衰减为零的 NPC 不触发 apply_delta

### 8.6 Loop Restart Behavior

- [ ] `reset_on_loop_restart = true` 的 NPC 在循环重启后恢复到 initial_trust / initial_suspicion
- [ ] `reset_on_loop_restart = false` 的 NPC 在循环重启后保留上一循环的值
- [ ] 重置操作通过 apply_delta() 执行（差值方式），确保阈值跨越信号正确发出

### 8.7 Edge Cases

- [ ] 极大 delta（+200.0 / -200.0）被正确钳位，不导致溢出
- [ ] 同一帧多次 apply_delta 顺序执行，每次基于最新值
- [ ] 精确阈值边界的 delta=0 不触发跨越信号
- [ ] TrustManager 在 NPCManager 之前加载时不崩溃（信号连接延迟生效）
- [ ] DialogueManager 查询不存在的 TrustManager 时获得默认值（50.0/0.0）

### 8.8 Performance

- [ ] `apply_delta()` 执行时间 < 0.1ms（两次 float clamp + 两次 propose_delta + 阈值扫描）
- [ ] 查询 API (`get_trust`, `get_suspicion`) 执行时间 < 0.01ms（Dictionary lookup）
- [ ] 无每帧处理（`set_process(false)`），所有操作事件驱动
- [ ] 运行时内存 < 2KB（5 NPC x 2 floats + 5 configs）
