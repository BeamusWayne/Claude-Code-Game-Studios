# QA Plan: Sprint 1 -- Foundation Layer

**Sprint**: Sprint 1 (2026-05-15 to 2026-05-21)
**Generated**: 2026-05-14
**QA Lead**: qa-lead
**Framework**: GDUnit4
**Coverage Target**: 80% minimum

---

## 1. Test Strategy Overview

Sprint 1 implements the Foundation layer -- four autoload singletons (LoopStateManager, InteractionBus, SaveManager, InkWashPostProcess) and the test harness itself. These are core systems that every subsequent sprint depends on. The testing strategy reflects this criticality.

### Applicable Test Types

| Test Type | Scope This Sprint | Tools |
|-----------|-------------------|-------|
| **Unit** | LoopStateManager state model, advance_night 7-step sequence, consequence registration, InteractionBus register/unregister/resolve, SaveManager atomic I/O, JSON schema, schema migration | GDUnit4 headless |
| **Integration** | SaveManager + LoopStateManager serialization coordination (S1-7); InteractionBus + Interactable component end-to-end event flow | GDUnit4 headless |
| **Visual/Feel** | Ink wash shader output (knowledge_level gradient, pressure_level effects, rain overlay) | Screenshot evidence + visual comparison |
| **Smoke** | Game boot, autoload initialization, no runtime errors on startup | Manual + headless runner |

### Sprint-Level Quality Gates

Before Sprint 1 can be marked Done:

- [ ] All Must Have stories (S1-1 through S1-5) have passing unit tests
- [ ] All tests pass via `godot --headless --script tests/gdunit4_runner.gd`
- [ ] Game boots without errors, all autoloads initialize
- [ ] 80% code coverage on `src/core/` and `src/persistence/`
- [ ] No S1 or S2 bugs open

---

## 2. Per-Story Test Matrix

### S1-1: GDUnit4 Installation + Test Harness Setup

| Field | Value |
|-------|-------|
| **Story Type** | Config/Data |
| **Required Evidence** | Smoke check pass -- runner executes without errors, directories exist |
| **Gate Level** | ADVISORY (but blocking for all downstream stories) |

**Test Cases:**

| Test Function | Description |
|---------------|-------------|
| `test_gdunit4_runner_executes` | `tests/gdunit4_runner.gd` runs and exits with code 0 |
| `test_unit_directory_exists` | `tests/unit/core/` directory is present |
| `test_integration_directory_exists` | `tests/integration/core/` directory is present |
| `test_sample_test_passes` | Sample test file runs green |

**Validation:** No ADR to validate. This story is infrastructure.

---

### S1-2: LoopStateManager -- Core State Model + Signals

| Field | Value |
|-------|-------|
| **Story Type** | Logic |
| **Required Evidence** | Automated unit tests in `tests/unit/core/` -- BLOCKING |
| **Primary ADR** | ADR-0004 (Loop State Management) |
| **ADR Validation Criteria** | 8-10 (signals and initialization) |
| **Gate Level** | BLOCKING |

**Test Cases:**

| Test Function | Description | ADR Criterion |
|---------------|-------------|---------------|
| `test_initial_night_is_one` | `current_night` starts at 1 | -- |
| `test_initial_phase_is_whisper` | `current_phase` starts at `NightPhase.WHISPER` | -- |
| `test_initial_not_transitioning` | `is_transitioning` starts false | -- |
| `test_three_state_layers_exist` | Template, PersistentMutations, PlayerKnowledge layers are modeled | -- |
| `test_night_phase_whisper_to_roar` | Phase transitions WHISPER to ROAR correctly | ADR VC 8 |
| `test_night_phase_roar_to_transition` | Phase transitions ROAR to TRANSITION correctly | ADR VC 8 |
| `test_night_advanced_signal_emitted` | `night_advanced` signal fires with correct old/new night values | ADR VC 9 |
| `test_night_ready_signal_on_init` | `night_ready` signal emitted after initialization | ADR VC 9 |
| `test_advance_failed_signal_on_error` | `advance_failed` signal emitted with step number and error message | ADR VC 10 |
| `test_consequence_registered_signal_emitted` | `consequence_registered` signal fires with correct ID | -- |
| `test_serialize_returns_valid_dictionary` | `serialize()` returns Dictionary with required keys | -- |
| `test_deserialize_restores_state` | `deserialize()` restores night and phase from serialized data | -- |

