# GF Data Editor 使用说明

本文只讲怎么用，不讲实现原理。

## 1. 启用插件

1. 打开 Godot 项目。
2. 进入 `项目 -> 项目设置 -> 插件`。
3. 启用 `GF Data Editor`。
4. 顶部主标签会出现 `数据编辑器`。

---

## 2. 目录约定

请使用以下目录：

- 配置结构脚本：`res://data_configs/`
- 配置数据文件：`res://game_data/`

---

## 3. 新建一个配置表

在 `res://data_configs/` 新建脚本，例如 `item.gd`：

```gdscript
## @tab_category("道具")
## @display_name("物品")
class_name item
extends GameConfig

## @display_name("标题")
@export var title: String = ""

## @config_ref(ExampleQuestConfig, display_field=title)
## @display_name("任务")
@export var quest_id: int = 0

@export var item_Resources: Array[item_resource] = []

## @config_ref(ExampleNpcConfig, display_field=name)
@export var npc_ids: Array[int] = []
```

说明：

- 顶层表请 `extends GameConfig`。
- `id` 已在 `GameConfig` 基类中，编辑器里只读显示。
- `@tab_category` 控制外层分类页签。
- `@display_name` 控制显示名。
- `@config_ref(...)` 可做单选引用或 `Array[int]` 多选引用。

---

## 4. 子结构（不是表）

如果只是嵌套结构，不是顶层表，请用 `GameStruct`：

```gdscript
class_name item_resource
extends GameStruct

## @display_name("标题")
@export var title: String = ""

## @config_ref(ExampleNpcConfig, display_field=name)
@export var npc_id: int = 0
```

说明：

- `GameStruct` 不会被当成表，不会出现在顶层 Tab。
- 常用于 `Array[item_resource]` 这种嵌套列表。
- 如果在 `GameStruct` 里实现了 `func _to_string() -> String`，编辑器会优先用它作为数组元素列表的缩略显示文本。

---

## 5. 在编辑器里编辑数据

1. 打开顶部 `数据编辑器`。
2. 左侧选条目，右侧改字段。
3. 使用 `添加 / 删除 / 保存 / 放弃更改` 按钮。
4. 保存后会写入 `res://game_data/<表名>.json`。

---

## 6. 生成运行时加载器（单例）

1. 在 `数据编辑器` 顶栏点击 `生成加载器`。
2. 会自动生成：
   - `res://scr/gf_dataeditor/gf_data_loader.gd`
3. 会自动注册 Autoload：
   - 单例名：`GFDataEditorLoader`

---

## 7. 运行时读取（直接用）

示例：

```gdscript
var item_table: Dictionary = GFDataEditorLoader.cfg_item
var item_1: item = item_table.get(1, null)
if item_1 != null:
	print(item_1.title)
	print(item_1.quest_id)
	print(item_1.npc_ids)           # Array[int]
	print(item_1.item_Resources)    # Array[item_resource]
```

按表名通用读取：

```gdscript
var table = GFDataEditorLoader.get_table("item")
var row = GFDataEditorLoader.get_row("item", 1)
```

---

## 8. 常见操作

- 新增字段后：回到 `数据编辑器` 点 `刷新`。
- 结构改动后：建议重新点一次 `生成加载器`。
- 想重载运行时缓存：调用 `GFDataEditorLoader.reload_all()`。
