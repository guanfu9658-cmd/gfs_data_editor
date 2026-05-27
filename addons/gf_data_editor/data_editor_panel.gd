@tool
extends Control

const ConfigTableEditorScene := preload("res://addons/gf_data_editor/ui/config_table_editor.tscn")
const _GameConfigScript := preload("res://addons/gf_data_editor/runtime/game_config.gd")

var _registry: ConfigTypeRegistry
var _store := JsonTableStore.new()
var _all_tables: Dictionary = {}
var _editors: Dictionary = {}

var _txt_project: Label
var _outer_tabs: TabContainer
var _btn_refresh: Button
var _btn_generate_loader: Button


func _ready() -> void:
	_bind_nodes()
	if _btn_refresh:
		_btn_refresh.pressed.connect(_reload_all)
	if _btn_generate_loader:
		_btn_generate_loader.pressed.connect(_generate_runtime_loader_singleton)


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		call_deferred("_reload_all")


func _bind_nodes() -> void:
	_txt_project = get_node_or_null("%TxtProjectInfo") as Label
	_outer_tabs = get_node_or_null("%OuterTabs") as TabContainer
	_btn_refresh = get_node_or_null("%BtnRefresh") as Button
	_btn_generate_loader = get_node_or_null("%BtnGenerateLoader") as Button
	if _txt_project == null:
		_txt_project = get_node_or_null("ProjectBar/BarRow/TxtProjectInfo") as Label
	if _outer_tabs == null:
		_outer_tabs = get_node_or_null("OuterTabs") as TabContainer
	if _btn_refresh == null:
		_btn_refresh = get_node_or_null("ProjectBar/BarRow/BtnRefresh") as Button
	if _btn_generate_loader == null:
		_btn_generate_loader = get_node_or_null("ProjectBar/BarRow/BtnGenerateLoader") as Button


func _get_registry() -> ConfigTypeRegistry:
	if _registry == null:
		_registry = ConfigTypeRegistry.new()
	return _registry


func _set_status(text: String) -> void:
	if _txt_project:
		_txt_project.text = text


func _reload_all() -> void:
	_bind_nodes()
	if _outer_tabs == null:
		_set_status("界面未就绪，请重新打开「数据编辑器」标签。")
		push_error("GF Data Editor: OuterTabs not found.")
		return

	_ensure_required_dirs()

	_set_status("正在扫描配置类型…")
	_ensure_game_config_registered()
	_get_registry().scan()

	var types := _get_registry().get_all()
	if types.is_empty():
		_clear_tabs()
		_set_status("未找到 *Config。请在 res://data_configs/ 添加继承 GameConfig 的脚本。")
		return

	_set_status("正在加载数据…")
	_load_all_tables()

	_set_status("正在构建界面…")
	if not _rebuild_tabs():
		_set_status("界面构建失败，请查看输出面板并点「刷新」。")
		return

	var names: PackedStringArray = []
	for info: ConfigTypeInfo in types:
		names.append(info.get_display_title())
	_set_status("已加载 %d 张表：%s" % [types.size(), ", ".join(names)])


func _ensure_required_dirs() -> void:
	_ensure_dir("res://data_configs")
	_ensure_dir("res://game_data")


