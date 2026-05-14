# ADR-0002: Knowledge Color Accumulation

## Status
Accepted

## Date
2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Rendering |
| **Knowledge Risk** | HIGH — Godot 4.6 is post-LLM-cutoff |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, prototypes/ink-wash-shader/REPORT.md, design/art/art-bible.md, design/gdd/systems-index.md |
| **Post-Cutoff APIs Used** | None — uses standard GDScript and shader uniforms |
| **Verification Required** | Verify per-NPC saturation override works with ADR-0001's ink wash shader (may require shader modification to accept per-NPC uniform data) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (ink-wash-shader-pipeline) — defines the shader pipeline that consumes knowledge_level |
| **Enables** | System #16 (色彩积累), System #18 (水墨视觉风格), System #19 (计时器/HUD UI) |
| **Blocks** | System #16 (色彩积累), all Presentation-layer systems that use knowledge-driven color |
| **Ordering Note** | Must be Accepted before GDD design of System #16 (色彩积累). Resolves TD-SYSTEM-BOUNDARY Concern #3. |

## Context

### Problem Statement

七夜的视觉身份核心是"知识 = 色彩"。玩家每发现一个真相，世界永久增加颜色。需要决定：(1) 色彩积累是洞察系统的派生视图还是独立的累加器？(2) 每位住客的颜色饱和度如何计算？(3) 线索连接产生的洞察如何用颜色表达？(4) 全局 vs 局部色彩恢复的比例？

### Constraints

- 色彩积累必须实时反映在渲染中（ADR-0001 的着色器管线）
- 5 位住客各有独特颜色（靛蓝、赭石、朱砂、青瓷、梅紫）
- 第 6 种颜色（藤黄）用于线索连接/洞察
- 幼者（Child）使用铅白（纸色——有意设计例外）
- 色彩积累不可逆——一旦获得知识，颜色永不消退
- 必须跨循环持久（循环重置不影响色彩）

### Requirements

- 全局 knowledge_level 驱动着色器的整体色彩恢复（ADR-0001）
- 每-NPC 颜色饱和度独立于全局 level
- 线索连接/洞察产生的藤黄色有其独立的强度计算
- 色彩数据必须可序列化（存档/读档系统）
- 颜色变化应有可见的过渡动画（非瞬间切换）

## Decision

**色彩积累是洞察系统的派生视图，不是独立累加器。** KnowledgeManager 从 InsightGenerator 和 ClueDatabase 读取数据，计算色彩参数，传递给 ADR-0001 定义的着色器管线。

### Architecture Diagram

```
┌─────────────┐     ┌──────────────┐     ┌──────────────────┐
│ ClueDatabase│────▶│InsightGenerator│───▶│KnowledgeManager  │
│ (线索+洞察)  │     │(连接→洞察)    │     │(派生计算)         │
└─────────────┘     └──────────────┘     └────────┬─────────┘
                                                   │
                                          ┌────────▼─────────┐
                                          │  色彩参数计算      │
                                          │                   │
                                          │ global_knowledge  │
                                          │ npc_saturation[]  │
                                          │ connection_gold   │
                                          └────────┬─────────┘
                                                   │ signals
                    ┌──────────────────────────────┼──────────────────┐
                    │                              │                  │
          ┌─────────▼──────────┐      ┌───────────▼────────┐  ┌──────▼──────┐
          │ InkWashShader      │      │ NPC Sprite Tint    │  │ Notebook UI │
          │ knowledge_level    │      │ per-NPC saturation │  │ connection  │
          │ (ADR-0001)         │      │                    │  │ gold lines  │
          └────────────────────┘      └────────────────────┘  └─────────────┘
```

### Color Accumulation Formulas

**1. 全局知识水平 (Global Knowledge Level)**:
```
knowledge_level = total_insights_generated / max_possible_insights
Range: 0.0 to 1.0
```

**2. 每位住客颜色饱和度 (Per-NPC Color Saturation)**:
```
npc_saturation[npc_id] = 0.10 + ((discoveries_for_npc / total_secrets_for_npc) * 0.90)
Range: 0.10 (always visible as faint tint) to 1.00 (full saturation)
```

**3. 连接/洞察藤黄强度 (Connection Gold Ochre Intensity)**:
```
connection_intensity = 0.40 + ((connections_made / total_possible_connections) * 0.60)
Range: 0.40 (base visibility) to 1.00 (full gold)
```

### Six Knowledge Colors

| Color | Hex | Role | Source System |
|-------|-----|------|---------------|
| 朱砂 Cinnabar | `#B22222` | 系统/UI 反馈 | KnowledgeManager (global) |
| 靛蓝 Indigo | `#3F51B5` | 观察者 (Watcher) | NPC discoveries |
| 赭石 Umber | `#A0522D` | 守门人 (Keeper) | NPC discoveries |
| 青瓷 Celadon | `#7DB9B6` | 倾听者 (Listener) | NPC discoveries |
| 梅紫 Plum Purple | `#8E4585` | 醉酒者 (Drunk) | NPC discoveries |
| 藤黄 Gold Ochre | `#CC7722` | 洞察/连接 | Clue connections |

