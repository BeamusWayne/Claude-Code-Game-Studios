extends Node

## NotebookManager — autoload singleton for the notebook/knowledge viewer.
## Read-only view over ClueDatabase. Delegates connections to ClueConnectionManager.
## GDD: design/gdd/notebook-system.md

signal notebook_opened
signal notebook_closed
signal board_updated
signal entry_selected(entry_id: StringName)
signal entry_deselected
signal connection_attempted(clue_a: StringName, clue_b: StringName, success: bool)

## Tuning knobs — GDD Section 7
@export var board_layout_radius: float = 200.0
@export var board_center_x: float = 640.0
@export var board_center_y: float = 360.0
@export var clue_node_size: float = 32.0
@export var insight_node_size: float = 40.0
@export var valid_edge_width: float = 2.0
@export var invalid_edge_width: float = 1.0
@export var invalid_edge_alpha: float = 0.3

## ADR-0002 six-color system
const NPC_COLOR_MAP: Dictionary = {
	&"guest_indigo": Color(0.247, 0.318, 0.710),
	&"guest_vermillion": Color(0.827, 0.255, 0.212),
	&"guest_jade": Color(0.180, 0.545, 0.341),
	&"guest_amber": Color(0.878, 0.678, 0.157),
	&"guest_azure": Color(0.255, 0.627, 0.843),
}
const GLOBAL_COLOR: Color = Color(0.8, 0.7, 0.6)
const GOLD_OCHRE: Color = Color(0.8, 0.467, 0.133)

var is_open: bool = false

var _selected_entries: Array[StringName] = []
var _node_positions: Dictionary = {}
var _previous_time_scale: float = 1.0
var _node_random_offsets: Dictionary = {}


func _ready() -> void:
	_connect_database_signals()


# -- Open / Close --------------------------------------------------------------


## Opens the notebook. Pauses timer, disables interactions.
## Returns false if dialogue is active or already open.
func open_notebook() -> bool:
	if is_open:
		return false

	var dialogue := _get_dialogue_manager()
	if dialogue != null and dialogue.is_active:
		return false

	is_open = true

	var timer := _get_timer_service()
	if timer != null:
		_previous_time_scale = timer.time_scale
		timer.set_time_scale(0.0)

	var bus := _get_interaction_bus()
	if bus != null and bus.has_method("set_accepting"):
		bus.set_accepting(false)

	_rebuild_board()
	notebook_opened.emit()
	return true


## Closes the notebook. Restores timer and interaction state.
func close_notebook() -> void:
	if not is_open:
		return

	is_open = false
	_selected_entries.clear()

	var timer := _get_timer_service()
	if timer != null:
		timer.set_time_scale(_previous_time_scale)

	var bus := _get_interaction_bus()
	if bus != null and bus.has_method("set_accepting"):
		bus.set_accepting(true)

	notebook_closed.emit()


# -- Search & Filter ----------------------------------------------------------


## Full-text search across title, description, and tags. Scored and sorted.
func search_entries(query: String) -> Array[StringName]:
	var db := _get_clue_database()
	if db == null:
		return []
	if query.is_empty():
		return get_all_visible()

	var scored: Array[Dictionary] = []
	for entry_id: StringName in db.entries:
		var entry: Dictionary = db.entries[entry_id]
		var score := _calculate_search_score(entry, query)
		if score > 0.0:
			scored.append({"id": entry_id, "score": score})

	scored.sort_custom(_compare_by_score_desc)

	var result: Array[StringName] = []
	for item: Dictionary in scored:
		result.append(item["id"])
	return result


## Filter entries by tag. Delegates to ClueDatabase.search_by_tag().
func filter_by_tag(tag: StringName) -> Array[StringName]:
	var db := _get_clue_database()
	if db == null:
		return []
	return db.search_by_tag(tag)


## Filter entries by npc_affinity. Delegates to ClueDatabase.search_by_npc().
func filter_by_npc(npc_id: StringName) -> Array[StringName]:
	var db := _get_clue_database()
	if db == null:
		return []
	return db.search_by_npc(npc_id)


## Filter entries by EntryType (0=CLUE, 1=INSIGHT).
func filter_by_type(entry_type: int) -> Array[StringName]:
	var db := _get_clue_database()
	if db == null:
		return []
	var result: Array[StringName] = []
	for entry_id: StringName in db.entries:
		if db.entries[entry_id]["entry_type"] == entry_type:
			result.append(entry_id)
	return result


