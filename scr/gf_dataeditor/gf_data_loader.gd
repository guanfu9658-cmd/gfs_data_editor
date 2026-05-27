extends Node

const JSON_DICT_LOADER_SCRIPT := preload("res://addons/gf_data_editor/runtime/json_dict_loader.gd")

var tables: Dictionary = {}

const SCRIPT_CFG_NPC := preload("res://data_configs/NPC.gd")

var cfg_npc: Dictionary = {}

func _ready() -> void:
	reload_all()

func reload_all() -> void:
	tables.clear()
	var raw_cfg_npc := JSON_DICT_LOADER_SCRIPT.load_table_int_dict("npc")
	cfg_npc = _to_typed_dict(raw_cfg_npc, SCRIPT_CFG_NPC)
	tables["npc"] = cfg_npc

func get_table(table_name: String) -> Dictionary:
	return tables.get(table_name, {})

func get_row(table_name: String, id: int) -> Variant:
	var table: Dictionary = get_table(table_name)
	var row = table.get(id, null)
	if row == null:
		row = table.get(str(id), null)
	return row

func _to_typed_dict(raw_table: Dictionary, script: Script) -> Dictionary:
	var result: Dictionary = {}
	for key in raw_table.keys():
		var row = raw_table[key]
		var id_val := int(key)
		if typeof(row) == TYPE_DICTIONARY:
			result[id_val] = _deserialize_object(script, row)
		else:
			result[id_val] = row
	return result

func _deserialize_object(script: Script, row: Dictionary) -> Variant:
	if script == null:
		return row
	var obj = script.new()
	if obj == null:
		return row
	for p in obj.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE):
			continue
		var prop_name := str(p.name)
		if not row.has(prop_name):
			continue
		var default_value = obj.get(prop_name)
		obj.set(prop_name, _deserialize_value(default_value, row[prop_name], p.type))
	return obj

func _deserialize_value(default_value: Variant, value: Variant, value_type: int) -> Variant:
	if value == null:
		return default_value
	if default_value is Resource and typeof(value) == TYPE_DICTIONARY:
		var nested_script: Script = (default_value as Resource).get_script()
		if nested_script != null:
			return _deserialize_object(nested_script, value)
	if value_type == TYPE_ARRAY and typeof(value) == TYPE_ARRAY:
		var out: Array = []
		var src: Array = value
		var typed_script: Script = null
		if typeof(default_value) == TYPE_ARRAY:
			var def_arr: Array = default_value
			typed_script = def_arr.get_typed_script()
		for it in src:
			if typed_script != null and typeof(it) == TYPE_DICTIONARY:
				out.append(_deserialize_object(typed_script, it))
			else:
				out.append(it)
		return out
	return value
