# 笔记本系统 (Notebook System)

**System ID**: #17
**Category**: Gameplay, MVP, Feature Layer
**Status**: GDD Complete
**Date**: 2026-05-14

---

## 1. Overview

笔记本系统是玩家的知识管理中心，汇总所有已发现的线索、建立的连接和生成的洞察。它由 NotebookManager（Autoload）协调——从 ClueDatabase 读取条目和连接数据，为笔记本 UI 提供结构化的查询接口。笔记本的核心视图是线索板（clue board）：以节点（线索/洞察）和边（连接线）构成的可视化推理网络，有效连接显示为藤黄金色，无效连接显示为灰色。玩家可以搜索/筛选条目、查看条目详情（包括 contextual_unlocks 带来的重新解读）、以及从笔记本发起线索连接操作。笔记本不存储自己的数据——它是 ClueDatabase 的只读视图，所有修改（连接、发现）通过下游系统执行。

## 2. Player Fantasy

你翻开笔记本。第一夜结束时，只有三个孤零零的碎片散落在空白页面上——一块碎灯笼、一封旧信、一句靛蓝住客不经意的话。但到了第四夜，页面上已经织出一张网。两条金色线从"碎灯笼"和"靛蓝的不在场证明"之间延伸出来，交汇成一个新节点："靛蓝的谎言"。你点开旧信——现在它下面多了一段文字，是你之前看不到的解读，因为那时候你还不知道她撒了谎。每一条灰色的线——你那些错误的猜测——也留在那里，不让你忘记自己走过的弯路。这不是一个工具，这是你思考过程的外化。

## 3. Detailed Rules

### 3.1 NotebookManager 职责边界

NotebookManager 负责：
- 从 ClueDatabase 读取条目和连接数据
- 为笔记本 UI 提供查询接口（筛选、搜索、详情）
- 管理 UI 视图状态（当前选中的条目、筛选条件、节点位置缓存）
- 委托线索连接操作给 ClueConnectionManager

NotebookManager **不**负责：
- 存储知识数据（ClueDatabase 是唯一数据源）
- 验证连接有效性（InsightGenerator 的职责）
- 触发线索发现（线索发现系统 #10 的职责）
- 计算知识色彩（KnowledgeManager 的职责）

### 3.2 笔记本视图模式

笔记本支持三种视图模式，玩家可以自由切换：

**板视图（Board View）**：
- 核心视图——线索板，展示所有已发现条目和连接的关系网络
- CLUE 条目显示为圆形节点，INSIGHT 条目显示为菱形节点
- 有效连接显示为藤黄金色实线（connection_gold，ADR-0002）
- 无效连接显示为灰色虚线
- 未连接的条目散布在板的边缘
- 玩家可以拖拽节点重新排列

**列表视图（List View）**：
- 所有条目按时间倒序排列（最新发现在前）
- 每行显示：标题、类型图标（CLUE/INSIGHT）、npc_affinity 色点、发现夜数
- 支持按 tag、npc_affinity、entry_type 筛选
- 支持关键词搜索（匹配 title 和 description）

**详情视图（Detail View）**：
- 展示单个条目的完整信息
- 包含：标题、描述、来源、发现时间、关联住客、标签
- 展示 contextual_unlocks：洞察对该线索的重新解读
- 展示所有连接关系（哪些线索与它连接，是否有效）
- 提供"连接"操作入口（跳转到板视图并选中该条目）

### 3.3 线索板数据模型

线索板的视觉状态由 NotebookBoard（RefCounted 工具类）管理：

**节点（BoardNode）**：
- 关联一个 KnowledgeEntry（CLUE 或 INSIGHT）
- 位置 (x, y) —— 由玩家拖拽或自动布局决定
- 大小：CLUE 节点固定尺寸，INSIGHT 节点略大
- 颜色：由 npc_affinity 映射到知识颜色（ADR-0002 六色系统）
- 状态：normal / selected / highlighted

**边（BoardEdge）**：
- 关联一个 Connection 记录
- 样式：有效连接 = 藤黄金色实线（宽度 2px），无效连接 = 灰色虚线（宽度 1px）
- 起止：连接 BoardNode clue_a 和 BoardNode clue_b

**布局**：
- 初始布局使用力导向算法（简化版），自动分散节点
- 玩家拖拽后位置被记住（存储在 NotebookManager 内部，非 ClueDatabase）
- 连接的两个节点间有吸引力（有效连接更强）

### 3.4 搜索与筛选

