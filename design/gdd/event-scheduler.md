# 事件调度器 (Event Scheduler)

> **Status**: GDD Complete
> **Author**: Katya + systems-designer
> **Last Updated**: 2026-05-14
> **Implements Pillar**: 支柱 2 (时间在低语与咆哮之间交替) — 通过定时和条件事件驱动每夜的节奏变化

## 1. Overview

事件调度器管理每夜中基于时间和条件的脚本事件调度。EventScheduler Autoload 单例从每夜的 ScriptedEvent Resource 列表加载事件定义，在 TimerService 的 `remaining_time` 达到阈值（TIME 触发器）或游戏状态满足条件（CONDITION 触发器）时触发事件动作（移动 NPC、启动对话、改变房间状态、发出自定义信号）。每个事件每夜最多触发一次，夜晚过渡时重置已触发集合并加载新夜的事件列表。系统仅负责调度和分发——不包含动作的执行逻辑。

## 2. Player Fantasy

**"世界在你不知道的地方运转着"** — 当你在书房翻阅旧信件时，靛蓝悄然从大厅走向花园。当你终于将两条线索连在一起时，梅紫已经关上了客房的门。事件调度器让旅馆成为一个活的空间：NPC 有自己的时间表，环境会随时间变化，某些对话只在特定时刻出现。玩家不是在"触发脚本"——他们在观察一个运转中的世界，而每次循环都能发现新的时间线上发生了什么。

## 3. Detailed Rules

### 3.1 EventScheduler Autoload

- 全局单例，挂载为 Autoload
- 不持有游戏状态（`fired_events` 是调度器自身的运行时追踪，不是游戏世界状态）
- 每帧在 `_process()` 中检查待触发事件（TIME 和 COMPOUND 触发器检查 remaining_time）
- CONDITION 触发器通过监听上游系统信号评估（不主动轮询）
- 提供 `load_night_events(night: int)` 接口，按夜号加载事件
- 提供 `force_trigger(event_id: StringName)` 接口，供脚本强制触发（仍计入 fired_events）

### 3.2 ScriptedEvent Resource

每个事件定义为 Godot Resource (.tres)，包含以下字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| event_id | StringName | 唯一标识符（格式：`night{N}_{descriptor}`） |
| trigger_type | TriggerType | TIME / CONDITION / COMPOUND |
| trigger_time | float | 秒数，从夜晚开始计时（TIME 和 COMPOUND 使用） |
| trigger_conditions | Array[EventCondition] | 条件列表（CONDITION 和 COMPOUND 使用） |
| actions | Array[EventAction] | 触发后执行的动作列表 |
| priority | int | 同帧多事件触发时的优先级（数值越高越先执行） |

### 3.3 触发器类型

**TIME 触发器**：当 `TimerService.remaining_time <= total_duration - trigger_time` 时触发。即 `trigger_time` 是从夜晚开始经过的秒数。

```
elapsed_time = total_duration - remaining_time
should_fire = (elapsed_time >= trigger_time)
```

**CONDITION 触发器**：当所有 `trigger_conditions` 都满足时触发。条件类型：

| 条件类型 | 检查内容 | 示例 |
|---------|---------|------|
| npc_in_room | NPC 当前在指定房间 | "靛蓝在花园" |
| npc_emotional_state | NPC 情绪状态匹配 | "赭石处于 ANXIOUS" |
| clue_discovered | 指定线索已发现 | "日记碎片 #3 已收集" |
| room_state | 房间状态匹配 | "书房灯已关" |
| custom_flag | LoopStateManager 中的布尔标志 | "bookshelf_searched" |
| phase_is | TimerService 当前压力阶段 | "phase == CRITICAL" |

CONDITION 触发器通过信号监听评估：
- `npc_in_room` / `npc_emotional_state`：监听 NPCManager 状态变更信号
- `clue_discovered`：监听 ClueDatabase 的 `clue_added` 信号
- `room_state`：监听 RoomManager 的 `room_state_changed` 信号
- `custom_flag`：监听 LoopStateManager 的 `state_changed` 信号
- `phase_is`：监听 TimerService 的 `phase_changed` 信号

当相关信号触发时，重新评估所有依赖该信号的 CONDITION 事件。

**COMPOUND 触发器**：TIME 和 CONDITION 都满足时触发。在 `_process()` 中同时检查时间阈值和条件状态。

### 3.4 动作类型

| 动作类型 | 参数 | 目标系统 | 说明 |
|---------|------|---------|------|
| move_npc | npc_id, target_room | NPCManager | 将 NPC 移动到指定房间 |
| start_dialogue | dialogue_id, npc_id | UIManager (future) | 启动指定对话 |
| change_room_state | room_id, state_key, value | RoomManager | 修改房间状态属性 |
| emit_custom_signal | signal_name, args | InteractionBus | 通过事件总线发出自定义信号 |

