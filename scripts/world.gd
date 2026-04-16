extends Node2D

@export var world_stabilize_interval: float = 0.4
@export var debug_hud_update_interval: float = 0.15
@export var ruler_search_bounds: Rect2 = Rect2(-1400.0, -1300.0, 5000.0, 3900.0)
@export var periodic_free_knight_spawn_interval: float = 22.0
@export var periodic_free_knight_spawn_enabled: bool = true
@export var periodic_free_knight_spawn_points: PackedVector2Array = PackedVector2Array([
	Vector2(-1000.0, 2000.0),
	Vector2(120.0, 120.0),
	Vector2(1330.0, 120.0),
	Vector2(730.0, 980.0),
])

var _stabilize_cooldown: float = 0.0
var _debug_hud_cooldown: float = 0.0
var _debug_events: Array[String] = []
var _debug_event_limit: int = 10
var _debug_focus_unit: Unit = null
var _periodic_spawn_cooldown: float = 0.0
var _validated_periodic_free_knight_spawn_points: PackedVector2Array = PackedVector2Array()
var _spawn_rng := RandomNumberGenerator.new()

const _FREE_KNIGHT_SCENE: PackedScene = preload("res://scenes/units/Unit.tscn")
const _SPAWN_POINT_DUPLICATE_EPSILON: float = 8.0
const _SPAWN_POINT_MIN_SPACING: float = 120.0
const _SPAWN_POINT_MIN_POOL_SIZE: int = 3
const _SPAWN_JITTER_RADIUS: float = 40.0
const _RULER_SEARCH_POINT_DUPLICATE_EPSILON: float = 8.0

@onready var _debug_status_label: Label = $DebugHud/Panel/Margin/Content/StatusLabel
@onready var _debug_events_label: Label = $DebugHud/Panel/Margin/Content/EventsLabel

func _ready() -> void:
	_spawn_rng.randomize()
	_periodic_spawn_cooldown = periodic_free_knight_spawn_interval
	_prepare_periodic_free_knight_spawn_points()
	_stabilize_world_state()
	_refresh_debug_hud()

func log_event(event_type: String, data: Dictionary) -> void:
	if event_type.is_empty():
		return

	var timestamp := Time.get_ticks_msec() / 1000.0
	var parts: Array[String] = []
	var keys := data.keys()
	keys.sort()
	for key in keys:
		parts.append("%s=%s" % [str(key), _format_log_value(data[key])])

	var line := "[%.2f] %s" % [timestamp, event_type]
	if not parts.is_empty():
		line += " " + " ".join(parts)

	print(line)
	_debug_events.append(line)
	while _debug_events.size() > _debug_event_limit:
		_debug_events.pop_front()

func _process(delta: float) -> void:
	_stabilize_cooldown -= delta
	if _stabilize_cooldown <= 0.0:
		_stabilize_cooldown = world_stabilize_interval
		_stabilize_world_state()

	_debug_hud_cooldown -= delta
	if _debug_hud_cooldown <= 0.0:
		_debug_hud_cooldown = debug_hud_update_interval
		_refresh_debug_hud()

	_process_periodic_free_knight_spawn(delta)

