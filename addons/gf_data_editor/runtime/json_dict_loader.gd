class_name JsonDictLoader
extends RefCounted

## 通用读取：把 JSON 文件解析为 Dictionary。
## 失败时返回 {}，并打印 warning。

static func load_dict(path: String) -> Dictionary:
	if path == "":
		push_warning("JsonDictLoader: path is empty")
		return {}
	if not FileAccess.file_exists(path):
		push_warning("JsonDictLoader: file not found: %s" % path)
		return {}

	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges() == "":
		return {}

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("JsonDictLoader: root is not Dictionary: %s" % path)
		return {}
	return parsed


## 把根字典的 key 转为 int（常用于配置表：{"1": {...}} -> {1: {...}}）。
static func load_dict_int_keys(path: String) -> Dictionary:
	var raw := load_dict(path)
	if raw.is_empty():
		return {}
	var out: Dictionary = {}
	for k in raw.keys():
		var key_str := str(k)
		if key_str.is_valid_int():
			out[int(key_str)] = raw[k]
		else:
			out[key_str] = raw[k]
	return out


## 便捷方法：按目录 + 表名读取（例如 res://game_data + item）。
static func load_table_dict(table_name: String, data_dir: String = "res://game_data/") -> Dictionary:
	var path := data_dir.path_join(table_name + ".json")
	return load_dict(path)


## 便捷方法：按目录 + 表名读取，并把根 key 转成 int。
static func load_table_int_dict(table_name: String, data_dir: String = "res://game_data/") -> Dictionary:
	var path := data_dir.path_join(table_name + ".json")
	return load_dict_int_keys(path)
