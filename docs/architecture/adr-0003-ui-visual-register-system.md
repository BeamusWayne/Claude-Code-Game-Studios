# ADR-0003: UI Visual Register System

## Status
Accepted

## Date
2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI |
| **Knowledge Risk** | HIGH — Godot 4.6 is post-LLM-cutoff |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, docs/engine-reference/godot/breaking-changes.md, design/art/art-bible.md Section 7 |
| **Post-Cutoff APIs Used** | Dual-focus system (4.6) — mouse/touch focus separate from keyboard/gamepad. FoldableContainer (4.5) for collapsible notebook sections. |
| **Verification Required** | Test dual-focus for HUD seal buttons. Test touch on mobile for dialogue. Test FoldableContainer for notebook pages. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (ink-wash-shader-pipeline) — defines CanvasLayer ordering |
| **Enables** | System #19 (计时器/HUD UI), System #20 (对话 UI), System #21 (笔记本 UI), System #22 (房间导航 UI) |
| **Blocks** | All Presentation-layer UI systems (#19-22) |
| **Ordering Note** | Must be Accepted before UI GDD design. ADR-0001 must be Accepted first. |

## Context

### Problem Statement

七夜的 UI 需要在水墨画视觉风格内呈现游戏信息。美术圣经定义了两个视觉语域：语域 A（笔记本——楷体、宣纸、手写感）和语域 B（HUD——仿宋、印章、系统信息）。需要决定 UI 架构如何实现双语域系统，同时确保移动端兼容性和无障碍性。

### Constraints

- 所有 UI 同时支持鼠标和触摸
- 无 hover-only 交互
- HUD 在 CanvasLayer 30+ 渲染
- 目标 60fps，UI draw calls ≤8
- 对话是独立游戏状态
- 笔记本是全屏宣纸覆盖

### Requirements

- 两种语域有明确的字体、风格和交互差异
- 计时器以朱砂印章呈现，开裂表示时间流逝
- 夜晚计数器以纵向印章柱呈现
- 对话面板底部 30%，NPC 文字用住客颜色
- 笔记本全屏宣纸，翻页和搜索
- 移动端替代 hover 的被动可发现性

## Decision

双语域 UI 架构，CanvasLayer 分层 + UIManager 状态管理。

### Architecture Diagram

```
CanvasLayer 30: HUD (语域 B — FangSong / Seal Stamps)
┌──────────────────────────────────────────────────────┐
│ ┌─────┐                                    ┌───────┐ │
│ │Night│                                    │Timer  │ │
│ │Pillar│                                   │Seal   │ │
│ │  ▓  │                                    │ ◇→◈  │ │
│ │  ▓  │                                    │click→ │ │
│ │  ░  │                                    │count  │ │
│ │  ░  │                                    │down   │ │
│ └─────┘                                    └───────┘ │
│       [交互提示 — 朱砂墨水小注]                         │
└──────────────────────────────────────────────────────┘

CanvasLayer 40: Dialogue (独立游戏状态)
┌──────────────────────────────────────────────────────┐
│    Scene darkens 70%, NPC color blooms                │
│  ┌──────────────────────────────────────────────────┐│
│  │  宣纸 panel (bottom 30%), NPC text in guest color ││
│  │  Player options as seal buttons (min 44px)        ││
│  │  [结束对话] always visible                         ││
│  └──────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────┘

CanvasLayer 50: Notebook (语域 A — KaiTi / Xuan Paper)
┌──────────────────────────────────────────────────────┐
│  Full-screen 宣纸, fiber texture                      │
│  楷体 entries, gold ochre connection lines            │
│  Page-based (8-12 clues/page), wet-finger search     │
│  Mobile: tap-select, tap-connect, pinch-zoom 2.5x    │
└──────────────────────────────────────────────────────┘
```

### CanvasLayer Ordering

| Layer | Content | Register |
|-------|---------|----------|
| 0-9 | Game scene | — |
| 10 | Ink wash post-process | — |
| 20 | Rain overlay | — |
| 30 | HUD | B |
| 40 | Dialogue panel | B+A |
| 50 | Notebook | A |
| 60 | Discovery notifications | B |

### Key Interfaces

**UIManager (Autoload)**:
```gdscript
class_name UIManager
extends Node

enum Register { NOTEBOOK, HUD }

signal notebook_opened
signal notebook_closed
signal dialogue_started(npc_id: StringName)
signal dialogue_ended
signal hud_element_activated(element: StringName)

var active_register: Register = Register.HUD
var is_dialogue_active: bool = false
var is_notebook_open: bool = false

func open_notebook() -> void
func close_notebook() -> void
func start_dialogue(npc_id: StringName) -> void
func end_dialogue() -> void
func show_discovery_notification(clue_id: StringName) -> void
```

**Timer Seal**:
- Idle: micro-breathing (2-3px oscillation, 4s cycle)
- Click/tap: show ink countdown (3s fadeout)
- Whisper: hairline cracks
- Roar: shattering
- Audio: 5min/2min/1min/30s chimes

**Dialogue State**:
- Scene darkens 70%, NPC color blooms
- Timer continues at 50% speed
- Bottom 30% 宣纸 panel
- NPC text in guest color
- Player options as seal buttons (min 44px)
- "End dialogue" always visible
- Notebook openable during dialogue

## Alternatives Considered

### Alternative 1: Single Register

- **Description**: All UI uses one visual language
- **Pros**: Simpler; one font pipeline
- **Cons**: Loses in-world vs system distinction
- **Rejection Reason**: Dual register is core art direction. Notebook is a physical game object; HUD is meta-knowledge.

### Alternative 2: Diegetic-Only UI

- **Description**: Timer is wall clock, notebook is physical object
- **Pros**: Maximum immersion
- **Cons**: Timer readability; accessibility; mobile touch targets
- **Rejection Reason**: UX flags readability issues. Hybrid balances immersion with usability.

### Alternative 3: Standard UI With Ink Theme

- **Description**: Rectangular panels with ink texture
- **Pros**: Fastest; standard Godot patterns
- **Cons**: Generic; loses seal-stamp identity
- **Rejection Reason**: Contradicts approved art bible Section 7.

## Consequences

### Positive

- Clear visual distinction between in-world and meta information
- Seal-stamp HUD is unique and thematically consistent
- Dialogue as game state gives appropriate visual weight
- CanvasLayer ordering ensures UI never ink-washed
- Mobile adaptations designed from start

### Negative

- Two font pipelines add ~40MB (Chinese character sets)
- Custom SVG seal icons needed per HUD element
- Dialogue state requires careful game state management
- Notebook overlay adds draw calls when open

### Risks

- **Font legibility**: FangSong at 10-14px may be illegible. Mitigation: 14px minimum for readable text.
- **Seal animation complexity**: Complex effect on small element. Mitigation: sprite sheet animation, not shader.
- **Mobile touch targets**: Mitigation: all interactive seals 48px+.
- **Notebook performance**: Mitigation: lazy-load pages, render visible page only.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-concept.md | 笔记本跨循环持久 | Register A reads from persistent ClueDatabase |
| game-concept.md | Pillar 2: 时间在低语与咆哮之间交替 | Timer seal cracking + audio cues at thresholds |
| game-concept.md | Pillar 3: 连接比线索更有力 | Gold ochre connection lines in notebook |
| art-bible.md Sec 7 | 双语域 UI | Two registers with distinct fonts, styles, interactions |
| art-bible.md Sec 7 | 对话独立游戏状态 | CanvasLayer 40 with scene darkening and timer slowdown |
| art-bible.md Sec 7 | 移动端湿光泽 | Items flash wet sheen every 8-10s |
| art-bible.md Sec 7 | 无障碍 | High-contrast mode, audio cues, colorblind backup |
| technical-preferences.md | 触摸 Full | All interactions touch-friendly; no hover-only |

## Performance Implications

- **CPU**: UI state trivial; dialogue transition ~1ms
- **Memory**: Two CJK fonts (~40MB), 宣纸 texture ~0.7MB
- **GPU**: HUD 5-8 draw calls; Dialogue 3-5; Notebook 8-12 (one page)
- **Load Time**: Font loading ~200ms at startup

## Migration Plan

New system. Implementation order: CanvasLayer framework → HUD → Dialogue → Notebook.

## Validation Criteria

1. HUD readable against ink-wash with backplate (contrast ≥4.3:1)
2. Timer seal shows correct time on click/tap
3. Night counter displays past/current/future
4. Dialogue enters cleanly (1.0s), NPC text in guest color
5. Notebook opens/closes correctly (0.5s / 0.3s)
6. All interactive elements ≥44px touch target
7. No hover-only interactions
8. High-contrast mode switches to white ink + dark backplate

## Related Decisions

- ADR-0001: Ink Wash Shader Pipeline — CanvasLayer ordering
- ADR-0002: Knowledge Color Accumulation — NPC colors in dialogue/notebook
- Art Bible Section 7: UI/HUD Visual Direction
- Art Bible Section 4: Color System
- Technical Preferences: Input & Platform
