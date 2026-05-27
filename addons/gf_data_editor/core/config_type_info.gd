class_name ConfigTypeInfo
extends RefCounted

var class_name_id: String
var script_path: String
var config_script: Script
var tab_category: String = "Other"
var tab_order: int = 0
var display_name: String = ""
var default_open_tab: bool = false
var default_open_priority: int = 9999
var fields: Array[Dictionary] = []


func get_display_title(fallback_index: int = 0) -> String:
	if display_name != "":
		return display_name
	return class_name_id if class_name_id != "" else ("表 %d" % fallback_index)


func get_field_display(field_name: String) -> String:
	for f in fields:
		if f.name == field_name:
			if f.display_name != "":
				return f.display_name
			return field_name
	return field_name


func find_field(field_name: String) -> Dictionary:
	for f in fields:
		if f.name == field_name:
			return f
	return {}
