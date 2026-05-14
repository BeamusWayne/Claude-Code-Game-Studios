# Architecture Traceability Index

Last Updated: 2026-05-14
Engine: Godot 4.6
Review: Second (13 ADRs, 5 GDDs)

## Coverage Summary

- Total requirements: 38
- Covered: 37 (97.4%)
- Partial: 1 (2.6%)
- Gaps: 0

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

## Remaining Partial Coverage

1. **TR-concept-010**: Cross-platform -- ADRs cover input and UI; no platform/export strategy ADR. LOW priority.

## Known Conflicts (non-blocking)

1. **ADR-0006 vs ADR-0007**: Interactable registration ownership -- resolve in Interaction System GDD (#7)

## Engine Specialist Findings

| Priority | Issue | ADR | Action |
|----------|-------|-----|--------|
| Medium | duplicate_deep() on Dictionary vs Resource | ADR-0004 | Clarify during implementation |
| Medium | TrustManager lookup fragile, not cached | ADR-0013 | Cache on first lookup |
| Medium | No autoload registration order manifest | All | Create centralized document |
| Low-Medium | Touch input propagation depends on Project Settings | ADR-0006 | Document required settings |
| Low | Typewriter Tween O(n) steps | ADR-0013 | Optimize for mobile |
| Low | find_children scans entire subtree | ADR-0007 | Use container children directly |

## Superseded Requirements

None.

## History

| Date | Review # | ADRs | GDDs | Total | Covered | Partial | Gaps | Verdict |
|------|----------|------|------|-------|---------|---------|------|---------|
| 2026-05-14 (first) | 1 | 7 | 4 | 28 | 23 (82%) | 4 (14%) | 1 (4%) | CONCERNS |
| 2026-05-14 (second) | 2 | 13 | 5 | 38 | 37 (97%) | 1 (3%) | 0 | PASS |
