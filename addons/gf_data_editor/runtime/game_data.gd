extends Node
## 运行时读取 game_data/*.json。在「项目 → 自动加载」中启用，或复制本脚本到你的工程。

const DEFAULT_DATA_DIR := "res://game_data/"

var _cache: Dictionary = {}


func clear_cache() -> void:
	_cache.clear()


func get_table_path(table_id: String) -> String:
	return DEFAULT_DATA_DIR + table_id + ".json"


func has_table(table_id: String) -> bool:
	return FileAccess.file_exists(get_table_path(table_id))


func get_table(table_id: String) -> Dictionary:
	if _cache.has(table_id):
		return _cache[table_id]
	var path := get_table_path(table_id)
	if not FileAccess.file_exists(path):
		_cache[table_id] = {}
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("GameData: invalid table json: %s" % path)
		_cache[table_id] = {}
		return {}
	_cache[table_id] = parsed
	return _cache[table_id]


func get_row(table_id: String, id: int) -> Dictionary:
	var table := get_table(table_id)
	var row = table.get(str(id), null)
	if row == null:
		return {}
	if typeof(row) != TYPE_DICTIONARY:
		return {}
	return row


func get_row_ids(table_id: String) -> Array:
	var table := get_table(table_id)
	var ids: Array = []
	for key in table.keys():
		if key == "_meta":
			continue
		ids.append(int(key))
	ids.sort()
	return ids