**搜索接口**：

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `search_entries(query)` | query: String | Array[StringName] | 全文搜索 title 和 description |
| `filter_by_tag(tag)` | tag: StringName | Array[StringName] | 按标签筛选 |
| `filter_by_npc(npc_id)` | npc_id: StringName | Array[StringName] | 按关联住客筛选 |
| `filter_by_type(type)` | type: EntryType | Array[StringName] | 按条目类型筛选 |
| `filter_by_night(night)` | night: int | Array[StringName] | 按发现夜晚筛选 |
| `get_all_visible()` | — | Array[StringName] | 所有已发现条目 |

所有筛选和搜索操作直接委托给 ClueDatabase 的对应接口。NotebookManager 不维护独立的数据副本。

### 3.5 条目详情与重新解读

详情视图展示 contextual_unlocks 机制（ADR-0005）的完整效果：

1. 展示条目的原始 description（发现时看到的文本）
2. 遍历 contextual_unlocks 数组，每条洞察提供：
   - 洞察标题
   - reinterpretation 文本（"新解读"）
   - 洞察的发现时间
3. 重新解读按洞察生成时间排序（最早在前）

当条目没有 contextual_unlocks 时，详情视图只显示原始描述——没有"锁定"或"隐藏"提示，避免破坏沉浸感。

### 3.6 从笔记本发起连接

玩家可以在笔记本中直接尝试连接线索：

1. 在板视图中选择两个 CLUE 节点（点击第一个，再点击第二个）
2. 点击"连接"按钮或使用快捷键
3. NotebookManager 委托给 ClueConnectionManager.request_connection()
4. ClueDatabase 处理验证和存储
5. 信号流回调更新板视图（新增边、可能的 INSIGHT 节点）

约束（与线索连接系统 #11 一致）：
- 只能连接 CLUE 类型的条目（不能连接 INSIGHT）
- 不能重复连接同一对线索
- 两条线索都必须已被发现

### 3.7 笔记本打开/关闭

- 笔记本是一个全屏覆盖 UI（CanvasLayer 50，高于对话面板 Layer 40）
- 打开笔记本时：TimerService 时间缩放设为 0.0（完全暂停），游戏世界不可交互
- 关闭笔记本时：TimerService 时间缩放恢复（如果对话同时活跃则 0.5x，否则 1.0x）
- 笔记本在对话期间不可打开（DialogueManager.is_active == true 时阻止）
- 笔记本打开时 InteractionBus 暂停（is_accepting = false）

### 3.8 信号流

```
玩家操作 → NotebookManager
    │
    ├─ [打开笔记本]
    │   ├─ TimerService.set_time_scale(0.0)
    │   ├─ InteractionBus.set_accepting(false)
    │   ├─ 从 ClueDatabase 加载所有已发现条目
    │   ├─ 构建 BoardNodes 和 BoardEdges
    │   └─ 显示笔记本 UI
    │
    ├─ [搜索/筛选]
    │   ├─ 委托 ClueDatabase.search_by_*()
    │   └─ 更新 UI 显示结果子集
    │
    ├─ [查看详情]
    │   ├─ 委托 ClueDatabase.get_entry()
    │   ├─ 委托 ClueDatabase.get_contextual_unlocks()
    │   ├─ 委托 ClueDatabase.get_connections_for()
    │   └─ 显示详情视图
    │
    ├─ [发起连接]
    │   ├─ 委托 ClueConnectionManager.request_connection()
    │   ├─ 等待 connection_made 信号
    │   └─ [有效] 等待 insight_generated 信号 → 更新板视图
    │
    ├─ [关闭笔记本]
    │   ├─ TimerService.set_time_scale(previous_scale)
    │   ├─ InteractionBus.set_accepting(true)
    │   └─ 隐藏笔记本 UI
    │
    └─ [被动更新]
        ├─ 监听 ClueDatabase.clue_discovered → 添加新节点
        ├─ 监听 ClueDatabase.insight_generated → 添加 INSIGHT 节点 + 更新 contextual_unlocks
        └─ 监听 ClueDatabase.connection_made → 添加新边
```

## 4. Formulas

### 4.1 板节点位置初始化

**Named Expression**:

```
x_init = center_x + radius * cos(angle)
y_init = center_y + radius * sin(angle)
angle = (entry_index / total_entries) * 2 * PI + random_offset
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `center_x`, `center_y` | float | board dimensions | 板中心坐标 |
| `radius` | float | 100.0 -- 400.0 | 初始分布半径 |
| `entry_index` | int | 0 -- total_entries-1 | 条目在排序中的位置 |
| `total_entries` | int | 1 -- 130 | 已发现条目总数 |
| `random_offset` | float | -0.3 -- +0.3 | 随机偏移（避免重叠） |
| `x_init`, `y_init` | float | board dimensions | 初始节点坐标 |

**Output Range**: Board coordinates. Nodes may overlap initially; player can rearrange.

**Worked Example**: 5 entries discovered, entry_index = 2, center = (400, 300), radius = 200.
- `angle = (2 / 5) * 2 * PI = 2.513`
- `x_init = 400 + 200 * cos(2.513) = 400 + 200 * (-0.809) = 238.2`
- `y_init = 300 + 200 * sin(2.513) = 300 + 200 * 0.588 = 417.6`

### 4.2 连接线颜色计算

**Named Expression**:

```
edge_color = {
    Color(GOLD_OCHRE_HEX, connection_intensity)  if connection.is_valid
    Color(0.5, 0.5, 0.5, 0.3)                   if not connection.is_valid
}
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `connection.is_valid` | bool | true/false | 连接是否有效 |
| `connection_intensity` | float | 0.40 -- 1.00 | 藤黄强度（ADR-0002） |
| `GOLD_OCHRE_HEX` | Color | #CC7722 | 藤黄知识色 |
| `edge_color` | Color | — | 连接线的颜色和透明度 |

**Output Range**: Valid edges use gold ochre with intensity-driven alpha. Invalid edges use fixed gray at 30% alpha.

**Worked Example**: 3 valid connections out of 12 max.
- `connection_intensity = 0.40 + (3/12) * 0.60 = 0.55`
- Valid edge: `Color(0.8, 0.467, 0.133, 0.55)` -- semi-transparent gold
- Invalid edge: `Color(0.5, 0.5, 0.5, 0.3)` -- faint gray

### 4.3 节点颜色映射

**Named Expression**:

