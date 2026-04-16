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
@export var ruler_search_move_interval_min: float = 2.4
@export var ruler_search_move_interval_max: float = 4.2
@export var ruler_search_move_distance_min: float = 180.0
@export var ruler_search_move_distance_max: float = 420.0
@export var disband_cooldown_duration: float = 60.0
@export var guard_target_reacquire_delay: float = 0.5
@export var guard_target_switch_cooldown: float = 0.45
@export var guard_chase_hysteresis: float = 36.0

var current_hp: float = 0.0

var _path := PackedVector2Array()
var _path_index: int = 0
var _attack_target: Unit = null
var _attack_cooldown: float = 0.0
var _repath_cooldown: float = 0.0
var _is_dead: bool = false
var _last_valid_attacker: Unit = null
var _rng := RandomNumberGenerator.new()
var _ruler_search_timer: float = 0.0
var _ruler_search_point: Vector2 = Vector2.ZERO
var _has_ruler_search_point: bool = false
var _current_search_target: Vector2 = Vector2.ZERO
var _has_active_search_order: bool = false
var _next_search_decision_time: float = 0.0
var _ruler_search_stuck_timer: float = 0.0
var _last_search_distance: float = INF
var _disband_cooldown_active: bool = false
var _disband_cooldown_timer: float = 0.0
var _guard_return_logged: bool = false
var _guard_target_reacquire_timer: float = 0.0
var _guard_target_switch_timer: float = 0.0
var _last_valid_ruler_search_point: Vector2 = Vector2.ZERO

const _HIT_SOUNDS: Array[AudioStream] = [
	preload("res://scripts/sound/sword_clash_1.mp3"),
	preload("res://scripts/sound/sword_clash_2.mp3"),
	preload("res://scripts/sound/sword_clash_3.mp3"),
]
const _RULER_SEARCH_STUCK_TIMEOUT: float = 1.4
const _RULER_SEARCH_STUCK_DELTA_EPSILON: float = 3.0
const _RULER_SEARCH_MIN_TARGET_DISTANCE: float = 96.0

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
			set_attack_target(clicked_unit, "player_click")
			return

		set_attack_target(null, "player_move_command")
		if world != null and world.has_method("find_path"):
			_path = world.find_path(global_position, get_global_mouse_position())
			_path_index = 0

func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _guard_target_reacquire_timer > 0.0:
		_guard_target_reacquire_timer = maxf(0.0, _guard_target_reacquire_timer - delta)
	if _guard_target_switch_timer > 0.0:
		_guard_target_switch_timer = maxf(0.0, _guard_target_switch_timer - delta)

	if _disband_cooldown_active:
		_process_disband_cooldown(delta)
		return

	if auto_aggro_enabled and not is_player_controlled:
		_update_npc_aggro_target()

	if role == UnitRole.ROYAL_GUARD:
		_process_guard_logic(delta)
		return

	if _attack_target != null:
		_process_attack_target(delta)
	elif role == UnitRole.RULER and not is_player_controlled:
		_process_ruler_search_movement(delta)
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

func set_attack_target(target: Unit, reason: String = "") -> void:
	if _is_dead:
		return

	var previous_target := get_attack_target()
	var next_target: Unit = null
	if target != null and is_instance_valid(target) and not target.is_dead() and target != self:
		if _disband_cooldown_active:
			return
		next_target = target

	_attack_target = next_target
	if _attack_target != null:
		_has_active_search_order = false
		_has_ruler_search_point = false
		_ruler_search_stuck_timer = 0.0
	if _attack_target == null:
		_guard_return_logged = false
	if previous_target == _attack_target:
		return

	if _attack_target == null:
		if role == UnitRole.ROYAL_GUARD and previous_target != null:
			_guard_target_reacquire_timer = guard_target_reacquire_delay
		var data := {
			"unit": name,
			"target": previous_target.name if previous_target != null else "-",
		}
		if not reason.is_empty():
			data["reason"] = reason
		_log_event("TARGET_LOST", data)
		return

	_log_event("TARGET_SET", {
		"unit": name,
		"target": _attack_target.name,
		"reason": reason if not reason.is_empty() else "-",
	})
	if role == UnitRole.ROYAL_GUARD and previous_target != null and previous_target != _attack_target:
		_guard_target_switch_timer = guard_target_switch_cooldown
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
	if is_node_ready():
		_apply_role_visuals()
	else:
		call_deferred("_apply_role_visuals")

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
	ruler_path = NodePath()
	guard_slot_index = 0
	_apply_role_visuals()

