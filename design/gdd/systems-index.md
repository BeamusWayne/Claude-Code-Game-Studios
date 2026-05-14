# Systems Index: 七夜 (Seven Nights)

> **Status**: Draft
> **Created**: 2026-05-14
> **Last Updated**: 2026-05-14
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

七夜是一款水墨风悬疑推理时间循环叙事冒险游戏。玩家被困在山间旅馆中，有 7 个循环揭开真相。系统设计围绕 4 个核心支柱：碎片拼图（线索系统）、时间节奏（倒计时系统）、连接洞察（推理系统）、住客秘密（NPC 系统）。共识别 24 个系统 + 1 个整合场景，按依赖关系分为 5 层，按优先级分为 MVP（4 周）和垂直切片（+2 周）两个里程碑。

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | 循环状态管理 (Loop State Management) | Core | MVP | Implemented | design/gdd/loop-state-management.md | — |
| 2 | 线索数据库 (Clue Database) | Core | MVP | Implemented | design/gdd/clue-database.md | — |
| 3 | 房间/位置管理 (Room/Location Management) | Core | MVP | Implemented | design/gdd/room-location-management.md | — |
| 4 | 存档/读档持久化 (Save/Load Persistence) | Persistence | MVP | Implemented | — | — |
| 5 | 倒计时系统 (Countdown Timer) | Gameplay | MVP | Implemented | design/gdd/countdown-timer.md | #1 |
| 6 | NPC 状态机 (NPC State Machine) | Gameplay | MVP | Implemented | design/gdd/npc-state-machine.md | #1 |
| 7 | 交互系统 (Interaction System) | Core | MVP | Implemented | design/gdd/interaction-system.md | #3 |
| 8 | 夜晚过渡控制器 (Night Transition Controller) | Core | MVP | Implemented | design/gdd/night-transition-controller.md | #1, #4 |
| 9 | 事件调度器 (Event Scheduler) | Gameplay | MVP | Implemented | design/gdd/event-scheduler.md | #5, #3, #6 |
| 10 | 线索发现 (Clue Discovery) | Gameplay | MVP | Implemented | design/gdd/clue-discovery.md | #7, #2 |
| 11 | 线索连接/推理 (Clue Connection/Deduction) | Gameplay | MVP | GDD Complete | design/gdd/clue-connection-deduction.md | #2, #10 |
| 12 | 洞察生成 (Insight Generation) | Gameplay | MVP | GDD Complete | design/gdd/insight-generation.md | #11, #2 |
| 13 | NPC 信任/怀疑 (NPC Trust/Suspicion) | Gameplay | MVP | Implemented | design/gdd/npc-trust-suspicion.md | #6, #7 |
| 14 | 条件性对话树 (Conditional Dialogue Trees) | Narrative | MVP | Not Started | — | #6, #13 |
| 15 | 住客审问 (Guest Interrogation) | Gameplay | MVP | Not Started | — | #14, #13, #7 |
| 16 | 色彩积累 (Color Accumulation) | Core | MVP | Implemented | design/gdd/color-accumulation.md | #12, #1 |
| 17 | 笔记本系统 (Notebook System) | Gameplay | MVP | Not Started | — | #2, #11, #12 |
| 18 | 水墨视觉风格 (Ink Wash Visual Style) | UI | MVP | Not Started | — | #16 |
| 19 | 计时器/HUD UI (Timer/HUD UI) | UI | MVP | Not Started | — | #5, #16 |
| 20 | 对话 UI (Dialogue UI) | UI | MVP | Not Started | — | #14 |
| 21 | 笔记本 UI (Notebook UI) | UI | MVP | Not Started | — | #17 |
| 22 | 房间导航 UI (Room Navigation UI) | UI | MVP | Not Started | — | #3, #7 |
| 23 | 结局触发逻辑 (Ending Trigger Logic) | Narrative | MVP | Not Started | — | #17, #6, #11 |
| 24 | 音频系统 (Audio System) | Audio | Vertical Slice | Not Started | — | #5, #9, #8 |
| 25 | 多结局 (Multiple Endings) | Narrative | Vertical Slice | Not Started | — | #23 |

