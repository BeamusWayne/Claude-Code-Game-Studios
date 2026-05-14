extends Node

# Autoload singleton for the unified clue/insight knowledge database.
# Manages KnowledgeEntry records, Connection records, and contextual unlocks.
# See ADR-0005 for full schema and design rationale.

signal clue_discovered(clue_id: StringName)
signal insight_generated(insight_id: StringName)
signal connection_made(clue_a: StringName, clue_b: StringName, is_valid: bool)

enum EntryType { CLUE, INSIGHT }

const SCHEMA_VERSION: int = 1

var entries: Dictionary = {}
var connections: Array[Dictionary] = []

var _current_night: int = 0


# -- CRUD ----------------------------------------------------------------------

## Adds a validated KnowledgeEntry to the database. Returns false on validation failure.
func add_entry(entry: Dictionary) -> bool:
	if not _validate_entry(entry):
		return false

	var entry_id: StringName = entry["id"]
	if entries.has(entry_id):
		push_warning("ClueDatabase: entry '%s' already exists" % entry_id)
		return false

	if entry["entry_type"] == EntryType.INSIGHT:
		if not _validate_insight_source_clues(entry):
			return false
		_cascade_contextual_unlocks(entry_id, entry["source_clues"])

	entries[entry_id] = entry.duplicate(true)

	if entry["entry_type"] == EntryType.CLUE:
		clue_discovered.emit(entry_id)
	else:
		insight_generated.emit(entry_id)

	return true


## Returns the KnowledgeEntry for the given id, or an empty Dictionary if not found.
func get_entry(id: StringName) -> Dictionary:
	if entries.has(id):
		return entries[id]
	return {}


## Updates fields on an existing entry. Returns false if entry not found.
func update_entry(id: StringName, updates: Dictionary) -> bool:
	if not entries.has(id):
		return false

	var entry: Dictionary = entries[id]
	for key: String in updates:
		if key == "id" or key == "entry_type":
			continue
		entry[key] = updates[key]

	return true


## Removes an entry by id. For insights, cascade-cleans contextual_unlocks on source clues.
func remove_entry(id: StringName) -> bool:
	if not entries.has(id):
		return false

	var entry: Dictionary = entries[id]

	if entry["entry_type"] == EntryType.INSIGHT:
		var source_clues: Array = entry.get("source_clues", [])
		_remove_contextual_unlocks(id, source_clues)
		_remove_connections_for_insight(id)

	entries.erase(id)
	return true


# -- Search --------------------------------------------------------------------

