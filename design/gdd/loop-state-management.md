# 循环状态管理 (Loop State Management)

> **Status**: In Design
> **Author**: Katya + agents
> **Last Updated**: 2026-05-14
> **Implements Pillar**: 支柱 1（每个碎片都是拼图）、支柱 3（连接产生洞察）、支柱 2（数据提供者——倒计时系统从本系统获取夜晚时长和节奏配置）、核心幻想（选择叠加并重塑世界）

## Overview

循环状态管理是七夜一切状态架构的脊柱。它负责三个核心职责：

1. **模板与持久变更分离**：每夜的旅馆有一个"模板状态"（默认房间布局、住客初始位置、门的锁定状态），玩家在每个循环中的行为产生"持久变更"（打开的门、获得的信任、触发的后果）。系统将两者严格分离——重置时模板覆盖临时状态，持久变更叠加在新模板之上。

2. **夜晚推进原子操作**（`advance_night()`）：当一夜结束时，系统在单一原子操作中完成——重置模板状态、保留持久变更、推进循环计数器、触发状态变更通知。夜晚过渡控制器只需调用此方法，无需了解内部机制。

3. **选择后果映射**：系统追踪"玩家行动 → 跨循环持久后果"的关系。每条后果记录包含触发行动、影响的目标系统、持久化的具体变更。这使得叙事系统和游戏系统可以查询"第 2 夜玩家选择 X 导致了什么后果"，而不需要各自维护状态追踪。

**设计原则**：循环状态管理只负责状态的存储、分离和生命周期管理。它不解释状态含义（那是各子系统的事），不决定状态如何呈现（那是表现层的事），不处理状态逻辑（那是各玩法系统的事）。它是状态的中立保管者。

## Player Fantasy

旅馆应该让人觉得它记得你做过什么，即使时钟倒转。当你之前夜里解锁的一扇门再次敞开，当一个住客用不该有的熟悉眼神看你时，玩家感受到选择后果逐夜叠加的重量。这不是一个简单重置的世界——它是一个累积你选择印记的世界，夜复一夜，直到第 7 夜的旅馆与第 1 夜的截然不同。你不是在重复同一个夜晚。你在把自己的历史写进旅馆的墙壁。

**支柱对齐**：支柱 1（每个行动留下痕迹——持久变更是拼图的一部分）、支柱 3（后果链复合积累——连接产生洞察的基础）、支柱 2（数据提供者——为倒计时系统提供节奏配置）、核心幻想（选择叠加并重塑世界）。

**可测试时刻**：玩家在第 3 夜看到一扇第 1 夜解锁的门仍然敞开时，是否感受到之前选择的重量？

## Detailed Design

### Core Rules

**规则 1：状态由三个层组成**

| 层 | 用途 | 生命周期 | 可变性 |
|---|------|---------|--------|
| 模板 (NightTemplate) | 每夜的默认状态 | 随游戏发行，运行时只读 | 设计师在编辑器中创作 |
| 活跃状态 (ActiveState) | 当前夜的实际运行时状态 | 每夜由 `advance_night()` 重建 | 运行时可变，通过 `propose_delta()` |
| 持久增量 (DeltaAccumulator) | 跨夜累积的玩家选择后果 | 贯穿整个游戏会话 | 仅追加，不删除不修改 |

**规则 2：模板 + 增量 → 活跃状态的重建公式**

每夜开始时，活跃状态从模板和增量重建：

1. 深拷贝当夜模板 → 新活跃状态
2. 遍历 DeltaAccumulator 中所有 `source_night < current_night` 的增量
3. 按优先级排序（高优先级胜出；同优先级时后发生的夜胜出）
4. 将每个增量应用到活跃状态的对应属性
5. 活跃状态替代旧状态，旧状态丢弃

**规则 3：所有状态变更通过 `propose_delta()`**

子系统不得直接修改活跃状态。所有变更必须通过单一入口：

`propose_delta(delta: StateDelta) -> bool`

循环状态管理验证 `target_path` 是否在已注册的有效路径中。验证通过后立即应用到活跃状态并存入 DeltaAccumulator。返回 `true`（接受）或 `false`（拒绝）。

