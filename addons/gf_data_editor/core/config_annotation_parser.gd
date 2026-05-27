class_name ConfigAnnotationParser
extends RefCounted

static var _re_tab_category: RegEx
static var _re_tab_order: RegEx
static var _re_display_name: RegEx
static var _re_default_open: RegEx
static var _re_default_open_priority: RegEx
static var _re_config_ref: RegEx


static func _ensure_regex() -> void:
	if _re_tab_category != null:
		return
	_re_tab_category = _compile('@tab_category\\(\\s*"([^"]*)"\\s*\\)')
	_re_tab_order = _compile('@tab_order\\(\\s*(-?\\d+)\\s*\\)')
	_re_display_name = _compile('@display_name\\(\\s*"([^"]*)"\\s*\\)')
	_re_default_open = _compile('@default_open_tab')
	_re_default_open_priority = _compile('@default_open_tab\\(\\s*(-?\\d+)\\s*\\)')
	_re_config_ref = _compile(
		'@config_ref\\(\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*(?:,\\s*display_field\\s*=\\s*([A-Za-z_][A-Za-z0-9_]*))?'
	)


static func _compile(pattern: String) -> RegEx:
	var re := RegEx.new()
	re.compile(pattern)
	return re


static func parse_class_annotations(source: String) -> Dictionary:
	_ensure_regex()
	var head := _class_header(source)
	return {
		"tab_category": _first_match(_re_tab_category, head, "Other"),
		"tab_order": int(_first_match(_re_tab_order, head, "0")),
		"display_name": _first_match(_re_display_name, head, ""),
		"default_open_tab": _re_default_open.search(head) != null,
		"default_open_priority": _default_open_priority(head),
	}


static func parse_field_annotations(source: String, field_name: String) -> Dictionary:
	_ensure_regex()
	var block := _field_annotation_block(source, field_name)
	var ref_match := _re_config_ref.search(block)
	var config_ref: Dictionary = {}
	if ref_match:
		config_ref = {
			"target": ref_match.get_string(1),
			"display_field": ref_match.get_string(2) if ref_match.get_string(2) != "" else "name",
		}
	var display := _first_match(_re_display_name, block, "")
	return {
		"display_name": display,
		"config_ref": config_ref,
	}


static func _class_header(source: String) -> String:
	var idx := source.find("@export")
	if idx < 0:
		idx = source.find("func ")
	if idx < 0:
		return source
	return source.substr(0, idx)


static func _field_annotation_block(source: String, field_name: String) -> String:
	var lines := source.split("\n")
	var export_idx := -1
	var needle := "@export var %s" % field_name
	for i in lines.size():
		var line := String(lines[i]).strip_edges()
		if line.begins_with(needle):
			export_idx = i
			break
	if export_idx <= 0:
		return ""

	# 只读取“紧贴字段上方”的注释块，避免类级 @display_name 泄漏到字段。
	var collected: Array[String] = []
	var i := export_idx - 1
	while i >= 0:
		var prev_line := String(lines[i]).strip_edges()
		if prev_line.begins_with("##"):
			collected.push_front(prev_line)
			i -= 1
			continue
		break

	if collected.is_empty():
		return ""
	return "\n".join(collected)


static func _first_match(regex: RegEx, text: String, fallback: String) -> String:
	var m := regex.search(text)
	if m:
		return m.get_string(1)
	return fallback


static func _default_open_priority(head: String) -> int:
	_ensure_regex()
	var m := _re_default_open_priority.search(head)
	if m:
		return int(m.get_string(1))
	if _re_default_open.search(head):
		return 0
	return 9999
