extends Node2D

@export var world_stabilize_interval: float = 0.4
@export var debug_hud_update_interval: float = 0.15

var _stabilize_cooldown: float = 0.0
var _debug_hud_cooldown: float = 0.0
var _debug_events: Array[String] = []
var _debug_focus_unit: Unit = null

@onready var _debug_status_label: Label = $DebugHud/Panel/Margin/Content/StatusLabel
@onready var _debug_events_label: Label = $DebugHud/Panel/Margin/Content/EventsLabel

func _ready() -> void:
	_stabilize_world_state()
	_push_debug_event("Debug-HUD aktiv.")
	_refresh_debug_hud()

func _process(delta: float) -> void:
	_stabilize_cooldown -= delta
	if _stabilize_cooldown <= 0.0:
		_stabilize_cooldown = world_stabilize_interval
		_stabilize_world_state()

	_debug_hud_cooldown -= delta
	if _debug_hud_cooldown <= 0.0:
		_debug_hud_cooldown = debug_hud_update_interval
		_refresh_debug_hud()

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

func on_ruler_died(dead_ruler: Unit, killer: Unit, role_at_death: Unit.UnitRole = Unit.UnitRole.FREE_KNIGHT) -> void:
	if dead_ruler == null or not is_instance_valid(dead_ruler):
		return
	if role_at_death != Unit.UnitRole.RULER:
		return

	# Zerfall: Eskorte des toten Herrschers wird frei, keine Rebind-Übernahme.
	var freed_guard_count := 0
	for guard in _get_live_units():
		if guard.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		if not _guard_references_unit(guard, dead_ruler):
			continue
		guard.clear_guard_assignment()
		guard.start_disband_cooldown()
		freed_guard_count += 1

	_push_debug_event("Herrscher tot: %s" % dead_ruler.name)
	if freed_guard_count > 0:
		_push_debug_event("Eskorte zerfiel: %s Guards frei" % freed_guard_count)

	if _is_valid_live_unit(killer) and killer != dead_ruler:
		killer.set_role(Unit.UnitRole.RULER)
		_push_debug_event("Neue Herrscherrolle: %s" % killer.name)

	_stabilize_world_state()
	_refresh_debug_hud()

func _stabilize_world_state() -> void:
	for unit in _get_live_units():
		if unit.role != Unit.UnitRole.ROYAL_GUARD:
			continue
		var guard_ruler := _get_guard_ruler(unit)
		if guard_ruler == null:
			unit.clear_guard_assignment()
			unit.start_disband_cooldown()
			_push_debug_event("Eskorte zerfiel: %s wurde frei" % unit.name)

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

func _push_debug_event(message: String) -> void:
	if message.is_empty():
		return
	_debug_events.append(message)
	while _debug_events.size() > 5:
		_debug_events.pop_front()

func _role_to_text(role: Unit.UnitRole) -> String:
	match role:
		Unit.UnitRole.RULER:
			return "RULER"
		Unit.UnitRole.ROYAL_GUARD:
			return "ROYAL_GUARD"
		_:
			return "FREE_KNIGHT"
