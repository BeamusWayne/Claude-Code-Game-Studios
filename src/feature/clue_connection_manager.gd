extends Node

## ClueConnectionManager — autoload singleton for clue connection/deduction.
## Coordinates connection requests, validates via InsightGenerator, generates insights.
## GDD: design/gdd/clue-connection-deduction.md, ADR-0005

signal connection_requested(clue_a: StringName, clue_b: StringName, is_valid: bool)

var _generator: RefCounted


func _ready() -> void:
	_generator = _create_generator()


## Registers a single ConnectionDefinition for valid clue pairs.
func register_definition(definition: Dictionary) -> void:
	_generator.register_definition(definition)


## Bulk-registers ConnectionDefinitions from an array.
func load_definitions(definitions: Array[Dictionary]) -> void:
	for def: Dictionary in definitions:
		_generator.register_definition(def)


## Requests a connection between two clues. Returns a result Dictionary.
## Returns: { ok: bool, reason: String, is_valid: bool, insight_id: StringName }
func request_connection(clue_a: StringName, clue_b: StringName) -> Dictionary:
	var db: Node = _get_clue_database()
	if db == null:
		return {"ok": false, "reason": "database_unavailable", "is_valid": false, "insight_id": &""}

	if clue_a == clue_b:
		return {"ok": false, "reason": "duplicate", "is_valid": false, "insight_id": &""}

	if not db.has_clue(clue_a) or not db.has_clue(clue_b):
		return {"ok": false, "reason": "clue_not_found", "is_valid": false, "insight_id": &""}

	var sorted_a: StringName = clue_a
	var sorted_b: StringName = clue_b
	if String(clue_b) < String(clue_a):
		sorted_a = clue_b
		sorted_b = clue_a

	if _connection_exists(db, sorted_a, sorted_b):
		return {"ok": false, "reason": "duplicate", "is_valid": false, "insight_id": &""}

	var definition: Dictionary = _generator.validate_connection(clue_a, clue_b)
	var is_valid: bool = not definition.is_empty()
	var insight_id: StringName = &""
	var night: int = db.get_current_night()

	var connection: Dictionary = {
		"clue_a": sorted_a,
		"clue_b": sorted_b,
		"made_at_night": night,
		"is_valid": is_valid,
		"insight_id": &"",
	}

	if is_valid:
		var insight_entry: Dictionary = _generator.generate_insight(definition, night)
		insight_id = insight_entry["id"]
		connection["insight_id"] = insight_id
		db.add_entry(insight_entry)

	db.connections.append(connection)
	db.connection_made.emit(sorted_a, sorted_b, is_valid)
	connection_requested.emit(sorted_a, sorted_b, is_valid)

	return {"ok": true, "reason": "", "is_valid": is_valid, "insight_id": insight_id}


## Returns true if a valid connection could be made for this pair.
func can_connect(clue_a: StringName, clue_b: StringName) -> bool:
	var db: Node = _get_clue_database()
	if db == null:
		return false
	if not db.has_clue(clue_a) or not db.has_clue(clue_b):
		return false
	if clue_a == clue_b:
		return false
	var sorted_a: StringName = clue_a
	var sorted_b: StringName = clue_b
	if String(clue_b) < String(clue_a):
		sorted_a = clue_b
		sorted_b = clue_a
	if _connection_exists(db, sorted_a, sorted_b):
		return false
	return not _generator.validate_connection(clue_a, clue_b).is_empty()


## Returns the InsightGenerator instance (for testing).
func get_generator() -> RefCounted:
	return _generator


func serialize() -> Dictionary:
	return {"definition_count": _generator.get_definition_count()}


func deserialize(_data: Dictionary) -> bool:
	return true


func reset() -> void:
	_generator = _create_generator()


func _connection_exists(db: Node, sorted_a: StringName, sorted_b: StringName) -> bool:
	for conn: Dictionary in db.connections:
		if conn["clue_a"] == sorted_a and conn["clue_b"] == sorted_b:
			return true
	return false


func _create_generator() -> RefCounted:
	var gen := RefCounted.new()
	gen.set_script(_generator_script())
	return gen


func _generator_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = (
		"extends RefCounted\n"
		+ "var _connection_lookup: Dictionary = {}\n"
		+ "func register_definition(definition: Dictionary) -> void:\n"
		+ "\tvar clue_a: StringName = definition.get(\"clue_a\", &\"\")\n"
		+ "\tvar clue_b: StringName = definition.get(\"clue_b\", &\"\")\n"
		+ "\tif clue_a == &\"\" or clue_b == &\"\":\n"
		+ "\t\treturn\n"
		+ "\tvar key: String = _make_key(clue_a, clue_b)\n"
		+ "\t_connection_lookup[key] = definition\n"
		+ "func validate_connection(clue_a: StringName, clue_b: StringName) -> Dictionary:\n"
		+ "\tvar key: String = _make_key(clue_a, clue_b)\n"
		+ "\tif _connection_lookup.has(key):\n"
		+ "\t\treturn _connection_lookup[key]\n"
		+ "\treturn {}\n"
		+ "func generate_insight(definition: Dictionary, night: int) -> Dictionary:\n"
		+ "\tvar insight_data: Dictionary = definition.get(\"resulting_insight\", {})\n"
		+ "\tvar source_a: StringName = definition.get(\"clue_a\", &\"\")\n"
		+ "\tvar source_b: StringName = definition.get(\"clue_b\", &\"\")\n"
		+ "\tvar tags: Array[StringName] = []\n"
		+ "\tfor tag: StringName in insight_data.get(\"tags\", []):\n"
		+ "\t\ttags.append(tag)\n"
		+ "\treturn {\n"
		+ "\t\t\"id\": insight_data.get(\"id\", &\"\"),\n"
		+ "\t\t\"entry_type\": 1,\n"
		+ "\t\t\"title\": insight_data.get(\"title\", \"\"),\n"
		+ "\t\t\"description\": insight_data.get(\"description\", \"\"),\n"
		+ "\t\t\"source\": source_a,\n"
		+ "\t\t\"discovered_at_night\": night,\n"
		+ "\t\t\"npc_affinity\": insight_data.get(\"npc_affinity\", &\"\"),\n"
		+ "\t\t\"tags\": tags,\n"
		+ "\t\t\"contextual_unlocks\": [],\n"
		+ "\t\t\"metadata\": {\"weight\": insight_data.get(\"weight\", 1.0)},\n"
		+ "\t\t\"source_clues\": [source_a, source_b],\n"
		+ "\t\t\"reinterpretation\": insight_data.get(\"reinterpretation\", \"\"),\n"
		+ "\t}\n"
		+ "func get_definition_count() -> int:\n"
		+ "\treturn _connection_lookup.size()\n"
		+ "func _make_key(clue_a: StringName, clue_b: StringName) -> String:\n"
		+ "\tvar a: String = String(clue_a)\n"
		+ "\tvar b: String = String(clue_b)\n"
		+ "\tif b < a:\n"
		+ "\t\treturn b + \"+\" + a\n"
		+ "\treturn a + \"+\" + b\n"
	)
	script.reload()
	return script


func _get_clue_database() -> Node:
	return get_node_or_null("/root/ClueDatabase")