## Filter entries by discovery night.
func filter_by_night(night: int) -> Array[StringName]:
	var db := _get_clue_database()
	if db == null:
		return []
	var result: Array[StringName] = []
	for entry_id: StringName in db.entries:
		if db.entries[entry_id].get("discovered_at_night", 0) == night:
			result.append(entry_id)
	return result


## Returns all discovered entry IDs.
func get_all_visible() -> Array[StringName]:
	var db := _get_clue_database()
	if db == null:
		return []
	var result: Array[StringName] = []
	for entry_id: StringName in db.entries:
		result.append(entry_id)
	return result


# -- Detail View --------------------------------------------------------------


## Returns full detail for an entry: original data, contextual unlocks, connections.
func get_entry_detail(entry_id: StringName) -> Dictionary:
	var db := _get_clue_database()
	if db == null:
		return {}

	var entry: Dictionary = db.get_entry(entry_id)
	if entry.is_empty():
		return {}

	var unlock_ids: Array = db.get_contextual_unlocks(entry_id)
	var unlock_details: Array[Dictionary] = []
	for insight_id: StringName in unlock_ids:
		var insight: Dictionary = db.get_entry(insight_id)
		if not insight.is_empty():
			unlock_details.append({
				"insight_id": insight_id,
				"title": insight.get("title", ""),
				"reinterpretation": insight.get("reinterpretation", ""),
				"discovered_at_night": insight.get("discovered_at_night", 0),
			})
	unlock_details.sort_custom(_compare_unlocks_by_night)

	var connections: Array[Dictionary] = db.get_connections_for(entry_id)

	return {
		"entry": entry,
		"contextual_unlocks": unlock_details,
		"connections": connections,
	}


# -- Board View ---------------------------------------------------------------


## Returns all board nodes (one per discovered entry).
## CLUE = circular node, INSIGHT = diamond node (larger).
func get_board_nodes() -> Array[Dictionary]:
	var db := _get_clue_database()
	if db == null:
		return []

	var nodes: Array[Dictionary] = []
	var index := 0
	var total := db.entries.size()

	for entry_id: StringName in db.entries:
		var entry: Dictionary = db.entries[entry_id]
		var pos := _get_node_position(entry_id, index, total)
		var node_color := _map_node_color(entry)
		var size := insight_node_size if entry["entry_type"] == 1 else clue_node_size
		var state: String = "selected" if entry_id in _selected_entries else "normal"

		nodes.append({
			"entry_id": entry_id,
			"position": pos,
			"size": size,
			"color": node_color,
			"state": state,
			"entry_type": entry["entry_type"],
		})
		index += 1

	return nodes


## Returns all board edges (one per connection).
## Valid = gold ochre solid, Invalid = gray dashed.
func get_board_edges() -> Array[Dictionary]:
	var db := _get_clue_database()
	if db == null:
		return []

	var edges: Array[Dictionary] = []
	var valid_conns: Array[Dictionary] = db.get_valid_connections()
	var all_clues: Array[StringName] = db.get_all_clues()
	var max_connections := maxi(all_clues.size() - 1, 1)

	for conn: Dictionary in db.connections:
		var edge_color: Color
		var edge_width: float

		if conn["is_valid"]:
			var intensity := 0.40 + (float(valid_conns.size()) / float(max_connections)) * 0.60
			edge_color = Color(GOLD_OCHRE.r, GOLD_OCHRE.g, GOLD_OCHRE.b, clampf(intensity, 0.0, 1.0))
			edge_width = valid_edge_width
		else:
			edge_color = Color(0.5, 0.5, 0.5, invalid_edge_alpha)
			edge_width = invalid_edge_width

		edges.append({
			"clue_a": conn["clue_a"],
			"clue_b": conn["clue_b"],
			"is_valid": conn["is_valid"],
			"color": edge_color,
			"width": edge_width,
		})

	return edges


## Saves a node position from player drag. Persists across open/close.
func update_node_position(entry_id: StringName, x: float, y: float) -> void:
	_node_positions[entry_id] = Vector2(x, y)


# -- Selection -----------------------------------------------------------------


## Selects an entry. Multiple entries can be selected simultaneously.
func select_entry(entry_id: StringName) -> void:
	if entry_id not in _selected_entries:
		_selected_entries.append(entry_id)
	entry_selected.emit(entry_id)


## Clears all selections.
func deselect_all() -> void:
	_selected_entries.clear()
	entry_deselected.emit()


## Returns currently selected entry IDs.
func get_selected() -> Array[StringName]:
	return _selected_entries.duplicate()


# -- Connection Delegation -----------------------------------------------------