**Test File:** `tests/unit/core/loop_state_manager_test.gd`

---

### S1-3: LoopStateManager -- advance_night + Consequence Registration

| Field | Value |
|-------|-------|
| **Story Type** | Logic (highest-risk story in sprint) |
| **Required Evidence** | Automated unit tests in `tests/unit/core/` -- BLOCKING |
| **Primary ADR** | ADR-0004 (Loop State Management) |
| **ADR Validation Criteria** | 1-7 (atomic advance, consequence survival, rollback) |
| **Gate Level** | BLOCKING |

**Test Cases:**

| Test Function | Description | ADR Criterion |
|---------------|-------------|---------------|
| `test_advance_night_increments` | `advance_night()` increments night from N to N+1 | ADR VC 1 |
| `test_advance_night_seven_triggers_game_end` | `advance_night()` at night 7 triggers game-end behavior, not night 8 | ADR VC 2 |
| `test_advance_night_resets_template_state` | Template state resets after `advance_night()` | ADR VC 3 |
| `test_consequences_survive_advance_night` | Registered consequences persist across `advance_night()` calls | ADR VC 4 |
| `test_consequences_replay_in_registration_order` | Consequences replay in the order they were registered | ADR VC 5 |
| `test_serialize_deserialize_round_trip` | Full round-trip preserves all state (night, phase, consequences, overrides) | ADR VC 6 |
| `test_is_transitioning_blocks_during_advance` | `is_transitioning` is true during advance, false after completion | ADR VC 7 |
| `test_register_consequence_stores_mutation` | `register_consequence()` stores mutation with `affects_nights` array | -- |
| `test_register_consequence_multiple` | Multiple consequences registered and all replay correctly | -- |
| `test_advance_night_step2_snapshot_deep_copy` | SNAPSHOT step produces true deep copy (nested dict isolation) | -- |
| `test_advance_night_rollback_on_load_fail` | Rollback restores state if LOAD step fails | -- |
| `test_advance_night_rollback_on_rebuild_fail` | Rollback restores state if REBUILD step fails | -- |
| `test_advance_night_rollback_on_increment_fail` | Rollback restores state if INCREMENT step fails | -- |
| `test_advance_night_atomic_five_plus_consequences` | Full atomic sequence with 5+ registered consequences completes end-to-end | ADR verification note |
| `test_get_template_override_returns_value` | `get_template_override()` returns override value for affected nights | -- |
| `test_get_template_override_returns_null_unaffected` | `get_template_override()` returns null for nights not in `affects_nights` | -- |

**Test File:** `tests/unit/core/loop_state_manager_advance_night_test.gd`

**Risk Note:** This is the highest-risk story. The 7-step atomic advance_night with rollback has multiple failure paths. Each failure step should be tested independently before testing the full happy path. TDD is mandatory: write the rollback tests first, then implement.

---

### S1-4: InteractionBus -- Event Bus + Interactable Component

| Field | Value |
|-------|-------|
| **Story Type** | Logic + Integration |
| **Required Evidence** | Automated unit tests in `tests/unit/core/` -- BLOCKING |
| **Primary ADR** | ADR-0006 (Interaction Event Bus) |
| **ADR Validation Criteria** | 1-10 (core behavior), 12-14 (edge cases) |
| **Gate Level** | BLOCKING |

**Test Cases:**