func _ensure_dir(res_path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(res_path)
	if abs_path == "":
		return
	var err := DirAccess.make_dir_recursive_absolute(abs_path)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_warning("GF Data Editor: 创建目录失败 %s (err=%d)" % [res_path, err])


func _ensure_game_config_registered() -> void:
	if ClassDB.class_exists(&"GameConfig"):
		return
	var _dummy = _GameConfigScript


func _load_all_tables() -> void:
	_all_tables.clear()
	for info: ConfigTypeInfo in _get_registry().get_all():
		_all_tables[info.class_name_id] = _store.load_table(info.class_name_id, info)


func _clear_tabs() -> void:
	for child in _outer_tabs.get_children():
		_outer_tabs.remove_child(child)
		child.queue_free()
	_editors.clear()


func _rebuild_tabs() -> bool:
	_clear_tabs()
	var categories := _get_registry().get_by_categories()
	if categories.is_empty():
		return false

	var default_type := _get_registry().get_default_open_type()
	var default_outer := 0
	var default_inner := 0

	for cat_idx in categories.size():
		var cat: Dictionary = categories[cat_idx]
		var inner := TabContainer.new()
		inner.name = "Category_%s" % str(cat.get("name", "Other"))
		_prepare_tab_content(inner)
		var types: Array = cat.get("types", [])
		for type_idx in types.size():
			var info: ConfigTypeInfo = types[type_idx]
			var editor: ConfigTableEditor = ConfigTableEditorScene.instantiate()
			if editor == null:
				push_error("GF Data Editor: ConfigTableEditor instantiate failed.")
				return false
			_prepare_tab_page(editor)
			inner.add_child(editor)
			editor.name = "Type_%s" % info.class_name_id
			inner.set_tab_title(type_idx, info.get_display_title(type_idx + 1))
			_editors[info.class_name_id] = editor
			_connect_table_editor_signals(editor)
			editor.setup(info, _get_registry(), _store, _all_tables)
			if default_type and info.class_name_id == default_type.class_name_id:
				default_outer = cat_idx
				default_inner = type_idx
		_prepare_tab_page(inner)
		_outer_tabs.add_child(inner)
		_outer_tabs.set_tab_title(cat_idx, str(cat.get("name", "Other")))

	_outer_tabs.current_tab = default_outer
	var inner_tabs := _get_inner_tab_container(default_outer)
	if inner_tabs and default_inner < inner_tabs.get_tab_count():
		inner_tabs.current_tab = default_inner
	call_deferred("_refresh_visible_editors")
	return true


func _refresh_visible_editors() -> void:
	for ed: ConfigTableEditor in _editors.values():
		if ed.is_inside_tree():
			ed.call_deferred("_refresh_list")


func _get_inner_tab_container(outer_index: int) -> TabContainer:
	if outer_index < 0 or outer_index >= _outer_tabs.get_child_count():
		return null
	return _outer_tabs.get_child(outer_index) as TabContainer


func _connect_table_editor_signals(editor: ConfigTableEditor) -> void:
	if editor == null:
		return
	if not editor.has_signal(&"table_saved"):
		push_warning("GF Data Editor: ConfigTableEditor missing table_saved signal.")
		return
	if not editor.table_saved.is_connected(_on_table_saved):
		editor.table_saved.connect(_on_table_saved)


func _on_table_saved(table_id: String) -> void:
	var ed: ConfigTableEditor = _editors.get(table_id)
	if ed:
		_all_tables[table_id] = ed.get_rows().duplicate(true)
		_notify_editor_file_updated(table_id)
	_refresh_config_ref_forms()


func _refresh_config_ref_forms() -> void:
	for ed: ConfigTableEditor in _editors.values():
		ed.update_all_tables_cache(_all_tables)


func _notify_editor_file_updated(table_id: String) -> void:
	if not Engine.is_editor_hint():
		return
	var fs := EditorInterface.get_resource_filesystem()
	if fs == null:
		return
	var path := _store.get_table_path(table_id)
	if path != "":
		fs.update_file(path)
	# 对已打开的文本标签（JSON）做强同步，避免只更新资源树不更新文本视图。
	if not fs.is_scanning():
		call_deferred("_full_editor_fs_scan")


func _full_editor_fs_scan() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs == null:
		return
	if fs.is_scanning():
		return
	fs.scan()


func _generate_runtime_loader_singleton() -> void:
	var data_dir := "res://game_data"
	var dir := DirAccess.open(data_dir)
	if dir == null:
		_set_status("生成失败：找不到 %s" % data_dir)
		return

	var table_names: Array[String] = []
	for file_name in dir.get_files():
		if file_name.ends_with(".json"):
			table_names.append(file_name.trim_suffix(".json"))
	table_names.sort()
	if table_names.is_empty():
		_set_status("生成失败：%s 下没有 json 文件" % data_dir)
		return

	var target_dir := "res://scr/gf_dataeditor"
	var abs_target_dir := ProjectSettings.globalize_path(target_dir)
	var mk_err := DirAccess.make_dir_recursive_absolute(abs_target_dir)
	if mk_err != OK:
		_set_status("生成失败：无法创建目录 %s" % target_dir)
		return

	var loader_path := target_dir + "/gf_data_loader.gd"
	var table_script_paths: Dictionary = {}
	for info: ConfigTypeInfo in _get_registry().get_all():
		table_script_paths[info.class_name_id] = info.script_path
	var source := _build_loader_script_source(table_names, table_script_paths)
	var f := FileAccess.open(loader_path, FileAccess.WRITE)
	if f == null:
		_set_status("生成失败：无法写入 %s" % loader_path)
		return
	f.store_string(source)
	f.flush()

	ProjectSettings.set_setting("autoload/GFDataEditorLoader", "*" + loader_path)
	var save_err := ProjectSettings.save()
	if save_err != OK:
		_set_status("脚本已生成，但写入 autoload 失败。")
		return

	_set_status("已生成加载器并注册单例：GFDataEditorLoader")
	call_deferred("_full_editor_fs_scan")


func _build_loader_script_source(table_names: Array[String], table_script_paths: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("extends Node")
	lines.append("")
	lines.append("const JSON_DICT_LOADER_SCRIPT := preload(\"res://addons/gf_data_editor/runtime/json_dict_loader.gd\")")
	lines.append("")
	lines.append("var tables: Dictionary = {}")
	lines.append("")
	for table_name in table_names:
		var var_name := _loader_var_name(table_name)
		var script_path := str(table_script_paths.get(table_name, ""))
		if script_path != "":
			lines.append("const SCRIPT_%s := preload(\"%s\")" % [var_name.to_upper(), script_path])
	if table_names.size() > 0:
		lines.append("")
	for table_name in table_names:
		var var_name := _loader_var_name(table_name)
		lines.append("var %s: Dictionary = {}" % var_name)
	lines.append("")
	lines.append("func _ready() -> void:")
	lines.append("\treload_all()")
	lines.append("")
	lines.append("func reload_all() -> void:")
	lines.append("\ttables.clear()")
	for table_name in table_names:
		var var_name := _loader_var_name(table_name)
		var script_path := str(table_script_paths.get(table_name, ""))
		lines.append("\tvar raw_%s := JSON_DICT_LOADER_SCRIPT.load_table_int_dict(\"%s\")" % [var_name, table_name])
		if script_path != "":
			lines.append("\t%s = _to_typed_dict(raw_%s, SCRIPT_%s)" % [var_name, var_name, var_name.to_upper()])
		else:
			lines.append("\t%s = raw_%s" % [var_name, var_name])
		lines.append("\ttables[\"%s\"] = %s" % [table_name, var_name])
	lines.append("")
	lines.append("func get_table(table_name: String) -> Dictionary:")
	lines.append("\treturn tables.get(table_name, {})")
	lines.append("")
	lines.append("func get_row(table_name: String, id: int) -> Variant:")
	lines.append("\tvar table: Dictionary = get_table(table_name)")
	lines.append("\tvar row = table.get(id, null)")
	lines.append("\tif row == null:")
	lines.append("\t\trow = table.get(str(id), null)")
	lines.append("\treturn row")
	lines.append("")
	lines.append("func _to_typed_dict(raw_table: Dictionary, script: Script) -> Dictionary:")
	lines.append("\tvar result: Dictionary = {}")
	lines.append("\tfor key in raw_table.keys():")
	lines.append("\t\tvar row = raw_table[key]")
	lines.append("\t\tvar id_val := int(key)")
	lines.append("\t\tif typeof(row) == TYPE_DICTIONARY:")
	lines.append("\t\t\tresult[id_val] = _deserialize_object(script, row)")
	lines.append("\t\telse:")
	lines.append("\t\t\tresult[id_val] = row")
	lines.append("\treturn result")
	lines.append("")
	lines.append("func _deserialize_object(script: Script, row: Dictionary) -> Variant:")
	lines.append("\tif script == null:")
	lines.append("\t\treturn row")
	lines.append("\tvar obj = script.new()")
	lines.append("\tif obj == null:")
	lines.append("\t\treturn row")
	lines.append("\tfor p in obj.get_property_list():")
	lines.append("\t\tif not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE):")
	lines.append("\t\t\tcontinue")
	lines.append("\t\tvar prop_name := str(p.name)")
	lines.append("\t\tif not row.has(prop_name):")
	lines.append("\t\t\tcontinue")
	lines.append("\t\tvar default_value = obj.get(prop_name)")
	lines.append("\t\tobj.set(prop_name, _deserialize_value(default_value, row[prop_name], p.type))")
	lines.append("\treturn obj")
	lines.append("")
	lines.append("func _deserialize_value(default_value: Variant, value: Variant, value_type: int) -> Variant:")
	lines.append("\tif value == null:")
	lines.append("\t\treturn default_value")
	lines.append("\tif default_value is Resource and typeof(value) == TYPE_DICTIONARY:")
	lines.append("\t\tvar nested_script: Script = (default_value as Resource).get_script()")
	lines.append("\t\tif nested_script != null:")
	lines.append("\t\t\treturn _deserialize_object(nested_script, value)")
	lines.append("\tif value_type == TYPE_ARRAY and typeof(value) == TYPE_ARRAY:")
	lines.append("\t\tvar out: Array = []")
	lines.append("\t\tvar src: Array = value")
	lines.append("\t\tvar typed_script: Script = null")
	lines.append("\t\tif typeof(default_value) == TYPE_ARRAY:")
	lines.append("\t\t\tvar def_arr: Array = default_value")
	lines.append("\t\t\ttyped_script = def_arr.get_typed_script()")
	lines.append("\t\tfor it in src:")
	lines.append("\t\t\tif typed_script != null and typeof(it) == TYPE_DICTIONARY:")
	lines.append("\t\t\t\tout.append(_deserialize_object(typed_script, it))")
	lines.append("\t\t\telse:")
	lines.append("\t\t\t\tout.append(it)")
	lines.append("\t\treturn out")
	lines.append("\treturn value")
	lines.append("")
	return "\n".join(lines) + "\n"


func _loader_var_name(table_name: String) -> String:
	var raw := table_name.to_lower()
	var out := ""
	for i in raw.length():
		var c := raw.substr(i, 1)
		var is_letter := c >= "a" and c <= "z"
		var is_digit := c >= "0" and c <= "9"
		if is_letter or is_digit:
			out += c
		else:
			out += "_"
	if out == "" or (out[0] >= "0" and out[0] <= "9"):
		out = "cfg_" + out
	while out.find("__") >= 0:
		out = out.replace("__", "_")
	return "cfg_" + out.strip_edges().trim_prefix("_").trim_suffix("_")


func _prepare_tab_content(control: Control) -> void:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_EXPAND_FILL


## TabContainer 的子节点只能用 size_flags 铺满，不能设 anchors（否则宽高会变成 0）。
func _prepare_tab_page(control: Control) -> void:
	_prepare_tab_content(control)
