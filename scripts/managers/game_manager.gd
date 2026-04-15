extends Node
class_name GameManager

@export var start_paused: bool = false

func _ready() -> void:
	get_tree().paused = start_paused
