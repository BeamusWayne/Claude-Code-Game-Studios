# 条件性对话树 (Conditional Dialogue Trees)

## 1. Overview

条件性对话树系统管理 NPC 对话的完整生命周期：从对话触发、条件评估、节点展示、玩家选择、到后果触发和对话结束。DialogueManager（Autoload）协调对话会话，使用数据驱动的 DialogueTree Resource（.tres 文件）定义对话内容。条件评估器查询 NPCManager、TrustManager、ClueDatabase、LoopStateManager 等多个系统，支持 8 种条件类型和 7 种比较操作。对话期间计时器减速到 50%，阻止夜间过渡，并为下游系统提供后果触发机制。

## 2. Player Fantasy

**"每个词语都是线索，每个选择都有后果"** — 你走向靛蓝住客，她看起来很焦虑。对话开始时，时间仿佛慢了下来——倒计时仍在继续，但节奏变缓。你看到两个选择：温柔地询问她的夜晚，或者直接展示你发现的破碎灯笼碎片。你选择后者——她的表情从焦虑变为惊讶，然后是愤怒。信任下降了，但她透露了一个之前隐藏的信息。你的选择改变了这段关系，也改变了你能获取的信息。

## 3. Detailed Rules

### 3.1 对话数据结构

**DialogueTree Resource**（.tres 文件）：
- `tree_id: StringName` — 对话树唯一标识
- `npc_id: StringName` — 关联的 NPC ID
- `start_node_id: StringName` — 起始节点
- `nodes: Dictionary[StringName, DialogueNode]` — 所有对话节点

**DialogueNode**：
- `node_id: StringName` — 节点唯一标识
- `speaker: StringName` — 说话者（NPC ID 或 &"player"）
- `text: String` — 对话文本（支持占位符 `{npc_name}`）
- `choices: Array[DialogueChoice]` — 玩家可选项（空 = 自动前进）
- `next_node_id: StringName` — 无选择时的下一节点（&"" = 结束）
- `conditions: Array[DialogueCondition]` — 显示此节点的条件
- `priority: int` — 多个节点条件满足时的优先级

**DialogueChoice**：
- `choice_id: StringName` — 选项唯一标识
- `text: String` — 选项文本
- `conditions: Array[DialogueCondition]` — 显示此选项的条件
- `consequences: Array[DialogueConsequence]` — 选择后的后果
- `next_node_id: StringName` — 选择后的下一节点（&"" 或 &"END" = 结束对话）

### 3.2 条件类型

| 条件源 (source) | 查询目标 | 返回类型 | 降级行为 |
|----------------|---------|---------|---------|
| npc_emotional_state | NPCManager.get_emotional_state() | int (enum) | 返回 NEUTRAL(0) |
| trust_level | TrustManager.get_trust() | float (0-100) | 返回 50.0 |
| suspicion_level | TrustManager.get_suspicion() | float (0-100) | 返回 0.0 |
| has_clue | ClueDatabase.has_entry() | bool | 返回 false |
| has_insight | ClueDatabase.has_entry() | bool | 返回 false |
| loop_state | LoopStateManager.get_active_state_value() | Variant | 返回 null |
| current_night | LoopStateManager.current_night | int | 返回 1 |
| current_phase | TimerService phase | int | 返回 0 (CALM) |

**比较操作**：eq, neq, gte, lte, gt, lt, exists, not_exists

**评估逻辑**：所有条件 AND 组合（全部满足才显示）。空 conditions 数组 = 无条件显示。

### 3.3 后果类型

| 后果类型 (type) | 目标系统 | 参数 |
|----------------|---------|------|
| modify_trust | TrustManager | target_id, delta (float) |
| modify_suspicion | TrustManager | target_id, delta (float) |
| change_emotional_state | NPCManager | target_id, new_state (int) |
| reveal_clue | ClueDatabase | clue_id (StringName) |
| register_consequence | LoopStateManager | key, value |
| trigger_event | EventScheduler | event_id (StringName) |

后果在玩家选择后立即应用。多个后果按数组顺序串行执行。

### 3.4 对话流程

```
触发条件满足 → DialogueManager.start_dialogue(npc_id, tree)
    │
    ├─ 设置 is_active = true
    ├─ TimerService.set_time_scale(0.5)
    ├─ UIManager.set_dialogue_active(true)
    ├─ 评估 start_node 的 conditions
    │   ├─ 条件满足 → 显示该节点
    │   └─ 条件不满足 → 尝试下一个满足条件的节点
    │
    ▼ 显示节点
    │
    ├─ 无 choices → advance() 自动前进到 next_node_id
    ├─ 有 choices → 等待玩家选择
    │   │
    │   ▼ select_choice(choice_id)
    │   ├─ 应用 consequences
    │   ├─ next_node_id == "END" → end_dialogue()
    │   └─ next_node_id != "" → 显示下一个节点
    │
    └─ end_dialogue()
        ├─ TimerService.set_time_scale(1.0)
        ├─ UIManager.set_dialogue_active(false)
        └─ dialogue_ended.emit(npc_id)
```

