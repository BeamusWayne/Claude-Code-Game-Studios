# Master Architecture Document

**Project**: 七夜 (Seven Nights) — Ink Wash Mystery Adventure
**Engine**: Godot 4.6 (pinned 2026-02-12)
**Last Updated**: 2026-05-14
**Architecture Review**: docs/architecture/architecture-review-2026-05-14.md

---

## System Layers

```
┌─────────────────────────────────────────────────────┐
│                   PRESENTATION                      │
│  UI Manager · Notebook · HUD · Dialogue · Menus     │
├─────────────────────────────────────────────────────┤
│                     FEATURE                         │
│  NPC AI · Dialogue Trees · Trust · Night Transition │
├─────────────────────────────────────────────────────┤
│                      CORE                           │
│  Clue DB · Knowledge · Timer · Room · Save/Load     │
├─────────────────────────────────────────────────────┤
│                   FOUNDATION                        │
│  Loop State · Interaction Bus · Ink Wash Shaders    │
└─────────────────────────────────────────────────────┘
```

Each layer depends only on layers below it. No upward imports from Foundation to Feature/Presentation.

---

## Autoload Registration Order

Singletons initialize in this order. Later singletons may reference earlier ones during `_ready()`.

| # | Name | Script | ADR | State Owned |
|---|------|--------|-----|-------------|
| 1 | LoopStateManager | `src/core/loop_state_manager.gd` | ADR-0004 | Night index, phase, active state, delta accumulator |
| 2 | InteractionBus | `src/core/interaction_bus.gd` | ADR-0006 | Event queue, subscriber registry |
| 3 | ClueDatabase | `src/core/clue_database.gd` | ADR-0005 | Knowledge entries, connections |
| 4 | KnowledgeManager | `src/core/knowledge_manager.gd` | ADR-0002 | Color accumulation map, insight registry |
| 5 | UIManager | `src/ui/ui_manager.gd` | ADR-0003 | Screen stack, visual register state |
| 6 | RoomManager | `src/core/room_manager.gd` | ADR-0007 | Current room, transition state |
| 7 | TimerService | `src/gameplay/timer_service.gd` | ADR-0008 | Countdown state, rhythm phase |
| 8 | NPCManager | `src/gameplay/npc_manager.gd` | ADR-0009 | NPC states, location assignments |
| 9 | TrustManager | `src/gameplay/trust_manager.gd` | ADR-0012 | Trust/suspicion levels per NPC |
| 10 | SaveManager | `src/persistence/save_manager.gd` | ADR-0010 | Save slots, dirty flags |
| 11 | NightTransitionController | `src/core/night_transition_controller.gd` | ADR-0011 | Transition phase, orchestration state |
| 12 | DialogueManager | `src/narrative/dialogue_manager.gd` | ADR-0013 | Active dialogue tree, node position |

---

## CanvasLayer Stack

Lower numbers render behind higher numbers.

| Layer | Name | Content | ADR |
|-------|------|---------|-----|
| 10 | Ink Wash | Post-process shader (paper grain, ink density, dry brush) | ADR-0001 |
| 20 | Rain | Weather particle effects | — |
| 30 | HUD | Time, suspicion gauge, seal-stamp notifications | ADR-0003 |
| 40 | Dialogue | Dialogue box, speaker portrait, choices | ADR-0013 |
| 50 | Notebook | Clue grid, connection board, insight journal | ADR-0003 |
| 60 | Notifications | Toast-style knowledge gain alerts | ADR-0003 |
| 100 | Fade Overlay | Ink-wash transition animation (RoomManager controls) | ADR-0007 |

---

## State Ownership Registry

Each piece of game state has exactly one authority. Other systems read via signals or API calls.

| State | Authority | Persistence | Resets Nightly? |
|-------|-----------|-------------|-----------------|
| Night index / phase | LoopStateManager | DeltaAccumulator | No (advances) |
| Room occupancy | RoomManager | NightTemplate → re-instantiated | Yes (template reset) |
| NPC position / state | NPCManager | DeltaAccumulator | Yes (template reset) |
| Trust / suspicion | TrustManager | DeltaAccumulator | No (cross-loop persistent) |
| Clue entries | ClueDatabase | Persistent file | No (cross-loop persistent) |
| Knowledge colors | KnowledgeManager | Derived from ClueDatabase | No (derived) |
| Countdown timer | TimerService | NightTemplate | Yes (template reset) |
| Dialogue state | DialogueManager | Ephemeral | N/A (session-scoped) |
| Save slots | SaveManager | Persistent file | On load |
| UI screen stack | UIManager | Ephemeral | N/A (session-scoped) |