动作列表按数组顺序依次执行。每个动作是独立调用——一个动作失败不阻止后续动作。

### 3.5 事件生命周期

1. **加载**：`night_ready` 信号 → `load_night_events(current_night)` → 从 Resource 加载当夜事件
2. **等待**：事件进入 `pending_events` 集合，等待触发条件满足
3. **触发**：条件满足 → 执行 actions → 事件 ID 加入 `fired_events`
4. **重置**：`night_advanced` 信号 → 清空 `fired_events` 和 `pending_events`
5. **重新加载**：NightTransitionController 完成 transition_complete → `load_night_events(new_night)`

### 3.6 每夜事件定义

事件通过 NightEvents Resource 定义，每夜一个 .tres 文件：

```
assets/data/events/night_1_events.tres
assets/data/events/night_2_events.tres
...
assets/data/events/night_7_events.tres
```

如果某夜没有对应文件，`load_night_events()` 加载空列表（无事件）。不报错。

### 3.7 同帧多事件处理

当同一帧有多个事件满足触发条件时：
1. 按 `priority` 降序排序
2. 按排序顺序依次执行
3. 每个事件执行后立即加入 `fired_events`（防止条件变化后重复触发）

### 3.8 序列化

EventScheduler 的序列化仅保存 `fired_events` 集合。事件定义从 Resource 重新加载（不序列化）。

```
serialize() -> { "fired_events": [...], "loaded_night": int }
deserialize(data) -> 恢复 fired_events，重新加载对应夜的事件列表（跳过已触发事件）
```

## 4. Formulas

### 时间触发判定

```
should_fire_time(event) = (NOT event.event_id IN fired_events)
    AND (elapsed_time >= event.trigger_time)

elapsed_time = TimerService.total_duration - TimerService.remaining_time
```

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| elapsed_time | float | 0.0 - total_duration | 从夜晚开始经过的时间（秒） |
| trigger_time | float | 0.0 - total_duration | 事件设定的触发时间偏移（秒） |
| fired_events | Set[StringName] | 动态增长 | 当夜已触发的事件 ID 集合 |

**Output range**: Boolean (true = should fire, false = should not fire)
**Worked example**: Night duration = 180s, event trigger_time = 60s. At remaining_time = 119s, elapsed_time = 61s >= 60s -> fires.

### 条件评估

```
should_fire_condition(event) = (NOT event.event_id IN fired_events)
    AND (ALL conditions evaluate to true)

evaluate_condition(cond) =
    SWITCH cond.type:
        npc_in_room         -> NPCManager.get_npc_position(cond.npc_id) == cond.room_id
        npc_emotional_state -> NPCManager.get_npc_state(cond.npc_id) == cond.state
        clue_discovered     -> ClueDatabase.has_clue(cond.clue_id)
        room_state          -> RoomManager.get_room_state(cond.room_id, cond.key) == cond.value
        custom_flag         -> LoopStateManager.get_state(cond.flag_path) == true
        phase_is            -> TimerService.current_phase == cond.phase
```

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| cond.type | enum | 6 种条件类型 | 条件检查的种类 |
| cond.npc_id | StringName | 5 个住客 ID | 目标 NPC 标识 |
| cond.room_id | StringName | 8 个房间 ID | 目标房间标识 |
| cond.clue_id | StringName | 线索 ID | 目标线索标识 |
| cond.state | int | NPC 情绪 Enum 值 | 期望的 NPC 情绪状态 |
| cond.phase | int | PressurePhase Enum 值 | 期望的压力阶段 |
| cond.value | Variant | 取决于 room_state 类型 | 期望的房间状态值 |

**Output range**: Boolean (all conditions must be true)
**Worked example**: Event requires npc_in_room(indigo, garden) AND clue_discovered(diary_3). If Indigo is in garden but diary_3 not found -> false. Both met -> true.

### COMPOUND 触发判定

```
should_fire_compound(event) = should_fire_time(event) AND should_fire_condition(event)
```

**Output range**: Boolean
**Worked example**: Event triggers at 90s elapsed AND npc_in_room(umber, study). At 92s elapsed, if Umber is in study -> fires. At 92s elapsed, if Umber is in lobby -> does not fire. At 85s elapsed, even if Umber is in study -> does not fire (time not reached).

### 事件加载路径

```
event_resource_path = "res://assets/data/events/night_{night}_events.tres"
```

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| night | int | 1-7 | 当前夜号 |
| event_resource_path | String | 有效路径或不存在 | 事件资源文件路径 |

