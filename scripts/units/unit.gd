extends CharacterBody2D
class_name Unit

@export var is_player_controlled: bool = true

@export var move_speed: float = 300.0
@export var waypoint_tolerance: float = 14.0

@export var max_hp: float = 100.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 58.0
@export var attack_interval: float = 0.75

var current_hp: float = 0.0

var _path := PackedVector2Array()
var _path_index := 0
var _attack_target: Unit = null
var _attack_cooldown: float = 0.0
var _repath_cooldown: float = 0.0
var _is_dead: bool = false

func _ready() -> void:
	current_hp = max_hp

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_controlled or _is_dead:
		return

	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		var clicked_unit := _find_clicked_unit(event.position)
		if clicked_unit != null and clicked_unit != self and not clicked_unit.is_dead():
			_attack_target = clicked_unit
			_path = PackedVector2Array()
			_path_index = 0
			_repath_cooldown = 0.0
			return

		_attack_target = null
		var world := get_parent()
		if world != null and world.has_method("find_path"):
			_path = world.find_path(global_position, get_global_mouse_position())
			_path_index = 0

func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _attack_target != null:
		_process_attack_target(delta)
	else:
		_follow_current_path()

func take_damage(amount: float, _attacker: Unit) -> void:
	if _is_dead:
		return

	current_hp -= amount
	if current_hp <= 0.0:
		_die()

func is_dead() -> bool:
	return _is_dead

func _process_attack_target(delta: float) -> void:
	if not is_instance_valid(_attack_target) or _attack_target.is_dead():
		_attack_target = null
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var target_distance := global_position.distance_to(_attack_target.global_position)
	if target_distance > attack_range:
		_repath_cooldown -= delta
		if _repath_cooldown <= 0.0:
			_repath_to(_attack_target.global_position)
			_repath_cooldown = 0.2
		_follow_current_path()
		return

	_path = PackedVector2Array()
	_path_index = 0
	velocity = Vector2.ZERO
	move_and_slide()

	_attack_cooldown -= delta
	if _attack_cooldown <= 0.0:
		_attack_target.take_damage(attack_damage, self)
		_attack_cooldown = attack_interval

func _follow_current_path() -> void:
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

func _repath_to(target_position: Vector2) -> void:
	var world := get_parent()
	if world != null and world.has_method("find_path"):
		_path = world.find_path(global_position, target_position)
		_path_index = 0

func _find_clicked_unit(screen_pos: Vector2) -> Unit:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var state := get_world_2d().direct_space_state
	var results := state.intersect_point(query, 16)
	for hit in results:
		var collider := hit.get("collider")
		if collider is Unit:
			return collider

	return null

func _die() -> void:
	if _is_dead:
		return

	_is_dead = true
	print("Unit died: ", name)
	queue_free()