> **整合场景（非独立系统）**：时间循环探索 (Time Loop Exploration) — 由 #1, #3, #5, #8 组合产生的玩家体验。记录为集成测试规范，不单独编写 GDD。

---

## Categories

| Category | Description | Systems |
|----------|-------------|---------|
| **Core** | 基础系统，一切依赖它们 | 循环状态管理, 线索数据库, 房间/位置管理, 交互系统, 夜晚过渡控制器, 色彩积累 |
| **Gameplay** | 让游戏好玩的核心机制 | 倒计时, NPC 状态机, 事件调度器, 线索发现, 线索连接/推理, 洞察生成, NPC 信任/怀疑, 住客审问, 笔记本系统 |
| **Persistence** | 状态保存和连续性 | 存档/读档持久化 |
| **UI** | 玩家面对的信息展示 | 水墨视觉风格, 计时器/HUD UI, 对话 UI, 笔记本 UI, 房间导航 UI |
| **Narrative** | 故事和对话传递 | 条件性对话树, 结局触发逻辑, 多结局 |
| **Audio** | 声音和音乐 | 音频系统 |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Timeline | System Count |
|------|------------|------------------|----------|-------------|
| **MVP** | 核心循环可运行——3 房间、3 住客、3 夜、1 结局、恒定倒计时、基础推理 | First Playable | 4 周 | 23 |
| **Vertical Slice** | 完整体验切片——完整音效、3 个结局 | Demo / VS | +2 周 | 2 |

> **注意**：由于七夜是小规模独立项目，几乎所有系统都属于 MVP。完整愿景和润色阶段增加的是内容量（8 房间、5 住客、7 夜）和品质（压力节奏变化、住客移动时间表），不是新系统。

---

## Dependency Map

### Foundation Layer（零依赖）

| System | Rationale |
|--------|-----------|
| 循环状态管理 | 一切状态架构的基础——模板与持久变更分离。所有时间循环相关系统依赖它。 |
| 线索数据库 | 推理系统的数据燃料。所有线索和推理系统依赖它。 |
| 房间/位置管理 | 空间骨架。交互、导航、事件调度依赖它。 |
| 存档/读档持久化 | 序列化基础设施。循环状态和玩家进度跨会话保存。 |

### Core Layer（依赖基础层）

| System | Depends On |
|--------|-----------|
| 倒计时系统 | 循环状态管理 |
| NPC 状态机 | 循环状态管理 |
| 交互系统 | 房间/位置管理 |
| 夜晚过渡控制器 | 循环状态管理, 存档/读档持久化 |
| 事件调度器 | 倒计时系统, 房间/位置管理, NPC 状态机 |
| 色彩积累 | 洞察生成, 循环状态管理 |

### Feature Layer（依赖核心层）

| System | Depends On |
|--------|-----------|
| 线索发现 | 交互系统, 线索数据库 |
| 线索连接/推理 | 线索数据库, 线索发现 |
| 洞察生成 | 线索连接/推理, 线索数据库 |
| NPC 信任/怀疑 | NPC 状态机, 交互系统 |
| 条件性对话树 | NPC 状态机, NPC 信任/怀疑 |
| 住客审问 | 条件性对话树, NPC 信任/怀疑, 交互系统 |
| 住客审问 | 条件性对话树, NPC 信任/怀疑, 交互系统 |
| 笔记本系统 | 线索数据库, 线索连接/推理, 洞察生成 |
| 结局触发逻辑 | 笔记本系统, NPC 状态机, 线索连接/推理 |

### Presentation Layer（依赖功能层）

