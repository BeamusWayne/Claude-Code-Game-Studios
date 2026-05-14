# NPC 状态机 (NPC State Machine)

## 1. Overview

每个 NPC 住客拥有独立的情绪状态机（6 种情绪），通过 Enum FSM 管理状态转换。NPC 状态分为模板层（每晚重置）和持久变异层（跨循环保留），所有变异通过 LoopStateManager 的 propose_delta() 管道提交。NPCManager Autoload 统一管理所有 NPC 的注册、查询和序列化。

## 2. Player Fantasy

**"每个住客都有自己的秘密要守护"** — NPC 不是信息贩卖机。他们有情绪、有防备、会因为玩家的提问方式而变化。同样的线索，在不同情绪状态下会得到完全不同的回应。玩家需要学会"读懂"NPC 的情绪，选择正确的时机和方式来获取信息。

## 3. Detailed Rules

### 3.1 情绪状态

| 状态 | 说明 | 对应行为 |
|------|------|---------|
| NEUTRAL | 默认平静状态 | 标准对话选项 |
| CURIOUS | 被玩家的新线索吸引 | 额外对话分支解锁 |
| ANXIOUS | 感到威胁或不安 | 回避敏感话题 |
| HOSTILE | 主动对抗，拒绝合作 | 限制对话选项 |
| TRUSTING | 对玩家产生信任 | 暗示性信息，主动分享 |
| FRIGHTENED | 极度恐惧 | 短对话，可能说出关键信息 |

### 3.2 状态转换

- 状态转换由外部事件触发（对话结果、玩家行为、时间压力）
- 所有转换必须通过 `LoopStateManager.propose_delta()` 提交
- NPC 不直接修改自己的情绪状态
- 非法转换被忽略（如从 HOSTILE 直接到 TRUSTING 需要中间状态）

### 3.3 NPCManager Autoload

- 统一管理所有 NPC 的注册和查询
- 每帧不执行逻辑——纯事件驱动
- 提供 `get_npc_state(npc_id)` 查询接口
- 提供 `get_npcs_in_emotional_state(state)` 批量查询

### 3.4 模板 vs 持久

| 属性 | 层级 | 每夜重置 |
|------|------|---------|
| position | 模板 | 是 |
| available | 模板 | 是 |
| emotional_state | 模板 | 是（回到 NEUTRAL） |
| discovered_secrets | 持久 | 否 |
| dialogue_history_flags | 持久 | 否 |

### 3.5 NPC 定义

5 个住客通过 NPCTemplate Resource 定义：

| NPC | 颜色 | 初始房间 | 性格关键词 |
|-----|------|---------|-----------|
| 靛蓝 (Indigo) | #3F51B5 | 大厅 | 冷静、观察者 |
| 赭石 (Umber) | #A0522D | 书房 | 学者、隐秘 |
| 朱砂 (Cinnabar) | #E4242C | 餐厅 | 热情、冲动 |
| 青瓷 (Celadon) | #73C2BE | 花园 | 温和、谨慎 |
| 梅紫 (Plum) | #8E4585 | 客房 | 神秘、警觉 |

## 4. Formulas

### 状态转换验证

```
is_valid_transition(from, to) -> bool:
    查询 TRANSITION_TABLE[from] 允许的目标列表
    NEUTRAL → [CURIOUS, ANXIOUS, TRUSTING]
    CURIOUS → [NEUTRAL, TRUSTING, ANXIOUS]
    ANXIOUS → [HOSTILE, FRIGHTENED, NEUTRAL]
    HOSTILE → [ANXIOUS, NEUTRAL]
    TRUSTING → [NEUTRAL, CURIOUS, ANXIOUS]
    FRIGHTENED → [ANXIOUS, HOSTILE, NEUTRAL]
```

### NPC 注册路径

```
state_path = "npc/{npc_id}/{property}"
例: "npc/indigo/emotional_state"
    "npc/indigo/position"
    "npc/indigo/available"
```

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 查询不存在的 NPC ID | 返回 null |
| 重复注册同一 NPC | 更新而非报错 |
| night_ready 时所有 NPC emotional_state 重置为 NEUTRAL | 正确——模板层重置 |
| 持久层属性（discovered_secrets）不受重置影响 | 正确——跨循环保留 |
| propose_delta 被拒绝（is_transitioning） | 状态转换不发生，下次重试 |
| NPC 不在当前房间被点击 | InteractionBus 不会路由到该 NPC |

## 6. Dependencies

### 上游依赖
- **循环状态管理 (#1)** — propose_delta() 管道、night_ready/night_advanced 信号
- **交互总线 (#6)** — NPC 点击事件路由

### 下游被依赖
- **NPC 信任/怀疑 (#13)** — 读取 emotional_state
- **条件性对话树 (#14)** — 查询 NPC 状态决定对话分支
- **住客审问 (#15)** — 审问可用性和 NPC 反应
- **事件调度器 (#9)** — 基于 NPC 状态调度事件

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| default_emotional_state | Enum | NEUTRAL | 6 种状态 | 每夜初始情绪 |
| npc_templates | Resource[] | 5 个住客 | — | NPC 定义数据 |

## 8. Acceptance Criteria

1. NPCManager 注册 5 个 NPC，每个有唯一 ID
2. get_npc_state() 返回正确的情绪状态
3. 状态转换通过 propose_delta() 提交，非直接修改
4. night_ready 信号触发所有 NPC 模板层重置（emotional_state → NEUTRAL）
5. 持久层属性跨 night_advanced 保留
6. 非法状态转换被拒绝（如 HOSTILE → TRUSTING）
7. serialize/deserialize 保留完整 NPC 状态
8. reset() 恢复所有 NPC 到模板初始状态
9. get_npcs_in_emotional_state() 返回正确子集
10. NPC 不包含交互处理游戏逻辑（仅路由事件）

## Open Questions

- MVP 是否只需要 NEUTRAL + TRUSTING + HOSTILE 三态？
- NPC 的房间位置是否应该由房间管理系统管理而非 NPC 模板？
- propose_delta 被拒绝时是否需要重试机制？