### 3.5 对话触发

- 通过 NPCManager.npc_interaction_requested 信号触发
- DialogueManager 查询 NPC 的可用对话树（按优先级排序）
- 选择第一个满足所有触发条件的对话树开始
- 如果所有对话树的条件都不满足，显示默认问候语

### 3.6 对话面板 UI

- CanvasLayer 40（ADR-0003）
- 水墨风格背景（半透明）
- 打字机效果（逐字显示文本）
- 最多 5 个选项按钮同时显示
- 选项按条件过滤——不满足条件的选项不显示
- 选项高亮跟随鼠标/触摸

### 3.7 优雅降级

- TrustManager 不可用 → trust_level 返回 50.0，suspicion_level 返回 0.0
- ClueDatabase 不可用 → has_clue/has_insight 返回 false
- TimerService 不可用 → 不调整时间缩放
- NPCManager 不可用 → 不触发对话（系统不工作）

## 4. Formulas

### 对话期间时间缩放
```
dialogue_time_scale = 0.5  (50% 正常速度)
effective_countdown_duration = remaining_time / 0.5
```

### 条件评估优先级
```
node_priority = node.priority (越低越优先)
当多个节点条件同时满足时，选择 priority 最小的节点
```

### 选项过滤
```
visible_choices = filter(choices, c → evaluate(c.conditions) == true)
max_visible = min(visible_choices.size(), 5)
```

### 打字机速度
```
characters_per_second = 30
display_duration = text.length() / characters_per_second
```

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 对话期间触发夜间过渡 | NightTransitionController 检测 is_dialogue_active，阻止过渡 |
| 对话期间再次点击同一 NPC | is_active == true → 忽略 |
| 对话期间点击其他 NPC | is_active == true → 忽略（一次只能一个对话） |
| 对话树中所有节点条件都不满足 | 显示默认问候语（"这个人似乎不想说话。"） |
| 选项的 consequences 中有无效目标 | 后果静默失败（push_warning，不崩溃） |
| 同一 consequence 被多次应用 | 每次选择都独立应用（信任可以累计增减） |
| 对话期间存档 | DialogueManager 无持久状态，不需要序列化 |
| 读档后有未完成的对话 | 对话状态不恢复——读档后从非对话状态开始 |
| 对话树中存在循环引用 | 循环检测在加载时执行，标记为警告但不阻止运行 |
| TrustManager 不可用时 modify_trust 后果 | 后果静默跳过（push_warning） |

## 6. Dependencies

### 上游依赖
- **NPC 状态机 (#6)** — NPCManager 提供交互信号和情绪状态
- **NPC 信任/怀疑 (#13)** — TrustManager 提供信任/警觉值查询

### 下游被依赖
- **住客审问 (#15)** — 审问是特殊类型的条件性对话
- **对话 UI (#20)** — 展示对话面板和选项

### ADR 引用
- **ADR-0013** — DialogueManager 架构、条件评估器、后果系统
- **ADR-0003** — CanvasLayer 层级（对话面板在 Layer 40）
- **ADR-0008** — 计时器减速（对话期间 0.5x）
- **ADR-0011** — 夜间过渡阻止（dialogue_active 检查）

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| dialogue_time_scale | float | 0.5 | 0.2-0.8 | 对话期间倒计时减速比例 |
| max_visible_choices | int | 5 | 2-6 | 同时显示的最大选项数 |
| typewriter_speed | float | 30.0 | 10-60 | 每秒显示的字符数 |
| default_trust_fallback | float | 50.0 | 0-100 | TrustManager 不可用时的默认信任值 |
| default_suspicion_fallback | float | 0.0 | 0-100 | TrustManager 不可用时的默认警觉值 |

## 8. Acceptance Criteria

1. start_dialogue() 正确初始化对话会话并设置时间缩放
2. 条件评估器对 8 种条件源返回正确的值
3. 不满足条件的节点不显示
4. 不满足条件的选项不显示
5. select_choice() 正确应用所有后果
6. modify_trust 后果正确调用 TrustManager
7. change_emotional_state 后果正确更新 NPC 情绪
8. reveal_clue 后果正确注册线索到 ClueDatabase
9. end_dialogue() 恢复时间缩放和 UI 状态
10. TrustManager 不可用时使用默认值，不崩溃
11. 对话期间 is_active == true，阻止新对话和夜间过渡
12. 打字机效果逐字显示文本
13. dialogue_started/dialogue_ended 信号正确发出
14. 空对话树（无节点）不崩溃，直接结束
15. 循环引用的对话树产生警告但不死锁
