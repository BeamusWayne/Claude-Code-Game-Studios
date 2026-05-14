# 线索发现 (Clue Discovery)

## 1. Overview

线索发现系统处理玩家在房间中发现线索的交互流程。它监听 InteractionBus 的交互事件，检查可交互对象是否关联线索定义，验证发现条件（前置线索、NPC 在场、特定夜晚），然后将线索注册到 ClueDatabase。系统通过 ClueDefinition 资源定义每条线索的发现条件，支持数据驱动的线索配置。

## 2. Player Fantasy

**"每个角落都藏着真相"** — 你走进昏暗的书房，注意到书桌上有一本翻开的日记。你点击它，水墨画面微微泛起波纹——你发现了一条新线索。有些线索需要你在正确的夜晚、正确的房间、面对正确的人才能发现。每次发现都让你的笔记本更丰富，让世界的色彩更鲜明。

## 3. Detailed Rules

### 3.1 发现流程

1. 玩家点击可交互对象 → InteractionBus 发出 `interaction_detected` 事件
2. ClueDiscoveryManager 收到事件，检查 `target_id` 是否关联 ClueDefinition
3. 如果关联且未被发现（ClueDatabase.has_entry == false），验证发现条件
4. 条件通过 → ClueDatabase.add_entry()，发出 `clue_discovered` 信号
5. 已发现的线索不重复注册

### 3.2 ClueDefinition 资源

每条线索定义为 ClueDefinition 资源（.tres 文件）：

```
clue_id: StringName          — 唯一标识
display_name: String          — 显示名称
description: String           — 线索描述
room_id: StringName           — 所在房间
interactable_id: StringName   — 关联的可交互对象 ID
discovery_conditions: Dictionary — 发现条件
associated_insight_ids: Array[StringName] — 关联的洞察 ID
weight: float                 — 对色彩积累的贡献权重
```

### 3.3 发现条件

| 条件类型 | 字段 | 含义 |
|---------|------|------|
| must_have_clues | Array[StringName] | 必须已发现这些线索 |
| npc_in_room | StringName | 该 NPC 必须在当前房间 |
| night_range | Vector2i | 夜晚范围 (min, max)，0 表示不限制 |
| min_night | int | 最低夜晚要求 |

- 所有条件必须同时满足（AND 逻辑）
- conditions 为空字典 = 无条件限制，点击即发现
- MVP 不支持 OR 条件组合

### 3.4 线索注册表

- ClueDiscoveryManager 维护一个 `_clue_registry: Dictionary[StringName, ClueDefinition]`
- 通过 `register_clue(clue_id, definition)` 注册线索定义
- 支持按房间查询：`get_clues_for_room(room_id) -> Array[StringName]`
- 支持按可交互对象查询：`get_clue_for_interactable(interactable_id) -> StringName`

### 3.5 信号集成

- 监听 InteractionBus.interaction_detected
- 发出 `clue_discovered(clue_id: StringName, clue_data: Dictionary)` 信号
- 信号携带线索信息供 UI 显示提示

### 3.6 房间切换集成

- 房间切换时不需要特殊处理——线索注册表是全局的
- 可交互对象由 RoomManager 管理注册/注销
- 交互事件通过 InteractionBus 传递，不依赖房间实例

## 4. Formulas

### 发现条件检查
```
can_discover(clue_id) =
  not ClueDatabase.has_entry(clue_id)
  AND all(must_have_clues) in ClueDatabase
  AND (npc_in_room == "" OR NPCManager.get_npc_location(npc_in_room) == current_room)
  AND (night_range.x == 0 OR current_night >= night_range.x)
  AND (night_range.y == 0 OR current_night <= night_range.y)
```

### 线索注册表容量（MVP）
```
total_clues = 15-20  (3 rooms × ~5-7 clues each)
```

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 重复点击已发现线索的可交互对象 | 不触发发现，ClueDatabase 已有该条目 |
| 前置线索尚未发现 | 不触发发现，条件检查失败 |
| 前置线索在同一次交互前刚发现 | 可以发现（条件检查读取最新状态） |
| NPC 不在房间中 | 不触发发现（npc_in_room 条件失败） |
| ClueDefinition 未注册 | 忽略该交互事件（无关联线索） |
| 可交互对象没有关联线索 | 正常交互但不触发线索发现 |
| 夜晚范围条件不满足 | 不触发发现（如只在第 3-5 夜可发现的线索） |
| ClueDatabase 不可用 | 不崩溃，记录警告，跳过发现 |
| 同一可交互对象关联多条线索 | 只取第一条（interactable_id 应唯一映射） |

## 6. Dependencies

### 上游依赖
- **交互系统 (#7)** — InteractionBus 提供交互事件
- **线索数据库 (#2)** — ClueDatabase 存储已发现的线索

### 下游被依赖
- **线索连接/推理 (#11)** — 使用已发现的线索进行推理
- **色彩积累 (#16)** — 线索发现间接驱动色彩变化（通过洞察）
- **笔记本系统 (#17)** — 展示已发现的线索

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| max_clues_per_room | int | 10 | 5-20 | 每个房间的最大线索数 |
| discovery_cooldown | float | 0.0 | 0.0-2.0 | 两次发现之间的最小间隔（秒） |

## 8. Acceptance Criteria

1. 点击关联线索的可交互对象时，线索被注册到 ClueDatabase
2. 已发现的线索不会被重复注册
3. must_have_clues 前置条件正确阻止未满足条件的发现
4. npc_in_room 条件在 NPC 不在场时正确阻止发现
5. night_range 条件在夜晚范围外时正确阻止发现
6. 无条件的线索点击即发现
7. clue_discovered 信号在发现时发出，携带正确的 clue_id
8. 未注册 ClueDefinition 的交互不触发发现且不崩溃
9. get_clues_for_room 返回正确房间的线索列表
10. serialize/deserialize 正确保存和恢复注册表状态
11. reset() 清空所有运行时状态