func start_disband_cooldown(duration: float = -1.0) -> void:
	_disband_cooldown_active = true
	_disband_cooldown_timer = duration if duration > 0.0 else disband_cooldown_duration
	_clear_active_combat_and_navigation_state("disband_cooldown_start")
	_log_event("DISBAND_COOLDOWN_START", {
		"unit": name,
		"duration": _disband_cooldown_timer,
	})

func is_disband_cooldown_active() -> bool:
	return _disband_cooldown_active

func _process_guard_logic(delta: float) -> void:
	var ruler := _get_ruler()
	if ruler == null:
		clear_guard_assignment()
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _attack_target != null:
		var guard_to_ruler_distance := global_position.distance_to(ruler.global_position)
		var target_to_ruler_distance := _attack_target.global_position.distance_to(ruler.global_position)
		if guard_to_ruler_distance > guard_chase_limit + guard_chase_hysteresis \
		and target_to_ruler_distance > guard_chase_limit + guard_chase_hysteresis:
			set_attack_target(null, "guard_chase_limit")
			if not _guard_return_logged:
				_log_event("GUARD_RETURN_TO_RULER", {
					"guard": name,
					"ruler": ruler.name,
				})
				_guard_return_logged = true
		else:
			_guard_return_logged = false
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
	if _visual == null:
		_visual = get_node_or_null("Visual") as Polygon2D
	if _ruler_marker == null:
		_ruler_marker = get_node_or_null("RulerMarker") as Node2D
	if _visual == null:
		push_warning("Unit '%s': Missing Visual node, skipping role visuals." % name)
		return

	match role:
		UnitRole.RULER:
			_visual.color = faction_color.lightened(0.2)
			if _ruler_marker != null:
				_ruler_marker.visible = true
		UnitRole.ROYAL_GUARD:
			_visual.color = faction_color.darkened(0.1)
			if _ruler_marker != null:
				_ruler_marker.visible = false
		_:
			_visual.color = free_knight_color
			if _ruler_marker != null:
				_ruler_marker.visible = false

func _process_attack_target(delta: float) -> void:
	if not is_instance_valid(_attack_target) or _attack_target.is_dead() or not _is_enemy(_attack_target):
		set_attack_target(null, "target_invalid_or_not_enemy")
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
		var attacked_unit := _attack_target
		attacked_unit.take_damage(attack_damage, self)
		if attacked_unit != null and is_instance_valid(attacked_unit):
			_log_event("ATTACK_HIT", {
				"attacker": name,
				"target": attacked_unit.name,
				"damage": attack_damage,
				"hp_after": maxf(0.0, attacked_unit.current_hp),
			})
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
	if _disband_cooldown_active:
		return

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
		set_attack_target(nearest_enemy, "npc_auto_aggro")

func _update_ruler_aggro_target() -> void:
	if _attack_target != null and is_instance_valid(_attack_target) and not _attack_target.is_dead() and _is_enemy(_attack_target):
		return

	var nearest_enemy := _find_nearest_enemy_in_range(ruler_search_radius)
	if nearest_enemy != null:
		set_attack_target(nearest_enemy, "ruler_enemy_spotted")
		_has_ruler_search_point = false
		_has_active_search_order = false
		_ruler_search_stuck_timer = 0.0

