
## @tab_category("综合")
## @display_name("任务")
class_name task
extends GameConfig
@export var title:String
##@display_name("任务接取人")
##@config_ref(npc, display_field=name)
@export var npc_id:int

##@display_name("对话列表")
@export var texts:Array[task_process]

##@config_ref(npc, display_field=name)
##@display_name("任务完成人列表")
@export var npcs:Array[int]