**规则 4：子系统注册自己的有效路径**

启动时，每个子系统调用 `register_state_paths(paths: Array[StringName])` 注册自己拥有的属性路径。循环状态管理不硬编码任何路径知识——它只维护一个索引。

**规则 5：后果注册制**

子系统在检测到有意义的玩家选择后果时，调用 `register_consequence(record: ConsequenceRecord)`。循环状态管理不解释后果含义——它只存储和索引。其他子系统通过 `query_consequences(filters)` 查询。

**规则 6：`advance_night()` 原子操作**

7 步操作，失败时回滚：

| 步骤 | 操作 | 失败处理 |
|------|------|---------|
| 1. VALIDATE | 断言当前夜 < 7，无待处理写入，活跃状态存在 | 返回错误，不做任何变更 |
| 2. SNAPSHOT | 深拷贝当前活跃状态作为回滚点 | 保存引用用于回滚 |
| 3. COLLECT | 比较当前活跃状态与模板，提取新增量 | 追加到 DeltaAccumulator |
| 4. LOAD | 加载 `night_N+1` 模板 | 回滚到快照 |
| 5. REBUILD | 从模板 + 全部增量重建活跃状态 | 回滚到快照 |
| 6. INCREMENT | `night_counter += 1` | 回滚到快照 |
| 7. NOTIFY | 发射 `night_advanced` 信号 | 不适用（最后一步） |

第 7 夜结束时：步骤 1 检测到 `night == 7`，发射 `night_ended_final` 信号而非正常推进。结局触发逻辑监听此信号。

**规则 7：PlayerState 最小化**

PlayerState 仅包含 `current_room: StringName`、`current_night: int`、`nights_completed: int`。知识（线索）、信任（NPC）、色彩（进度）各自归属子系统数据库，不存入 PlayerState。

### States and Transitions

**循环状态生命周期**

```
[游戏启动] → 加载存档或创建新状态
       ↓
[夜 N 开始] ← 模板 + 增量 → 活跃状态
       ↓
[夜 N 进行中] ← 玩家行动 → propose_delta() → 活跃状态更新
       ↓                                    → 增量追加
[夜 N 结束] → advance_night()
       ↓
   NIGHT < 7? ──YES──→ [夜 N+1 开始]
       │
       NO
       ↓
   [发射 night_ended_final] → [结局评估]
```

**关键数据结构**

```
StateDelta:
  source_night: int           # 产生此增量的夜编号 (1-7)
  source_action: StringName   # 触发行动 (如 "unlocked_door")
  target_path: StringName     # 属性路径 (如 "rooms.basement.door_locked")
  override_value: Variant     # 覆盖值
  priority: int               # 冲突解决优先级 (默认 0, 叙事权威 10+)
  sequence_index: int         # 自动递增的追加序号，作为同优先级同夜的决胜列

ConsequenceRecord:
  id: StringName              # 唯一标识 (如 "trust_gatekeeper_shown_letter")
  source_action: StringName   # 玩家行动
  source_night: int           # 发生在哪个夜
  target_system: StringName   # 负责解释后果的子系统
  delta_reference: StringName # 关联的 StateDelta ID (可选)
  conditions: Dictionary      # 查询用元数据
```

**Resource 模型**

```
LoopState (Autoload — 协调器)
  ├── night_counter: int (1-7)
  ├── template_state: NightTemplate (Resource, 每夜独立)
  │   ├── rooms: Dictionary[StringName, RoomTemplate]
  │   ├── npcs: Dictionary[StringName, NPCTemplate]
  │   └── meta: Dictionary (计时器时长, 事件调度等)
  ├── active_state: ActiveState (Resource, 每夜重建)
  │   ├── rooms: Dictionary[StringName, RoomState]
  │   ├── npcs: Dictionary[StringName, NPCState]
  │   └── player: PlayerState
  ├── delta_accumulator: DeltaAccumulator (Resource, 跨夜持久)
  │   └── deltas: Array[StateDelta]
  └── consequence_registry: ConsequenceRegistry (Resource, 跨夜持久)
      └── consequences: Array[ConsequenceRecord]
  └── _pending_write: bool  # advance_night() 执行标志，阻止并发写入
```

