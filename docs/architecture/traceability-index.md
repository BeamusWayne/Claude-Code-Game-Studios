# Architecture Traceability Index

Last Updated: 2026-05-15
Engine: Godot 4.6
Review: Third (14 ADRs, 21 GDDs)

## Coverage Summary

- Total requirements: ~137
- Covered: ~108 (78.8%)
- Partial: ~9 (6.6%)
- Gaps: ~20 (14.6%)

## Full Matrix

| Requirement ID | GDD | System | Requirement | ADR Coverage | Status |
|---|---|---|---|---|---|
| TR-concept-001 | game-concept.md | Rendering | Ink wash rendering (paper grain, ink density, dry brush) | ADR-0001 | Covered |
| TR-concept-002 | game-concept.md | Core | Knowledge-driven dynamic color restoration | ADR-0002 | Covered |
| TR-concept-003 | game-concept.md | Rendering | Per-guest unique traditional colors (5 + gold) | ADR-0002 | Covered |
| TR-concept-004 | game-concept.md | Core | 7-night loop: scene resets, knowledge persists | ADR-0004 | Covered |
| TR-concept-005 | game-concept.md | Core | Player choices create lasting cross-loop changes | ADR-0004 | Covered |
| TR-concept-006 | game-concept.md | Gameplay | Countdown pressure with whisper/roar rhythm | ADR-0008 | Covered |
| TR-concept-007 | game-concept.md | Core | Clue connection/deduction with insight generation | ADR-0005 | Covered |
| TR-concept-008 | game-concept.md | Narrative | NPC interrogation + conditional dialogue trees | ADR-0012, ADR-0013 | Covered |
| TR-concept-009 | game-concept.md | Input | Point-and-click interaction model (mouse + touch) | ADR-0006 | Covered |
| TR-concept-010 | game-concept.md | Platform | Cross-platform (PC, macOS, mobile) | ADR-0003, ADR-0006 | Partial |
| TR-concept-011 | game-concept.md | Gameplay | Pressure rhythm phases (whisper/roar/transition) | ADR-0008 | Covered |
| TR-concept-012 | game-concept.md | Input | Touch-friendly all interactions | ADR-0003, ADR-0006 | Covered |
| TR-concept-013 | game-concept.md | UI | Dual visual register (notebook=KaiTi, HUD=FangSong) | ADR-0003 | Covered |
| TR-concept-014 | game-concept.md | Persistence | Save/load persistence with crash recovery | ADR-0010 | Covered |
| TR-concept-015 | game-concept.md | Core | Notebook persists across loops | ADR-0005 | Covered |
| TR-loop-001 | loop-state.md | Core | Three-layer state separation (Template/Active/Delta) | ADR-0004 | Covered |
| TR-loop-002 | loop-state.md | Core | Atomic advance_night() with 7-step rollback | ADR-0004 | Covered |
| TR-loop-003 | loop-state.md | Core | propose_delta() as sole mutation entry point | ADR-0004 | Covered |
| TR-loop-004 | loop-state.md | Core | Subsystem path registration (register_state_paths) | ADR-0004 | Covered |
| TR-loop-005 | loop-state.md | Core | Delta conflict resolution (sort_key formula) | ADR-0004 | Covered |
| TR-loop-006 | loop-state.md | Core | Signal interface for loop transitions | ADR-0004 | Covered |
| TR-loop-007 | loop-state.md | Core | Deep-copy guarantee for SNAPSHOT step | ADR-0004 | Covered |
| TR-loop-008 | loop-state.md | Core | Night rhythm config support (NIGHT_RHYTHM_CONFIG) | ADR-0004 | Covered |
| TR-loop-009 | loop-state.md | Persistence | Save/load crash recovery integrity | ADR-0004 | Covered |
| TR-clue-001 | clue-db.md | Core | Unified KnowledgeEntry (clue + insight) | ADR-0005 | Covered |
| TR-clue-002 | clue-db.md | Core | Connection structure with valid/invalid tracking | ADR-0005 | Covered |
| TR-clue-003 | clue-db.md | Core | contextual_unlocks cascade mechanism | ADR-0005 | Covered |
| TR-clue-004 | clue-db.md | Core | CRUD, search, connection operations | ADR-0005 | Covered |
| TR-room-001 | room-location.md | Core | Single-room-in-memory with on-demand PackedScene instantiation and ROOM_PATHS registry | ADR-0007 | Covered |
| TR-room-002 | room-location.md | Core | 9-step atomic transition protocol with concurrency guard and rollback | ADR-0007 | Covered |
| TR-room-003 | room-location.md | Core | Template vs persistent state separation with PackedScene re-instantiation for nightly reset | ADR-0007, ADR-0004 | Covered |
| TR-room-004 | room-location.md | Core | RoomManager-owned Interactable registration lifecycle (POST_LOAD/PRE_UNLOAD) | ADR-0007, ADR-0006 | Covered |
| TR-room-005 | room-location.md | Core | Exit handling via InteractionBus event filtering + spawn_point propagation | ADR-0007, ADR-0006 | Covered |
| TR-room-006 | room-location.md | Lifecycle | Night reset integration via night_ready/night_advanced signals with _pending_reset | ADR-0007, ADR-0011 | Covered |
| TR-room-007 | room-location.md | Rendering | Fade overlay CanvasLayer 100 with Tween EASE_IN/EASE_OUT animation | ADR-0007, ADR-0003 | Covered |
| TR-room-008 | room-location.md | Core | Graceful error handling for PackedScene load failure with fallback | ADR-0007 | Covered |
| TR-room-009 | room-location.md | Performance | Memory footprint and transition time budget formulas (F1-F4) | ADR-0007 | Covered |
| TR-room-010 | room-location.md | Core | Scene structure validation (4 required child groups) on LOAD | ADR-0007 | Covered |