| Test Function | Description | ADR Criterion |
|---------------|-------------|---------------|
| `test_register_interactable` | `register_interactable()` adds entry to registry | -- |
| `test_unregister_interactable` | `unregister_interactable()` removes entry from registry | -- |
| `test_click_event_emitted_on_mouse` | CLICK event emitted on InputEventMouseButton release | ADR VC 1 |
| `test_click_event_emitted_on_touch` | CLICK event emitted on InputEventScreenTouch release | ADR VC 1 |
| `test_long_press_event_after_duration` | LONG_PRESS event emitted after `long_press_duration` sustained press | ADR VC 2 |
| `test_long_press_cancel_on_mouse_exit` | LONG_PRESS canceled when cursor leaves Area2D before threshold | ADR VC 3 |
| `test_touch_canceled_resets_state` | InputEventScreenTouch.canceled resets press state, no spurious event | ADR VC 4 |
| `test_input_method_tagged_mouse` | Event tagged `InputMethod.MOUSE` for mouse input | ADR VC 5 |
| `test_input_method_tagged_touch` | Event tagged `InputMethod.TOUCH` for touch input | ADR VC 5 |
| `test_target_id_populated` | Event `target_id` matches Interactable's exported `target_id` | ADR VC 6 |
| `test_target_type_populated` | Event `target_type` matches Interactable's exported `target_type` | ADR VC 6 |
| `test_timestamp_populated` | Event `timestamp` is a valid `Time.get_ticks_msec()` value | ADR VC 7 |
| `test_overlapping_resolved_by_priority` | Deferred dispatch resolves overlapping interactables by priority | ADR VC 8 |
| `test_single_event_per_frame` | Only one event emitted per frame when multiple interactables fire | ADR VC 9 |
| `test_unregister_on_exit_tree` | Interactable unregisters from bus on `_exit_tree` | ADR VC 10 |
| `test_input_pickable_forced_true` | `input_pickable` forced true in `_ready()` regardless of editor setting | ADR VC 13 |
| `test_metadata_no_game_logic_keys` | Emitted event metadata does not contain game logic keys | ADR VC 14 |
| `test_frame_buffer_cleared_after_resolve` | Frame buffer is empty after `_process` resolves events | -- |
| `test_no_event_when_buffer_empty` | No signal emitted when frame buffer is empty | -- |

**Test Files:**
- `tests/unit/core/interaction_bus_test.gd` (bus logic)
- `tests/unit/core/interactable_component_test.gd` (component detection)

**Note on ADR VC 11 (debug overlay) and VC 12 (44px minimum touch target):** These are development tooling and authoring constraints, not unit-testable logic. Validate VC 11 visually during development. Validate VC 12 via scene inspection or a lint-style check, not runtime tests. VC 15 (touch hardware verification) is deferred to playtest -- cannot be unit-tested headlessly.

---

### S1-5: SaveManager -- Atomic File I/O + JSON Schema

| Field | Value |
|-------|-------|
| **Story Type** | Logic |
| **Required Evidence** | Automated unit tests in `tests/unit/core/` -- BLOCKING |
| **Primary ADR** | ADR-0010 (Save/Load Persistence) |
| **ADR Validation Criteria** | 1-6 (file operations, schema, slots, fallback) |
| **Gate Level** | BLOCKING |

**Test Cases:**

