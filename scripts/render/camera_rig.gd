extends Camera2D
## Follows the player smoothly; zoom via keys/wheel handled by controller.

var target: Node2D = null


func _process(_delta: float) -> void:
	if target != null:
		global_position = target.global_position