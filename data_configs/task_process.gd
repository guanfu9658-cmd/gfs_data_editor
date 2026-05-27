class_name task_process
extends GameStruct

##@display_name("npc")
##@@config_ref(npc, display_field=name)
@export var npc_id:int
##@display_name("对话")
@export var text:String
func _to_string() -> String:
	return text