| System | Depends On |
|--------|-----------|
| 水墨视觉风格 | 色彩积累 |
| 计时器/HUD UI | 倒计时系统, 色彩积累 |
| 对话 UI | 条件性对话树 |
| 笔记本 UI | 笔记本系统 |
| 房间导航 UI | 房间/位置管理, 交互系统 |
| 音频系统 | 倒计时系统, 事件调度器, 夜晚过渡控制器 |

### Polish Layer

| System | Depends On |
|--------|-----------|
| 多结局 | 结局触发逻辑 |

---

## Recommended Design Order

| Order | System | Priority | Layer | Agent(s) | Est. Effort |
|-------|--------|----------|-------|----------|-------------|
| 1 | 循环状态管理 | MVP | Foundation | systems-designer + godot-specialist | L |
| 2 | 线索数据库 | MVP | Foundation | systems-designer | M |
| 3 | 房间/位置管理 | MVP | Foundation | systems-designer + godot-specialist | S |
| 4 | 存档/读档持久化 | MVP | Foundation | godot-specialist | S |
| 5 | 倒计时系统 | MVP | Core | systems-designer | S |
| 6 | NPC 状态机 | MVP | Core | systems-designer | M |
| 7 | 交互系统 | MVP | Core | systems-designer + godot-specialist | M |
| 8 | 夜晚过渡控制器 | MVP | Core | systems-designer + godot-specialist | M |
| 9 | 事件调度器 | MVP | Core | systems-designer | S |
| 10 | 色彩积累 | MVP | Core | systems-designer + godot-shader-specialist | S |
| 11 | 线索发现 | MVP | Feature | systems-designer | S |
| 12 | 线索连接/推理 | MVP | Feature | systems-designer | L |
| 13 | 洞察生成 | MVP | Feature | systems-designer | M |
| 14 | NPC 信任/怀疑 | MVP | Feature | systems-designer | M |
| 15 | 条件性对话树 | MVP | Feature | systems-designer | L |
| 16 | 住客审问 | MVP | Feature | systems-designer | M |
| 17 | 笔记本系统 | MVP | Feature | systems-designer | M |
| 18 | 水墨视觉风格 | MVP | Presentation | godot-shader-specialist | M |
| 19 | 计时器/HUD UI | MVP | Presentation | godot-specialist | S |
| 20 | 对话 UI | MVP | Presentation | godot-specialist | S |
| 21 | 笔记本 UI | MVP | Presentation | godot-specialist | M |
| 22 | 房间导航 UI | MVP | Presentation | godot-specialist | S |
| 23 | 结局触发逻辑 | MVP | Feature | systems-designer | S |
| 24 | 音频系统 | Vertical Slice | Presentation | sound-designer + godot-specialist | M |
| 25 | 多结局 | Vertical Slice | Polish | systems-designer | S |

> Effort: S = 1 session, M = 2-3 sessions, L = 4+ sessions.

### GDD 设计备忘（来自总监审查）

**循环状态管理 GDD 需包含**：
- `advance_night()` 契约——夜晚重置的原子性操作（TD Concern #6）
- **选择后果映射**——明确拥有"行动 X → 跨循环持久后果 Y"的追踪职责（CD Concern #3）

**线索数据库 GDD 需包含**：
- 统一 schema——同时容纳"发现的线索"和"生成的洞察"（TD Concern #1）
- **线索再解释行为**——"当洞察 X 触发时，线索 Y 获得新上下文"的 `contextual_unlocks` 机制（CD Concern #2）

**倒计时系统或事件调度器 GDD 需包含**：
- **节奏规则**——低语/咆哮的触发条件。MVP 简化为 3 个预定义压力峰值 + 喘息窗口（CD Concern #1）

**交互系统 GDD 需包含**：
- 窄契约——事件总线模式，只负责交互检测和分发，不负责后果逻辑（TD Concern #2）

**NPC 信任/怀疑 GDD 需包含**：
- 信任变化时序——实时反映还是对话结束后应用（TD Concern #4）

