extends Node
func _ready() -> void:
	var npcdic:Dictionary = GFDataEditorLoader.cfg_npc
	var item1:npc = npcdic.get(1,null)
	if item1 != null:
		print(item1.id)
		print(item1.name)