**信号接口**

```
signal night_advanced(old_night: int, new_night: int)
signal night_ended_final(night: int)
signal night_ready(night: int)  # 初始化完成或存档加载后发射，子系统可安全 propose_delta
signal state_changed(target_path: StringName, old_value: Variant, new_value: Variant, overridden: bool)
signal consequence_registered(record: ConsequenceRecord)
signal advance_failed(step: int, error: String)
```

### Interactions with Other Systems

| 系统 | 数据流方向 | 接口 |
|------|-----------|------|
| 倒计时系统 | 循环状态 → 倒计时 | `get_current_night()` 获取当前夜，决定当夜时长 |
| NPC 状态机 | 循环状态 ↔ NPC 状态 | NPC 注册路径，通过 `propose_delta()` 修改 NPC 状态 |
| 夜晚过渡控制器 | 过渡控制器 → 循环状态 | 调用 `advance_night()`，接收 `night_advanced` 信号 |
| 事件调度器 | 循环状态 → 事件调度 | 查询后果注册表决定哪些事件触发 |
| 色彩积累 | 循环状态 → 色彩 | 查询 DeltaAccumulator 数量或后果数决定色彩级别 |
| 存档/读档持久化 | 持久化 → 循环状态 | 加载时反序列化 LoopState，保存时序列化 LoopState |
| 线索数据库 | 无直接交互 | 线索数据库是独立系统，不通过循环状态管理 |

## Formulas

### delta_resolution — 增量冲突解决

当多个增量目标同一 `target_path` 时，确定哪个胜出。

`winner = argmax(d, d in deltas | sort_key(d))`
`sort_key(d) = (d.priority * PRIORITY_WEIGHT) + d.source_night`

**变量表：**

| 变量 | 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|------|
| 增量集 | `deltas` | Array[StateDelta] | 1..N | 目标同一属性的所有增量 |
| 优先级 | `d.priority` | int | 0..100 | 默认=0，叙事权威=10+，引擎保留=50+ |
| 来源夜 | `d.source_night` | int | 1..7 | 产生此增量的夜 |
| 优先级权重 | `PRIORITY_WEIGHT` | int | 8（常量）| 确保优先级层始终压过夜编号。必须 > 7 |
| 排序键 | `sort_key` | int | 1..807 | 比较用标量 |

**输出范围**：返回输入集中唯一一个 StateDelta。输入为空时使用模板值。

**示例**：三个增量目标 `rooms.basement.door_locked`：

| 增量 | priority | source_night | sort_key |
|------|----------|-------------|----------|
| A（玩家解锁） | 0 | 2 | 2 |
| B（玩家再锁） | 0 | 5 | 5 |
| C（叙事强制开） | 10 | 3 | 83 |

胜出：C（sort_key 83）。无 C 时 B 胜出（同优先级后夜胜）。

### night_duration — 每夜时长

> **计时器时长由 TimerService 拥有**（见 `design/gdd/countdown-timer.md` 和 ADR-0008）。循环状态管理不定义计时器时长——它仅提供当夜编号供 TimerService 查询。以下公式保留作为概念参考，实际值以 TimerService 为准。

`night_duration(night) = BASE_DURATION + rhythm_offset(night)`

MVP：`rhythm_offset(night) = 0`（恒定时长）。
未来节奏支持：`rhythm_offset(night) = RHYTHM_TABLE[night]`（只需填充数组，无代码变更）。

**变量表：**

| 变量 | 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|------|
| 夜编号 | `night` | int | 1..7 | 当前夜 |
| 基础时长 | `BASE_DURATION` | float | — | 由 TimerService 定义（见 countdown-timer.md） |
| 节奏偏移 | `rhythm_offset` | float | 0.0 (MVP) | 每夜时长增减 |
| 最短时长 | `MIN_NIGHT_DURATION` | float | — | 由 TimerService 定义（见 countdown-timer.md） |
| 夜时长 | `night_duration` | float | ≥ MIN | 实现时 clamp: max(MIN, result) |