| Test Function | Description | ADR Criterion |
|---------------|-------------|---------------|
| `test_atomic_write_creates_json` | `_atomic_write()` produces valid JSON at `user://save_{slot}.json` | ADR VC 1 |
| `test_atomic_write_uses_tmp_then_rename` | Write goes to `.tmp` first, then renamed to `.json` | -- |
| `test_rotate_backup_preserves_previous` | `_rotate_backup()` preserves previous save as `.bak` | ADR VC 4 |
| `test_read_save_file_happy_path` | `_read_save_file()` returns valid Dictionary from primary file | -- |
| `test_read_save_file_fallback_to_bak` | `_read_save_file()` falls back to `.bak` when primary is corrupt | ADR VC 5 |
| `test_read_save_file_both_corrupt` | `_read_save_file()` returns empty Dictionary when both files are corrupt | -- |
| `test_build_save_envelope_schema` | `_build_save_envelope()` includes `schema_version`, `timestamp`, `slot_id`, `systems` | ADR VC 1 |
| `test_three_slot_paths_correct` | 3 slot paths generated: `save_1.json`, `save_2.json`, `save_3.json` | ADR VC 6 |
| `test_slots_independent` | Saving to slot 2 does not affect slots 1 or 3 | ADR VC 6 |
| `test_schema_version_is_one` | `SCHEMA_VERSION` constant is 1 | -- |
| `test_migration_framework_exists` | `_migrate_save()` runs without error on schema_version=1 data | -- |
| `test_save_manager_owns_no_state` | SaveManager does not cache game state between operations | Boundary rule |
| `test_tmp_cleanup_on_startup` | `_ready()` deletes leftover `.tmp` files from interrupted saves | Implementation guideline 8 |

**Test File:** `tests/unit/core/save_manager_test.gd`

**Note:** Tests requiring `user://` file I/O should use a test subdirectory or mock FileAccess. GDUnit4 may need a test fixture that sets up/tears down temp files. Verify that the test runner can write to `user://` in headless mode.

---

### S1-6: Ink Wash Shader -- Production Implementation

| Field | Value |
|-------|-------|
| **Story Type** | Visual/Feel |
| **Required Evidence** | Screenshot evidence in `production/qa/evidence/` + lead sign-off |
| **Primary ADR** | ADR-0001 (Ink Wash Shader Pipeline) |
| **ADR Validation Criteria** | 1-6 (visual output and performance) |
| **Gate Level** | ADVISORY |

**Test Cases:**

| Test Function | Description | ADR Criterion |
|---------------|-------------|---------------|
| `test_knowledge_zero_near_monochrome` | Screenshot at `knowledge_level=0.0` shows near-monochrome (desat >= 80%) | ADR VC 1 |
| `test_knowledge_one_visible_color` | Screenshot at `knowledge_level=1.0` shows visible color in ink-dense areas | ADR VC 2 |
| `test_paper_white_stays_monochrome` | Paper-white areas remain monochrome at all knowledge levels | ADR VC 3 |
| `test_combined_shader_time_under_3ms` | Both shaders combined under 3.0ms at 1280x720 | ADR VC 4 |
| `test_rain_toggle_independent` | Rain overlay toggles without affecting ink wash | ADR VC 5 |
| `test_no_visual_artifacts_60fps` | No banding, flickering, or temporal instability at 60fps | ADR VC 6 |

**Evidence Requirements:**
- Screenshots saved to `production/qa/evidence/s1-6-ink-wash/`
- Minimum 3 screenshots: `knowledge_level=0.0`, `knowledge_level=0.5`, `knowledge_level=1.0`
- Performance profiling output showing GPU time per shader
- Both shaders combined, at 1280x720, on target hardware (or closest available GPU)

**Note:** Visual validation cannot be fully automated. The performance test (VC 4) can be automated with Godot's performance monitors. Visual tests (VC 1-3, VC 5-6) require screenshot capture + manual review or lead sign-off.

---

### S1-7: SaveManager -- Full System Integration

| Field | Value |
|-------|-------|
| **Story Type** | Integration |
| **Required Evidence** | Integration tests in `tests/integration/core/` -- BLOCKING |
| **Primary ADR** | ADR-0010 (Save/Load Persistence) |
| **ADR Validation Criteria** | 7, 8, 10, 11 (auto-save, debounce, deserialization order, save blocking) |
| **Gate Level** | BLOCKING |
| **Priority** | Nice to Have -- may slip to Sprint 2 |

**Test Cases:**