func _process_ruler_search_movement(delta: float) -> void:
	if _attack_target != null:
		return

	_next_search_decision_time = maxf(0.0, _next_search_decision_time - delta)

	var reached_target := false
	var target_invalid := false
	var stuck_timeout := false

	if _has_active_search_order:
		reached_target = global_position.distance_to(_current_search_target) <= waypoint_tolerance + 6.0
		target_invalid = not _is_search_target_valid(_current_search_target)

		var current_distance := global_position.distance_to(_current_search_target)
		var distance_delta := _last_search_distance - current_distance
		if _path_index < _path.size() and not reached_target:
			if distance_delta <= _RULER_SEARCH_STUCK_DELTA_EPSILON:
				_ruler_search_stuck_timer += delta
			else:
				_ruler_search_stuck_timer = 0.0
		else:
			_ruler_search_stuck_timer = 0.0
		_last_search_distance = current_distance
		stuck_timeout = _ruler_search_stuck_timer >= _RULER_SEARCH_STUCK_TIMEOUT

	if reached_target or target_invalid:
		_has_active_search_order = false
		_has_ruler_search_point = false
		_path = PackedVector2Array()
		_path_index = 0

	var should_pick_new_target := not _has_active_search_order \
		or reached_target \
		or stuck_timeout \
		or _next_search_decision_time <= 0.0

	if should_pick_new_target:
		_ruler_search_point = _pick_ruler_search_point(_current_search_target)
		if _ruler_search_point.distance_to(global_position) < _RULER_SEARCH_MIN_TARGET_DISTANCE:
			return
		_has_ruler_search_point = true
		var is_new_target := not _has_active_search_order or _current_search_target.distance_to(_ruler_search_point) > 1.0
		_current_search_target = _ruler_search_point
		_has_active_search_order = true
		_ruler_search_stuck_timer = 0.0
		_last_search_distance = global_position.distance_to(_current_search_target)
		_repath_to(_ruler_search_point)
		_ruler_search_timer = _rng.randf_range(ruler_search_move_interval_min, ruler_search_move_interval_max)
		_next_search_decision_time = _ruler_search_timer
		if is_new_target:
			_log_event("RULER_SEARCH_MOVE", {
				"ruler": name,
				"target_point": _ruler_search_point,
			})

	_follow_current_path()

func _is_search_target_valid(target_point: Vector2) -> bool:
	var world: Node = get_parent()
	if world == null:
		return true
	if world.has_method("is_valid_ruler_search_point"):
		return world.is_valid_ruler_search_point(global_position, target_point)
	if world.has_method("get_clamped_ruler_search_point"):
		var clamped: Vector2 = world.get_clamped_ruler_search_point(global_position, target_point, target_point)
		return clamped.distance_to(target_point) <= 1.0
	return true

func _pick_ruler_search_point(previous_target: Vector2 = Vector2.ZERO) -> Vector2:
	var world: Node = get_parent()
	var nearest_enemy := _find_nearest_enemy_any_distance()
	if nearest_enemy != null:
		var enemy_point := nearest_enemy.global_position
		if world != null and world.has_method("get_clamped_ruler_search_point"):
			enemy_point = world.get_clamped_ruler_search_point(global_position, enemy_point, _last_valid_ruler_search_point)
		if enemy_point.distance_to(global_position) >= _RULER_SEARCH_MIN_TARGET_DISTANCE:
			_last_valid_ruler_search_point = enemy_point
			return enemy_point

	var fallback_target := _last_valid_ruler_search_point
	if fallback_target == Vector2.ZERO:
		fallback_target = previous_target

	for attempt in 10:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(ruler_search_move_distance_min, ruler_search_move_distance_max)
		var offset := Vector2.RIGHT.rotated(angle) * distance
		var roam_point := global_position + offset
		if world != null and world.has_method("get_clamped_ruler_search_point"):
			roam_point = world.get_clamped_ruler_search_point(global_position, roam_point, fallback_target)
		if roam_point.distance_to(global_position) < _RULER_SEARCH_MIN_TARGET_DISTANCE:
			continue
		if previous_target != Vector2.ZERO and roam_point.distance_to(previous_target) <= 1.0:
			continue
		_last_valid_ruler_search_point = roam_point
		return roam_point

	var emergency_point := global_position + Vector2.RIGHT * maxf(_RULER_SEARCH_MIN_TARGET_DISTANCE, ruler_search_move_distance_min)
	if world != null and world.has_method("get_clamped_ruler_search_point"):
		emergency_point = world.get_clamped_ruler_search_point(global_position, emergency_point, fallback_target)
	if emergency_point.distance_to(global_position) < _RULER_SEARCH_MIN_TARGET_DISTANCE:
		emergency_point = global_position + Vector2.DOWN * _RULER_SEARCH_MIN_TARGET_DISTANCE
	_last_valid_ruler_search_point = emergency_point
	return emergency_point

