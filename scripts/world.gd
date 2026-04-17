extends Node2D

@export var world_stabilize_interval: float = 0.4
@export var debug_hud_update_interval: float = 0.15
@export var ruler_search_bounds: Rect2 = Rect2(-1400.0, -1300.0, 5000.0, 3900.0)
@export var periodic_free_knight_spawn_interval: float = 22.0
@export var periodic_free_knight_spawn_enabled: bool = true
@export var periodic_free_knight_spawn_points: PackedVector2Array = PackedVector2Array([
	Vector2(120.0, 120.0),
	Vector2(1330.0, 120.0),
	Vector2(730.0, 980.0),
])
@export var environment_tileset: TileSet

var _stabilize_cooldown: float = 0.0
var _debug_hud_cooldown: float = 0.0
var _debug_events: Array[String] = []
var _debug_event_limit: int = 10
var _debug_focus_unit: Unit = null
var _periodic_spawn_cooldown: float = 0.0
var _validated_periodic_free_knight_spawn_points: PackedVector2Array = PackedVector2Array()
var _spawn_rng := RandomNumberGenerator.new()
var _map_layers_ready_logged: bool = false
var _environment_tileset_state_logged: bool = false

const _FREE_KNIGHT_SCENE: PackedScene = preload("res://scenes/units/Unit.tscn")
const _SPAWN_POINT_DUPLICATE_EPSILON: float = 8.0
const _SPAWN_POINT_MIN_SPACING: float = 120.0
const _SPAWN_POINT_MIN_POOL_SIZE: int = 3
const _RULER_SEARCH_POINT_DUPLICATE_EPSILON: float = 8.0
const _SPAWN_JITTER_RADIUS: float = 24.0
const _ENVIRONMENT_ROOT_NAME := "Environment"
const _MAP_LAYERS_ROOT_NAME := "MapLayers"
const _ENVIRONMENT_ROOT_Z_INDEX := -100
const _GROUND_VISUAL_PATH := "Environment/Ground/GroundVisual"
const _ENV_TILE_SIZE := Vector2i(64, 64)
const _ENV_TERRAIN_TEXTURE_PATH := "res://assets/Terrain/Tileset/Tilemap_color3.png"
const _ENV_WATER_TEXTURE_PATH := "res://assets/Terrain/Tileset/Water Background color.png"
const _ENV_SHADOW_TEXTURE_PATH := "res://assets/Terrain/Tileset/Shadow.png"
const _ENV_SOURCE_WATER := 100
const _ENV_SOURCE_TERRAIN := 200
const _ENV_SOURCE_SHADOW := 300
const _MAP_LAYER_CONFIGS := [
	{"name": "Water", "z_index": 0, "y_sort_enabled": false, "y_sort_origin": 0},
	{"name": "Ground", "z_index": 10, "y_sort_enabled": false, "y_sort_origin": 0},
	{"name": "Shadows", "z_index": 15, "y_sort_enabled": false, "y_sort_origin": 0},
	{"name": "Cliffs", "z_index": 20, "y_sort_enabled": false, "y_sort_origin": 0},
	{"name": "PropsGround", "z_index": 40, "y_sort_enabled": true, "y_sort_origin": 0},
	{"name": "PropsPlateau", "z_index": 50, "y_sort_enabled": true, "y_sort_origin": 0},
]

@onready var _debug_status_label: Label = $DebugHud/Panel/Margin/Content/StatusLabel
@onready var _debug_events_label: Label = $DebugHud/Panel/Margin/Content/EventsLabel

func _ready() -> void:
	_spawn_rng.randomize()
	_periodic_spawn_cooldown = periodic_free_knight_spawn_interval
	_setup_map_infrastructure()
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

# Map infrastructure

func _setup_map_infrastructure() -> void:
	var layers := _ensure_map_layers()
	var environment_setup := _load_environment_tileset()
	_apply_environment_tileset_to_layers(environment_setup.get("tileset", null) as TileSet)
	_set_ground_visual_visible(true)
	_log_environment_tileset_state(environment_setup)
	_build_test_island(environment_setup, layers)

func _ensure_map_layers() -> Dictionary:
	var layers: Dictionary = {}
	var map_layers_root := _ensure_map_layers_root()

	for layer_config in _MAP_LAYER_CONFIGS:
		var layer_name := str(layer_config.get("name", "Layer"))
		var layer := map_layers_root.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			layer = TileMapLayer.new()
			layer.name = layer_name
			map_layers_root.add_child(layer)
			map_layers_root.move_child(layer, map_layers_root.get_child_count() - 1)

		layer.enabled = true
		layer.collision_enabled = false
		layer.navigation_enabled = false
		layer.occlusion_enabled = false
		layer.z_index = int(layer_config.get("z_index", 0))
		layer.y_sort_enabled = bool(layer_config.get("y_sort_enabled", false))
		layer.y_sort_origin = int(layer_config.get("y_sort_origin", 0))
		layers[layer_name] = layer

	if not _map_layers_ready_logged:
		log_event("MAP_LAYERS_READY", {
			"layer_count": layers.size(),
			"root": map_layers_root.get_path(),
		})
		_map_layers_ready_logged = true

	return layers

