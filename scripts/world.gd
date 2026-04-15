extends Node2D

var _current_ruler: Unit = null

func _ready() -> void:
	_refresh_current_ruler()
	_stabilize_ruler_and_guards()

func find_path(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var nav_map := get_world_2d().navigation_map
	var path := NavigationServer2D.map_get_path(nav_map, from_position, to_position, false)
	if path.is_empty():
		return PackedVector2Array([to_position])
	return path

func get_current_ruler() -> Unit:
	if _is_valid_live_unit(_current_ruler):
		return _current_ruler
	return null

func on_ruler_attacked(ruler: Unit, attacker: Unit) -> void:
	if ruler != get_current_ruler():
		return
	if attacker == null or not is_instance_valid(attacker) or attacker.is_dead():
		return

	for child in get_children():
		if not (child is Unit):
			continue
		if child.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		var guard_ruler := _get_guard_ruler(child)
		if guard_ruler != ruler:
			continue
		child.set_attack_target(attacker)

func on_ruler_died(dead_ruler: Unit, killer: Unit) -> void:
	if dead_ruler == null or dead_ruler != get_current_ruler():
		return

	_current_ruler = null

	for child in get_children():
		if not (child is Unit):
			continue
		if child.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		var guard_ruler := _get_guard_ruler(child)
		if guard_ruler != dead_ruler:
			continue
		child.clear_guard_assignment()

	if _is_valid_live_unit(killer) and killer != dead_ruler:
		killer.set_role(Unit.UnitRole.RULER)
		_current_ruler = killer

	_stabilize_ruler_and_guards()

func _refresh_current_ruler() -> void:
	_current_ruler = null
	for child in get_children():
		if not (child is Unit):
			continue
		if child.role != Unit.UnitRole.RULER:
			continue
		if not _is_valid_live_unit(child):
			continue
		_current_ruler = child
		return

func _stabilize_ruler_and_guards() -> void:
	var live_ruler := get_current_ruler()
	for child in get_children():
		if not (child is Unit):
			continue
		if child.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		var guard_ruler := _get_guard_ruler(child)
		if live_ruler == null or guard_ruler != live_ruler:
			child.clear_guard_assignment()

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
