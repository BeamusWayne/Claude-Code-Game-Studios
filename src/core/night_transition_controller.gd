extends Node

## NightTransitionController -- autoload singleton that orchestrates the
## night-to-night transition sequence (ADR-0011).
##
## Coordinates: save -> stop timer -> fade out -> advance night ->
## (downstream systems react via signals) -> fade in -> restart timer -> complete.
##
## The controller owns NO game state. All mutations go through the owning
## system's methods. The transition uses a callback chain driven by Tweens,
## not await/coroutines.

signal night_transition_started(old_night: int)
signal night_transition_completed(new_night: int)
signal night_transition_failed(reason: String)
signal game_ending_triggered(final_night: int)

const FADE_DURATION: float = 0.3
const MAX_NIGHTS: int = 7

## Whether a night transition is currently in progress.
## Other systems can read this to block operations during transition.
var is_transitioning: bool = false

var _pending_transition: bool = false


func _ready() -> void:
	set_process(false)
	_connect_timer_signal()
	_connect_loop_state_signals()
	_connect_blocking_signals()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


## Public entry point for night transition.
## Called when timer expires, or by scripted events that force night end.
## Guards: blocks during dialogue, room transition, or existing night transition.
func request_night_transition() -> void:
	if is_transitioning:
		return
	if not _can_start_transition():
		_pending_transition = true
		return
	_execute_transition()


# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------


## Check all blocking conditions. Returns true if transition can proceed.
func _can_start_transition() -> bool:
	var ui_manager: Node = _get_ui_manager()
	if ui_manager != null and ui_manager.has_method("is_dialogue_active"):
		if ui_manager.is_dialogue_active():
			return false

	var room_manager: Node = _get_room_manager()
	if room_manager != null:
		if room_manager.has_method("get_is_transitioning"):
			if room_manager.get_is_transitioning():
				return false
		elif "_is_transitioning" in room_manager:
			if room_manager._is_transitioning:
				return false

	return true


# ---------------------------------------------------------------------------
# Transition Sequence (callback chain, NOT await)
# ---------------------------------------------------------------------------


## Begin the transition: save, stop, emit, then fade out.
func _execute_transition() -> void:
	var loop_state: Node = _get_loop_state_manager()
	var old_night: int = _get_current_night()

	# Night 7 check: timer expiration on the final night triggers game ending.
	if old_night >= MAX_NIGHTS:
		game_ending_triggered.emit(old_night)
		return

	is_transitioning = true
	if loop_state != null:
		loop_state.is_transitioning = true

	# Step 1: PRE_SAVE -- save before advancing night.
	# ADR-0010: save must happen before advance_night() because
	# save_game() is blocked during LoopStateManager.is_transitioning.
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("save_game"):
		var slot: int = _get_save_slot(save_manager)
		if slot >= 0:
			var save_ok: bool = save_manager.save_game(slot)
			if not save_ok:
				_abort_transition("Save failed before night advance")
				return

	# Step 2: STOP -- halt the countdown timer.
	var timer_service: Node = _get_timer_service()
	if timer_service != null:
		if timer_service.has_method("stop_timer"):
			timer_service.stop_timer()
		if timer_service.has_method("set_time_scale"):
			timer_service.set_time_scale(0.0)

	# Step 3: SIGNAL -- notify all systems that transition is starting.
	night_transition_started.emit(old_night)

	# Step 4: FADE_OUT -- animate fade overlay to cover the screen.
	# Uses RoomManager's fade overlay (CanvasLayer 100, per ADR-0007).
	_fade_out(_on_fade_out_complete)


## Step 5: ADVANCE -- call the atomic advance_night() operation.
func _on_fade_out_complete() -> void:
	var loop_state: Node = _get_loop_state_manager()
	if loop_state == null or not loop_state.has_method("advance_night"):
		_on_advance_failed(1, "LoopStateManager not available or missing advance_night")
		return
	loop_state.advance_night()
	# advance_night() emits night_advanced synchronously on success,
	# which triggers _on_night_advanced via signal connection.
	# On failure, advance_failed signal fires, triggering _on_advance_failed.


## Step 6: POST -- downstream systems react to night_advanced.
## NPCManager re-initializes from templates (ADR-0009).
## RoomManager applies template reset (ADR-0007).
## These happen via their own night_advanced signal connections.
##
## After downstream systems complete, fade back in.
func _on_night_advanced(_old_night: int, _new_night: int) -> void:
	_fade_in(_on_fade_in_complete)


## Step 7-8: COMPLETE -- transition finished.
## TimerService restarts via night_ready signal (ADR-0008):
##   LoopStateManager.night_ready -> TimerService._on_night_ready -> start_night_timer()
func _on_fade_in_complete() -> void:
	is_transitioning = false

	var loop_state: Node = _get_loop_state_manager()
	if loop_state != null:
		loop_state.is_transitioning = false

	var timer_service: Node = _get_timer_service()
	if timer_service != null and timer_service.has_method("set_time_scale"):
		timer_service.set_time_scale(1.0)

	var new_night: int = _get_current_night()
	night_transition_completed.emit(new_night)

	# Check for pending transition (queued while we were busy).
	if _pending_transition:
		_pending_transition = false
		call_deferred("request_night_transition")


# ---------------------------------------------------------------------------
# Error Recovery
# ---------------------------------------------------------------------------


