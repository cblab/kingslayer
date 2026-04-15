extends Node2D
class_name Unit

@export var unit_id: StringName
@export var display_name: String = "Unit"

func setup(_id: StringName, _name: String) -> void:
	unit_id = _id
	display_name = _name
