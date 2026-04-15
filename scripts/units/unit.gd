extends CharacterBody2D
class_name Unit

enum UnitRole {
	FREE_KNIGHT,
	RULER,
	ROYAL_GUARD,
}

@export var role: UnitRole = UnitRole.FREE_KNIGHT
@export var is_player_controlled: bool = true
@export var ruler_path: NodePath
@export var guard_slot_index: int = 0

@export var faction_id: int = -1
@export var faction_color: Color = Color(0.82, 0.24, 0.24, 1.0)
@export var free_knight_color: Color = Color(0.55, 0.6, 0.68, 1.0)

@export var auto_aggro_enabled: bool = true
@export var aggro_radius: float = 260.0
@export var ruler_search_radius: float = 420.0
@export var guard_protect_radius: float = 260.0

@export var move_speed: float = 300.0
@export var waypoint_tolerance: float = 14.0

@export var max_hp: float = 100.0
@export var player_test_max_hp: float = 520.0
@export var ruler_hp_bonus: float = 40.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 58.0
@export var attack_interval: float = 0.75

@export var guard_hold_radius: float = 110.0
@export var guard_return_distance: float = 24.0
@export var guard_chase_limit: float = 440.0

var current_hp: float = 0.0

var _path := PackedVector2Array()
var _path_index: int = 0
var _attack_target: Unit = null
var _attack_cooldown: float = 0.0
var _repath_cooldown: float = 0.0
var _is_dead: bool = false
var _last_valid_attacker: Unit = null
var _rng := RandomNumberGenerator.new()

const _HIT_SOUNDS: Array[AudioStream] = [
	preload("res://scripts/sound/sword_clash_1.mp3"),
	preload("res://scripts/sound/sword_clash_2.mp3"),
	preload("res://scripts/sound/sword_clash_3.mp3"),
]

@onready var _visual: Polygon2D = $Visual
@onready var _ruler_marker: Node2D = $RulerMarker
@onready var _hit_audio: AudioStreamPlayer2D = $HitAudio

func _ready() -> void:
	_rng.randomize()
	max_hp = _resolve_initial_max_hp()
	current_hp = max_hp
	_apply_role_visuals()

func _unhandled_input(event: InputEvent) -> void:
	if not is_player_controlled or _is_dead:
		return

	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		var clicked_unit: Unit = _find_clicked_unit()
		var world: Node = get_parent()
		if clicked_unit != null and world != null and world.has_method("set_debug_focus_unit"):
			world.set_debug_focus_unit(clicked_unit)
		if clicked_unit != null and clicked_unit != self and not clicked_unit.is_dead():
			_attack_target = clicked_unit
			_path = PackedVector2Array()
			_path_index = 0
			_repath_cooldown = 0.0
			return

		_attack_target = null
		if world != null and world.has_method("find_path"):
			_path = world.find_path(global_position, get_global_mouse_position())
			_path_index = 0

func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if auto_aggro_enabled and not is_player_controlled:
		_update_npc_aggro_target()

	if role == UnitRole.ROYAL_GUARD:
		_process_guard_logic(delta)
		return

	if _attack_target != null:
		_process_attack_target(delta)
	else:
		_follow_current_path()

func take_damage(amount: float, attacker: Unit) -> void:
	if _is_dead:
		return

	if attacker != null and is_instance_valid(attacker) and not attacker.is_dead() and attacker != self:
		_last_valid_attacker = attacker

	current_hp -= amount

	if role == UnitRole.RULER and attacker != null:
		var world: Node = get_parent()
		if world != null and world.has_method("on_ruler_attacked"):
			world.on_ruler_attacked(self, attacker)

	if current_hp <= 0.0:
		_die()

func is_dead() -> bool:
	return _is_dead

func set_attack_target(target: Unit) -> void:
	if _is_dead:
		return
	if target == null or not is_instance_valid(target) or target.is_dead() or target == self:
		_attack_target = null
		return
	_attack_target = target
	_repath_cooldown = 0.0
	_path = PackedVector2Array()
	_path_index = 0

func get_attack_target() -> Unit:
	if _attack_target == null or not is_instance_valid(_attack_target):
		return null
	if _attack_target.is_dead():
		return null
	return _attack_target

func get_last_valid_attacker() -> Unit:
	if _last_valid_attacker == null or not is_instance_valid(_last_valid_attacker):
		return null
	if _last_valid_attacker.is_dead():
		return null
	return _last_valid_attacker

func set_role(new_role: UnitRole) -> void:
	role = new_role
	if role != UnitRole.ROYAL_GUARD:
		ruler_path = NodePath()
	guard_slot_index = 0
	_apply_role_visuals()

func assign_guard_to_ruler(ruler: Unit, slot_index: int = 0) -> void:
	if _is_dead:
		return
	if ruler == null or not is_instance_valid(ruler) or ruler.is_dead():
		clear_guard_assignment()
		return
	role = UnitRole.ROYAL_GUARD
	ruler_path = get_path_to(ruler)
	guard_slot_index = slot_index
	faction_id = ruler.faction_id
	faction_color = ruler.faction_color
	_apply_role_visuals()

func clear_guard_assignment() -> void:
	_attack_target = null
	_path = PackedVector2Array()
	_path_index = 0
	set_role(UnitRole.FREE_KNIGHT)
	faction_id = -1
	_apply_role_visuals()

func _process_guard_logic(delta: float) -> void:
	var ruler := _get_ruler()
	if ruler == null:
		clear_guard_assignment()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _attack_target != null:
		if global_position.distance_to(ruler.global_position) > guard_chase_limit:
			_attack_target = null
			_path = PackedVector2Array()
			_path_index = 0
		else:
			_process_attack_target(delta)
			return

	var hold_position := _get_guard_hold_position(ruler)
	if global_position.distance_to(hold_position) <= guard_return_distance:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_repath_cooldown -= delta
	if _repath_cooldown <= 0.0:
		_repath_to(hold_position)
		_repath_cooldown = 0.35
	_follow_current_path()