**输出范围**：正浮点数，不低于 MIN_NIGHT_DURATION（TimerService 定义）。

### consequence_count — 后果计数查询

`consequence_count(filters) = |{ r in registry : matches(r, filters) }|`

`matches(r, filters)` 当 filters 中每个键值对等于 r 对应字段时返回 true。空过滤器匹配全部记录。

**变量表：**

| 变量 | 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|------|
| 过滤器 | `filters` | Dictionary | 0..K 键 | 查询参数（target_system, source_night 等） |
| 匹配数 | `consequence_count` | int | 0..N | 满足条件的记录数 |

**输出范围**：非负整数。注册表为空时返回 0。

**示例**：注册表有 5 条后果，查询 `{"target_system": "npc_trust"}` 返回 4（其中 4 条是 NPC 信任相关）。

## Edge Cases

### 边界条件

- **If `advance_night()` 在第 7 夜调用**: 发射 `night_ended_final(7)` 信号（仅首次），不修改任何状态。重复调用返回 `advance_failed(1, "night_7_final_already")`。
- **If DeltaAccumulator 为空**: 正常推进。REBUILD 应用零增量，产生纯模板状态。
- **If 两个增量同优先级同夜**: 追加顺序靠后的胜出。`sequence_index`（自动递增）作为第三决胜列。
- **If `source_night` 超出 1-7 范围**: `propose_delta()` 拒绝。`source_night` 必须等于当前 `night_counter`。
- **If `advance_night()` 在 night_counter 为 0 时调用**: VALIDATE 失败（active_state 为 null），返回错误。

### 并发访问

- **If 同一帧内两个子系统 `propose_delta()` 同一属性**: 两者都接受并存入。活跃状态反映最后一次写入。下次 REBUILD 用 sort_key + sequence_index 决胜。帧内两次写入之间无渲染，玩家不可见。
- **If `propose_delta()` 在 `advance_night()` 执行中调用**: `pending_write` 标志（内嵌于 LoopState）阻止写入，返回 `false`。增量必须在 `advance_night()` 完成后提交。

### 过期数据

- **If 增量引用未注册的 `target_path`**: `propose_delta()` 拒绝。路径必须在启动时注册。
- **If 增量引用其他子系统注册的路径**: 接受。路径注册是启动排序声明，非运行时权限检查。优先级系统解决跨子系统冲突。
- **If 增量目标属性在模板中不存在**: 创建该属性（"增量添加"模式）。玩家可以发现模板中不存在的新状态。
- **If 模板移除了前夜存在的属性但增量目标它**: 同上——增量重新引入该属性。模板是基线，不是上限。

### 存档损坏

- **If 崩溃在 REBUILD 中途（步骤 4-6）**: `night_counter` 未递增，是提交标记。下次加载重新从保存点尝试推进。自动存档必须在步骤 6 完成后触发。
- **If 存档包含 `source_night > night_counter` 的增量**: 加载成功。REBUILD 过滤掉这些孤儿增量（规则 2 步骤 2）。记录警告。
- **If 存档缺少 DeltaAccumulator**: 初始化为空。从模板开始，无持久变更。可恢复但可能不正确——记录警告。
- **If 存档包含重复增量**: 两者都应用。由于值相同，结果正确。不需要去重。

### 模板-增量冲突

- **If 叙事覆盖（priority 10+）vs 后夜玩家行动（priority 0）**: 叙事胜出。`sort_key` 差距确保优先级层压过夜编号。玩家需收到反馈（表现层职责，非本系统）。
- **If 两叙事覆盖同属性（同 priority 10+）**: 后夜叙事胜出。叙事权威内部冲突由夜编号解决。
- **If 玩家在同夜内覆盖叙事状态**: 当前夜活跃状态反映玩家操作（last-write-wins）。下次 REBUILD 叙事重新胜出。设计明确：夜间状态为"最后写入胜"，跨夜重建重新评估。这是特性——"叙事在一夜之间覆盖你的选择"创造游戏张力。

