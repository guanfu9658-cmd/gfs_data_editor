class_name JsonTableStore
extends RefCounted

var data_dir: String = GfPaths.GAME_DATA_DIR


func get_table_path(table_id: String) -> String:
	return data_dir.path_join(table_id + ".json")


func load_table(table_id: String, type_info: ConfigTypeInfo) -> Dictionary:
	var path := get_table_path(table_id)
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("JsonTableStore: invalid json %s" % path)
		return {}
	return _normalize_loaded_table(parsed, type_info)


func save_table(table_id: String, rows: Dictionary) -> Error:
	var abs_dir := ProjectSettings.globalize_path(data_dir)
	if abs_dir != "":
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var path := get_table_path(table_id)
	var to_save := rows.duplicate(true)
	if to_save.has("_meta"):
		to_save.erase("_meta")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_save, "\t"))
	return OK


func _normalize_loaded_table(raw: Dictionary, type_info: ConfigTypeInfo) -> Dictionary:
	var result: Dictionary = {}
	for key in raw.keys():
		if str(key) == "_meta":
			continue
		var row = raw[key]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		result[str(key)] = GameConfig.merge_row_with_defaults(type_info.config_script, row)
	return result


func compute_next_id(rows: Dictionary) -> int:
	var max_id := 0
	for key in rows.keys():
		var row: Dictionary = rows[key]
		if row.has("id"):
			max_id = maxi(max_id, int(row["id"]))
		else:
			max_id = maxi(max_id, int(key))
	return max_id + 1