func _resolve_initial_max_hp() -> float:
	if is_player_controlled:
		return max(max_hp, player_test_max_hp)
	if role == UnitRole.RULER:
		return max_hp + ruler_hp_bonus
	return max_hp

func _get_ruler() -> Unit:
	if ruler_path.is_empty():
		return null
	var node := get_node_or_null(ruler_path)
	if node is Unit and not node.is_dead():
		return node
	return null

func _get_guard_hold_position(ruler: Unit) -> Vector2:
	var angle := PI * 0.5 * float(guard_slot_index)
	var offset := Vector2.RIGHT.rotated(angle) * guard_hold_radius
	return ruler.global_position + offset

func _apply_role_visuals() -> void:
	match role:
		UnitRole.RULER:
			_visual.color = faction_color.lightened(0.2)
			_ruler_marker.visible = true
		UnitRole.ROYAL_GUARD:
			_visual.color = faction_color.darkened(0.1)
			_ruler_marker.visible = false
		_:
			_visual.color = free_knight_color
			_ruler_marker.visible = false

func _process_attack_target(delta: float) -> void:
	if not is_instance_valid(_attack_target) or _attack_target.is_dead() or not _is_enemy(_attack_target):
		_attack_target = null
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var target_distance: float = global_position.distance_to(_attack_target.global_position)
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
		_play_hit_sound()
		_attack_cooldown = attack_interval

func _follow_current_path() -> void:
	if _path_index >= _path.size():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var target: Vector2 = _path[_path_index]

	if global_position.distance_to(target) <= waypoint_tolerance:
		_path_index += 1

		if _path_index >= _path.size():
			velocity = Vector2.ZERO
			move_and_slide()
			return

		target = _path[_path_index]

	var direction: Vector2 = global_position.direction_to(target)
	velocity = direction * move_speed
	move_and_slide()

func _repath_to(target_position: Vector2) -> void:
	var world: Node = get_parent()
	if world != null and world.has_method("find_path"):
		_path = world.find_path(global_position, target_position)
		_path_index = 0

func _update_npc_aggro_target() -> void:
	match role:
		UnitRole.ROYAL_GUARD:
			_update_guard_aggro_target()
			return
		UnitRole.RULER:
			_update_ruler_aggro_target()
			return

	if _attack_target != null and is_instance_valid(_attack_target) and not _attack_target.is_dead() and _is_enemy(_attack_target):
		return

	var nearest_enemy := _find_nearest_enemy_in_range(aggro_radius)
	if nearest_enemy != null:
		set_attack_target(nearest_enemy)

func _update_ruler_aggro_target() -> void:
	if _attack_target != null and is_instance_valid(_attack_target) and not _attack_target.is_dead() and _is_enemy(_attack_target):
		return

	var nearest_enemy := _find_nearest_enemy_in_range(ruler_search_radius)
	if nearest_enemy != null:
		set_attack_target(nearest_enemy)

func _update_guard_aggro_target() -> void:
	var ruler := _get_ruler()
	if ruler == null:
		_attack_target = null
		return

	var ruler_attacker := ruler.get_last_valid_attacker()
	if ruler_attacker != null and _is_enemy(ruler_attacker):
		if ruler.global_position.distance_to(ruler_attacker.global_position) <= guard_chase_limit:
			set_attack_target(ruler_attacker)
			return

	var nearest_threat := _find_nearest_enemy_to_point_in_range(ruler.global_position, guard_protect_radius)
	if nearest_threat != null:
		set_attack_target(nearest_threat)
		return

	if _attack_target != null and is_instance_valid(_attack_target) and not _attack_target.is_dead() and _is_enemy(_attack_target):
		if global_position.distance_to(ruler.global_position) <= guard_chase_limit:
			return

	_attack_target = null
	_path = PackedVector2Array()
	_path_index = 0

func _find_nearest_enemy_in_range(radius: float) -> Unit:
	return _find_nearest_enemy_to_point_in_range(global_position, radius)

func _find_nearest_enemy_to_point_in_range(center: Vector2, radius: float) -> Unit:
	var parent := get_parent()
	if parent == null:
		return null

	var nearest: Unit = null
	var nearest_distance := INF
	for child in parent.get_children():
		if not (child is Unit):
			continue
		if child == self or child.is_dead():
			continue
		if not _is_enemy(child):
			continue
		var distance := center.distance_to(child.global_position)
		if distance > radius:
			continue
		if distance < nearest_distance:
			nearest = child
			nearest_distance = distance

	return nearest

func _play_hit_sound() -> void:
	if _hit_audio == null or _HIT_SOUNDS.is_empty():
		return
	var sound_index := _rng.randi_range(0, _HIT_SOUNDS.size() - 1)
	_hit_audio.stream = _HIT_SOUNDS[sound_index]
	_hit_audio.play()

func _is_enemy(other: Unit) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	if other == self or other.is_dead():
		return false
	return faction_id != other.faction_id

func _find_clicked_unit() -> Unit:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var state := get_world_2d().direct_space_state
	var results: Array[Dictionary] = state.intersect_point(query, 16)

	for hit in results:
		var collider = hit.get("collider")
		if collider is Unit:
			return collider

	return null

func _die() -> void:
	if _is_dead:
		return

	_is_dead = true
	print("Unit died: ", name)

	if role == UnitRole.RULER:
		var world: Node = get_parent()
		if world != null and world.has_method("on_ruler_died"):
			world.on_ruler_died(self, get_last_valid_attacker())

	queue_free()