### 异常序列

- **If `advance_night()` 双重调用**: `pending_write` 标志阻止第二次。返回 `advance_failed(1, "advance_in_progress")`。
- **If `propose_delta()` 在游戏初始化前调用**: active_state 为 null，返回 `false`。子系统应等待 `night_ready` 信号。
- **If `night_counter` 为非法值（负数、> 7）**: VALIDATE 失败，发射 `advance_failed`。不自动修正——失败可见以便开发者察觉。
- **If `register_state_paths()` 在游戏中途调用**: 新路径对后续 `propose_delta()` 生效。之前被拒绝的增量不会回溯应用。记录警告。
- **If `register_consequence()` 使用重复 ID**: 拒绝。不覆盖。后果 ID 是唯一标识，重复表明调用子系统逻辑错误。
- **If `query_consequences()` 使用未知过滤键**: 返回 0 结果。不报错。过滤器是开放式字典，系统不预设所有可能字段。
- **If DeltaAccumulator 增长到数百条**: 无需处理。7 夜 x ~50 路径 = 理论最大 ~350 条。REBUILD 遍历全部，性能可忽略。不需要压缩或分页。

## Dependencies

### 上游依赖（本系统依赖的）

无。循环状态管理是 Foundation 层系统，零依赖。

### 下游依赖（依赖本系统的）

