extends Node2D

@export var world_stabilize_interval: float = 0.4

var _stabilize_cooldown: float = 0.0

func _ready() -> void:
	_stabilize_world_state()

func _process(delta: float) -> void:
	_stabilize_cooldown -= delta
	if _stabilize_cooldown > 0.0:
		return
	_stabilize_cooldown = world_stabilize_interval
	_stabilize_world_state()

func find_path(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var nav_map := get_world_2d().navigation_map
	var path := NavigationServer2D.map_get_path(nav_map, from_position, to_position, false)
	if path.is_empty():
		return PackedVector2Array([to_position])
	return path

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

func on_ruler_died(dead_ruler: Unit, killer: Unit) -> void:
	if dead_ruler == null or not is_instance_valid(dead_ruler):
		return

	# Zerfall: Eskorte des toten Herrschers wird frei, keine Rebind-Übernahme.
	for guard in _get_live_units():
		if guard.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		var guard_ruler := _get_guard_ruler(guard)
		if guard_ruler != dead_ruler:
			continue
		guard.clear_guard_assignment()

	if _is_valid_live_unit(killer) and killer != dead_ruler:
		killer.set_role(Unit.UnitRole.RULER)

	_stabilize_world_state()

func _stabilize_world_state() -> void:
	for unit in _get_live_units():
		if unit.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		var guard_ruler := _get_guard_ruler(unit)
		if guard_ruler == null:
			unit.clear_guard_assignment()

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
	if guard == null or not is_instance_valid(guard):
		return null
	if guard.role != Unit.UnitRole.ROYAL_GUARD:
		return null
	if guard.ruler_path.is_empty():
		return null

	var ruler := guard.get_node_or_null(guard.ruler_path)
	if ruler is Unit and _is_valid_live_unit(ruler):
		return ruler
	return null

func _is_valid_live_unit(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	return not unit.is_dead()
