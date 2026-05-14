# 线索连接/推理 (Clue Connection/Deduction)

## 1. Overview

线索连接/推理系统允许玩家将两条已发现的线索尝试连接，验证是否产生新的洞察。它由 ClueConnectionManager 协调——接收玩家的连接请求，调用 ClueDatabase.connect_clues() 记录连接，通过 InsightGenerator（RefCounted 工具类）验证连接是否正确，如果正确则自动生成 INSIGHT 类型的 KnowledgeEntry 并触发 contextual_unlocks 级联。系统记录所有连接尝试（有效和无效），供笔记本系统展示推理历史。

## 2. Player Fantasy

**"连接碎片，照亮真相"** — 你在笔记本上看到两条看似无关的线索："走廊尽头的碎灯笼"和"红色住客的不在场证明"。你选中它们，划出一条连接线。如果你的直觉正确，线变成藤黄金色——一个新的洞察诞生了："红色住客的谎言"。旧的线索获得了新的解读。如果你的直觉错误，线变成暗灰色——但错误也是推理的一部分，留在笔记本上提醒你。即使时间循环重置，你建立的连接不会消失。

## 3. Detailed Rules

### 3.1 连接流程

1. 玩家在笔记本 UI 中选择两条已发现的线索
2. 玩家点击"连接"按钮（或拖拽操作）
3. ClueConnectionManager 收到连接请求，调用 `ClueDatabase.connect_clues(clue_a, clue_b)`
4. ClueDatabase 创建 Connection 记录（is_valid 待定）
5. InsightGenerator 检查预撰写的连接定义表（ConnectionDefinition 资源）
6. 如果匹配 → 生成 INSIGHT 条目，Connection.is_valid = true
7. 如果不匹配 → Connection.is_valid = false
8. ClueDatabase 发出 `connection_made(clue_a, clue_b, is_valid)` 信号
9. 如果有效 → 同时发出 `insight_generated(insight_id)` 信号

### 3.2 ConnectionDefinition 资源

每个有效的线索连接定义为一个 ConnectionDefinition 资源：

```
clue_a: StringName           — 第一条线索 ID
clue_b: StringName           — 第二条线索 ID
resulting_insight: Dictionary — 生成的洞察条目
  id: StringName
  title: String
  description: String
  reinterpretation: String   — 对两条线索的新解读
  npc_affinity: StringName   — 关联住客
  tags: Array[StringName]
  weight: float              — 对知识水平的贡献权重
```

- 连接是无序的（A+B = B+A），匹配时自动排序
- 每对线索最多产生一个洞察
- 连接定义表在游戏启动时加载到 InsightGenerator

### 3.3 InsightGenerator（RefCounted 工具类）

- 不是 Autoload，不是 Node——纯粹的逻辑工具
- 维护一个 `_connection_lookup: Dictionary` 键为排序后的线索对
- `validate_connection(clue_a, clue_b) -> ConnectionDefinition?`
  - 查找排序后的键 `min(a,b) + "+" + max(a,b)`
  - 返回匹配的 ConnectionDefinition 或 null
- `generate_insight(definition: ConnectionDefinition, night: int) -> Dictionary`
  - 构建 INSIGHT KnowledgeEntry
  - 设置 source_clues、reinterpretation、discovered_at_night 等

### 3.4 连接约束

- 只能连接 CLUE 类型的条目（不能连接 INSIGHT）
- 两条线索都必须已被发现（存在于 ClueDatabase.entries 中）
- 不能重复连接同一对线索
- 玩家可以在任意夜晚连接任意已发现的线索（无夜晚限制）

### 3.5 无效连接的价值

- 无效连接不会消失——记录在 ClueDatabase.connections 中
- 笔记本系统可以展示"错误的尝试"作为推理历程
- 无效连接不产生洞察，不驱动色彩积累
- 无效连接不消耗任何资源（鼓励玩家大胆尝试）

### 3.6 信号流

```
Player Action
    │
    ▼
ClueConnectionManager.request_connection(clue_a, clue_b)
    │
    ▼
ClueDatabase.connect_clues(clue_a, clue_b)
    │
    ├─ 创建 Connection 记录
    ├─ 调用 InsightGenerator.validate_connection()
    │
    ├─ [有效] → InsightGenerator.generate_insight()
    │          → ClueDatabase.add_entry(INSIGHT)
    │          → contextual_unlocks 级联
    │          → connection_made(a, b, true)
    │          → insight_generated(id)
    │
    └─ [无效] → connection_made(a, b, false)
```