| 系统 | 依赖类型 | 接口 | 状态 |
|------|---------|------|------|
| 倒计时系统 (#5) | 硬依赖 | `get_current_night()` → 夜编号 | 未设计 |
| NPC 状态机 (#6) | 硬依赖 | 注册路径 + `propose_delta()` + `night_advanced` 信号 | 未设计 |
| 夜晚过渡控制器 (#8) | 硬依赖 | 调用 `advance_night()` | 未设计 |
| 事件调度器 (#9) | 硬依赖 | `query_consequences()` + `state_changed` 信号 | 未设计 |
| 色彩积累 (#16) | 硬依赖 | `consequence_count()` 或 DeltaAccumulator 查询 | 未设计 |
| 存档/读档持久化 (#4) | 硬依赖 | 序列化/反序列化 LoopState Resource | 未设计 |
| 线索数据库 (#2) | 无直接依赖 | 线索数据库是独立系统 | 未设计 |

> **注意**：所有下游系统均为未设计状态。本 GDD 定义的接口是契约——下游 GDD 必须遵守这些接口，如需变更则需回到本 GDD 修改。

## Tuning Knobs

| 旋钮 | 默认值 | 安全范围 | 效果 |
|------|--------|---------|------|
| `BASE_DURATION` | — | — | **已迁移至 TimerService**（见 countdown-timer.md 和 ADR-0008）。循环状态管理不再定义此值 |
| `MIN_NIGHT_DURATION` | — | — | **已迁移至 TimerService**（见 countdown-timer.md 和 ADR-0008）。循环状态管理不再定义此值 |
| `PRIORITY_WEIGHT` | 8 | 8–100 | 增量冲突解决中的优先级乘数。必须 > max_night (7) |
| `DEFAULT_DELTA_PRIORITY` | 0 | 0–9 | 玩家行动产生的增量的默认优先级 |
| `NARRATIVE_DELTA_PRIORITY` | 10 | 10–49 | 叙事覆盖使用的优先级 |
| `ENGINE_DELTA_PRIORITY` | 50 | 50–100 | 引擎级状态覆盖的保留优先级 |
| `MAX_NIGHTS` | 7 | 3–10 | 游戏总夜数。影响循环计数器和模板加载数量 |
| `RHYTHM_TABLE` | — | — | **已迁移至 TimerService**（见 countdown-timer.md 和 ADR-0008）。循环状态管理不再定义此值 |
| `NIGHT_RHYTHM_CONFIG` | — | — | **已迁移至 TimerService**（见 countdown-timer.md 和 ADR-0008）。循环状态管理不再定义此值 |

> **计时器旋钮迁移说明**：`BASE_DURATION`、`MIN_NIGHT_DURATION`、`RHYTHM_TABLE`、`NIGHT_RHYTHM_CONFIG` 已迁移至 TimerService（见 `design/gdd/countdown-timer.md` 和 ADR-0008）。循环状态管理不再负责计时器配置——它只提供 `current_night` 供 TimerService 查询当夜编号。

## Acceptance Criteria

### 规则验证（18 条）

**规则 1：三层状态**

- AC-R1-01: Given 系统初始化完成, When 夜 N 开始, Then 活跃状态由当夜模板深拷贝生成
- AC-R1-02: Given 模板状态已加载, When 运行时代码尝试直接修改模板, Then 修改被拒绝（模板运行时只读）
- AC-R1-03: Given DeltaAccumulator 为空, When REBUILD 执行, Then 活跃状态等于纯模板（零增量叠加）

**规则 2：重建公式**

- AC-R2-01: Given 3 个增量目标同一属性（priority 分别为 0/0/10, night 分别为 2/5/3）, When REBUILD 执行, Then priority=10 的增量胜出（sort_key=83）
- AC-R2-02: Given 两个增量同优先级同夜, When REBUILD 执行, Then sequence_index 更高的胜出
- AC-R2-03: Given 无增量目标某属性, When REBUILD 执行, Then 使用模板值

**规则 3：propose_delta()**

- AC-R3-01: Given 已注册路径 "rooms.basement.door_locked", When propose_delta() 目标此路径, Then 返回 true 且活跃状态立即更新
- AC-R3-02: Given 未注册路径, When propose_delta() 目标此路径, Then 返回 false 且无状态变更
- AC-R3-03: Given source_night ≠ 当前 night_counter, When propose_delta() 提交, Then 返回 false

**规则 4：路径注册**

- AC-R4-01: Given 子系统在启动时注册路径, When 后续 propose_delta() 目标这些路径, Then 增量被接受
- AC-R4-02: Given 子系统在游戏中途注册新路径, When 后续 propose_delta() 目标新路径, Then 增量被接受（之前被拒绝的不回溯应用）

**规则 5：后果注册**

- AC-R5-01: Given 唯一 ID 的后果记录, When register_consequence() 调用, Then 记录被存储且 consequence_registered 信号发射
- AC-R5-02: Given 重复 ID 的后果记录, When register_consequence() 调用, Then 拒绝注册（不覆盖）
- AC-R5-03: Given 注册表有 5 条后果（4 条 target_system="npc_trust"）, When query_consequences({"target_system": "npc_trust"}) 查询, Then 返回 4 条匹配记录

**规则 6：advance_night()**

- AC-R6-01: Given night_counter = 3, When advance_night() 成功完成 7 步, Then night_counter = 4 且 night_advanced(3, 4) 信号发射
- AC-R6-02: Given night_counter = 7, When advance_night() 调用, Then night_ended_final(7) 信号发射，night_counter 不变
- AC-R6-03: Given advance_night() 正在执行中, When propose_delta() 调用, Then 返回 false（_pending_write 阻止）
- AC-R6-04: Given advance_night() 正在执行, When 第二次 advance_night() 调用, Then 返回 advance_failed(1, "advance_in_progress")

**规则 7：PlayerState 最小化**

- AC-R7-01: Given PlayerState 被检查, When 查看其字段, Then 仅包含 current_room, current_night, nights_completed

### 公式验证（9 条）

**delta_resolution**

- AC-F1-01: Given 增量 A (p=0, n=2, key=2), B (p=0, n=5, key=5), C (p=10, n=3, key=83), When 冲突解决, Then C 胜出
- AC-F1-02: Given 仅 A (key=2) 和 B (key=5), When 冲突解决, Then B 胜出（同优先级后夜胜）
- AC-F1-03: Given 无增量, When delta_resolution 查询, Then 返回模板值

**night_duration**

- AC-F2-01: Given BASE_DURATION 由 TimerService 提供（见 countdown-timer.md）, RHYTHM_TABLE=[], When night_duration(1) 计算, Then 返回 TimerService 配置的基础时长
- AC-F2-02: Given TimerService 配置的 BASE_DURATION 和 RHYTHM_TABLE=[-120], When 计算, Then 返回 max(MIN_NIGHT_DURATION, 结果)（clamp 生效，MIN 由 TimerService 定义）
- AC-F2-03: Given MIN_NIGHT_DURATION 由 TimerService 定义, BASE_DURATION 低于 MIN, When 计算, Then 返回 MIN_NIGHT_DURATION（不低于安全下限）

**consequence_count**

- AC-F3-01: Given 空注册表, When consequence_count({}) 查询, Then 返回 0
- AC-F3-02: Given 注册表有 5 条后果（4 条 target_system="npc_trust"）, When 过滤查询, Then 返回 4
- AC-F3-03: Given 未知过滤键, When consequence_count({"unknown_key": "value"}) 查询, Then 返回 0（不报错）

### 信号发射（4 条）

- AC-S1: Given 夜 N 成功推进, When advance_night() 完成步骤 7, Then night_advanced(old, new) 信号发射
- AC-S2: Given 夜 7 结束, When advance_night() 检测 night==7, Then night_ended_final(7) 信号发射（仅首次）
- AC-S3: Given 初始化或存档加载完成, When 活跃状态准备就绪, Then night_ready(night) 信号发射
- AC-S4: Given propose_delta() 接受增量且值实际改变, When 应用成功, Then state_changed(path, old, new, overridden) 信号发射，overridden=true 当且仅当本次写入覆盖了叙事权威增量

### 存档/读档完整性（4 条）

- AC-P1: Given 游戏在第 3 夜存档, When 存档加载, Then night_counter=3, delta_accumulator 完整, active_state 正确重建
- AC-P2: Given 存档包含 source_night > night_counter 的孤儿增量, When 加载, Then 增量保留但 REBUILD 过滤掉（记录警告）
- AC-P3: Given 存档缺少 DeltaAccumulator, When 加载, Then 初始化为空，从模板开始（记录警告）
- AC-P4: Given 崩溃发生在步骤 4-6 之间, When 下次加载, Then night_counter 未递增，从保存点重新推进

### 边界条件（7 条）

- AC-E1: Given night_ended_final 已发射, When 再次 advance_night() 调用, Then 返回 advance_failed(1, "night_7_final_already")
- AC-E2: Given active_state 为 null（初始化前）, When propose_delta() 调用, Then 返回 false
- AC-E3: Given 增量目标属性在模板中不存在, When propose_delta() 接受, Then 活跃状态中创建该属性（增量添加模式）
- AC-E4: Given 模板移除了前夜存在的属性, When 增量目标该属性, Then 增量重新引入该属性
- AC-E5: Given 同帧内两个子系统 propose_delta() 同一属性, When 两者都执行, Then 活跃状态反映最后一次写入，两个增量都存入 DeltaAccumulator
- AC-E6: Given 存档包含重复增量, When 加载并 REBUILD, Then 两者都应用（结果正确，不需去重）
- AC-E7: Given night_counter 为非法值（负数或 >7）, When advance_night() 调用, Then VALIDATE 失败并发射 advance_failed

## Open Questions

1. **多存档槽位**：多存档是否各自拥有独立的 DeltaAccumulator，还是共享？当前设计假设独立——需在存档/读档 GDD (#4) 中确认。
2. **调试检查器**：是否需要运行时增量检查器（显示当前夜的所有增量、冲突解决结果）用于开发调试？MVP 不需要，但后期品质阶段可能有价值。
3. **模板热重载**：开发期间修改 NightTemplate Resource 后是否需要运行时热重载？当前设计未包含——开发流程需重启场景测试新模板。
4. **增量压缩**：当前设计假设 7 夜 × ~50 路径 ≈ 350 条上限。若游戏扩展到 >7 夜或 >50 路径，DeltaAccumulator 是否需要压缩或分页？MVP 不需要。
5. **跨子系统路径冲突可视化**：当两个子系统 propose_delta() 同一属性时，调试时如何快速定位冲突来源？sequence_index 记录了来源但缺少子系统标识字段——是否需要在 StateDelta 中添加 `source_system: StringName`？