## advance_night() failed at a specific step.
## LoopStateManager handles rollback internally (restores SNAPSHOT).
## We need to abort the transition and restore visual state.
func _on_advance_failed(step: int, error: String) -> void:
	var reason: String = "advance_night() failed at step %d: %s" % [step, error]
	push_error("NightTransitionController: " + reason)

	is_transitioning = false

	var loop_state: Node = _get_loop_state_manager()
	if loop_state != null:
		loop_state.is_transitioning = false

	# Fade back in to show the restored state.
	_fade_in(func() -> void:
		night_transition_failed.emit(reason)

		var timer_service: Node = _get_timer_service()
		if timer_service != null:
			if timer_service.has_method("set_time_scale"):
				timer_service.set_time_scale(1.0)
			if timer_service.has_method("start_night_timer"):
				timer_service.start_night_timer()
	)


## Abort before advance_night() was called (e.g., save failed).
func _abort_transition(reason: String) -> void:
	is_transitioning = false

	var loop_state: Node = _get_loop_state_manager()
	if loop_state != null:
		loop_state.is_transitioning = false

	var timer_service: Node = _get_timer_service()
	if timer_service != null and timer_service.has_method("set_time_scale"):
		timer_service.set_time_scale(1.0)

	night_transition_failed.emit(reason)


# ---------------------------------------------------------------------------
# Timer Expiration Handler
# ---------------------------------------------------------------------------


## TimerService.night_timer_ended fires when countdown reaches zero.
## Deferred to next frame to avoid same-frame ordering issues
## (ADR-0008 risk: TimerService emits at end of _process;
##  transition controller should defer advance_night()).
func _on_night_timer_ended(_night: int) -> void:
	call_deferred("request_night_transition")


# ---------------------------------------------------------------------------
# Blocking Condition Clearing
# ---------------------------------------------------------------------------


## Called when a blocking condition clears (dialogue ended, room transition done).
func _on_blocking_cleared(_arg: Variant = null) -> void:
	if _pending_transition and not is_transitioning:
		_pending_transition = false
		call_deferred("request_night_transition")


# ---------------------------------------------------------------------------
# Signal Connections
# ---------------------------------------------------------------------------


## Connect to TimerService.night_timer_ended if the autoload is present.
func _connect_timer_signal() -> void:
	var timer_service: Node = _get_timer_service()
	if timer_service != null and timer_service.has_signal("night_timer_ended"):
		timer_service.night_timer_ended.connect(_on_night_timer_ended)


## Connect to LoopStateManager signals for advance result.
func _connect_loop_state_signals() -> void:
	var loop_state: Node = _get_loop_state_manager()
	if loop_state == null:
		return
	if loop_state.has_signal("night_advanced"):
		loop_state.night_advanced.connect(_on_night_advanced)
	if loop_state.has_signal("advance_failed"):
		loop_state.advance_failed.connect(_on_advance_failed)


## Connect to signals that indicate blocking conditions have cleared.
func _connect_blocking_signals() -> void:
	var ui_manager: Node = _get_ui_manager()
	if ui_manager != null and ui_manager.has_signal("dialogue_ended"):
		ui_manager.dialogue_ended.connect(_on_blocking_cleared)

	var room_manager: Node = _get_room_manager()
	if room_manager != null and room_manager.has_signal("room_transition_completed"):
		room_manager.room_transition_completed.connect(_on_blocking_cleared)


# ---------------------------------------------------------------------------
# Fade Helpers (Tween-based, callback chain)
# ---------------------------------------------------------------------------


## Animate the fade overlay alpha 0.0 -> 1.0 over FADE_DURATION.
func _fade_out(on_complete: Callable) -> void:
	var room_manager: Node = _get_room_manager()
	if room_manager == null or not room_manager.has_method("set_fade_alpha"):
		on_complete.call()
		return
	var tween: Tween = create_tween()
	tween.tween_method(room_manager.set_fade_alpha, 0.0, 1.0, FADE_DURATION)
	tween.tween_callback(on_complete)


## Animate the fade overlay alpha 1.0 -> 0.0 over FADE_DURATION.
func _fade_in(on_complete: Callable) -> void:
	var room_manager: Node = _get_room_manager()
	if room_manager == null or not room_manager.has_method("set_fade_alpha"):
		on_complete.call()
		return
	var tween: Tween = create_tween()
	tween.tween_method(room_manager.set_fade_alpha, 1.0, 0.0, FADE_DURATION)
	tween.tween_callback(on_complete)


# ---------------------------------------------------------------------------
# Autoload Accessors (guarded, overridable for tests)
# ---------------------------------------------------------------------------


func _get_timer_service() -> Node:
	return get_node_or_null("/root/TimerService")


func _get_loop_state_manager() -> Node:
	return get_node_or_null("/root/LoopStateManager")


func _get_room_manager() -> Node:
	return get_node_or_null("/root/RoomManager")


func _get_save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")


func _get_ui_manager() -> Node:
	return get_node_or_null("/root/UIManager")


# ---------------------------------------------------------------------------
# Private Helpers
# ---------------------------------------------------------------------------


## Get the current night from LoopStateManager, defaulting to 1.
func _get_current_night() -> int:
	var loop_state: Node = _get_loop_state_manager()
	if loop_state != null and loop_state.has_method("get_current_night"):
		return loop_state.get_current_night()
	if loop_state != null and "current_night" in loop_state:
		return loop_state.current_night
	return 1


## Get the active save slot from SaveManager, defaulting to -1 (no save).
func _get_save_slot(save_manager: Node) -> int:
	if "current_slot" in save_manager:
		var slot: int = save_manager.current_slot
		if slot >= 0:
			return slot
	return -1


## Serialize controller state. The controller holds no persistent state,
## so this always returns an empty dictionary.
func serialize() -> Dictionary:
	return {}


## Deserialize is a no-op. Transition progress is never restored from saves.
func deserialize(_data: Dictionary) -> void:
	pass


## Reset the controller to its non-transitioning initial state.
func reset() -> void:
	is_transitioning = false
	_pending_transition = false