| Test Function | Description | ADR Criterion |
|---------------|-------------|---------------|
| `test_collect_snapshots_calls_serialize` | `_collect_snapshots()` calls `LoopStateManager.serialize()` and returns result | ADR VC 2 |
| `test_distribute_snapshots_calls_deserialize` | `_distribute_snapshots()` calls `LoopStateManager.deserialize()` first | ADR VC 10 |
| `test_deserialize_order_loop_state_first` | LoopStateManager deserializes before other systems | ADR VC 10 |
| `test_auto_save_on_consequence_registered` | Auto-save triggers after `consequence_registered` signal | ADR VC 7 |
| `test_auto_save_debounce_two_seconds` | Second auto-save within 2 seconds is skipped | ADR VC 8 |
| `test_save_blocked_during_transition` | `save_game()` returns false when `is_transitioning` is true | ADR VC 11 |
| `test_full_round_trip_loop_state` | Save with LoopStateManager data -> load -> verify night, phase, consequences match | ADR VC 2 |

**Test File:** `tests/integration/core/save_manager_integration_test.gd`

**Note:** This story depends on S1-3 (advance_night) and S1-5 (atomic I/O) being complete. If time runs out, this story carries to Sprint 2 without blocking the sprint.

---

## 3. Test Execution Plan

### Running Tests

**Primary command (all tests):**
```bash
godot --headless --script tests/gdunit4_runner.gd
```

**Per-system (during development):**
```bash
# Run only LoopStateManager tests
godot --headless --script tests/gdunit4_runner.gd -- --suite loop_state_manager

# Run only InteractionBus tests
godot --headless --script tests/gdunit4_runner.gd -- --suite interaction_bus
```

### Execution Schedule

| When | What | Who |
|------|------|-----|
| Before each story implementation | Write test file first (TDD RED) | Implementing specialist |
| During each story implementation | Run tests per system until GREEN | Implementing specialist |
| After each story completion | Run full suite to check for regressions | qa-lead or specialist |
| End of sprint (before review) | Full suite + smoke check | qa-lead |
| Pre-QA gate | `/smoke-check` | qa-lead |

### CI Integration

- Automated test suite runs on every push to main and every PR
- No merge if tests fail -- tests are a blocking gate in CI
- CI command: `godot --headless --script tests/gdunit4_runner.gd`
- Never disable or skip failing tests to make CI pass

---

## 4. Coverage Targets

### Minimum: 80%

Coverage is measured per system. The following targets apply:

| System | Target Coverage | Priority |
|--------|----------------|----------|
| LoopStateManager (state model) | >= 85% | HIGH -- every downstream system depends on this |
| LoopStateManager (advance_night) | >= 90% | HIGH -- highest-risk code path, 7-step atomic with rollback |
| InteractionBus | >= 80% | HIGH -- all interaction depends on this |
| Interactable component | >= 75% | MEDIUM -- scene-tree dependent, some paths need manual validation |
| SaveManager (file I/O) | >= 80% | HIGH -- crash recovery depends on correctness |
| InkWashPostProcess driver | >= 60% | LOW -- visual system, most validation is manual |

### Systems Requiring Coverage

Coverage must include these critical paths:

- `advance_night()` happy path and all 7 failure/rollback steps
- `register_consequence()` and consequence replay
- `serialize()` / `deserialize()` round-trip
- `register_interactable()` / `unregister_interactable()` lifecycle
- Frame buffer collection and priority resolution
- `_atomic_write()` success, failure, and partial-write scenarios
- `_read_save_file()` primary and backup fallback paths
- Schema migration framework

---

## 5. Risk-Based Testing

### Highest Risk: advance_night() 7-Step Atomic Operation (S1-3)

**Why it is risky:** A 7-step sequence with deep-copy snapshot, template loading, consequence replay, and rollback on failure. Any step can fail, and rollback must restore exact prior state. The deep-copy integrity risk (GDScript `duplicate()` vs `duplicate_deep()`) is specifically called out in ADR-0004.

**Testing approach:**
1. Test each step failure independently (LOAD fail, REBUILD fail, INCREMENT fail)
2. Verify snapshot is a true deep copy (modify snapshot, check original unchanged)
3. Test with 5+ registered consequences to validate replay ordering
4. Test night 7 boundary (must not go to night 8)
5. Test rollback restores `current_night`, `current_phase`, `is_transitioning`, and all state layers

