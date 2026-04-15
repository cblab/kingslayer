extends CharacterBody2D
class_name Unit

@export var move_speed: float = 220.0
@export var stop_distance: float = 6.0

var _target_position: Vector2
var _has_target: bool = false

func _ready() -> void:
	_target_position = global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_target_position = get_global_mouse_position()
		_has_target = true

func _physics_process(_delta: float) -> void:
	if not _has_target:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_target := _target_position - global_position
	var distance := to_target.length()

	if distance <= stop_distance:
		_has_target = false
		velocity = Vector2.ZERO
	else:
		velocity = to_target.normalized() * move_speed

	move_and_slide()