func _ensure_map_layers_root() -> Node2D:
	var environment_root := _ensure_environment_root()
	var map_layers_root := environment_root.get_node_or_null(_MAP_LAYERS_ROOT_NAME) as Node2D
	if map_layers_root == null:
		map_layers_root = Node2D.new()
		map_layers_root.name = _MAP_LAYERS_ROOT_NAME
		environment_root.add_child(map_layers_root)
	return map_layers_root

func _ensure_environment_root() -> Node2D:
	var environment_root := get_node_or_null(_ENVIRONMENT_ROOT_NAME) as Node2D
	if environment_root == null:
		environment_root = Node2D.new()
		environment_root.name = _ENVIRONMENT_ROOT_NAME
		add_child(environment_root)
		move_child(environment_root, 0)

	environment_root.z_index = _ENVIRONMENT_ROOT_Z_INDEX
	environment_root.y_sort_enabled = false
	return environment_root

func _load_environment_tileset() -> Dictionary:
	var result := {
		"status": "missing",
		"ready": false,
		"tileset": null,
		"source_path": "",
		"missing_assets": [],
	}

	if environment_tileset != null:
		result["status"] = "ready"
		result["ready"] = true
		result["tileset"] = environment_tileset
		result["source_path"] = "<exported>"
		return result

	var runtime_tileset := _build_runtime_environment_tileset()
	if runtime_tileset != null:
		result["status"] = "ready"
		result["ready"] = true
		result["tileset"] = runtime_tileset
		result["source_path"] = "<runtime:%s>" % _ENV_TERRAIN_TEXTURE_PATH
		return result

	result["status"] = "missing"
	result["missing_assets"] = _get_missing_environment_asset_paths()
	return result

func _apply_environment_tileset_to_layers(tileset: TileSet) -> void:
	var layers := _ensure_map_layers()
	for layer_name in layers.keys():
		var layer := layers[layer_name] as TileMapLayer
		if layer == null:
			continue
		layer.tile_set = tileset
		layer.fix_invalid_tiles()

func _log_environment_tileset_state(environment_setup: Dictionary) -> void:
	if _environment_tileset_state_logged:
		return

	var status := str(environment_setup.get("status", "missing"))
	match status:
		"ready":
			var tileset := environment_setup.get("tileset", null) as TileSet
			log_event("ENVIRONMENT_TILESET_READY", {
				"source": str(environment_setup.get("source_path", "")),
				"source_count": tileset.get_source_count() if tileset != null else 0,
			})
		_:
			log_event("ENVIRONMENT_TILESET_MISSING", {
				"missing_asset_count": (environment_setup.get("missing_assets", []) as Array).size(),
			})

	_environment_tileset_state_logged = true

func _build_runtime_environment_tileset() -> TileSet:
	var terrain_texture := load(_ENV_TERRAIN_TEXTURE_PATH) as Texture2D
	var water_texture := load(_ENV_WATER_TEXTURE_PATH) as Texture2D
	var shadow_texture := load(_ENV_SHADOW_TEXTURE_PATH) as Texture2D
	if terrain_texture == null or water_texture == null or shadow_texture == null:
		return null

	var tileset := TileSet.new()
	tileset.tile_size = _ENV_TILE_SIZE

	var water_source := TileSetAtlasSource.new()
	water_source.texture = water_texture
	water_source.texture_region_size = _ENV_TILE_SIZE
	water_source.create_tile(Vector2i.ZERO)
	tileset.add_source(water_source, _ENV_SOURCE_WATER)

	var terrain_source := TileSetAtlasSource.new()
	terrain_source.texture = terrain_texture
	terrain_source.texture_region_size = _ENV_TILE_SIZE
	terrain_source.create_tile(Vector2i(0, 0), Vector2i(3, 3))
	terrain_source.create_tile(Vector2i(3, 0), Vector2i(1, 3))
	terrain_source.create_tile(Vector2i(0, 3), Vector2i(3, 1))
	terrain_source.create_tile(Vector2i(3, 3), Vector2i(1, 1))
	terrain_source.create_tile(Vector2i(0, 4), Vector2i(2, 2))
	terrain_source.create_tile(Vector2i(2, 4), Vector2i(2, 2))
	terrain_source.create_tile(Vector2i(5, 0), Vector2i(3, 3))
	terrain_source.create_tile(Vector2i(8, 0), Vector2i(1, 3))
	terrain_source.create_tile(Vector2i(5, 3), Vector2i(3, 3))
	terrain_source.create_tile(Vector2i(8, 3), Vector2i(1, 3))
	tileset.add_source(terrain_source, _ENV_SOURCE_TERRAIN)

	var shadow_source := TileSetAtlasSource.new()
	shadow_source.texture = shadow_texture
	shadow_source.texture_region_size = _ENV_TILE_SIZE
	shadow_source.create_tile(Vector2i.ZERO, Vector2i(3, 3))
	tileset.add_source(shadow_source, _ENV_SOURCE_SHADOW)

	return tileset

