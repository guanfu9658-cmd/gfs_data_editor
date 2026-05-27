class_name GameConfig
extends Resource
## 所有配置表类型的基类。用户只需 `extends GameConfig` 并声明 @export 字段。

## 主键统一放在基类中，业务配置不需要重复声明。
@export var id: int = 0


## 将当前 Resource 转为可写入 JSON 的字典（仅 @export 脚本变量）。
func to_row_dict() -> Dictionary:
	var result: Dictionary = {}
	for prop in _export_properties_from_script(get_script()):
		result[prop.name] = get(prop.name)
	return result


## 用字典填充当前对象（用于加载行数据）；缺失字段保留默认值。
func apply_row_dict(row: Dictionary) -> void:
	for prop in _export_properties_from_script(get_script()):
		if row.has(prop.name):
			set(prop.name, _coerce_value(prop, row[prop.name]))


static func make_default_row(script: Script) -> Dictionary:
	if script == null:
		return {}
	var inst = script.new()
	if inst == null:
		return {}
	var result: Dictionary = {}
	for prop in _export_properties_from_script(script):
		result[prop.name] = inst.get(prop.name)
	return result


static func merge_row_with_defaults(script: Script, row: Dictionary) -> Dictionary:
	var merged := make_default_row(script)
	for key in row.keys():
		merged[key] = row[key]
	if merged.has("id") and row.has("id"):
		merged["id"] = int(row["id"])
	return merged


static func _export_properties_from_script(script: Script) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if script == null:
		return list
	var inst = script.new()
	if inst == null:
		return list
	for p in inst.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE:
			if p.name.begins_with("_"):
				continue
			list.append(p)
	return list


static func _coerce_value(prop: Dictionary, value: Variant) -> Variant:
	if value == null:
		return prop.get("value", null)
	match prop.type:
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING:
			return str(value)
		_:
			return value