## Delegates a connection request to ClueConnectionManager.
func request_connection(clue_a: StringName, clue_b: StringName) -> Dictionary:
	var ccm := _get_connection_manager()
	if ccm == null:
		connection_attempted.emit(clue_a, clue_b, false)
		return {"ok": false, "reason": "connection_manager_unavailable", "is_valid": false, "insight_id": &""}

	var result: Dictionary = ccm.request_connection(clue_a, clue_b)
	var success: bool = result.get("ok", false)
	connection_attempted.emit(clue_a, clue_b, success)
	return result


# -- Serialization -------------------------------------------------------------


## Serializes node positions for save/load.
func serialize() -> Dictionary:
	var positions: Dictionary = {}
	for entry_id: StringName in _node_positions:
		var pos: Vector2 = _node_positions[entry_id]
		positions[String(entry_id)] = {"x": pos.x, "y": pos.y}
	return {"node_positions": positions}


## Restores node positions from serialized data.
func deserialize(data: Dictionary) -> bool:
	var positions: Dictionary = data.get("node_positions", {})
	_node_positions.clear()
	for entry_key: String in positions:
		var pos_data: Dictionary = positions[entry_key]
		_node_positions[StringName(entry_key)] = Vector2(
			pos_data.get("x", 0.0),
			pos_data.get("y", 0.0),
		)
	return true


## Resets to default state.
func reset() -> void:
	if is_open:
		close_notebook()
	_selected_entries.clear()
	_node_positions.clear()
	_previous_time_scale = 1.0
	_node_random_offsets.clear()


# -- Private -------------------------------------------------------------------


func _rebuild_board() -> void:
	_ensure_random_offsets()
	board_updated.emit()


func _calculate_search_score(entry: Dictionary, query: String) -> float:
	var score := 0.0
	var lower_query := query.to_lower()

	if entry.get("title", "").to_lower().contains(lower_query):
		score += 2.0
	if entry.get("description", "").to_lower().contains(lower_query):
		score += 1.0

	var tags: Array = entry.get("tags", [])
	for tag: StringName in tags:
		if String(tag).to_lower().contains(lower_query):
			score += 0.5
			break

	return score


static func _compare_by_score_desc(a: Dictionary, b: Dictionary) -> bool:
	return a["score"] > b["score"]


static func _compare_unlocks_by_night(a: Dictionary, b: Dictionary) -> bool:
	return a.get("discovered_at_night", 0) < b.get("discovered_at_night", 0)


func _get_node_position(entry_id: StringName, index: int, total: int) -> Vector2:
	if _node_positions.has(entry_id):
		return _node_positions[entry_id]

	var angle := (float(index) / float(maxi(total, 1))) * TAU + _node_random_offsets.get(entry_id, 0.0)
	var x := board_center_x + board_layout_radius * cos(angle)
	var y := board_center_y + board_layout_radius * sin(angle)
	return Vector2(x, y)


func _ensure_random_offsets() -> void:
	var db := _get_clue_database()
	if db == null:
		return
	for entry_id: StringName in db.entries:
		if not _node_random_offsets.has(entry_id):
			_node_random_offsets[entry_id] = randf_range(-0.3, 0.3)


func _map_node_color(entry: Dictionary) -> Color:
	var affinity: StringName = entry.get("npc_affinity", &"")
	if affinity == &"":
		return GLOBAL_COLOR
	if NPC_COLOR_MAP.has(affinity):
		return NPC_COLOR_MAP[affinity]
	return GLOBAL_COLOR


func _connect_database_signals() -> void:
	var db := _get_clue_database()
	if db == null:
		return
	if db.has_signal("clue_discovered"):
		db.clue_discovered.connect(_on_entry_discovered)
	if db.has_signal("insight_generated"):
		db.insight_generated.connect(_on_entry_discovered)
	if db.has_signal("connection_made"):
		db.connection_made.connect(_on_connection_changed)


func _on_entry_discovered(_entry_id: StringName) -> void:
	if is_open:
		_rebuild_board()


func _on_connection_changed(_a: StringName, _b: StringName, _valid: bool) -> void:
	if is_open:
		_rebuild_board()


func _get_clue_database() -> Node:
	return get_node_or_null("/root/ClueDatabase")


func _get_connection_manager() -> Node:
	return get_node_or_null("/root/ClueConnectionManager")


func _get_timer_service() -> Node:
	return get_node_or_null("/root/TimerService")


func _get_interaction_bus() -> Node:
	return get_node_or_null("/root/InteractionBus")


func _get_dialogue_manager() -> Node:
	return get_node_or_null("/root/DialogueManager")
