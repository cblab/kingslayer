extends CharacterBody2D
class_name Unit

@export var move_speed: float = 300.0
@export var waypoint_tolerance: float = 14.0

var _path := PackedVector2Array()
var _path_index := 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		var world := get_parent()
		if world != null and world.has_method("find_path"):
			_path = world.find_path(global_position, get_global_mouse_position())
			_path_index = 0

func _physics_process(_delta: float) -> void:
	if _path_index >= _path.size():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var target := _path[_path_index]

	if global_position.distance_to(target) <= waypoint_tolerance:
		_path_index += 1

		if _path_index >= _path.size():
			velocity = Vector2.ZERO
			move_and_slide()
			return

		target = _path[_path_index]

	var direction := global_position.direction_to(target)
	velocity = direction * move_speed
	move_and_slide()