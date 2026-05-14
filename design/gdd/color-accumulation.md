# 色彩积累 (Color Accumulation)

## 1. Overview

色彩积累系统跟踪玩家累积的知识/洞察进度，驱动水墨着色器的色彩饱和度（knowledge_level）。它是洞察系统的派生视图——从 ClueDatabase 读取已生成的洞察数据，计算全局知识水平、每位住客的颜色饱和度、以及线索连接的藤黄强度。knowledge_level 不可逆且跨循环持久：一旦获得知识，颜色永不消退。

## 2. Player Fantasy

**"真相着色"** — 世界从水墨黑白开始。每一个你揭开的秘密都为世界注入一丝色彩。靛蓝、赭石、朱砂、青瓷、梅紫——五位住客各有独特色彩，随着你深入了解他们的秘密而逐渐显现。而当你将线索连接成洞察时，藤黄的金色线将你的推理可视化。知识就是颜色，颜色就是真相。即使时间循环重置，你已看到的颜色不会消失。

## 3. Detailed Rules

### 3.1 全局知识水平

- `knowledge_level` 范围：0.0（纯黑白）到 1.0（全彩色）
- 每个洞察有一个权重（`weight`），反映其对真相的重要性
- knowledge_level = 已发现洞察的权重总和 / 所有可能洞察的权重总和
- knowledge_level 变化时发出 `knowledge_level_changed(new_level)` 信号
- InkWashDriver 监听此信号，更新着色器的 `knowledge_level` uniform

### 3.2 每位住客颜色饱和度

- 每位住客有独立的基础饱和度 0.10（始终可见为淡色调）
- npc_saturation[npc_id] = 0.10 + (与该住客相关的发现数 / 该住客的总秘密数) × 0.90
- 范围：0.10（淡色调）到 1.00（全饱和）
- 6 种知识颜色：

| 颜色 | Hex | 角色 | 来源 |
|------|-----|------|------|
| 靛蓝 | #3F51B5 | 观察者 | NPC 发现 |
| 赭石 | #A0522D | 守门人 | NPC 发现 |
| 朱砂 | #B22222 | 系统/UI 反馈 | 全局 |
| 青瓷 | #7DB9B6 | 倾听者 | NPC 发现 |
| 梅紫 | #8E4585 | 醉酒者 | NPC 发现 |
| 藤黄 | #CC7722 | 洞察/连接 | 线索连接 |

- 幼者使用铅白 #E8E0D4（纸色——有意设计例外）

### 3.3 压力惩罚

- 在 INTENSE/CRITICAL 阶段，知识色彩暂时消退（压力下知识变得模糊）
- effective_level = knowledge_level × (1.0 - pressure_penalty × pressure_level)
- pressure_penalty 默认 0.3（最多 30% 色彩损失）
- 压力结束后，effective_level 恢复到 knowledge_level

### 3.4 跨循环持久性

- knowledge_level 跨夜累积，不随 night_advanced 重置
- 派生值（knowledge_level、npc_saturations）不直接序列化
- 序列化的是底层数据：哪些洞察已生成、哪些线索已发现、哪些连接已建立
- 读档后重新计算派生值

### 3.5 MVP 简化

- MVP 阶段，由于洞察生成系统尚未实现，使用 ClueDatabase 的 INSIGHT 类型条目作为代理
- knowledge_level 基于已生成的 insight 条目数量计算
- 每位住客的饱和度基于与该住客关联的 insight 条目计算

## 4. Formulas

### 全局知识水平
```
knowledge_level = clamp(sum(weights of generated insights) / sum(all insight weights), 0.0, 1.0)
```

### 等权重简化版（MVP）
```
knowledge_level = clamp(generated_insight_count / max_insights, 0.0, 1.0)
```
- max_insights: 常量，MVP 默认 10

### 每位住客饱和度
```
npc_saturation[npc_id] = 0.10 + (npc_insights[npc_id] / npc_total_secrets[npc_id]) × 0.90
```
- npc_insights[npc_id]: 与该住客相关的已生成洞察数
- npc_total_secrets[npc_id]: 该住客的总秘密数（配置值）

### 压力惩罚
```
effective_knowledge = knowledge_level × (1.0 - pressure_penalty × pressure_level)
pressure_penalty = 0.3  (default)
pressure_level 来自 TimerService
```

### 连接藤黄强度
```
connection_intensity = 0.40 + (connections_made / total_possible_connections) × 0.60
```

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 没有任何洞察生成 | knowledge_level = 0.0，画面纯黑白 |
| 所有洞察全部生成 | knowledge_level = 1.0，画面全彩色 |
| 压力达到 CRITICAL 同时有高知识 | effective_level 最低降到 0.7 × knowledge_level，不会完全黑白 |
| 跨夜后知识不重置 | knowledge_level 只增不减 |
| 新洞察在压力期间生成 | knowledge_level 立即增加，但 effective_level 受压力惩罚影响 |
| NPC 关联洞察数为 0 | npc_saturation = 0.10（基础淡色调） |
| NPC 关联洞察数等于总秘密数 | npc_saturation = 1.00（全饱和） |
| max_insights 为 0（除零保护） | knowledge_level = 0.0 |

## 6. Dependencies

### 上游依赖
- **线索数据库 (#2)** — insight 条目的数据源
- **倒计时系统 (#5)** — pressure_level 驱动压力惩罚
- **InkWashDriver** — 接收 knowledge_level 更新着色器

### 下游被依赖
- **水墨视觉风格 (#18)** — 使用 npc_saturations 和 connection_intensity
- **计时器/HUD UI (#19)** — 显示 knowledge_level 进度

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| max_insights | int | 10 | 5-30 | 全局知识水平的分母 |
| pressure_penalty | float | 0.3 | 0.0-0.5 | 压力对色彩的削减比例 |
| base_npc_saturation | float | 0.10 | 0.0-0.3 | 每位住客的基础饱和度 |
| base_connection_intensity | float | 0.40 | 0.0-0.5 | 连接藤黄的基础强度 |
| transition_speed | float | 2.0 | 0.5-5.0 | 色彩变化动画速度 |

## 8. Acceptance Criteria

1. knowledge_level 从 ClueDatabase insight 条目正确计算
2. 新 insight 创建后 knowledge_level 立即更新
3. knowledge_level 达到 1.0 时画面全彩色
4. knowledge_level 为 0.0 时画面纯黑白
5. 压力惩罚在 INTENSE/CRITICAL 阶段正确减少 effective_knowledge
6. 压力结束后 effective_knowledge 恢复
7. knowledge_level 跨夜不重置
8. 每位住客的 npc_saturation 独立计算
9. InkWashDriver.knowledge_level 与 KnowledgeManager 同步
10. serialize/deserialize 后重新计算派生值
11. 除零保护：max_insights = 0 时返回 0.0