func _get_missing_environment_asset_paths() -> Array[String]:
	var missing: Array[String] = []
	for path in [
		_ENV_TERRAIN_TEXTURE_PATH,
		_ENV_WATER_TEXTURE_PATH,
		_ENV_SHADOW_TEXTURE_PATH,
	]:
		if not ResourceLoader.exists(path):
			missing.append(path)
	return missing

func _set_ground_visual_visible(is_visible: bool) -> void:
	var ground_visual := get_node_or_null(_GROUND_VISUAL_PATH) as CanvasItem
	if ground_visual != null:
		ground_visual.visible = is_visible

func _build_test_island(environment_setup: Dictionary, layers: Dictionary) -> void:
	var tileset := environment_setup.get("tileset", null) as TileSet
	if tileset == null:
		log_event("TEST_ISLAND_SKIPPED", {
			"reason": "missing_environment_tileset",
		})
		return

	for layer_name in layers.keys():
		var layer := layers[layer_name] as TileMapLayer
		if layer == null:
			continue
		layer.clear()

	var water_layer := layers.get("Water", null) as TileMapLayer
	var ground_layer := layers.get("Ground", null) as TileMapLayer
	var shadow_layer := layers.get("Shadows", null) as TileMapLayer
	var cliff_layer := layers.get("Cliffs", null) as TileMapLayer
	var props_ground_layer := layers.get("PropsGround", null) as TileMapLayer
	var props_plateau_layer := layers.get("PropsPlateau", null) as TileMapLayer

	var island_origin := Vector2i(-18, 28)
	var water_fill := _make_tile_ref(_ENV_SOURCE_WATER, Vector2i.ZERO)
	var ground_block := _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(0, 0))
	var ground_strip_vertical := _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(3, 0))
	var ground_strip_horizontal := _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(0, 3))
	var ground_corner := _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(3, 3))
	var cliff_plateau := _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(5, 3))
	var cliff_column := _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(8, 3))
	var shadow_blob := _make_tile_ref(_ENV_SOURCE_SHADOW, Vector2i.ZERO)

	_paint_rect(water_layer, Rect2i(island_origin + Vector2i(-3, -2), Vector2i(10, 9)), water_fill)
	_set_layer_cell(ground_layer, island_origin, ground_block)
	_set_layer_cell(ground_layer, island_origin + Vector2i(3, 0), ground_strip_vertical)
	_set_layer_cell(ground_layer, island_origin + Vector2i(0, 3), ground_strip_horizontal)
	_set_layer_cell(ground_layer, island_origin + Vector2i(3, 3), ground_corner)
	_set_layer_cell(cliff_layer, island_origin + Vector2i(0, 0), cliff_plateau)
	_set_layer_cell(cliff_layer, island_origin + Vector2i(3, 0), cliff_column)
	_set_layer_cell(shadow_layer, island_origin + Vector2i(1, 1), shadow_blob)

	for layer_node in [
		water_layer,
		ground_layer,
		shadow_layer,
		cliff_layer,
		props_ground_layer,
		props_plateau_layer,
	]:
		if layer_node != null:
			layer_node.update_internals()

	log_event("TEST_ISLAND_BUILT", {
		"tileset": str(environment_setup.get("source_path", "<runtime>")),
		"origin": island_origin,
	})

func _make_tile_ref(source_id: int, atlas_coords: Vector2i, alternative_tile: int = 0) -> Dictionary:
	return {
		"source_id": source_id,
		"atlas_coords": atlas_coords,
		"alternative_tile": alternative_tile,
	}

func _paint_rect(layer: TileMapLayer, rect: Rect2i, tile_ref: Dictionary) -> void:
	if layer == null or tile_ref.is_empty():
		return

	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			_set_layer_cell(layer, Vector2i(x, y), tile_ref)

func _paint_cells(layer: TileMapLayer, cells: Array[Vector2i], tile_ref: Dictionary) -> void:
	if layer == null or tile_ref.is_empty():
		return

	for coords in cells:
		_set_layer_cell(layer, coords, tile_ref)

func _set_layer_cell(layer: TileMapLayer, coords: Vector2i, tile_ref: Dictionary) -> void:
	layer.set_cell(
		coords,
		int(tile_ref.get("source_id", -1)),
		tile_ref.get("atlas_coords", Vector2i(-1, -1)),
		int(tile_ref.get("alternative_tile", 0))
	)

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