## Returns all entry IDs whose tags array contains the given tag.
func search_by_tag(tag: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for entry_id: StringName in entries:
		var tags: Array = entries[entry_id].get("tags", [])
		if tag in tags:
			result.append(entry_id)
	return result


## Returns all entry IDs whose source matches the given source.
func search_by_source(source: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for entry_id: StringName in entries:
		if entries[entry_id].get("source", &"") == source:
			result.append(entry_id)
	return result


## Returns all entry IDs whose npc_affinity matches the given value.
func search_by_npc(npc_affinity: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for entry_id: StringName in entries:
		if entries[entry_id].get("npc_affinity", &"") == npc_affinity:
			result.append(entry_id)
	return result


## Returns all CLUE entry IDs.
func get_all_clues() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry_id: StringName in entries:
		if entries[entry_id]["entry_type"] == EntryType.CLUE:
			result.append(entry_id)
	return result


## Returns all INSIGHT entry IDs.
func get_all_insights() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry_id: StringName in entries:
		if entries[entry_id]["entry_type"] == EntryType.INSIGHT:
			result.append(entry_id)
	return result


## Returns all CLUE entry IDs that are not referenced by any insight's source_clues.
func get_undiscovered_clues() -> Array[StringName]:
	var discovered: Dictionary = {}
	for entry_id: StringName in entries:
		if entries[entry_id]["entry_type"] == EntryType.INSIGHT:
			var sources: Array = entries[entry_id].get("source_clues", [])
			for clue_id: StringName in sources:
				discovered[clue_id] = true

	var result: Array[StringName] = []
	for entry_id: StringName in entries:
		if entries[entry_id]["entry_type"] == EntryType.CLUE:
			if not discovered.has(entry_id):
				result.append(entry_id)
	return result


## Returns true if a CLUE entry with the given id exists.
func has_clue(id: StringName) -> bool:
	if not entries.has(id):
		return false
	return entries[id]["entry_type"] == EntryType.CLUE


## Returns true if an INSIGHT entry with the given id exists.
func has_insight(id: StringName) -> bool:
	if not entries.has(id):
		return false
	return entries[id]["entry_type"] == EntryType.INSIGHT


# -- Connections ---------------------------------------------------------------

## Connects two clue entries. Returns {ok, connection, reason} dict.
func connect_clues(clue_a: StringName, clue_b: StringName) -> Dictionary:
	if not entries.has(clue_a) or not entries.has(clue_b):
		return {"ok": false, "connection": {}, "reason": "clue_not_found"}

	if entries[clue_a]["entry_type"] != EntryType.CLUE or entries[clue_b]["entry_type"] != EntryType.CLUE:
		return {"ok": false, "connection": {}, "reason": "invalid_types"}

	var sorted_a: StringName = clue_a
	var sorted_b: StringName = clue_b
	if String(clue_b) < String(clue_a):
		sorted_a = clue_b
		sorted_b = clue_a

	if _connection_exists(sorted_a, sorted_b):
		return {"ok": false, "connection": {}, "reason": "duplicate"}

	var connection: Dictionary = {
		"clue_a": sorted_a,
		"clue_b": sorted_b,
		"made_at_night": _current_night,
		"is_valid": false,
		"insight_id": &"",
	}

	connections.append(connection)
	connection_made.emit(sorted_a, sorted_b, false)
	return {"ok": true, "connection": connection, "reason": ""}


## Returns all connections involving the given clue ID.
func get_connections_for(clue_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for conn: Dictionary in connections:
		if conn["clue_a"] == clue_id or conn["clue_b"] == clue_id:
			result.append(conn)
	return result


## Returns all connections where is_valid is true.
func get_valid_connections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for conn: Dictionary in connections:
		if conn["is_valid"]:
			result.append(conn)
	return result


## Returns all connections where is_valid is false.
func get_invalid_connections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for conn: Dictionary in connections:
		if not conn["is_valid"]:
			result.append(conn)
	return result


# -- Contextual Unlocks --------------------------------------------------------

## Returns the contextual_unlocks array for the given clue ID.
func get_contextual_unlocks(clue_id: StringName) -> Array[StringName]:
	if not entries.has(clue_id):
		return []
	var unlocks: Array = entries[clue_id].get("contextual_unlocks", [])
	var result: Array[StringName] = []
	for unlock_id: StringName in unlocks:
		result.append(unlock_id)
	return result


## Returns true if the given clue has at least one contextual unlock (insight).
func has_insight_for(clue_id: StringName) -> bool:
	if not entries.has(clue_id):
		return false
	var unlocks: Array = entries[clue_id].get("contextual_unlocks", [])
	return not unlocks.is_empty()


# -- Night Tracking (set by gameplay layer) ------------------------------------

## Sets the current night value used for connection timestamps.
func set_current_night(night: int) -> void:
	_current_night = night


## Returns the current night value.
func get_current_night() -> int:
	return _current_night


# -- Serialization -------------------------------------------------------------

## Serializes all entries and connections to a Dictionary suitable for JSON.
func serialize() -> Dictionary:
	var serialized_entries: Dictionary = {}
	for entry_id: StringName in entries:
		serialized_entries[String(entry_id)] = _serialize_entry(entries[entry_id])

	var serialized_connections: Array = []
	for conn: Dictionary in connections:
		serialized_connections.append(_serialize_connection(conn))

	return {
		"schema_version": SCHEMA_VERSION,
		"entries": serialized_entries,
		"connections": serialized_connections,
	}


## Restores database state from a serialized Dictionary. Returns false on failure.
func deserialize(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	if data.get("schema_version", 0) != SCHEMA_VERSION:
		push_warning("ClueDatabase: unsupported schema version %d" % data.get("schema_version", 0))
		return false

	entries.clear()
	connections.clear()

	var raw_entries: Dictionary = data.get("entries", {})
	for entry_key: String in raw_entries:
		var entry: Dictionary = raw_entries[entry_key]
		var typed_entry: Dictionary = _deserialize_entry(entry)
		entries[StringName(entry_key)] = typed_entry

	var raw_connections: Array = data.get("connections", [])
	for conn_data: Dictionary in raw_connections:
		var conn: Dictionary = _deserialize_connection(conn_data)
		connections.append(conn)

	return true


## Clears all entries and connections, resetting to empty state.
func reset() -> void:
	entries.clear()
	connections.clear()
	_current_night = 0


# -- Private: Validation -------------------------------------------------------

func _validate_entry(entry: Dictionary) -> bool:
	var required_keys: Array[String] = [
		"id", "entry_type", "title", "description", "source",
		"discovered_at_night", "npc_affinity", "tags",
		"contextual_unlocks", "metadata",
	]
	for key: String in required_keys:
		if not entry.has(key):
			push_warning("ClueDatabase: missing required field '%s'" % key)
			return false

	var entry_type: int = entry["entry_type"]
	if entry_type != EntryType.CLUE and entry_type != EntryType.INSIGHT:
		push_warning("ClueDatabase: invalid entry_type %d" % entry_type)
		return false

	if entry_type == EntryType.INSIGHT:
		if not entry.has("source_clues"):
			push_warning("ClueDatabase: INSIGHT entry missing 'source_clues'")
			return false
		if not entry.has("reinterpretation"):
			push_warning("ClueDatabase: INSIGHT entry missing 'reinterpretation'")
			return false

	return true


func _validate_insight_source_clues(entry: Dictionary) -> bool:
	var source_clues: Array = entry.get("source_clues", [])
	if source_clues.size() != 2:
		push_warning("ClueDatabase: INSIGHT must have exactly 2 source_clues, got %d" % source_clues.size())
		return false

	for clue_id: StringName in source_clues:
		if not entries.has(clue_id):
			push_warning("ClueDatabase: source clue '%s' does not exist" % clue_id)
			return false
		if entries[clue_id]["entry_type"] != EntryType.CLUE:
			push_warning("ClueDatabase: source '%s' is not a CLUE" % clue_id)
			return false

	return true


# -- Private: Contextual Unlock Cascade ----------------------------------------

func _cascade_contextual_unlocks(insight_id: StringName, source_clues: Array) -> void:
	for clue_id: StringName in source_clues:
		if entries.has(clue_id):
			var unlocks: Array = entries[clue_id].get("contextual_unlocks", [])
			if not insight_id in unlocks:
				unlocks.append(insight_id)
			entries[clue_id]["contextual_unlocks"] = unlocks


func _remove_contextual_unlocks(insight_id: StringName, source_clues: Array) -> void:
	for clue_id: StringName in source_clues:
		if entries.has(clue_id):
			var unlocks: Array = entries[clue_id].get("contextual_unlocks", [])
			unlocks.erase(insight_id)
			entries[clue_id]["contextual_unlocks"] = unlocks


func _remove_connections_for_insight(insight_id: StringName) -> void:
	var i: int = connections.size() - 1
	while i >= 0:
		if connections[i].get("insight_id", &"") == insight_id:
			connections.remove_at(i)
		i -= 1


# -- Private: Connection Helpers -----------------------------------------------

func _connection_exists(clue_a: StringName, clue_b: StringName) -> bool:
	for conn: Dictionary in connections:
		if conn["clue_a"] == clue_a and conn["clue_b"] == clue_b:
			return true
	return false


# -- Private: Serialization Helpers --------------------------------------------

func _serialize_entry(entry: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"id": String(entry["id"]),
		"entry_type": entry["entry_type"],
		"title": entry["title"],
		"description": entry["description"],
		"source": String(entry["source"]),
		"discovered_at_night": entry["discovered_at_night"],
		"npc_affinity": String(entry["npc_affinity"]),
		"tags": [],
		"contextual_unlocks": [],
		"metadata": entry.get("metadata", {}),
	}

	var tags: Array = entry.get("tags", [])
	for tag: StringName in tags:
		result["tags"].append(String(tag))

	var unlocks: Array = entry.get("contextual_unlocks", [])
	for unlock_id: StringName in unlocks:
		result["contextual_unlocks"].append(String(unlock_id))

	if entry["entry_type"] == EntryType.INSIGHT:
		var source_clues: Array = entry.get("source_clues", [])
		var serialized_sources: Array = []
		for clue_id: StringName in source_clues:
			serialized_sources.append(String(clue_id))
		result["source_clues"] = serialized_sources
		result["reinterpretation"] = entry.get("reinterpretation", "")

	return result


func _serialize_connection(conn: Dictionary) -> Dictionary:
	return {
		"clue_a": String(conn["clue_a"]),
		"clue_b": String(conn["clue_b"]),
		"made_at_night": conn["made_at_night"],
		"is_valid": conn["is_valid"],
		"insight_id": String(conn.get("insight_id", &"")),
	}


func _deserialize_entry(raw: Dictionary) -> Dictionary:
	var tags: Array[StringName] = []
	for tag: String in raw.get("tags", []):
		tags.append(StringName(tag))

	var unlocks: Array[StringName] = []
	for unlock_id: String in raw.get("contextual_unlocks", []):
		unlocks.append(StringName(unlock_id))

	var entry: Dictionary = {
		"id": StringName(raw.get("id", &"")),
		"entry_type": raw.get("entry_type", EntryType.CLUE),
		"title": raw.get("title", ""),
		"description": raw.get("description", ""),
		"source": StringName(raw.get("source", &"")),
		"discovered_at_night": raw.get("discovered_at_night", 0),
		"npc_affinity": StringName(raw.get("npc_affinity", &"")),
		"tags": tags,
		"contextual_unlocks": unlocks,
		"metadata": raw.get("metadata", {}),
	}

	if entry["entry_type"] == EntryType.INSIGHT:
		var source_clues: Array[StringName] = []
		for clue_id: String in raw.get("source_clues", []):
			source_clues.append(StringName(clue_id))
		entry["source_clues"] = source_clues
		entry["reinterpretation"] = raw.get("reinterpretation", "")

	return entry


func _deserialize_connection(raw: Dictionary) -> Dictionary:
	return {
		"clue_a": StringName(raw.get("clue_a", &"")),
		"clue_b": StringName(raw.get("clue_b", &"")),
		"made_at_night": raw.get("made_at_night", 0),
		"is_valid": raw.get("is_valid", false),
		"insight_id": StringName(raw.get("insight_id", &"")),
	}
