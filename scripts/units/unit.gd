extends CharacterBody2D
class_name Unit

@export var move_speed: float = 220.0

@onready var _navigation_agent: NavigationAgent2D = $NavigationAgent2D

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_navigation_agent.target_position = get_global_mouse_position()

func _physics_process(_delta: float) -> void:
	if _navigation_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var next_path_position := _navigation_agent.get_next_path_position()
	var to_next := next_path_position - global_position

	if to_next.length_squared() <= 0.0001:
		velocity = Vector2.ZERO
	else:
		velocity = to_next.normalized() * move_speed

	move_and_slide()