## New Systems (Review #3 — 16 additional GDDs)

### Systems with ADR Coverage

| System | GDD | ADR | Status |
|--------|-----|-----|--------|
| Countdown Timer (#5) | countdown-timer.md | ADR-0008 | Covered |
| NPC State Machine (#6) | npc-state-machine.md | ADR-0009 | Partial (enum mismatch) |
| Interaction System (#7) | interaction-system.md | ADR-0006 | Covered |
| Night Transition (#8) | night-transition-controller.md | ADR-0011 | Covered |
| Event Scheduler (#9) | event-scheduler.md | ADR-0014 | Covered (Proposed) |
| Color Accumulation (#16) | color-accumulation.md | ADR-0002 | Covered |
| NPC Trust/Suspicion (#13) | npc-trust-suspicion.md | ADR-0012 | Covered |
| Conditional Dialogue (#14) | conditional-dialogue-trees.md | ADR-0013 | Covered |

### Systems with Partial/No ADR Coverage

| System | GDD | Status |
|--------|-----|--------|
| Clue Discovery (#10) | clue-discovery.md | Partial (data schema only) |
| Clue Connection (#11) | clue-connection-deduction.md | Partial (schema only) |
| Insight Generation (#12) | insight-generation.md | Covered |
| Guest Interrogation (#15) | guest-interrogation.md | Gap |
| Notebook System (#17) | notebook-system.md | Gap |
| Ending Trigger (#23) | ending-trigger-logic.md | Gap |
| Ink Wash Visual (#18) | ink-wash-visual-style.md | Gap (shader covered, state machine not) |
| Dialogue UI (#20) | dialogue-ui.md | Partial (CanvasLayer only) |

## Known Conflicts

1. **NPC enum mismatch**: GDD vs ADR-0009 — HIGH
2. **BASE_DURATION**: loop-state=300s vs timer=180s — MEDIUM
3. **ADR-0014 interfaces**: Undefined methods — MEDIUM
4. **ADR-0014 Proposed**: Not Accepted — MEDIUM
5. **Interactable registration**: ADR-0006 vs ADR-0007 (carried over) — MEDIUM

## Engine Specialist Findings (Review #3)

| Priority | Issue | Action |
|----------|-------|--------|
| HIGH | DialoguePanel @onready dead code | Remove |
| HIGH | Typewriter Tween O(n) | Refactor |
| HIGH | find_children wildcard | Filter |
| MEDIUM | Immutability in register_consequence | Fix |
| MEDIUM | InteractionBus idle process | Guard |
| MEDIUM | VisualParams mutation | Fix |
| LOW | Hardcoded configs | Extract |
| LOW | 18 autoloads order | Document |

## Superseded Requirements

None.

## History

| Date | Review # | ADRs | GDDs | Total | Covered | Partial | Gaps | Verdict |
|------|----------|------|------|-------|---------|---------|------|---------|
| 2026-05-14 | 1 | 7 | 4 | 28 | 23 (82%) | 4 (14%) | 1 (4%) | CONCERNS |
| 2026-05-14 | 2 | 13 | 5 | 38 | 37 (97%) | 1 (3%) | 0 | PASS |
| 2026-05-15 | 3 | 14 | 21 | ~137 | ~108 (79%) | ~9 (7%) | ~20 (14%) | CONCERNS |