**Worked example**: Night 3 -> loads "res://assets/data/events/night_3_events.tres". If file does not exist -> empty event list.

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| trigger_time = 0 | 事件在夜晚开始后立即满足时间条件（第一帧即可触发） |
| trigger_time > total_duration | 事件的时间条件永远不满足，永远不会触发 |
| 条件引用不存在的 NPC ID | 条件评估返回 false，事件不触发 |
| 条件引用不存在的 clue_id | ClueDatabase.has_clue() 返回 false，条件不满足 |
| 事件文件不存在（如 night_4_events.tres 缺失） | 加载空事件列表，不报错 |
| 所有条件在第一帧就满足 | CONDITION 事件在加载后的第一帧立即触发（通过信号驱动评估） |
| 同一帧触发超过 MAX_EVENTS_PER_FRAME 个事件 | 只处理前 MAX_EVENTS_PER_FRAME 个（按优先级排序），剩余下一帧处理 |
| force_trigger 已触发的事件 | 忽略——fired_events 已包含该 ID |
| force_trigger 不存在的事件 ID | 忽略——不在 pending_events 中 |
| 存档时已触发 3 个事件，读档后 | 恢复 fired_events（3 个 ID），重新加载事件列表，跳过已触发事件 |
| 对话中事件触发（move_npc） | NPC 仍然移动——事件调度不受 time_scale 影响（动作是即时的） |
| TimerService 未启动时加载事件 | 事件进入 pending，但 TIME/COMPOUND 触发器无法评估（elapsed_time 不可用），等待计时器启动 |
| COMPOUND 条件先于时间满足 | 事件等待时间条件也满足后才触发 |
| 夜晚过渡中事件触发 | night_advanced 已清空 pending_events，不会触发 |

## 6. Dependencies

### 上游依赖
- **倒计时系统 (#5)** — 读取 `remaining_time`、`total_duration`、`current_phase`；监听 `phase_changed` 信号评估 TIME 和 COMPOUND 触发器
- **房间/位置管理 (#3)** — 读取房间状态评估条件；执行 `change_room_state` 动作；监听 `room_state_changed` 信号
- **NPC 状态机 (#6)** — 读取 NPC 位置和情绪状态评估条件；执行 `move_npc` 动作；监听 NPC 状态变更信号
- **循环状态管理 (#1)** — 读取 `current_night`；监听 `night_ready` 和 `night_advanced` 信号管理事件生命周期；读取 custom_flag 条件
- **线索数据库 (#2)** — 查询线索发现状态评估条件；监听 `clue_added` 信号
- **夜晚过渡控制器 (#8)** — 监听 `transition_complete` 信号加载新夜事件

### 下游被依赖
- **NPC 信任/怀疑 (#13)** — 事件可触发信任变化（通过 emit_custom_signal）
- **条件性对话树 (#14)** — 事件可触发对话启动（通过 start_dialogue 动作）
- **音频系统 (#24)** — 事件可触发音效/音乐变化（通过 emit_custom_signal）
- **结局触发逻辑 (#23)** — 特定事件可推进结局条件

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| MAX_EVENTS_PER_FRAME | int | 5 | 1-20 | 每帧最多处理的事件数，防止帧卡顿 |
| CONDITION_RECHECK_INTERVAL | float | 0.0 | 0.0-1.0 | CONDITION 事件信号驱动评估的最小间隔（秒），0 = 每次信号都评估 |
| EVENT_CHECK_ORDER | String | "priority_desc" | priority_desc / time_asc | 同帧多事件的排序方式 |

## 8. Acceptance Criteria

1. 从 NightEvents Resource 正确加载指定夜号的事件列表
2. TIME 触发器在 elapsed_time >= trigger_time 时触发，误差 < 1 帧
3. CONDITION 触发器在所有条件满足时触发（信号驱动，无延迟）
4. COMPOUND 触发器要求 TIME 和 CONDITION 同时满足
5. 每个事件每夜最多触发一次（fired_events 去重）
6. night_advanced 信号清空 fired_events 和 pending_events
7. night_ready / transition_complete 信号触发新夜事件加载
8. 事件文件缺失时加载空列表，不报错
9. 同帧多事件按 priority 降序执行
10. move_npc 动作正确调用 NPCManager 移动接口
11. start_dialogue 动作正确调用 UIManager 对话接口（或 future 对话系统）
12. change_room_state 动作正确调用 RoomManager 状态接口
13. emit_custom_signal 动作正确通过 InteractionBus 分发
14. serialize/deserialize 保留 fired_events 集合和 loaded_night
15. reset() 清空 fired_events、pending_events，loaded_night 重置为 -1
16. force_trigger() 可触发未触发事件，但跳过已触发事件
17. 条件引用不存在的 NPC/clue/room 时返回 false，不崩溃
18. MAX_EVENTS_PER_FRAME 限制生效，超出事件推迟到下一帧

## Open Questions

- start_dialogue 动作的目标系统是否应为 DialogueManager（待设计）而非直接调用 UIManager？
- 是否需要事件间的依赖关系（Event B 仅在 Event A 触发后才评估）？MVP 不包含，但条件系统可部分覆盖。
- 夜晚过渡期间（NightTransitionController 8 步序列中）是否应完全暂停事件评估？
