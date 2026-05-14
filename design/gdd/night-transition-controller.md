# 夜晚过渡控制器 (Night Transition Controller)

## 1. Overview

夜晚过渡控制器协调从一个夜晚到下一个夜晚的完整过渡序列。NightTransitionController Autoload 单例按固定顺序编排 8 个阶段：保存存档 → 停止计时器 → 淡出画面 → 推进夜晚 → 重新初始化系统 → 淡入画面 → 重启计时器 → 完成。控制器不持有游戏状态，仅负责编排和错误恢复。它处理阻断条件（对话进行中、房间切换中），在第 7 夜触发游戏结局。

## 2. Player Fantasy

**"黎明前的黑暗"** — 当倒计时归零，世界并没有突然结束。画面缓缓暗下，雨声渐弱，然后——一切重来。但玩家知道，这一次带着上一夜的记忆。夜晚过渡是「七夜」循环感的物理体现：不是失败后的重试，而是带着新知重新出发。每一次过渡都让玩家更接近真相。

## 3. Detailed Rules

### 3.1 过渡阶段序列

| 阶段 | 名称 | 操作 | 可失败 |
|------|------|------|--------|
| 1 | SAVE | SaveManager.save_game() | 是 |
| 2 | STOP_TIMER | TimerService.stop_timer() | 否 |
| 3 | FADE_OUT | RoomManager.fade_out() | 否 |
| 4 | ADVANCE_NIGHT | LoopStateManager.advance_night() | 是 |
| 5 | REINIT_SYSTEMS | NPCManager.reset_templates(), RoomManager.load_room() | 否 |
| 6 | FADE_IN | RoomManager.fade_in() | 否 |
| 7 | START_TIMER | TimerService.start_night_timer() | 否 |
| 8 | COMPLETE | 发出 transition_complete 信号 | 否 |

- 每个阶段必须在前一阶段完成后才开始
- 阶段 1 (SAVE) 和阶段 4 (ADVANCE_NIGHT) 可以失败并触发回滚
- 阶段序列不可跳过、不可重排

### 3.2 触发条件

夜晚过渡由以下任一条件触发：
1. **计时器归零**：TimerService 发出 `night_timer_ended` 信号
2. **玩家主动结束**：UI 中的"结束今夜"按钮
3. **脚本触发**：特定剧情事件强制推进

所有触发条件最终调用 `NightTransitionController.start_transition()`。

### 3.3 阻断条件

以下条件会阻止过渡开始：

| 条件 | 检查方式 | 用户反馈 |
|------|---------|---------|
| 对话进行中 | UIManager.is_dialogue_active() | "请先结束对话" |
| 房间切换中 | RoomManager.is_transitioning | 等待切换完成 |
| 已在过渡中 | is_transitioning 标志 | 忽略重复触发 |
| 第 7 夜已完成 | current_night >= MAX_NIGHTS | 触发结局 |

阻断条件在 `start_transition()` 入口处检查，不排队等待。

### 3.4 错误恢复

| 失败阶段 | 恢复策略 |
|---------|---------|
| SAVE 失败 | 跳过保存（非阻断），继续过渡。发出 `save_failed_during_transition` 警告信号 |
| ADVANCE_NIGHT 失败 | 中止过渡。淡入画面恢复。发出 `transition_failed` 信号，附带失败原因 |
| REINIT 系统失败 | 记录错误日志，继续过渡。单个系统失败不阻断整体流程 |

### 3.5 第 7 夜结局

- 当 `LoopStateManager.current_night == MAX_NIGHTS (7)` 且 `advance_night()` 被调用时
- NightTransitionController 不执行常规过渡
- 改为发出 `game_ending_triggered` 信号
- UIManager 负责显示结局画面（不在本系统范围内）

### 3.6 夜晚过渡期间的时间缩放

- 过渡开始时，TimerService 已停止（阶段 2），不存在 time_scale 问题
- 过渡完成后，TimerService 重启（阶段 7），time_scale 恢复为 1.0
- 对话期间的 time_scale = 0.5 由 TimerService 自行管理，不通过本控制器

### 3.7 序列化

- NightTransitionController 不持有需要序列化的状态
- 过渡进度不持久化——如果游戏在过渡期间被中断：
  - 读档时 LoopStateManager 恢复到上一个完整保存的夜晚
  - 不恢复"过渡中"的中间状态

## 4. Formulas

### 过渡总时长

```
transition_duration = FADE_OUT_DURATION + PROCESSING_BUFFER + FADE_IN_DURATION
// 默认: 1.0 + 0.5 + 1.0 = 2.5 秒
```

### 阶段超时