---

## Signal Architecture

Key cross-system signal flows:

```
LoopStateManager
  ├─→ night_advanced ─→ RoomManager._pending_reset
  │                  ─→ NPCManager._reset_night_states
  │                  ─→ TimerService._start_countdown
  │                  ─→ SaveManager._auto_save
  │
  └─→ night_ready ──→ RoomManager._apply_pending_reset
                    ─→ UIManager._show_night_banner

InteractionBus
  └─→ interaction_occurred ─→ ClueDatabase._check_unlock
                            ─→ DialogueManager._trigger_contextual
                            ─→ KnowledgeManager._evaluate_insight

ClueDatabase
  └─→ knowledge_gained ─→ KnowledgeManager._accumulate_color
                       ─→ UIManager._show_notification

KnowledgeManager
  └─→ insight_generated ─→ ClueDatabase._add_contextual_unlock
                        ─→ UIManager._flash_insight_effect

RoomManager
  └─→ room_changed ─→ NPCManager._update_npc_locations
                    ─→ UIManager._update_minimap
```

---

## ADR Dependency Graph

```
Foundation (no dependencies):
  ADR-0001: Ink Wash Shader Pipeline
  ADR-0004: Loop State Management
  ADR-0006: Interaction Event Bus

Depends on Foundation:
  ADR-0002: Knowledge Color Accumulation (requires ADR-0001, ADR-0004)
  ADR-0005: Clue/Insight Unified Schema (requires ADR-0004)
  ADR-0007: Room/Location Management (requires ADR-0004, ADR-0006)
  ADR-0008: Countdown Timer System (requires ADR-0004)
  ADR-0010: Save/Load Persistence (requires ADR-0004)

Depends on Core:
  ADR-0003: UI Visual Register System (requires ADR-0002, ADR-0005)
  ADR-0009: NPC State Machine (requires ADR-0007)
  ADR-0011: Night Transition Controller (requires ADR-0004, ADR-0008)
  ADR-0012: NPC Trust/Suspicion (requires ADR-0009)
  ADR-0013: Conditional Dialogue Trees (requires ADR-0009, ADR-0012)
```

---

## Known Issues (Non-Blocking)

1. **TR-concept-010 (Cross-Platform)**: No dedicated platform/export ADR. Godot handles cross-platform export natively; export configuration is project setup, not architecture. Priority: LOW.

2. **ADR-0006 vs ADR-0007 (Interactable Registration)**: RoomManager owns Interactable lifecycle, but InteractionBus subscribes to their signals. Registration order matters — RoomManager must complete POST_LOAD before InteractionBus processes events. Addressed via signal deferral in ADR-0007 step 5. Priority: MEDIUM (documented workaround).

3. **ADR-0004 Interface vs GDD**: LoopStateManager public API has minor naming differences from loop-state-management GDD. GDD is authoritative; implementation should match GDD naming at coding time. Priority: LOW.

4. **HUD Seal Routing (ADR-0003 vs ADR-0005)**: Knowledge gain notifications could route through either KnowledgeManager or ClueDatabase depending on entry type. UIManager should subscribe to both signals and deduplicate. Priority: LOW.

---

## Related Documents

| Document | Path | Purpose |
|----------|------|---------|
| Architecture Review | `docs/architecture/architecture-review-2026-05-14.md` | Traceability, conflict analysis, engine audit |
| Traceability Index | `docs/architecture/traceability-index.md` | GDD requirement → ADR coverage matrix |
| TR Registry | `docs/architecture/tr-registry.yaml` | Stable requirement IDs (TR-[system]-NNN) |
| ADR Index | `docs/registry/architecture.yaml` | All ADR metadata and status |
| Engine Reference | `docs/engine-reference/godot/VERSION.md` | Version pin, knowledge gaps, breaking changes |
| Technical Preferences | `.claude/docs/technical-preferences.md` | Naming, performance budgets, forbidden patterns |
| Systems Index | `design/gdd/systems-index.md` | All systems, priority tiers, GDD links |
