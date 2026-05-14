# 线索数据库 (Clue Database)

> **Status**: GDD Complete
> **Author**: Katya + agents
> **Last Updated**: 2026-05-14
> **CD-GDD-ALIGN**: CONCERNS (resolved) — 多住客 npc_affinity 边缘案例已添加、洞察 affinity 临时规则已添加；InsightDefinitionTable 设计张力已记录为有意权衡，推迟至推理系统 GDD (#11)
> **Implements Pillar**: 支柱 1（每个碎片都是拼图——线索是碎片的数据基础）、支柱 3（连接产生洞察——Connection 结构是连接的载体）、核心幻想（跨循环积累的知识）

## Overview

线索数据库是七夜一切知识管理的存储和查询基础设施。它维护两类数据——KnowledgeEntry（统一覆盖线索和洞察）和 Connection（玩家建立的线索连接）——提供 CRUD、搜索、连接操作和 contextual_unlocks 级联机制。它不解释线索含义（那是推理系统的事）、不决定如何呈现（那是笔记本 UI 的事）、不处理发现触发（那是交互系统的事）。它是知识的中立保管者。

数据结构、接口签名和架构决策由 ADR-0005（Clue/Insight Unified Schema）定义。本 GDD 在 ADR-0005 基础上补充操作规则、数据公式、边界条件和验收标准——不重复 ADR 已定义的 schema 细节，而是引用它。

**设计原则**：线索数据库只负责知识的存储、索引和连接关系维护。它不知道什么是"真相"（那是洞察生成系统的职责），不知道哪些连接有效（那是线索连接/推理系统的职责），不知道知识意味着什么颜色（那是色彩积累系统的职责）。

## Player Fantasy

笔记本不是一个容器——它是一面慢慢变清晰的镜子。你发现一条线索时，它只是一个碎片。但在第 4 夜，当你将两个碎片连在一起、洞察如涟漪般扩散时，旧的碎片突然有了新的含义。之前读过的一条描述，现在读起来完全不同了。仿佛每次重读同一页笔记本，都像一个更聪明的人在阅读。不是游戏在替你解读——是你的知识改变了你看到的内容。数据库不可见，但它的存在让玩家在翻开旧页时感到一阵认知电流：你以为你知道的东西，现在你知道得更多了。

**支柱对齐**：支柱 3（连接产生洞察——contextual_unlocks 是核心交付机制）、支柱 1（每个碎片都是拼图——没有任何碎片因为循环重置而浪费）、核心幻想（跨循环积累的知识）。

**可测试时刻**：玩家在第 4 夜打开笔记本，看到第 1 夜的一条线索现在显示了第二段解读文字（来自 insight 的 reinterpretation），意识到自己第一次什么都没看懂。

## Detailed Design

### Core Rules

**规则 1：条目生命周期（CRUD）**

**规则 1.1**：ID 不可变、全局唯一、域前缀化。模式 `clue_<key>` 或 `insight_<key>`，非空，不可重复。

**规则 1.2**：`add_entry(entry: Dictionary) -> bool` — 9 步原子操作：

| 步骤 | 操作 | 失败 |
|------|------|------|
| 1. VALIDATE | 断言含 "id" 且非空 | 返回 false |
| 2. UNIQUE | 断言无同 id 条目 | 返回 false |
| 3. REQUIRED | 断言含 entry_type, title, description, source, discovered_at_night | 返回 false |
| 4. TYPE CHECK | 若 INSIGHT：断言 source_clues 含恰好 2 个元素 | 返回 false |
| 5. DEFAULTS | 填充缺失可选字段（tags=[], contextual_unlocks=[], npc_affinity=&"", metadata={}） | — |
| 6. STORE | 插入 entries 字典 | — |
| 7. CASCADE | 若 INSIGHT：执行 contextual_unlocks 级联（规则 3） | 回滚 STORE，返回 false |
| 8. SIGNAL | CLUE 发射 clue_discovered，INSIGHT 发射 insight_generated | — |
| 9. RETURN | 返回 true | — |

**规则 1.3**：`get_entry(id: StringName) -> Dictionary` — 返回条目或空字典 `{}`。永不返回 null。

**规则 1.4**：`update_entry(id: StringName, updates: Dictionary) -> bool` — 合并更新到已有条目。拒绝修改 id 或 entry_type。拒绝在 CLUE 条目上设置 source_clues。

**规则 1.5**：`remove_entry(id: StringName) -> bool` — 删除条目并级联清理：若为 INSIGHT，从两条源线索的 contextual_unlocks 中移除自身；删除所有引用该条目的 Connection 记录。

**规则 2：连接生命周期**

**规则 2.1**：连接双向且去重。内部存储时 clue_a 为字典序较小者，clue_b 为较大者。

**规则 2.2**：`connect_clues(clue_a: StringName, clue_b: StringName) -> Dictionary`

返回值（解决 TD-ADR Concern #3）：
```
{ ok: bool, connection: Dictionary, reason: String }
```
reason 枚举：""（成功）, "same_clue", "clue_not_found", "invalid_types", "duplicate"

10 步操作：自检 → 存在性 → 类型检查 → 归一化 → 去重 → 创建 → 验证（委托 InsightGenerator） → 存储 → 信号 → 返回。无效连接仍存储（is_valid=false），供笔记本历史记录。

**规则 2.3**：InsightGenerator 归属（解决 TD-ADR Concern #2）

ClueDatabase 不验证连接有效性。它委托给 InsightGenerator（RefCounted 工具类，非 Autoload）：
1. 接收 (clue_a, clue_b)
2. 在预定义的 InsightDefinitionTable（JSON 配置文件，启动时加载）中查找配对
3. 若找到：构造 INSIGHT 条目 → 调用 ClueDatabase.add_entry()（触发 contextual_unlocks 级联）→ 更新 Connection 的 is_valid=true
4. 若未找到：Connection 保持 is_valid=false

**所有权边界**：ClueDatabase 拥有存储和级联机制。InsightGenerator 拥有验证查找和洞察构造。

**规则 3：contextual_unlocks 级联（解决 TD-ADR Concern #4）**

**规则 3.1**：级联在 add_entry() 步骤 7 中自动触发（仅 INSIGHT 类型）：
- 7a. 解析两条 source_clues → 若任一不存在，整个 add_entry 失败（原子性）
- 7b. 将 insight.id 追加到 source_clues[0] 的 contextual_unlocks
- 7c. 将 insight.id 追加到 source_clues[1] 的 contextual_unlocks
- 7d. 去重：若已存在则跳过（幂等）

**规则 3.2**：remove_entry() 删除 INSIGHT 时清理：从两条源线索的 contextual_unlocks 中移除 insight.id。若源线索已被删除，静默跳过。

**规则 3.3**：`get_contextual_unlocks(clue_id) -> Array[StringName]` — 返回条目的 contextual_unlocks 数组。

**规则 3.4**：`has_insight_for(clue_id) -> bool` — 便捷方法，contextual_unlocks 非空则 true。

**规则 4：序列化（解决 TD-ADR Concern #1）**

**规则 4.1**：Schema 版本格式：
```json
{ "schema_version": int, "entries": {...}, "connections": [...] }
```
当前版本：1。版本号单调递增。

**规则 4.2**：`serialize() -> Dictionary` — 深拷贝当前状态为快照。

**规则 4.3**：`deserialize(data: Dictionary) -> bool` — 7 步操作：

| 步骤 | 操作 | 失败 |
|------|------|------|
| 1. VERSION | 断言 schema_version 存在且为已知版本 | 返回 false |
| 2. MIGRATE | 若版本较旧，运行迁移链（当前无迁移） | — |
| 3. VALIDATE | 断言 entries 为 Dictionary, connections 为 Array | 返回 false |
| 4. CLEAR | 清空内部 entries 和 connections | — |
| 5. RESTORE ENTRIES | 逐条验证并插入。跳过无效条目，记录警告 | — |
| 6. RESTORE CONNECTIONS | 逐条验证并追加。跳过无效连接，记录警告 | — |
| 7. REBUILD CASCADES | 对每个 INSIGHT 重新执行规则 3.1，重建 contextual_unlocks | 跳过源线索缺失的洞察 |

步骤 7 关键：contextual_unlocks 从 source_clues 重建，存档中的值被覆盖。保证一致性。

**规则 4.4**：往返保证——对任意有效状态 S，deserialize(serialize(S)) 产生等价状态。100 条目 + 50 连接范围内保证。

**规则 5：搜索与查询**

- `search_by_tag(tag) -> Array[StringName]` — O(n) 线性扫描
- `search_by_source(source) -> Array[StringName]` — O(n)
- `search_by_npc(npc_affinity) -> Array[StringName]` — O(n)
- `get_all_clues()` / `get_all_insights()` — 类型过滤
- `get_undiscovered_clues()` — 永远返回空数组（发现追踪属于线索发现系统 #10）
- `get_valid_connections()` / `get_invalid_connections()` — 过滤连接

所有搜索函数返回空数组（永不返回 null）。

**规则 6：数据完整性**

- **6.1**：无重复 ID — add_entry() 拒绝，update_entry() 不可改 id
- **6.2**：无重复连接 — connect_clues() 归一化后去重
- **6.3**：孤儿容忍——删除条目时清理引用，但外部缓存的引用不通知。反序列化时孤儿洞察保留但级联重建跳过
- **6.4**：entry_type 不可变——CLUE 不能变成 INSIGHT
- **6.5**：重入保护——`_adding: bool` 标志防止信号处理器中递归调用 add_entry()

**ClueDatabase 不做的事（边界清晰度）**：

| 不属于 ClueDatabase | 归属于 |
|---------------------|--------|
| 决定哪些连接有效 | InsightGenerator（查找表） |
| 构造洞察内容 | InsightGenerator（预定义数据） |
| 追踪哪些线索已被发现 | 线索发现系统 (#10) |
| 渲染笔记本 | 笔记本 UI (#21) |
| 触发线索发现 | 交互系统 (#7) + 线索发现 (#10) |
| 计算知识色彩 | KnowledgeManager (ADR-0002) |

### States and Transitions

ClueDatabase 是无状态的数据存储——没有内部状态机。系统生命周期遵循启动→运行→关闭模式：

```
[游戏启动] → 加载 InsightDefinitionTable (JSON) + deserialize (存档)
       ↓
[运行中] ← add_entry / connect_clues / search → 纯数据操作
       ↓
[存档] → serialize → 写入持久层
       ↓
[游戏关闭]
```

**数据结构状态**：

```
ClueDatabase (Autoload)
  ├── entries: Dictionary[StringName, KnowledgeEntry]
  │   └── 每个 KnowledgeEntry 包含：id, entry_type, title, description,
  │       source, discovered_at_night, npc_affinity, tags,
  │       contextual_unlocks, metadata
  │       (INSIGHT 额外: source_clues, reinterpretation)
  ├── connections: Array[Connection]
  │   └── 每个 Connection 包含：clue_a, clue_b, made_at_night,
  │       is_valid, insight_id
  ├── _insight_table: InsightDefinitionTable (启动时加载，运行时只读)
  ├── _insight_gen: InsightGenerator (RefCounted 工具类)
  └── _adding: bool = false (重入保护标志)
```

**信号接口**：

```
signal clue_discovered(clue_id: StringName)
signal insight_generated(insight_id: StringName)
signal connection_made(clue_a: StringName, clue_b: StringName, is_valid: bool)
```

### Interactions with Other Systems

| 系统 | 数据流方向 | 接口 |
|------|-----------|------|
| 线索发现 (#10) | 线索发现 → ClueDatabase | 调用 add_entry() 存储新发现的 CLUE 条目 |
| 线索连接/推理 (#11) | 推理系统 → ClueDatabase | 调用 connect_clues() 建立连接，接收 connection_made 信号 |
| 洞察生成 (#12) | InsightGenerator ↔ ClueDatabase | ClueDatabase 委托验证给 InsightGenerator；InsightGenerator 回调 add_entry() 存储洞察 |
| 色彩积累 (#16) | ClueDatabase → KnowledgeManager | KnowledgeManager 调用 get_all_insights().size()、search_by_npc() 等计算色彩（ADR-0002） |
| 笔记本系统 (#17) | ClueDatabase → 笔记本 | 笔记本调用搜索和查询接口渲染内容，调用 get_contextual_unlocks() 显示再解读 |
| 结局触发 (#23) | ClueDatabase → 结局逻辑 | 结局系统查询特定洞察或连接数量判断触发条件 |
| 存档/读档 (#4) | 持久化 ↔ ClueDatabase | 调用 serialize()/deserialize() 保存和恢复数据 |
| 循环状态管理 (#1) | 无直接交互 | 线索数据库是 Player Knowledge 层，跨循环不重置 |
| 条件性对话 (#14) | ClueDatabase → 对话 | 对话系统查询特定条目是否存在或洞察是否已生成，决定对话分支 |

## Formulas

ClueDatabase 是数据存储系统，无 gameplay 计算公式。以下为数据容量和性能相关的度量公式。

### entry_capacity — 条目容量估算

`entry_capacity = MAX_CLUES + MAX_INSIGHTS`

**变量表：**

| 变量 | 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|------|
| 最大线索数 | MAX_CLUES | int | 30–100 | 游戏中所有可发现线索的总数 |
| 最大洞察数 | MAX_INSIGHTS | int | 10–30 | 有效连接产生的洞察总数 |
| 条目容量 | entry_capacity | int | 40–130 | 总条目上限 |

**输出范围**：正整数。MVP 预期 50 条线索 + 20 洞察 = 70 条目。

**示例**：完整游戏（100 线索 + 30 洞察）= 130 条目。Dictionary 查找 O(1)，线性搜索 O(130)，可忽略。

### connection_capacity — 连接容量估算

`connection_capacity = MAX_ENTRIES * (MAX_ENTRIES - 1) / 2`

**变量表：**

| 变量 | 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|------|
| 参与连接的条目数 | MAX_ENTRIES | int | 30–100 | 仅为 CLUE 类型条目（INSIGHT 不参与连接） |
| 连接容量 | connection_capacity | int | 435–4950 | 理论最大连接数 |

**输出范围**：实际有效连接远少于理论值。MVP 预期 ≤30 条连接（包括有效和无效）。

**示例**：50 条可连接线索的理论最大连接数 = 50 × 49 / 2 = 1,225。实际玩家尝试的连接远少于此——约 30-50 次。

### memory_footprint — 内存占用估算

`memory_footprint = (entry_count * ENTRY_BYTES) + (connection_count * CONNECTION_BYTES)`

**变量表：**

| 变量 | 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|------|
| 条目数 | entry_count | int | 0–130 | 当前存储的条目总数 |
| 条目字节数 | ENTRY_BYTES | int | ~500 | 平均每个 KnowledgeEntry 的内存占用（字符串+数组+字典） |
| 连接数 | connection_count | int | 0–50 | 当前存储的连接总数 |
| 连接字节数 | CONNECTION_BYTES | int | ~100 | 每个 Connection 的内存占用 |
| 内存占用 | memory_footprint | int | ≤50KB | 完整游戏会话的数据内存 |

**输出范围**：0 到 ~65KB。MVP 典型值：38KB。

**示例**：50 线索 + 20 洞察 + 30 连接 = (70 × 500) + (30 × 100) = 38,000 bytes ≈ 37KB。远低于 512MB 移动端预算。

## Edge Cases

### 条目操作边界

- **如果 `add_entry()` 接收空 id（`&""`）**：步骤 1 VALIDATE 拒绝，返回 false。
- **如果 `add_entry()` 接收已存在的 id**：步骤 2 UNIQUE 拒绝，返回 false。不覆盖。
- **如果 INSIGHT 条目的 source_clues 包含 0 或 1 个元素**：步骤 4 TYPE CHECK 拒绝，返回 false。
- **如果 INSIGHT 条目的 source_clues 包含 3+ 个元素**：步骤 4 TYPE CHECK 拒绝，返回 false。洞察恰好来自 2 条线索。
- **如果 INSIGHT 条目的 source_clues 引用不存在的 id**：步骤 7 CASCADE 失败，回滚 STORE，返回 false。洞察不存储。
- **如果 `update_entry()` 尝试修改 entry_type**：步骤 2 IMMUTABLE 拒绝，返回 false。
- **如果 `remove_entry()` 删除的条目被其他 INSIGHT 引用为 source_clue**：步骤 2 清理该 INSIGHT 的 contextual_unlocks 引用。INSIGHT 本身保留（孤儿洞察）——规则 6.3 孤儿容忍。

### 连接操作边界

- **如果 `connect_clues()` 连接同一 id**：步骤 1 SELF-CHECK 拒绝，返回 `{"ok": false, "reason": "same_clue"}`。
- **如果 `connect_clues()` 中任一 id 不存在**：步骤 2 EXIST 拒绝，返回 `{"ok": false, "reason": "clue_not_found"}`。
- **如果 `connect_clues()` 连接两个 INSIGHT**：步骤 3 TYPE CHECK 拒绝，返回 `{"ok": false, "reason": "invalid_types"}`。只有 CLUE 可以被连接。
- **如果重复连接已连接的线索对**：步骤 5 DUPLICATE 拒绝，返回 `{"ok": false, "connection": existing, "reason": "duplicate"}`。返回已有连接记录供调用者参考。
- **如果 InsightDefinitionTable 中不存在该配对**：连接存储为 is_valid=false，无洞察生成。玩家可以看到自己尝试过但失败的连接。

### contextual_unlocks 边界

- **如果同一条洞察被 add_entry() 重复调用（幂等测试）**：步骤 2 UNIQUE 拒绝第二次调用。级联不重复执行。
- **如果删除源线索后再删除引用它的洞察**：洞察的 source_clues 中的已删除线索被跳过，仅清理仍存在的线索的 contextual_unlocks。

### 序列化边界

- **如果存档 schema_version 为未知值（如 99）**：步骤 1 VERSION 拒绝，返回 false。不尝试解释未来版本。
- **如果存档缺少 connections 字段**：步骤 3 VALIDATE 拒绝（Array 类型检查失败），返回 false。
- **如果存档包含 id 重复的条目**：步骤 5 RESTORE ENTRIES 中先遇到的条目保留，后续重复条目跳过并记录警告。
- **如果存档包含 source_clues 引用不存在的洞察**：步骤 7 REBUILD CASCADES 跳过该洞察的级联重建，洞察本身保留。contextual_unlocks 在加载后不包含该洞察——与正常流程一致。
- **如果 deserialize() 在步骤 5-7 中途崩溃**：部分数据已加载。entries 和 connections 可能不一致——但 contextual_unlocks 由步骤 7 重建，保证最终一致。

### 搜索边界

- **如果搜索空 tag（`&""`）**：返回空数组。不报错。
- **如果搜索不存在的 npc_affinity**：返回空数组。不报错。
- **如果 get_entry() 查询不存在的 id**：返回空字典 `{}`。调用者用 `.is_empty()` 判断。

### 多住客关联边界

- **如果一条线索涉及多个住客**：`npc_affinity` 是单个 StringName，代表"此线索最直接关联的住客"。对于涉及多个住客的线索，使用 `tags` 字段标记次要住客关联（如 `tags: ["npc_red", "npc_blue"]`），`npc_affinity` 设为主要住客。下游系统可通过 `search_by_tag("npc_red")` 查询所有关联某住客的线索。
- **如果 INSIGHT 的两条源线索关联不同住客**：InsightGenerator 在构造洞察时应从两条源线索中选择 `npc_affinity` 不为空的第一个作为洞察的主 affinity，同时在 `tags` 中包含两条源线索的所有住客标签。临时规则，待洞察生成 GDD (#12) 最终确认。

### 性能边界

- **如果条目增长到 200+ 条**：搜索操作 O(200) ≈ 0.1ms，可忽略。Dictionary 查找仍为 O(1)。无需索引优化。
- **如果连接增长到 100+ 条**：get_connections_for() 扫描 O(100) ≈ 0.05ms，可忽略。若未来需要，可添加 Dictionary[StringName, Array] 索引。MVP 不需要。

## Dependencies

### 上游依赖（本系统依赖的）

无。线索数据库是 Foundation 层系统，零依赖。InsightGenerator 和 InsightDefinitionTable 是本系统的内部组件，非外部依赖。

### 下游依赖（依赖本系统的）

| 系统 | 依赖类型 | 接口 | 状态 |
|------|---------|------|------|
| 线索发现 (#10) | 硬依赖 | add_entry(CLUE) | 未设计 |
| 线索连接/推理 (#11) | 硬依赖 | connect_clues() + connection_made 信号 | 未设计 |
| 洞察生成 (#12) | 硬依赖 | InsightGenerator 回调 add_entry(INSIGHT) | 未设计 |
| 色彩积累 (#16) | 硬依赖 | get_all_insights().size(), search_by_npc() | 未设计 |
| 笔记本系统 (#17) | 硬依赖 | 所有搜索/查询接口 + get_contextual_unlocks() | 未设计 |
| 条件性对话 (#14) | 软依赖 | get_entry() + has_insight_for() 查询特定知识 | 未设计 |
| 结局触发 (#23) | 软依赖 | get_all_insights(), get_valid_connections().size() | 未设计 |
| 存档/读档 (#4) | 硬依赖 | serialize() / deserialize() | 未设计 |
| 循环状态管理 (#1) | 无直接依赖 | Player Knowledge 层独立于循环重置 | GDD 完成 |

> **注意**：所有下游系统均为未设计状态。本 GDD 定义的接口是契约——下游 GDD 必须遵守这些接口，如需变更则需回到本 GDD 修改。

## Tuning Knobs

| 旋钮 | 默认值 | 安全范围 | 效果 |
|------|--------|---------|------|
| `SCHEMA_VERSION` | 1 | 1–N（单调递增） | 序列化格式版本。增版本号必须提供迁移函数。不可回退。 |
| `MAX_CLUES` | 50 | 30–100 | 游戏中可发现线索总数上限。影响搜索性能和内存占用。降低=更少的推理组合，提高=更多收集满足感 |
| `MAX_INSIGHTS` | 20 | 10–30 | 有效连接产生的洞察数上限。必须 ≤ COMBIN(MAX_CLUES, 2)。影响色彩积累速度（ADR-0002 读取此值） |
| `MAX_CONNECTIONS` | 50 | 30–100 | 玩家可尝试的连接数上限（包括有效和无效）。get_connections_for() 的扫描范围 |
| `DUPLICATE_REASON_THRESHOLD` | 3 | 1–10 | 同一线索对被重复连接多少次后，UI 应显示提示（"你已经尝试过这个组合"）。纯 UI 行为——ClueDatabase 始终拒绝重复，此旋钮控制下游系统何时提醒玩家 |
| `INSIGHT_TABLE_PATH` | "res://data/insight_definitions.json" | — | InsightDefinitionTable 的文件路径。开发期间可替换为调试版本（更多/更少洞察定义） |

> **交互说明**：`MAX_INSIGHTS` 和 `MAX_CLUES` 共同决定色彩积累速度（ADR-0002 的 KnowledgeManager 从 ClueDatabase 读取条目数量）。降低 MAX_INSIGHTS 但保持色彩阈值不变会让色彩更难获取。调整时需同步检查色彩积累 GDD (#16) 的阈值。

## Acceptance Criteria

### 条目生命周期（8 条）

- AC-E1-01: Given 空数据库, When add_entry({id: "clue_letter", entry_type: CLUE, title: "信件", description: "一封旧信", source: "room_basement", discovered_at_night: 1}), Then 返回 true 且 clue_discovered 信号发射
- AC-E1-02: Given 已有条目 "clue_letter", When add_entry({id: "clue_letter", ...}), Then 返回 false（重复 id 拒绝）
- AC-E1-03: Given 已有条目 "clue_a" 和 "clue_b", When add_entry({id: "insight_ab", entry_type: INSIGHT, source_clues: ["clue_a", "clue_b"], ...}), Then 返回 true 且 insight_generated 信号发射且两条源线索的 contextual_unlocks 包含 "insight_ab"
- AC-E1-04: Given 空数据库, When add_entry({id: "insight_orphan", entry_type: INSIGHT, source_clues: ["nonexistent_a", "nonexistent_b"]}), Then 返回 false（源线索不存在）
- AC-E1-05: Given 已有条目, When get_entry("clue_letter") 查询, Then 返回完整条目字典
- AC-E1-06: Given 已有条目, When get_entry("nonexistent") 查询, Then 返回空字典 {}
- AC-E1-07: Given 已有条目, When update_entry("clue_letter", {tags: ["burned"]}), Then 返回 true 且 tags 已更新
- AC-E1-08: Given 已有洞察引用两条源线索, When remove_entry("insight_ab"), Then 洞察被删除且两条源线索的 contextual_unlocks 不再包含 "insight_ab"

### 连接操作（6 条）

- AC-C1-01: Given 两条 CLUE 条目, When connect_clues("clue_a", "clue_b"), Then 返回 {ok: true, reason: ""} 且 connection_made 信号发射
- AC-C1-02: Given 已连接 "clue_a"-"clue_b", When connect_clues("clue_b", "clue_a")（反向）, Then 返回 {ok: false, reason: "duplicate"} 且返回已有连接记录
- AC-C1-03: Given 一条 CLUE 和一条 INSIGHT, When connect_clues("clue_a", "insight_ab"), Then 返回 {ok: false, reason: "invalid_types"}
- AC-C1-04: Given 存在有效配对的 InsightDefinitionTable, When connect_clues 连接有效对, Then 连接 is_valid=true 且自动生成洞察
- AC-C1-05: Given 不存在配对的 InsightDefinitionTable, When connect_clues 连接无效对, Then 连接 is_valid=false 且无洞察生成
- AC-C1-06: Given connect_clues("clue_a", "clue_a")（同一 id）, Then 返回 {ok: false, reason: "same_clue"}

### contextual_unlocks 级联（4 条）

- AC-U1-01: Given 洞察 "insight_ab" 引用 "clue_a" 和 "clue_b", When add_entry() 成功, Then get_contextual_unlocks("clue_a") 包含 "insight_ab" 且 has_insight_for("clue_a") 返回 true
- AC-U1-02: Given 无洞察的线索, When has_insight_for("clue_x") 查询, Then 返回 false
- AC-U1-03: Given 洞察已创建, When 删除洞察后查询源线索, Then contextual_unlocks 数组为空
- AC-U1-04: Given 洞察的源线索已被删除, When 删除该洞察, Then 不崩溃（静默跳过已删除的源线索）

### 序列化（4 条）

- AC-S1-01: Given 含 50 条目 + 20 连接的数据库, When serialize() 后 deserialize(), Then 条目数、连接数、contextual_unlocks 数组完全一致
- AC-S1-02: Given schema_version=99 的存档, When deserialize(), Then 返回 false（未知版本）
- AC-S1-03: Given 缺少 connections 字段的存档, When deserialize(), Then 返回 false
- AC-S1-04: Given 含孤儿洞察（source_clues 引用已删除线索）的存档, When deserialize(), Then 洞察保留但 contextual_unlocks 不包含该洞察

### 搜索（3 条）

- AC-Q1-01: Given 3 条带 tag="burned" 的条目, When search_by_tag("burned"), Then 返回 3 个 id
- AC-Q1-02: Given 2 条 npc_affinity="indigo" 的条目, When search_by_npc("indigo"), Then 返回 2 个 id
- AC-Q1-03: Given 空数据库, When get_all_clues(), Then 返回空数组

### 数据完整性（3 条）

- AC-I1-01: Given update_entry("clue_a", {entry_type: INSIGHT}), Then 返回 false（entry_type 不可变）
- AC-I1-02: Given add_entry() 执行中（_adding=true）, When 信号处理器再次调用 add_entry(), Then 返回 false（重入保护）
- AC-I1-03: Given remove_entry("clue_a") 且 clue_a 被 3 条连接引用, Then 3 条连接全部被删除

## Open Questions

1. **InsightDefinitionTable 格式**：JSON 配置文件的具体 schema 需要在线索连接/推理 GDD (#11) 中定义。本 GDD 只定义了 ClueDatabase 对 InsightGenerator 的委托接口，不定义配对规则格式。
2. **洞察的 NPC affinity 继承**：临时规则——InsightGenerator 优先使用源线索中第一个非空 npc_affinity 作为洞察的主 affinity，同时在 tags 中包含两条源线索的所有住客标签。待洞察生成 GDD (#12) 最终确认。
3. **无效连接的笔记本展示**：is_valid=false 的连接是否在笔记本中显示？显示方式如何？这是笔记本系统 (#17) 的职责，但本系统存储了这些数据——下游 GDD 需决定是否使用。
4. **搜索性能索引**：当前所有搜索为 O(n) 线性扫描。若线索数量超过 200，可能需要按 tag 和 npc_affinity 建立倒排索引。MVP 不需要，但值得在生产期评估。
