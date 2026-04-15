extends Node2D

func find_path(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var nav_map := get_world_2d().navigation_map
	var path := NavigationServer2D.map_get_path(nav_map, from_position, to_position, false)
	if path.is_empty():
		return PackedVector2Array([to_position])
	return path

func on_ruler_attacked(ruler: Unit, attacker: Unit) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.is_dead():
		return

	for child in get_children():
		if not (child is Unit):
			continue
		if child.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		var guard_ruler := child.get_node_or_null(child.ruler_path)
		if guard_ruler != ruler:
			continue
		child.set_attack_target(attacker)
