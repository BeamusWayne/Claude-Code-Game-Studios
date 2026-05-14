# 洞察生成 (Insight Generation)

## 1. Overview

洞察生成系统封装了从线索连接到洞察创建的验证和生成逻辑。它以 InsightGenerator（RefCounted 工具类）为核心，维护预撰写的连接定义表，验证玩家提交的线索对是否为有效组合，并在有效时构建 INSIGHT 类型的 KnowledgeEntry。系统还负责 contextual_unlocks 级联——当洞察生成时，自动更新两条源线索的重新解读列表。InsightGenerator 是纯逻辑工具，无状态、无信号、不依赖 Node 生命周期。

## 2. Player Fantasy

**"真相在连接中浮现"** — 你不是在"使用"一个推理系统。你是在思考。当你把两个碎片放在一起，如果它们真的相关，新的理解会自然浮现——一条新的洞察写入你的笔记本，旧线索展现出你之前没注意到的含义。如果它们无关，你会看到一条灰色的标记——这不是惩罚，这是你思考过程的足迹。每一种新的洞察都为世界注入一抹色彩。

## 3. Detailed Rules

### 3.1 InsightGenerator 职责边界

InsightGenerator 负责：
- 加载和维护连接定义表（ConnectionDefinition 资源列表）
- 验证线索对是否为有效连接
- 构建有效的 INSIGHT KnowledgeEntry

InsightGenerator **不**负责：
- 写入 ClueDatabase（由 ClueConnectionManager 协调）
- 发出信号（由 ClueDatabase 发出）
- UI 反馈（由笔记本 UI 处理）
- 色彩更新（由 KnowledgeManager 处理）

### 3.2 连接定义表

- 游戏数据通过 ConnectionDefinition 资源（.tres 文件）定义
- 启动时由 ClueConnectionManager 加载所有定义，注入 InsightGenerator
- 查找结构：`_connection_lookup: Dictionary[String, ConnectionDefinition]`
- 键生成规则：`min(a, b) + "+" + max(a, b)`（确保 A+B = B+A）

### 3.3 洞察生成条件

洞察自动生成，无需额外触发。条件：
1. 两条线索都必须是 CLUE 类型（非 INSIGHT）
2. 两条线索都必须存在于 ClueDatabase.entries 中
3. 该线索对在连接定义表中有匹配
4. 该线索对尚未被连接过（无重复）

所有条件在 ClueDatabase.connect_clues() 中原子检查。

### 3.4 INSIGHT 条目结构

生成的 INSIGHT 条目（ADR-0005 定义）：

| 字段 | 来源 |
|------|------|
| id | ConnectionDefinition.resulting_insight.id |
| entry_type | EntryType.INSIGHT (1) |
| title | ConnectionDefinition.resulting_insight.title |
| description | ConnectionDefinition.resulting_insight.description |
| source | StringName 连接来源标记（如 &"connection"） |
| discovered_at_night | 当前夜晚（从 LoopStateManager 获取） |
| npc_affinity | ConnectionDefinition.resulting_insight.npc_affinity |
| tags | ConnectionDefinition.resulting_insight.tags |
| contextual_unlocks | []（洞察本身不会被再次解读） |
| metadata | {} |
| source_clues | [clue_a, clue_b] |
| reinterpretation | ConnectionDefinition.resulting_insight.reinterpretation |

### 3.5 contextual_unlocks 级联

当 INSIGHT 条目通过 add_entry() 写入 ClueDatabase 时：
1. ClueDatabase 检测 entry_type == INSIGHT
2. 取出 source_clues[0] 和 source_clues[1]
3. 将 insight.id 追加到两条源线索的 contextual_unlocks 数组
4. 笔记本 UI 读取 contextual_unlocks 时展示新的解读文本

当 INSIGHT 条目被 remove_entry() 删除时：
1. 从两条源线索的 contextual_unlocks 数组中移除 insight.id
2. 级联清理确保一致性

### 3.6 洞察与线索的关系

```
线索A ────────────┐
                  ├──→ 连接 ──→ [有效] ──→ INSIGHT
线索B ────────────┘                  │
                                    ├─→ 线索A.contextual_unlocks += [insight.id]
                                    └─→ 线索B.contextual_unlocks += [insight.id]
```

- 一条线索可以被多条洞察重新解读（多个 contextual_unlocks）
- 一条洞察只由两条线索产生（source_clues 固定 2 个）
- 洞察不能再被连接（只有 CLUE 可以连接）

## 4. Formulas

### 洞察权重对知识水平的贡献
```
knowledge_level = count(generated insights) / max_valid_connections
```
MVP 使用等权重：每条洞察贡献 `1 / max_valid_connections`。

### contextual_unlocks 长度
```
max_unlocks_per_clue = max_valid_connections / 2 ≈ 6
```
平均每条线索被 ~6 条洞察引用（上界）。

### 洞察生成率（设计目标）
```
discovery_rate = insights_generated / gameplay_hours
target: 2-3 insights per hour of gameplay
```
MVP 3 夜 × ~10 分钟 = ~30 分钟，目标 6-9 条洞察。

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 两条有效线索但不在定义表中 | 连接创建为 is_valid=false，不生成洞察 |
| source_clues 中有一条线索被删除 | contextual_unlocks 级联清理时跳过不存在的线索 |
| 洞察的 npc_affinity 为空 | 全局色彩（朱砂）而非住客专属色彩 |
| 两条线索属于不同住客 | 洞察的 npc_affinity 取定义表中的值（可手动指定任一方） |
| 所有洞察已全部生成 | 后续连接均为无效，knowledge_level = 1.0 |
| 洞察被删除后重新连接同一对 | 需要先删除旧 Connection 记录才能重新创建 |
| ConnectionDefinition 的 resulting_insight.id 冲突 | add_entry() 返回 false（ID 必须唯一） |
| 同一对线索有多个 ConnectionDefinition | 只使用第一个加载的定义（不允许多对多） |

## 6. Dependencies

### 上游依赖
- **线索连接/推理 (#11)** — 连接流程触发洞察验证和生成
- **线索数据库 (#2)** — ClueDatabase 存储 INSIGHT 条目、管理 contextual_unlocks

### 下游被依赖
- **色彩积累 (#16)** — 洞察数量驱动 knowledge_level
- **笔记本系统 (#17)** — 展示洞察内容和重新解读

### ADR 引用
- **ADR-0005** — KnowledgeEntry 统一 schema、contextual_unlocks 机制

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| max_valid_connections | int | 12 | 8-20 | 可生成的洞察数上限 |
| insight_weight_mode | String | "equal" | "equal"/"custom" | 等权重或自定义权重 |
| auto_unlock_contextual | bool | true | true/false | 洞察生成时是否自动级联 contextual_unlocks |

## 8. Acceptance Criteria

1. InsightGenerator.validate_connection() 对有效线索对返回 ConnectionDefinition
2. InsightGenerator.validate_connection() 对无效线索对返回 null
3. InsightGenerator.generate_insight() 构建正确的 INSIGHT KnowledgeEntry
4. 生成的 INSIGHT 包含正确的 source_clues（恰好 2 条）
5. 生成的 INSIGHT 包含 reinterpretation 文本
6. contextual_unlocks 在洞察写入后自动更新两条源线索
7. 删除洞察时 contextual_unlocks 正确清理
8. 查找键对 A+B 和 B+A 返回相同结果
9. 无效连接不调用 generate_insight()
10. InsightGenerator 为 RefCounted（非 Node），无场景树依赖
11. ConnectionDefinition 可从 .tres 资源加载
12. 所有生成的 INSIGHT 的 entry_type 为 1 (INSIGHT)