### 3.7 与 KnowledgeManager 集成

- 每当 insight_generated 信号发出，KnowledgeManager 重新计算 knowledge_level
- 每当 connection_made 信号发出，KnowledgeManager 更新 connection_intensity
- 色彩变化通过 KnowledgeManager 的信号传递给 InkWashDriver 和 UI

## 4. Formulas

### 连接验证查找键
```
lookup_key = min(clue_a, clue_b) + "+" + max(clue_a, clue_b)
```
字符串比较确保 A+B 和 B+A 映射到同一键。

### 有效连接数上限（MVP）
```
max_valid_connections = 10-15
total_clue_pairs = C(total_clues, 2) ≈ C(20, 2) = 190
valid_ratio = max_valid_connections / total_clue_pairs ≈ 5-8%
```
玩家需要从 ~190 种可能组合中找到 ~10-15 个有效连接。

### 洞察权重（MVP 等权重）
```
weight_per_insight = 1.0 / max_valid_connections
knowledge_level = generated_insights / max_valid_connections
```

### 藤黄强度（ADR-0002）
```
connection_intensity = 0.40 + (valid_connections / max_valid_connections) × 0.60
```

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 连接两条未发现的线索 | 拒绝——connect_clues() 检查两条线索都存在于 entries 中 |
| 连接一条 CLUE 和一条 INSIGHT | 拒绝——connect_clues() 返回 invalid_types |
| 重复连接同一对线索 | 拒绝——connect_clues() 返回 duplicate |
| 连接一条线索和自己 | 拒绝——clue_a == clue_b 返回 duplicate |
| 所有有效连接都已找到 | 后续连接全部为无效连接，正常记录 |
| InsightGenerator 未加载任何定义 | 所有连接均为无效（无洞察生成） |
| 连接后读档回滚 | 连接和洞察随 ClueDatabase 状态恢复 |
| 线索在连接后被 contextual_unlock 重新解读 | contextual_unlocks 数组已包含洞察 ID，笔记本显示新解读 |
| ClueDatabase 不可用 | request_connection() 返回失败，不崩溃 |
| 同一帧内多次连接请求 | 串行处理——每次 connect_clues() 完成后才处理下一个 |

## 6. Dependencies

### 上游依赖
- **线索数据库 (#2)** — ClueDatabase 提供条目存储和 connect_clues() API
- **线索发现 (#10)** — 只有已发现的线索才能被连接

### 下游被依赖
- **洞察生成 (#12)** — 连接产生的 INSIGHT 条目是洞察生成系统的核心输出
- **色彩积累 (#16)** — 连接数驱动 connection_intensity（藤黄强度）
- **笔记本系统 (#17)** — 展示连接关系和推理历史

### ADR 引用
- **ADR-0005** — 统一 KnowledgeEntry schema、Connection 结构、contextual_unlocks 机制
- **ADR-0002** — 色彩积累公式（knowledge_level、connection_intensity）

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| max_valid_connections | int | 12 | 8-20 | 有效连接数上限，控制推理复杂度 |
| allow_invalid_connections | bool | true | true/false | 是否记录无效连接到历史 |
| max_total_connections | int | 50 | 30-100 | 总连接记录上限（含无效），防止数据膨胀 |
| show_hint_on_invalid | bool | false | true/false | 无效连接时是否给提示（MVP 关闭） |

## 8. Acceptance Criteria

1. 玩家可以请求连接两条已发现的 CLUE 条目
2. 有效连接自动生成 INSIGHT 条目，写入 ClueDatabase
3. 无效连接被记录但标记 is_valid = false
4. 重复连接同一对线索被拒绝（不创建重复记录）
5. 连接 INSIGHT 类型条目被拒绝
6. 连接未发现的线索被拒绝
7. insight_generated 信号在有效连接时发出
8. connection_made 信号在每次连接尝试时发出（含 is_valid 状态）
9. contextual_unlocks 级联正确更新两条源线索
10. KnowledgeManager.knowledge_level 在新洞察生成后更新
11. serialize/deserialize 正确保存和恢复连接记录
12. InsightGenerator 查找键对 A+B 和 B+A 返回相同结果
13. 无效连接不产生洞察、不驱动色彩、不更新 knowledge_level
14. ConnectionDefinition 资源可从 .tres 文件数据驱动加载