```
SAVE_TIMEOUT = 3.0     // 秒
FADE_TIMEOUT = 2.0     // 秒（每个淡入/淡出）
ADVANCE_TIMEOUT = 1.0  // 秒
REINIT_TIMEOUT = 2.0   // 秒
```

### 第 7 夜判定

```
is_final_night = (current_night >= MAX_NIGHTS)
// MAX_NIGHTS = 7
```

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 计时器归零时对话正在进行 | 阻断——等待对话结束。计时器已停（归零），不继续消耗时间 |
| 房间切换中计时器归零 | 阻断——等待切换完成后再开始过渡 |
| 过渡期间收到第二次触发 | 忽略（is_transitioning = true） |
| SAVE 失败但 ADVANCE_NIGHT 成功 | 继续过渡，不回滚。保存失败是非阻断的 |
| ADVANCE_NIGHT 失败 | 中止过渡，淡入恢复，发出 transition_failed |
| 游戏在 FADE_OUT 期间被关闭 | 下次读档恢复到上一个完整保存的夜晚 |
| 第 7 夜玩家点"结束今夜" | 触发结局，不执行常规过渡序列 |
| REINIT 中 NPCManager 失败但 RoomManager 成功 | 记录 NPC 错误，继续过渡。NPC 状态可能不一致但不会卡住 |
| MAX_NIGHTS = 7 但存档中 current_night = 6 | 正常过渡到第 7 夜，不是结局 |
| 存档中 current_night = 7 | 读档后处于第 7 夜。当晚结束时触发结局 |

## 6. Dependencies

### 上游依赖
- **循环状态管理 (#1)** — `advance_night()`, `current_night`, `night_ready` 信号
- **存档/读档持久化 (#4)** — `SaveManager.save_game()`
- **倒计时系统 (#5)** — `TimerService.stop_timer()`, `start_night_timer()`, `night_timer_ended` 信号
- **房间/位置管理 (#3)** — `RoomManager.fade_out()`, `fade_in()`, `is_transitioning`
- **NPC 状态机 (#6)** — `NPCManager.reset_templates()`（模板层重置）
- **ADR-0011 夜晚过渡控制器** — 本系统的架构决策基础

### 下游被依赖
- **结局触发 (#23)** — 监听 `game_ending_triggered` 信号
- **UI 系统** — 监听过渡状态更新 UI（"正在过渡..."提示）
- **事件调度器 (#9)** — 监听 `transition_complete` 调度新夜事件

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| MAX_NIGHTS | int | 7 | 5-10 | 游戏总夜数 |
| FADE_OUT_DURATION | float | 1.0 | 0.5-3.0 | 淡出动画时长（秒） |
| FADE_IN_DURATION | float | 1.0 | 0.5-3.0 | 淡入动画时长（秒） |
| PROCESSING_BUFFER | float | 0.5 | 0.1-1.0 | 阶段间处理缓冲（秒） |
| SAVE_TIMEOUT | float | 3.0 | 1.0-10.0 | 保存操作超时（秒） |
| ADVANCE_TIMEOUT | float | 1.0 | 0.5-5.0 | 推进夜晚超时（秒） |
| REINIT_TIMEOUT | float | 2.0 | 1.0-5.0 | 系统重新初始化超时（秒） |
| save_on_transition | bool | true | — | 过渡时是否自动保存 |

## 8. Acceptance Criteria

1. 过渡序列按 8 个阶段严格顺序执行，不可跳过或重排
2. 计时器归零（night_timer_ended）触发过渡
3. 对话进行中时 start_transition() 被阻断，不进入过渡
4. 房间切换中时 start_transition() 被阻断
5. is_transitioning = true 时重复触发被忽略
6. SAVE 失败不阻断过渡，发出 save_failed_during_transition 信号
7. ADVANCE_NIGHT 失败中止过渡，淡入恢复，发出 transition_failed
8. 第 7 夜结束时发出 game_ending_triggered 而非常规过渡
9. 过渡完成后 TimerService 重启，time_scale = 1.0
10. 过渡完成后 NPCManager 模板层重置（emotional_state → NEUTRAL）
11. 过渡期间 InteractionBus 暂停事件分发
12. serialize/deserialize 不需要保存过渡状态
13. reset() 恢复到非过渡的初始状态

## Open Questions

- 过渡期间是否需要过渡动画（如水墨晕染效果）？还是简单的淡黑？
- 玩家是否可以在过渡期间跳过动画（点击/按键跳过淡入淡出）？
- 如果所有 7 夜都结束但玩家没有找到真相，是否触发默认结局？
- 过渡期间是否需要显示"第 N 夜"的文字提示？