**色彩积累**：
- 已从功能层提升至核心层（CD Concern #4）。GDD 需明确是洞察状态的派生视图还是独立累加器（TD Concern #3）
| 24 | 音频系统 | Vertical Slice | Presentation | sound-designer + godot-specialist | M |
| 25 | 多结局 | Vertical Slice | Polish | systems-designer | S |

> Effort: S = 1 session, M = 2-3 sessions, L = 4+ sessions.

---

## Circular Dependencies

未发现循环依赖。依赖关系为严格的单向分层。

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| 循环状态管理 | Technical | 最高瓶颈系统——6+ 个系统依赖它。架构设计错误影响面极大。 | 在写任何游戏代码前完成 ADR 和原型验证。 |
| 条件性对话树 | Scope | 5 住客 x 7 夜 x 跨循环状态条件 = 大量分支。自建系统风险高。 | 使用 Dialogic 或 Ink 插件，不自建对话引擎。 |
| 线索连接/推理 | Design | "连接产生洞察"的交互方式需要原型验证。拖拽式 vs 对话式 vs 自动检测尚未决定。 | MVP 前原型验证至少一种连接方式。 |
| 水墨视觉风格 | Technical | 80% 正确的水墨着色器看起来 0% 艺术感。着色器质量门槛高。 | 着色器原型已完成（prototypes/ink-wash-shader/）。风险已降低。 |
| NPC 信任/怀疑 | Design | 信任变化在对话中实时反映还是对话结束后应用？接口契约需明确。 | GDD 中明确时序和传播机制（TD Concern #4）。 |

---

## Architectural Notes (from Director Reviews)

> **TD-SYSTEM-BOUNDARY**: CONCERNS (accepted) 2026-05-14 — 6 项边界细节需在 GDD 编写阶段解决：
> 1. 洞察是否写回线索数据库——在 Clue Database GDD 中定义统一 schema
> 2. 交互系统应为事件总线而非上帝对象——在 Interaction System GDD 中定义窄契约
> 3. 色彩积累层级位置待评估——GDD 阶段决定是否移至 Core Layer
> 4. NPC 信任→对话传播时序——在 NPC Trust GDD 中明确
> 5. 时间循环探索为整合场景，不写 GDD
> 6. 夜晚重置原子性——循环状态管理 GDD 提供 `advance_night()` 契约

> **PR-SCOPE**: OPTIMISTIC (accepted) 2026-05-14 — MVP 延长至 4 周（从 2-3 周调整）。

> **CD-SYSTEMS**: CONCERNS (accepted) 2026-05-14 — 4 项支柱交付缺口已修正：
> 1. 节奏规则已分配给倒计时/事件调度器 GDD（支柱 2 交付机制）
> 2. 线索再解释行为已分配给线索数据库 GDD（支柱 3 交付机制）
> 3. 选择后果映射已分配给循环状态管理 GDD（核心幻想交付机制）
> 4. 色彩积累已从功能层提升至核心层（视觉支柱交付机制）

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 24 + 1 integration scenario |
| Systems implemented | 12 (Foundation + Core + Feature layers) |
| Design docs started | 14 |
| Design docs reviewed | 1 |
| Design docs approved | 0 |
| MVP systems designed | 12 / 23 |
| MVP systems implemented | 12 / 23 |
| Vertical Slice systems designed | 0 / 2 |

---

## Next Steps

- [ ] 审核并批准此系统枚举
- [ ] 为循环状态管理编写 ADR（架构决策记录）——在写任何游戏代码前完成
- [ ] 设计 MVP 级系统（使用 `/design-system [system-name]`）
- [ ] 每完成一个 GDD 后运行 `/design-review design/gdd/[system].md`
- [ ] 所有 MVP GDD 完成后运行 `/gate-check pre-production`
- [ ] 高风险系统原型验证：`/prototype clue-connection`（推理交互方式）