### High Risk: InteractionBus Frame Buffer (S1-4)

**Why it is risky:** Deferred dispatch means events are buffered and resolved in `_process`. Overlapping interactables, rapid clicks, and register/unregister during event processing could cause stale references or dropped events.

**Testing approach:**
1. Test buffer clears after resolution (no stale events from previous frame)
2. Test priority resolution with 3+ overlapping interactables
3. Test unregister during press (before release) does not crash
4. Test rapid click sequence produces correct number of resolved events
5. Test empty buffer produces no signal emission

### Medium Risk: SaveManager Atomic Write (S1-5)

**Why it is risky:** File corruption on crash depends on the write-to-tmp-then-rename pattern being correct. Platform-specific behavior (especially Android's copy+delete rename) could break atomicity.

**Testing approach:**
1. Simulate interrupted write (write .tmp, skip rename, verify .bak intact)
2. Test corrupt primary + valid backup falls back correctly
3. Test both files corrupt returns empty dict without crash
4. Test concurrent save guard (_is_saving flag)

### Lower Risk: GDUnit4 Setup (S1-1)

**Why it is lower risk:** Infrastructure story. The main risk is GDUnit4 not being installable from AssetLib (noted in sprint risks). Mitigation: complete first, document manual steps.

### Lower Risk: Ink Wash Shader (S1-6)

**Why it is lower risk:** Should Have priority, prototype-validated, visual-only validation. Performance risk is mitigated by the prototype confirming < 3.0ms. The 4.6 glow rework interaction needs specific verification.

---

## 6. Regression Checkpoint

After each story is marked Done, verify the following to catch regressions early:

### After S1-1 (Test Harness)
- [ ] `tests/gdunit4_runner.gd` executes with exit code 0
- [ ] Sample test still passes
- [ ] Directory structure intact

### After S1-2 (LoopStateManager Core)
- [ ] All S1-2 tests pass
- [ ] Game boots without errors (LoopStateManager autoload initializes)
- [ ] `current_night` is 1, `current_phase` is WHISPER on fresh start
- [ ] Signals emit correctly (connect a test listener)

### After S1-3 (LoopStateManager advance_night)
- [ ] All S1-3 tests pass
- [ ] All S1-2 tests still pass (no regression from new code)
- [ ] `advance_night()` increments night correctly
- [ ] Night 7 boundary handled (no night 8)
- [ ] Rollback works on simulated failure

### After S1-4 (InteractionBus)
- [ ] All S1-4 tests pass
- [ ] All S1-2 and S1-3 tests still pass
- [ ] InteractionBus autoload initializes at boot
- [ ] Register/unregister lifecycle works with test interactables

### After S1-5 (SaveManager I/O)
- [ ] All S1-5 tests pass
- [ ] All previous tests still pass
- [ ] SaveManager autoload initializes at boot
- [ ] Atomic write produces valid JSON
- [ ] Backup rotation works

### After S1-6 (Ink Wash Shader)
- [ ] Screenshots captured in `production/qa/evidence/`
- [ ] Performance profiling shows < 3.0ms combined GPU time
- [ ] knowledge_level gradient visually correct
- [ ] No visual artifacts

### After S1-7 (SaveManager Integration) -- if completed
- [ ] All S1-7 integration tests pass
- [ ] All previous unit tests still pass
- [ ] Full save/load round-trip with LoopStateManager data works
- [ ] Auto-save debounce verified
- [ ] Save blocked during transition verified

### End-of-Sprint Regression
- [ ] Full test suite passes: `godot --headless --script tests/gdunit4_runner.gd`
- [ ] Game boots, all autoloads initialize, no errors
- [ ] No S1 or S2 bugs open
- [ ] Coverage >= 80% on `src/core/` and `src/persistence/`