func _update_guard_aggro_target() -> void:
	var ruler := _get_ruler()
	if ruler == null:
		set_attack_target(null, "guard_lost_ruler")
		return

	if _attack_target == null and _guard_target_reacquire_timer > 0.0:
		return

	var current_target := get_attack_target()
	if current_target != null and _is_enemy(current_target):
		var current_target_distance_to_ruler := current_target.global_position.distance_to(ruler.global_position)
		if current_target_distance_to_ruler <= guard_chase_limit + guard_chase_hysteresis:
			return

	var ruler_attacker := ruler.get_last_valid_attacker()
	if ruler_attacker != null and _is_enemy(ruler_attacker):
		if ruler.global_position.distance_to(ruler_attacker.global_position) <= guard_chase_limit:
			if _guard_target_switch_timer > 0.0 and current_target != null and current_target != ruler_attacker:
				return
			set_attack_target(ruler_attacker, "protect_ruler_attacker")
			return

	var nearest_threat := _find_nearest_enemy_to_point_in_range(ruler.global_position, guard_protect_radius)
	if nearest_threat != null:
		if _guard_target_switch_timer > 0.0 and current_target != null and current_target != nearest_threat:
			return
		set_attack_target(nearest_threat, "guard_protect_radius")
		return

	if current_target != null and global_position.distance_to(ruler.global_position) <= guard_chase_limit + guard_chase_hysteresis:
		return

	set_attack_target(null, "guard_out_of_chase_range")
	_path = PackedVector2Array()
	_path_index = 0

func _process_disband_cooldown(delta: float) -> void:
	_disband_cooldown_timer = maxf(0.0, _disband_cooldown_timer - delta)
	if _attack_target != null or _path_index < _path.size():
		_clear_active_combat_and_navigation_state("disband_cooldown_enforced")
	velocity = Vector2.ZERO
	move_and_slide()

	if _disband_cooldown_timer <= 0.0:
		_disband_cooldown_active = false
		_log_event("DISBAND_COOLDOWN_END", {
			"unit": name,
		})

func _find_nearest_enemy_in_range(radius: float) -> Unit:
	return _find_nearest_enemy_to_point_in_range(global_position, radius)

func _find_nearest_enemy_any_distance() -> Unit:
	return _find_nearest_enemy_to_point_in_range(global_position, INF)

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

	# Freie Ritter sollen nach dem Guard-Zerfall wieder normal vom Spieler anwählbar sein.
	# Während des Disband-Cooldowns bleibt das Ziel ungültig.
	if is_player_controlled and other.role == UnitRole.FREE_KNIGHT:
		return not other.is_disband_cooldown_active()
	if other.is_player_controlled and role == UnitRole.FREE_KNIGHT:
		return not is_disband_cooldown_active()
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
	var role_at_death := role
	_log_event("UNIT_DIED", {
		"unit": name,
		"role_at_death": _role_to_text(role_at_death),
	})

	if role_at_death == UnitRole.RULER:
		var world: Node = get_parent()
		if world != null and world.has_method("on_ruler_died"):
			world.on_ruler_died(self, get_last_valid_attacker(), role_at_death)

	queue_free()

func _log_event(event_type: String, data: Dictionary) -> void:
	var world: Node = get_parent()
	if world != null and world.has_method("log_event"):
		world.log_event(event_type, data)

func _role_to_text(current_role: UnitRole) -> String:
	match current_role:
		UnitRole.RULER:
			return "RULER"
		UnitRole.ROYAL_GUARD:
			return "ROYAL_GUARD"
		_:
			return "FREE_KNIGHT"

func _clear_active_combat_and_navigation_state(reason: String = "") -> void:
	if _attack_target != null:
		set_attack_target(null, reason)
	_path = PackedVector2Array()
	_path_index = 0
	velocity = Vector2.ZERO
	_repath_cooldown = 0.0
	_attack_cooldown = 0.0
	_has_ruler_search_point = false
	_ruler_search_point = global_position
	_ruler_search_timer = 0.0
	_has_active_search_order = false
	_current_search_target = global_position
	_next_search_decision_time = 0.0
	_ruler_search_stuck_timer = 0.0
	_last_search_distance = INF
	_guard_return_logged = false