```
node_color = {
    NPC_COLOR_MAP[entry.npc_affinity]  if entry.npc_affinity in NPC_COLOR_MAP
    Color(0.8, 0.7, 0.6)              if entry.npc_affinity == &"" (global)
}
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `entry.npc_affinity` | StringName | NPC ID or &"" | 条目关联的住客 |
| `NPC_COLOR_MAP` | Dictionary | 5 entries | 住客 ID 到知识颜色的映射（ADR-0002） |
| `node_color` | Color | — | 节点显示颜色 |

**Output Range**: One of 6 knowledge colors or a default warm neutral.

**Worked Example**:
- `npc_affinity = &"guest_indigo"` -> `Color(0.247, 0.318, 0.710)` (靛蓝)
- `npc_affinity = &""` -> `Color(0.8, 0.7, 0.6)` (全局线索，暖中性色)

### 4.4 搜索评分（排序用）

**Named Expression**:

```
search_score = (title_match * 2.0) + (description_match * 1.0) + (tag_match * 0.5)
```

**Variable Table**:

| Symbol | Type | Range | Description |
|--------|------|-------|-------------|
| `title_match` | float | 0.0 or 1.0 | 查询词是否出现在标题中 |
| `description_match` | float | 0.0 or 1.0 | 查询词是否出现在描述中 |
| `tag_match` | float | 0.0 or 1.0 | 查询词是否匹配任一标签 |
| `search_score` | float | 0.0 -- 3.5 | 条目与查询的相关度分数 |

**Output Range**: 0.0 to 3.5. Higher score = more relevant. Entries with score 0 are excluded from results.

**Worked Example**: Search query "灯笼" (lantern).
- Entry "破碎的灯笼": title_match=1.0, description_match=1.0, tag_match=0.0 -> score=3.0
- Entry "走廊的黑暗": title_match=0.0, description_match=1.0, tag_match=0.0 -> score=1.0

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 笔记本中没有条目（游戏刚开始） | 显示空白板视图和引导文字："探索世界，发现线索。" |
| 只有一条线索被发现了 | 板视图显示单个节点，无法发起连接 |
| 所有有效连接都已找到 | 后续连接尝试全部为灰色线，板视图显示完整的金色网络 |
| 条目的 contextual_unlocks 被清空（洞察被删除） | 详情视图回退到仅显示原始描述 |
| 笔记本打开时新线索被发现（通过事件） | clue_discovered 信号触发板视图动态添加节点 |
| 笔记本打开时洞察被生成 | insight_generated 信号触发板视图添加菱形节点 + 新边 |
| 搜索查询为空字符串 | 返回所有条目（无筛选） |
| 搜索查询无匹配结果 | 显示"没有找到相关条目"提示 |
| npc_affinity 为空字符串的条目 | 节点显示为暖中性色（非住客关联线索） |
| 两个被连接的线索属于不同住客 | 连接线使用藤黄色（洞察色），两端节点使用各自住客色 |
| 笔记本中发起连接但 ClueDatabase 不可用 | 连接操作失败，显示错误提示，不崩溃 |
| 板视图节点过多（50+）超出可视区域 | 支持缩放和平移；超出范围的节点可滚动查看 |
| 玩家在对话期间尝试打开笔记本 | 阻止——DialogueManager.is_active == true 时笔记本不可用 |
| 笔记本打开期间触发夜间过渡 | 时间缩放为 0.0，倒计时暂停，夜间过渡不会触发 |
| 玩家拖拽节点后关闭再打开笔记本 | 节点位置恢复到上次拖拽后的位置（NotebookManager 内部缓存） |
| 玩家关闭笔记本时忘记选中连接的两个节点 | 选中的节点状态清除，下次打开从无选中开始 |

## 6. Dependencies

### 上游依赖

| System | ADR | Relationship | Nature |
|--------|-----|-------------|--------|
| Clue Database | ADR-0005 | 笔记本的数据源 | 读取 entries、connections、contextual_unlocks；委托搜索查询 |
| Clue Connection/Deduction | — | 连接操作 | 委托 request_connection() 给 ClueConnectionManager |
| Insight Generation | — | 洞察展示 | 监听 insight_generated 信号更新板视图 |
| Color Accumulation | ADR-0002 | 色彩参数 | 读取 connection_intensity 和 npc_saturation 用于视觉渲染 |
| Timer Service | ADR-0008 | 时间控制 | 笔记本打开时 set_time_scale(0.0) 暂停倒计时 |
| Interaction Bus | ADR-0006 | 交互控制 | 笔记本打开时 set_accepting(false) 禁用世界交互 |

### 下游被依赖

| System | Relationship | Nature |
|--------|-------------|--------|
| Notebook UI (#21) | 笔记本的视觉呈现 | 消费 NotebookManager 的查询接口渲染 UI |
| Ending Trigger Logic (#23) | 查询知识状态 | 结局系统可能查询笔记本的洞察数量和连接数 |

### ADR 引用

- **ADR-0005** — KnowledgeEntry 统一 schema、Connection 结构、contextual_unlocks 机制
- **ADR-0002** — 六种知识颜色、connection_intensity、per-NPC saturation
- **ADR-0003** — CanvasLayer 层级（笔记本在 Layer 50）

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| board_layout_radius | float | 200.0 | 100.0--400.0 | 初始节点分布半径 |
| board_center_x | float | 视口宽度/2 | — | 板中心 X 坐标 |
| board_center_y | float | 视口高度/2 | — | 板中心 Y 坐标 |
| clue_node_size | float | 32.0 | 20.0--60.0 | CLUE 节点直径 |
| insight_node_size | float | 40.0 | 24.0--72.0 | INSIGHT 节点直径（比 CLUE 略大） |
| valid_edge_width | float | 2.0 | 1.0--4.0 | 有效连接线宽度 |
| invalid_edge_width | float | 1.0 | 0.5--2.0 | 无效连接线宽度 |
| invalid_edge_alpha | float | 0.3 | 0.1--0.5 | 无效连接线透明度 |
| detail_scroll_speed | float | 300.0 | 100.0--600.0 | 详情视图滚动速度 |
| notebook_time_scale | float | 0.0 | 0.0 | 笔记本打开时的时间缩放（固定 0.0 = 暂停） |

## 8. Acceptance Criteria

1. NotebookManager 从 ClueDatabase 正确读取所有已发现的 CLUE 和 INSIGHT 条目
2. 板视图正确显示所有已发现条目为节点（CLUE = 圆形，INSIGHT = 菱形）
3. 有效连接显示为藤黄金色实线，无效连接显示为灰色虚线
4. 节点颜色正确映射到 6 种知识颜色（npc_affinity -> NPC_COLOR_MAP）
5. 搜索接口返回与查询匹配的条目，按 search_score 排序
6. 筛选接口按 tag、npc_affinity、entry_type、discovered_at_night 正确过滤
7. 详情视图展示原始描述和所有 contextual_unlocks 的重新解读
8. 从笔记本发起连接正确委托给 ClueConnectionManager.request_connection()
9. 有效连接自动触发板视图更新（新 INSIGHT 节点 + 新边）
10. 无效连接在板视图中添加灰色边
11. 重复连接被拒绝，显示"你已经尝试过这个组合"提示
12. 打开笔记本时 TimerService.set_time_scale(0.0) 被调用，倒计时暂停
13. 关闭笔记本时时间缩放恢复到之前的值
14. 笔记本打开时 InteractionBus.set_accepting(false) 被调用
15. 对话期间（DialogueManager.is_active == true）无法打开笔记本
16. clue_discovered 信号在笔记本打开时触发板视图动态添加节点
17. insight_generated 信号在笔记本打开时触发板视图添加 INSIGHT 节点
18. 空笔记本（无条目）显示引导文字，不崩溃
19. 50+ 条目的板视图支持缩放和平移
20. 玩家拖拽节点后位置在关闭/重新打开笔记本后保留
