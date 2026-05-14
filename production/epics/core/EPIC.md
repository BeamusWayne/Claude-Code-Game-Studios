# Epic: Core

**Layer**: Core
**Status**: Planning
**ADRs**: ADR-0002, ADR-0005, ADR-0007, ADR-0008, ADR-0009, ADR-0011
**GDDs**: clue-database.md, room-location-management.md, game-concept.md, systems-index.md

## Goal

Implement the six Core-layer systems that depend on the Foundation epic and
provide the game's primary gameplay mechanics: clue collection, knowledge-driven
color, room exploration, countdown pressure, NPC behavior, and the night-to-night
transition orchestrator.

## Stories

| # | Title | Type | TR-IDs | ADR | Status |
|---|-------|------|--------|-----|--------|
| 001 | Clue Database -- KnowledgeEntry schema and CRUD operations | Logic | TR-clue-001, TR-clue-004 | ADR-0005 | Planning |
| 002 | Clue Database -- Connection schema and connect_clues operation | Logic | TR-clue-002, TR-clue-003 | ADR-0005 | Planning |
| 003 | Clue Database -- serialization round-trip and InsightGenerator integration | Integration | TR-clue-004, TR-concept-015 | ADR-0005 | Planning |
| 004 | Knowledge Color Manager -- global knowledge_level and per-NPC saturation | Logic | TR-concept-002, TR-concept-003 | ADR-0002 | Planning |
| 005 | Knowledge Color Manager -- connection gold ochre and six-color system | Logic | TR-concept-002, TR-concept-003 | ADR-0002 | Planning |
| 006 | Room Manager -- single-room-in-memory and ROOM_PATHS registry | Logic | TR-room-001, TR-room-003 | ADR-0007 | Planning |
| 007 | Room Manager -- 9-step atomic transition protocol | Integration | TR-room-002, TR-room-008 | ADR-0007 | Planning |
| 008 | Room Manager -- Interactable registration lifecycle and exit handling | Integration | TR-room-004, TR-room-005 | ADR-0007 | Planning |
| 009 | Room Manager -- night reset integration and pending-reset deferred execution | Integration | TR-room-006, TR-room-003 | ADR-0007 | Planning |
| 010 | Room Manager -- fade overlay and performance validation | Visual/Feel | TR-room-007, TR-room-009, TR-room-010 | ADR-0007 | Planning |
| 011 | Timer Service -- countdown, pressure curve, and phase state machine | Logic | TR-concept-006, TR-concept-011 | ADR-0008 | Planning |
| 012 | Timer Service -- time_scale mechanism and night lifecycle integration | Integration | TR-concept-006, TR-loop-008 | ADR-0008 | Planning |
| 013 | NPC Manager -- NPCEmotionalState enum and transition validation | Logic | TR-concept-008 | ADR-0009 | Planning |
| 014 | NPC Manager -- NPCTemplate resources and propose_delta integration | Integration | TR-concept-008 | ADR-0009 | Planning |
| 015 | NPC Manager -- InteractionBus filtering and location tracking | Integration | TR-concept-008 | ADR-0009 | Planning |
| 016 | Night Transition Controller -- full save-stop-fade-advance-restart sequence | Integration | TR-concept-004, TR-concept-005, TR-concept-006, TR-concept-014 | ADR-0011 | Planning |
| 017 | Night Transition Controller -- blocking guards and error recovery | Logic | TR-concept-004, TR-concept-005 | ADR-0011 | Planning |
| 018 | Night Transition Controller -- night 7 game ending and pending transition queue | Logic | TR-concept-004 | ADR-0011 | Planning |

## Dependencies

| Story | Depends On (Foundation Stories) |
|-------|--------------------------------|
| 001-003 (Clue Database) | F-001, F-002 (Loop State Manager) |
| 004-005 (Knowledge Color) | F-006, F-008 (Ink Wash Shader) + Core-001 (Clue Database) |
| 006-010 (Room Manager) | F-004, F-005 (Interaction Bus) + F-001 (Loop State Manager) |
| 011-012 (Timer Service) | F-001 (Loop State Manager) |
| 013-015 (NPC Manager) | F-001, F-002 (Loop State Manager) + F-004, F-005 (Interaction Bus) |
| 016-018 (Night Transition) | All Foundation stories + Core-006 through Core-015 |

## Acceptance Criteria

- ClueDatabase stores CLUE and INSIGHT entries with unified KnowledgeEntry schema
- connect_clues() creates valid connections; duplicate connections rejected
- contextual_unlocks cascade works when insights are created
- KnowledgeManager derives knowledge_level from ClueDatabase entry counts
- Per-NPC saturation formula produces correct range (0.10 to 1.00)
- RoomManager loads/unloads rooms via PackedScene with correct 9-step transition
- Interactable registration lifecycle bound to room enter/exit
- Template reset restores room state on night_advanced
- Fade overlay hides all load/unload artifacts (no visible frame of unload)
- TimerService pressure_level follows Curve Resource from 0.0 to 1.0
- Phase transitions (CALM/INTENSE/CRITICAL) aligned with ADR-0001 shader ranges
- NPCManager registers state paths and routes mutations through propose_delta()
- Transition validation blocks invalid emotional state transitions
- NightTransitionController orchestrates full save-stop-fade-advance-restart sequence
- Night 7 timer expiration emits game_ending_triggered, not advance to night 8
- All systems pass their ADR validation criteria
- All Logic/Integration stories have passing unit/integration tests
- No S1 or S2 bugs in delivered systems
