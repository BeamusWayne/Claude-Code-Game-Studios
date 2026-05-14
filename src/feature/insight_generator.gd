class_name InsightGenerator
extends RefCounted

## Pure logic utility for validating clue connections and generating insight entries.
## Not a Node, not an Autoload -- stateless validation and construction only.
## GDD: design/gdd/insight-generation.md, ADR-0005

var _connection_lookup: Dictionary = {}


## Loads connection definitions from an array of Dictionaries.
## Each definition must have clue_a, clue_b, and resulting_insight keys.
func load_definitions(definitions: Array[Dictionary]) -> void:
	for def: Dictionary in definitions:
		register_definition(def)


## Registers a single connection definition. Silently skips invalid entries.
func register_definition(definition: Dictionary) -> void:
	var clue_a: StringName = definition.get("clue_a", &"")
	var clue_b: StringName = definition.get("clue_b", &"")
	if clue_a == &"" or clue_b == &"":
		return
	var key: String = _make_key(clue_a, clue_b)
	_connection_lookup[key] = definition


## Validates whether a clue pair has a matching connection definition.
## Returns the definition Dictionary if found, or empty Dictionary if not.
func validate_connection(clue_a: StringName, clue_b: StringName) -> Dictionary:
	var key: String = _make_key(clue_a, clue_b)
	if _connection_lookup.has(key):
		return _connection_lookup[key]
	return {}


## Generates an INSIGHT KnowledgeEntry from a valid connection definition.
## The definition should come from validate_connection().
## Builds the full entry following ADR-0005 schema.
func generate_insight(definition: Dictionary, current_night: int) -> Dictionary:
	var insight_data: Dictionary = definition.get("resulting_insight", {})
	var source_a: StringName = definition.get("clue_a", &"")
	var source_b: StringName = definition.get("clue_b", &"")

	var tags: Array[StringName] = []
	for tag: StringName in insight_data.get("tags", []):
		tags.append(tag)

	return {
		"id": insight_data.get("id", &""),
		"entry_type": 1,  # EntryType.INSIGHT
		"title": insight_data.get("title", ""),
		"description": insight_data.get("description", ""),
		"source": &"connection",
		"discovered_at_night": current_night,
		"npc_affinity": insight_data.get("npc_affinity", &""),
		"tags": tags,
		"contextual_unlocks": [],
		"metadata": {"weight": insight_data.get("weight", 1.0)},
		"source_clues": [source_a, source_b],
		"reinterpretation": insight_data.get("reinterpretation", ""),
	}


## Returns the number of registered connection definitions.
func get_definition_count() -> int:
	return _connection_lookup.size()


## Generates the bidirectional lookup key for a clue pair.
## min(a,b) + "+" + max(a,b) ensures A+B and B+A map to the same key.
func _make_key(clue_a: StringName, clue_b: StringName) -> String:
	var a: String = String(clue_a)
	var b: String = String(clue_b)
	if b < a:
		return b + "+" + a
	return a + "+" + b