func find_path(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var nav_map := get_world_2d().navigation_map
	var path := NavigationServer2D.map_get_path(nav_map, from_position, to_position, false)
	if path.is_empty():
		return PackedVector2Array([to_position])
	return path

func get_clamped_ruler_search_point(from_position: Vector2, desired_point: Vector2, fallback_point: Vector2 = Vector2.ZERO) -> Vector2:
	var clamped := _clamp_to_ruler_search_bounds(desired_point)
	if clamped.distance_to(from_position) > 1.0:
		return clamped

	var fallback_clamped := _clamp_to_ruler_search_bounds(fallback_point)
	if fallback_clamped.distance_to(from_position) > 1.0:
		return fallback_clamped

	return _clamp_to_ruler_search_bounds(from_position)

func is_valid_ruler_search_point(_from_position: Vector2, point: Vector2) -> bool:
	return ruler_search_bounds.has_point(point)

func try_get_valid_ruler_search_point(from_pos: Vector2, min_dist: float, max_dist: float, attempts := 12) -> Dictionary:
	if attempts <= 0:
		return {"ok": false}
	if max_dist <= min_dist:
		max_dist = min_dist + 80.0

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sampled_points: Array[Vector2] = []

	for _attempt in attempts:
		var angle := rng.randf_range(0.0, TAU)
		var distance := rng.randf_range(min_dist, max_dist)
		var raw_point := from_pos + Vector2.RIGHT.rotated(angle) * distance
		var candidate := _clamp_to_ruler_search_bounds(raw_point)

		if not is_valid_ruler_search_point(from_pos, candidate):
			continue

		var candidate_distance := candidate.distance_to(from_pos)
		if candidate_distance < min_dist or candidate_distance > max_dist + 1.0:
			continue

		var is_duplicate := false
		for sampled in sampled_points:
			if sampled.distance_to(candidate) <= _RULER_SEARCH_POINT_DUPLICATE_EPSILON:
				is_duplicate = true
				break
		if is_duplicate:
			continue

		sampled_points.append(candidate)
		return {
			"ok": true,
			"point": candidate,
		}

	return {"ok": false}

func on_ruler_attacked(ruler: Unit, attacker: Unit) -> void:
	if not _is_valid_live_unit(ruler):
		return
	if attacker == null or not is_instance_valid(attacker) or attacker.is_dead():
		return

	for guard in _get_live_units():
		if guard.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		var guard_ruler := _get_guard_ruler(guard)
		if guard_ruler != ruler:
			continue
		guard.set_attack_target(attacker)

func on_ruler_died(dead_ruler: Unit, killer: Unit, role_at_death: Unit.UnitRole = Unit.UnitRole.FREE_KNIGHT) -> void:
	if dead_ruler == null or not is_instance_valid(dead_ruler):
		return
	if role_at_death != Unit.UnitRole.RULER:
		return

	var freed_guard_count := 0
	for guard in _get_live_units():
		if guard.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		if not _guard_references_unit(guard, dead_ruler):
			continue
		log_event("GUARD_DISBANDED", {
			"guard": guard.name,
			"old_ruler": dead_ruler.name,
		})
		guard.clear_guard_assignment()
		guard.start_disband_cooldown()
		freed_guard_count += 1

	log_event("RULER_DIED", {
		"ruler": dead_ruler.name,
		"killer": killer.name if _is_valid_live_unit(killer) else "-",
		"role_at_death": _role_to_text(role_at_death),
		"guards_freed": freed_guard_count,
	})

	var killer_is_valid := _is_valid_live_unit(killer) and killer != dead_ruler
	var killer_is_valid_candidate := killer_is_valid \
		and not killer.is_disband_cooldown_active() \
		and killer.role != Unit.UnitRole.ROYAL_GUARD

	if killer_is_valid_candidate:
		_transfer_ruler_identity(dead_ruler, killer)
		log_event("RULER_SUCCESSION", {
			"old_ruler": dead_ruler.name,
			"new_ruler": killer.name,
		})
	elif killer_is_valid and killer.role == Unit.UnitRole.ROYAL_GUARD:
		var guard_owner_ruler := _get_guard_ruler(killer)
		if _is_valid_live_unit(guard_owner_ruler):
			guard_owner_ruler.set_role(Unit.UnitRole.RULER)
			log_event("RULER_SUCCESSION_VIA_GUARD", {
				"old_ruler": dead_ruler.name,
				"killer": killer.name,
				"new_ruler": guard_owner_ruler.name,
			})
		else:
			log_event("RULER_SUCCESSION_BLOCKED_ROYAL_GUARD", {
				"old_ruler": dead_ruler.name,
				"killer": killer.name,
			})
	elif killer_is_valid and killer.is_disband_cooldown_active():
		log_event("RULER_SUCCESSION_BLOCKED_COOLDOWN", {
			"old_ruler": dead_ruler.name,
			"killer": killer.name,
		})

	_stabilize_world_state()
	_refresh_debug_hud()

func _stabilize_world_state() -> void:
	for unit in _get_live_units():
		if unit.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		var guard_ruler := _get_guard_ruler_reference(unit)
		if guard_ruler == null:
			log_event("GUARD_DISBANDED", {
				"guard": unit.name,
				"old_ruler": "-",
			})
			unit.clear_guard_assignment()
			unit.start_disband_cooldown()
			continue
		if guard_ruler.is_dead():
			log_event("GUARD_DISBANDED", {
				"guard": unit.name,
				"old_ruler": guard_ruler.name,
			})
			unit.clear_guard_assignment()
			unit.start_disband_cooldown()

func _get_live_units() -> Array[Unit]:
	var units: Array[Unit] = []
	for child in get_children():
		if not (child is Unit):
			continue
		if not _is_valid_live_unit(child):
			continue
		units.append(child)
	return units

func _get_guard_ruler(guard: Unit) -> Unit:
	var ruler := _get_guard_ruler_reference(guard)
	if _is_valid_live_unit(ruler):
		return ruler
	return null

func _get_guard_ruler_reference(guard: Unit) -> Unit:
	if guard == null or not is_instance_valid(guard):
		return null
	if guard.role != Unit.UnitRole.ROYAL_GUARD:
		return null
	if guard.ruler_path.is_empty():
		return null

	var ruler := guard.get_node_or_null(guard.ruler_path)
	if ruler is Unit:
		return ruler
	return null

func _guard_references_unit(guard: Unit, target_unit: Unit) -> bool:
	if guard == null or not is_instance_valid(guard):
		return false
	if target_unit == null or not is_instance_valid(target_unit):
		return false
	if guard.role != Unit.UnitRole.ROYAL_GUARD:
		return false
	if guard.ruler_path.is_empty():
		return false

	var ruler := guard.get_node_or_null(guard.ruler_path)
	return ruler == target_unit

func _is_valid_live_unit(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	return not unit.is_dead()

func set_debug_focus_unit(unit: Unit) -> void:
	if not _is_valid_live_unit(unit):
		return
	_debug_focus_unit = unit
	_refresh_debug_hud()

func _refresh_debug_hud() -> void:
	if _debug_status_label == null or _debug_events_label == null:
		return

	var live_units := _get_live_units()
	var live_rulers: Array[Unit] = []
	var free_knights := 0
	var player_unit: Unit = null
	for unit in live_units:
		if unit.role == Unit.UnitRole.RULER:
			live_rulers.append(unit)
		if unit.role == Unit.UnitRole.FREE_KNIGHT:
			free_knights += 1
		if player_unit == null and unit.is_player_controlled:
			player_unit = unit

	var lines: Array[String] = []
	lines.append("DEBUG HUD")
	lines.append("Lebende Herrscher: %s" % live_rulers.size())
	if not live_rulers.is_empty():
		var ruler_names: Array[String] = []
		for ruler in live_rulers:
			ruler_names.append(ruler.name)
		lines.append("Rulers: %s" % ", ".join(ruler_names))
	lines.append("Freie Ritter: %s" % free_knights)

	if _debug_focus_unit != null and (not is_instance_valid(_debug_focus_unit) or _debug_focus_unit.is_dead()):
		_debug_focus_unit = null

	var relevant_unit := _debug_focus_unit
	if relevant_unit == null and player_unit != null:
		relevant_unit = player_unit.get_attack_target()

	if player_unit != null:
		lines.append("")
		lines.append("Spieler: %s" % player_unit.name)
		lines.append("Spieler-Rolle: %s" % _role_to_text(player_unit.role))
		lines.append("Spieler-HP: %.0f / %.0f" % [player_unit.current_hp, player_unit.max_hp])
		var player_target := player_unit.get_attack_target()
		lines.append("Spieler-Ziel: %s" % (player_target.name if player_target != null else "-"))

	if relevant_unit != null:
		lines.append("")
		lines.append("Relevante Unit: %s" % relevant_unit.name)
		lines.append("Rolle: %s" % _role_to_text(relevant_unit.role))
		lines.append("HP: %.0f / %.0f" % [relevant_unit.current_hp, relevant_unit.max_hp])

	_debug_status_label.text = "\n".join(lines)
	_debug_events_label.text = "Events:\n%s" % "\n".join(_debug_events)

func _format_log_value(value: Variant) -> String:
	if value is Vector2:
		var vec: Vector2 = value
		return "(%.1f,%.1f)" % [vec.x, vec.y]
	return str(value)

func _role_to_text(role: Unit.UnitRole) -> String:
	match role:
		Unit.UnitRole.RULER:
			return "RULER"
		Unit.UnitRole.ROYAL_GUARD:
			return "ROYAL_GUARD"
		_:
			return "FREE_KNIGHT"

func _clamp_to_ruler_search_bounds(point: Vector2) -> Vector2:
	var max_x := ruler_search_bounds.position.x + ruler_search_bounds.size.x
	var max_y := ruler_search_bounds.position.y + ruler_search_bounds.size.y
	return Vector2(
		clampf(point.x, ruler_search_bounds.position.x, max_x),
		clampf(point.y, ruler_search_bounds.position.y, max_y)
	)

func _process_periodic_free_knight_spawn(delta: float) -> void:
	if not periodic_free_knight_spawn_enabled:
		return
	if _validated_periodic_free_knight_spawn_points.is_empty():
		return
	if periodic_free_knight_spawn_interval <= 0.0:
		return

	_periodic_spawn_cooldown -= delta
	if _periodic_spawn_cooldown > 0.0:
		return

	_periodic_spawn_cooldown = periodic_free_knight_spawn_interval
	_spawn_free_knight_at_next_point()

func _spawn_free_knight_at_next_point() -> void:
	if _FREE_KNIGHT_SCENE == null:
		return
	if _validated_periodic_free_knight_spawn_points.is_empty():
		return

	var spawn_anchor := _validated_periodic_free_knight_spawn_points[_spawn_rng.randi_range(0, _validated_periodic_free_knight_spawn_points.size() - 1)]
	var jitter := Vector2.RIGHT.rotated(_spawn_rng.randf_range(0.0, TAU)) * _spawn_rng.randf_range(0.0, _SPAWN_JITTER_RADIUS)
	var spawn_point := _clamp_to_ruler_search_bounds(spawn_anchor + jitter)

	var spawned_node := _FREE_KNIGHT_SCENE.instantiate()
	if not (spawned_node is Unit):
		if spawned_node != null:
			spawned_node.queue_free()
		return

	var spawned_unit: Unit = spawned_node
	spawned_unit.name = "SpawnedFreeKnight_%d" % Time.get_ticks_msec()
	spawned_unit.is_player_controlled = false
	spawned_unit.reset_free_knight_identity()
	add_child(spawned_unit)
	spawned_unit.global_position = spawn_point
	spawned_unit.set_role(Unit.UnitRole.FREE_KNIGHT)

	log_event("FREE_KNIGHT_SPAWNED", {
		"unit": spawned_unit.name,
		"point": spawned_unit.global_position,
	})

func _prepare_periodic_free_knight_spawn_points() -> void:
	_validated_periodic_free_knight_spawn_points = PackedVector2Array()

	for source_point in periodic_free_knight_spawn_points:
		var validated_spawn_point := _resolve_valid_spawn_point(source_point)
		if validated_spawn_point == Vector2.INF:
			log_event("FREE_KNIGHT_SPAWN_POINT_INVALID", {
				"reason": "invalid_spawn_point",
				"source_point": source_point,
			})
			continue
		if _is_spawn_point_near_duplicate(_validated_periodic_free_knight_spawn_points, validated_spawn_point):
			continue
		if _is_spawn_point_too_close(_validated_periodic_free_knight_spawn_points, validated_spawn_point):
			continue
		_validated_periodic_free_knight_spawn_points.append(validated_spawn_point)

	if _validated_periodic_free_knight_spawn_points.size() < _SPAWN_POINT_MIN_POOL_SIZE:
		log_event("FREE_KNIGHT_SPAWN_POOL_DEGENERATE", {
			"validated_points": _validated_periodic_free_knight_spawn_points.size(),
		})

func _is_spawn_point_near_duplicate(points: PackedVector2Array, candidate: Vector2) -> bool:
	for point in points:
		if point.distance_to(candidate) <= _SPAWN_POINT_DUPLICATE_EPSILON:
			return true
	return false

func _is_spawn_point_too_close(points: PackedVector2Array, candidate: Vector2) -> bool:
	for point in points:
		if point.distance_to(candidate) < _SPAWN_POINT_MIN_SPACING:
			return true
	return false

func _resolve_valid_spawn_point(raw_spawn_point: Vector2) -> Vector2:
	if not ruler_search_bounds.has_point(raw_spawn_point):
		return Vector2.INF
	return raw_spawn_point

func _transfer_ruler_identity(dead_ruler: Unit, successor: Unit) -> void:
	if not _is_valid_live_unit(dead_ruler):
		return
	if not _is_valid_live_unit(successor):
		return
	successor.absorb_ruler_identity_from(dead_ruler)