**幼者 (Child)**: 铅白 Lead White `#E8E0D4` — 纸色，有意设计例外。

### Key Interfaces

**KnowledgeManager (Autoload Singleton)**:
```gdscript
class_name KnowledgeManager
extends Node

signal knowledge_level_changed(new_level: float)
signal npc_color_updated(npc_id: StringName, saturation: float)
signal connection_intensity_changed(intensity: float)

var knowledge_level: float = 0.0
var npc_saturations: Dictionary = {}
var connection_intensity: float = 0.0

func get_npc_saturation(npc_id: StringName) -> float
func get_npc_color(npc_id: StringName) -> Color
func get_connection_color() -> Color
```

**State Ownership**:
- `knowledge_level` — owned by knowledge-color-system, derived from InsightGenerator
- `npc_saturations` — owned by knowledge-color-system, derived from ClueDatabase
- `connection_intensity` — owned by knowledge-color-system, derived from ClueConnection counts

**Save/Load**: Persists underlying data (insights, discoveries, connections), NOT derived values.

## Alternatives Considered

### Alternative 1: Independent Accumulator

- **Description**: KnowledgeManager maintains own discovery counter independent of insight/clue systems
- **Pros**: Simpler mental model; accumulates from any source
- **Cons**: Data duplication; sync bugs; stale data risk
- **Rejection Reason**: TD-SYSTEM-BOUNDARY Concern #3 resolved for derived view. Single source of truth prevents sync bugs.

### Alternative 2: Per-Discovery Color Events

- **Description**: Each discovery emits a signal with color; shader accumulates over time
- **Pros**: Organic accumulation; unique color patterns per playthrough
- **Cons**: Non-deterministic visual state; hard to serialize; shader complexity
- **Rejection Reason**: Predictable visuals needed for QA. Formula-based ensures identical playthroughs look identical.

### Alternative 3: Fixed Knowledge Gates

- **Description**: Color unlocks at fixed thresholds (3 insights = +10%)
- **Pros**: Simple; predictable pacing
- **Cons**: Discrete jumps; doesn't reflect per-NPC depth
- **Rejection Reason**: Continuous formula matches art bible's "色彩逐渐丰富" direction.

## Consequences

### Positive

- Single source of truth — InsightGenerator owns data; KnowledgeManager derives color
- Cross-loop persistence automatic — if insights persist, color persists
- Per-NPC saturation gives individual visual feedback for each character arc
- Gold ochre connections make clue-linking visually rewarding
- Formulas transparent and tunable

### Negative

- KnowledgeManager depends on InsightGenerator and ClueDatabase schemas
- Per-NPC tinting may require shader changes to ADR-0001
- Lead White child creates explicit exception needing test coverage

### Risks

- **Per-NPC shader support**: ADR-0001 uses single global knowledge_level. Per-NPC may need lookup texture or additional uniforms. Mitigation: start global for MVP; add per-NPC in production.
- **Formula tuning**: 10%/40% base values are estimates. Mitigation: expose as TuningKnobs in GDD.
- **Color explosion**: Too many colors at high knowledge could look chaotic. Mitigation: cap saturation at 90%; ensure shared ink-wash undertone.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-concept.md | Pillar 1: 知识 = 色彩 | knowledge_level drives color restoration formula |
| game-concept.md | Pillar 3: 连接比线索更有力 | Gold ochre color rewards connections specifically |
| game-concept.md | Pillar 4: 每个住客有要守护的秘密 | Per-NPC saturation reflects secret-discovery progress |
| art-bible.md Sec 1 | 知识着色原则 | Derivation ensures every color maps to a specific discovery |
| art-bible.md Sec 4 | 六种知识色 | All 6 colors defined with hex values and roles |
| art-bible.md Sec 4 | 住客饱和度公式 | `10% + (discoveries/total * 90%)` formula |
| systems-index.md | TD Concern #3 | Resolves: derived view, not independent |
| systems-index.md | CD Concern #4 | Resolves: color accumulation in Core layer |

## Performance Implications

- **CPU**: One dictionary lookup per NPC per frame (~5 lookups). Trivial.
- **Memory**: ~100 bytes for color state.
- **GPU**: No direct GPU impact — formulas produce uniform values for ADR-0001 shader.
- **Network**: N/A

## Migration Plan

Not applicable — new system. For MVP: implement global knowledge_level only. Per-NPC tinting is production enhancement.

## Validation Criteria

1. knowledge_level = 0.0 when no insights; = 1.0 when all found
2. NPC saturation starts at 10%; reaches 100% when all secrets discovered
3. Connection gold starts at 40%; reaches 100% when all connections made
4. Knowledge persists across loop resets
5. Color changes animated (target 0.5s transition)
6. Lead White child unaffected by color accumulation

## Related Decisions

- ADR-0001: Ink Wash Shader Pipeline — consumes knowledge_level uniform
- Art Bible Section 1: Visual Identity Statement
- Art Bible Section 4: Color System
- Art Bible Section 5: Character Design
- Systems Index: System #16 (色彩积累)
