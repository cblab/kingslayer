extends Node2D

@export var world_stabilize_interval: float = 0.4
@export var debug_hud_update_interval: float = 0.15
@export var ruler_search_bounds: Rect2 = Rect2(-1400.0, -1300.0, 5000.0, 3900.0)
@export var periodic_free_knight_spawn_interval: float = 22.0
@export var periodic_free_knight_spawn_enabled: bool = true
@export var periodic_free_knight_spawn_points: PackedVector2Array = PackedVector2Array([
	Vector2(-896.0, 512.0),
	Vector2(704.0, 640.0),
	Vector2(1984.0, 1024.0),
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
var _arena_walkable_cells: Array[Vector2i] = []
var _arena_walkable_cell_set: Dictionary = {}
var _arena_walkable_rect: Rect2 = Rect2()

const _FREE_KNIGHT_SCENE: PackedScene = preload("res://scenes/units/Unit.tscn")
const _SPAWN_POINT_DUPLICATE_EPSILON: float = 8.0
const _SPAWN_POINT_MIN_SPACING: float = 120.0
const _SPAWN_POINT_MIN_POOL_SIZE: int = 3
const _RULER_SEARCH_POINT_DUPLICATE_EPSILON: float = 8.0
const _SPAWN_JITTER_RADIUS: float = 24.0
const _ENVIRONMENT_ROOT_NAME := "Environment"
const _MAP_LAYERS_ROOT_NAME := "MapLayers"
const _ENV_COLLIDERS_ROOT_NAME := "TerrainCollision"
const _ENVIRONMENT_ROOT_Z_INDEX := -100
const _ENV_TILE_SIZE := Vector2i(64, 64)
const _ENV_TERRAIN_TEXTURE_PATH := "res://assets/Terrain/Tileset/Tilemap_color3.png"
const _ENV_WATER_TEXTURE_PATH := "res://assets/Terrain/Tileset/Water Background color.png"
const _ENV_SHADOW_TEXTURE_PATH := "res://assets/Terrain/Tileset/Shadow.png"
const _ENV_SOURCE_WATER := 100
const _ENV_SOURCE_TERRAIN := 200
const _ENV_SOURCE_SHADOW := 300
const _TEST_MAP_VERSION := "tile_arena_v1"
const _START_ANCHOR_PLAYER := "player"
const _START_ANCHOR_RULER_RED := "ruler_red"
const _START_ANCHOR_RULER_GREEN := "ruler_green"
const _START_ANCHOR_RULER_BLUE := "ruler_blue"
const _GUARD_NEARBY_OFFSETS: Array[Vector2] = [
	Vector2(-128.0, 0.0),
	Vector2(128.0, 0.0),
	Vector2(0.0, -128.0),
	Vector2(0.0, 128.0),
]
const _ARENA_BOUND_MARGIN := 32.0
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
	_refresh_arena_walkable_space()
	_apply_start_anchors_to_core_units()
	_snap_initial_units_to_walkable_ground()
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
	_log_environment_tileset_state(environment_setup)
	_build_tile_arena(environment_setup, layers)
	_rebuild_environment_colliders_from_tiles(layers)

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

func _ensure_environment_colliders_root() -> Node2D:
	var environment_root := _ensure_environment_root()
	var colliders_root := environment_root.get_node_or_null(_ENV_COLLIDERS_ROOT_NAME) as Node2D
	if colliders_root == null:
		colliders_root = Node2D.new()
		colliders_root.name = _ENV_COLLIDERS_ROOT_NAME
		environment_root.add_child(colliders_root)
	return colliders_root

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
	for y in range(6):
		for x in range(9):
			terrain_source.create_tile(Vector2i(x, y))
	tileset.add_source(terrain_source, _ENV_SOURCE_TERRAIN)

	var shadow_source := TileSetAtlasSource.new()
	shadow_source.texture = shadow_texture
	shadow_source.texture_region_size = _ENV_TILE_SIZE
	for y in range(3):
		for x in range(3):
			shadow_source.create_tile(Vector2i(x, y))
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

func _map_layers_have_tiles(layers: Dictionary) -> bool:
	for layer_name in ["Water", "Ground", "Cliffs", "Shadows"]:
		var layer := layers.get(layer_name, null) as TileMapLayer
		if layer == null:
			continue
		if not layer.get_used_cells().is_empty():
			return true
	return false

func _build_tile_arena(environment_setup: Dictionary, layers: Dictionary) -> void:
	var tileset := environment_setup.get("tileset", null) as TileSet
	if tileset == null:
		log_event("TILE_ARENA_SKIPPED", {
			"reason": "missing_environment_tileset",
		})
		return

	var tile_refs := _pick_test_island_tile_refs(tileset)
	if tile_refs.is_empty():
		log_event("TILE_ARENA_SKIPPED", {
			"reason": "tileset_has_no_atlas_tiles",
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

	var ground_rect := Rect2i(Vector2i(-18, -12), Vector2i(58, 44))
	var water_rect := ground_rect.grow(6)
	var border_cliffs := _build_border_cliff_cells(ground_rect)
	var interior_cliffs := _build_interior_cliff_cells()
	var all_cliffs := border_cliffs + interior_cliffs
	var shadow_cells := _build_border_shadow_cells(ground_rect)

	_paint_rect(water_layer, water_rect, tile_refs.get("Water", {}))
	_paint_rect(ground_layer, ground_rect, tile_refs.get("Ground", {}))
	_paint_cells(cliff_layer, all_cliffs, tile_refs.get("Cliffs", {}))
	_paint_cells(shadow_layer, shadow_cells, tile_refs.get("Shadows", {}))

	for layer_name in ["PropsGround", "PropsPlateau"]:
		var props_layer := layers.get(layer_name, null) as TileMapLayer
		if props_layer != null:
			props_layer.clear()

	for layer_node in [water_layer, ground_layer, cliff_layer, shadow_layer]:
		if layer_node != null:
			layer_node.update_internals()

	log_event("TILE_ARENA_BUILT", {
		"ground_rect": ground_rect,
		"water_rect": water_rect,
		"border_cliff_cells": border_cliffs.size(),
		"interior_cliff_cells": interior_cliffs.size(),
		"map_version": _TEST_MAP_VERSION,
		"tileset": str(environment_setup.get("source_path", "<runtime>")),
	})

func _rebuild_environment_colliders_from_tiles(layers: Dictionary) -> void:
	var colliders_root := _ensure_environment_colliders_root()
	for child in colliders_root.get_children():
		colliders_root.remove_child(child)
		child.queue_free()

	var blocked_cells := _collect_visible_blocked_cells(layers)

	var collider_count := _add_environment_colliders_for_blocked_cells(colliders_root, blocked_cells)
	log_event("ENVIRONMENT_COLLIDERS_REBUILT", {
		"blocked_cell_count": blocked_cells.size(),
		"collider_count": collider_count,
	})

func _collect_visible_blocked_cells(layers: Dictionary) -> Dictionary:
	var blocked_cells := {}
	var ground_cells := {}
	var water_total := 0
	var water_blocking := 0
	var cliff_total := 0

	var ground_layer := layers.get("Ground", null) as TileMapLayer
	if ground_layer != null:
		for cell in ground_layer.get_used_cells():
			ground_cells[cell] = true

	var cliff_layer := layers.get("Cliffs", null) as TileMapLayer
	if cliff_layer != null:
		for cell in cliff_layer.get_used_cells():
			cliff_total += 1
			blocked_cells[cell] = true

	var water_layer := layers.get("Water", null) as TileMapLayer
	if water_layer != null:
		for cell in water_layer.get_used_cells():
			water_total += 1
			if ground_cells.has(cell):
				continue
			water_blocking += 1
			blocked_cells[cell] = true

	log_event("ENV_BLOCK_SOURCE_COUNTS", {
		"water_total_cells": water_total,
		"water_blocking_cells": water_blocking,
		"cliff_cells": cliff_total,
		"ground_cells": ground_cells.size(),
	})
	return blocked_cells

func _add_environment_colliders_for_blocked_cells(parent: Node, blocked_cells: Dictionary) -> int:
	if parent == null or blocked_cells.is_empty():
		return 0

	var rows := {}
	for cell in blocked_cells.keys():
		var c := cell as Vector2i
		if not rows.has(c.y):
			rows[c.y] = []
		(rows[c.y] as Array).append(c.x)

	var row_keys := rows.keys()
	row_keys.sort()
	var collider_index := 0
	for y in row_keys:
		var xs := rows[y] as Array
		xs.sort()
		if xs.is_empty():
			continue
		var run_start := int(xs[0])
		var run_end := run_start
		for i in range(1, xs.size()):
			var x := int(xs[i])
			if x == run_end + 1:
				run_end = x
				continue
			collider_index += _add_environment_collider_run(parent, collider_index, run_start, run_end, int(y))
			run_start = x
			run_end = x
		collider_index += _add_environment_collider_run(parent, collider_index, run_start, run_end, int(y))

	return collider_index

func _add_environment_collider_run(parent: Node, collider_index: int, start_x: int, end_x: int, y: int) -> int:
	if end_x < start_x:
		return 0

	var width := (end_x - start_x) + 1
	var world_size := Vector2(width * _ENV_TILE_SIZE.x, _ENV_TILE_SIZE.y)

	var body := StaticBody2D.new()
	body.name = "Blocked_%d" % collider_index
	parent.add_child(body)

	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = world_size
	shape.shape = rectangle
	shape.position = Vector2(
		(start_x * _ENV_TILE_SIZE.x) + (world_size.x * 0.5),
		(y * _ENV_TILE_SIZE.y) + (world_size.y * 0.5)
	)
	body.add_child(shape)
	return 1

func _build_border_cliff_cells(ground_rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(ground_rect.position.y, ground_rect.end.y):
		for x in range(ground_rect.position.x, ground_rect.end.x):
			if x == ground_rect.position.x \
			or x == ground_rect.end.x - 1 \
			or y == ground_rect.position.y \
			or y == ground_rect.end.y - 1:
				cells.append(Vector2i(x, y))
	return cells

func _build_interior_cliff_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(-1, 5):
		for x in range(4, 10):
			cells.append(Vector2i(x, y))
	for y in range(12, 18):
		for x in range(20, 28):
			cells.append(Vector2i(x, y))
	return cells

func _build_border_shadow_cells(ground_rect: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(ground_rect.position.x, ground_rect.end.x):
		cells.append(Vector2i(x, ground_rect.position.y + 1))
	return cells

func _pick_test_island_tile_refs(tileset: TileSet) -> Dictionary:
	var preferred_tile_refs := {
		"Water": _make_tile_ref(_ENV_SOURCE_WATER, Vector2i(0, 0)),
		"Ground": _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(1, 1)),
		"Cliffs": _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(6, 4)),
		"Shadows": _make_tile_ref(_ENV_SOURCE_SHADOW, Vector2i(1, 1)),
		"PropsGround": _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(2, 1)),
		"PropsPlateau": _make_tile_ref(_ENV_SOURCE_TERRAIN, Vector2i(8, 4)),
	}
	if _tileset_has_tile_ref(tileset, preferred_tile_refs["Water"]) \
	and _tileset_has_tile_ref(tileset, preferred_tile_refs["Ground"]) \
	and _tileset_has_tile_ref(tileset, preferred_tile_refs["Cliffs"]) \
	and _tileset_has_tile_ref(tileset, preferred_tile_refs["Shadows"]):
		return preferred_tile_refs

	var atlas_tile_refs := _collect_tileset_atlas_tile_refs(tileset)
	var single_cell_tile_refs := _collect_tileset_atlas_tile_refs(tileset, true)
	var tile_refs_pool := single_cell_tile_refs if not single_cell_tile_refs.is_empty() else atlas_tile_refs
	if tile_refs_pool.is_empty():
		return {}

	var water_candidates := _filter_tile_refs_by_source_keywords(tile_refs_pool, [
		"water background",
		"water",
	])
	if water_candidates.is_empty():
		water_candidates = tile_refs_pool
	var terrain_candidates := _filter_tile_refs_by_source_keywords(tile_refs_pool, [
		"tilemap_color3",
		"tilemap",
		"terrain",
	])
	if terrain_candidates.is_empty():
		terrain_candidates = tile_refs_pool
	var shadow_candidates := _filter_tile_refs_by_source_keywords(tile_refs_pool, [
		"shadow",
	])
	if shadow_candidates.is_empty():
		shadow_candidates = terrain_candidates

	var ground_candidates := _filter_tile_refs_by_atlas_x_range(terrain_candidates, 0, 4)
	if ground_candidates.is_empty():
		ground_candidates = terrain_candidates

	var cliff_candidates := _filter_tile_refs_by_atlas_x_range(terrain_candidates, 5, 8)
	if cliff_candidates.is_empty():
		cliff_candidates = terrain_candidates

	return {
		"Water": _get_tile_ref_or_first(water_candidates, 0),
		"Ground": _get_tile_ref_or_first(ground_candidates, 0),
		"Cliffs": _get_tile_ref_or_first(cliff_candidates, 0),
		"Shadows": _get_tile_ref_or_first(shadow_candidates, 0),
		"PropsGround": _get_tile_ref_or_first(ground_candidates, 1),
		"PropsPlateau": _get_tile_ref_or_first(cliff_candidates, 1),
	}

func _collect_tileset_atlas_tile_refs(tileset: TileSet, single_cell_only := false) -> Array[Dictionary]:
	var refs: Array[Dictionary] = []
	if tileset == null:
		return refs

	for source_index in tileset.get_source_count():
		var source_id := tileset.get_source_id(source_index)
		var source := tileset.get_source(source_id)
		if not (source is TileSetAtlasSource):
			continue
		var atlas_source := source as TileSetAtlasSource

		for tile_index in atlas_source.get_tiles_count():
			var atlas_coords := atlas_source.get_tile_id(tile_index)
			var tile_size_in_atlas: Vector2i = atlas_source.get_tile_size_in_atlas(atlas_coords)
			if single_cell_only and tile_size_in_atlas != Vector2i.ONE:
				continue
			var alternative_id := 0
			if atlas_source.get_alternative_tiles_count(atlas_coords) > 0:
				alternative_id = atlas_source.get_alternative_tile_id(atlas_coords, 0)
			var texture_path := ""
			if atlas_source.texture != null:
				texture_path = atlas_source.texture.resource_path.to_lower()
			refs.append({
				"source_id": source_id,
				"atlas_coords": atlas_coords,
				"alternative_tile": alternative_id,
				"tile_size_in_atlas": tile_size_in_atlas,
				"source_path": texture_path,
			})

	return refs

func _filter_tile_refs_by_source_keywords(tile_refs: Array[Dictionary], keywords: Array[String]) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for tile_ref in tile_refs:
		var source_path := str(tile_ref.get("source_path", "")).to_lower()
		for keyword in keywords:
			if source_path.contains(keyword):
				matches.append(tile_ref)
				break
	return matches

func _filter_tile_refs_by_atlas_x_range(tile_refs: Array[Dictionary], min_x: int, max_x: int) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for tile_ref in tile_refs:
		var atlas_coords := tile_ref.get("atlas_coords", Vector2i.ZERO) as Vector2i
		if atlas_coords.x < min_x or atlas_coords.x > max_x:
			continue
		matches.append(tile_ref)
	return matches

func _get_tile_ref_or_first(tile_refs: Array[Dictionary], index: int) -> Dictionary:
	if tile_refs.is_empty():
		return {}
	return tile_refs[min(index, tile_refs.size() - 1)]

func _make_tile_ref(source_id: int, atlas_coords: Vector2i, alternative_tile: int = 0) -> Dictionary:
	return {
		"source_id": source_id,
		"atlas_coords": atlas_coords,
		"alternative_tile": alternative_tile,
	}

func _tileset_has_tile_ref(tileset: TileSet, tile_ref: Dictionary) -> bool:
	if tileset == null or tile_ref.is_empty():
		return false
	var source_id := int(tile_ref.get("source_id", -1))
	var source := tileset.get_source(source_id)
	if not (source is TileSetAtlasSource):
		return false
	return source.has_tile(tile_ref.get("atlas_coords", Vector2i(-1, -1)))

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

func _refresh_arena_walkable_space() -> void:
	_arena_walkable_cells.clear()
	_arena_walkable_cell_set.clear()
	var layers := _ensure_map_layers()
	var ground_layer := layers.get("Ground", null) as TileMapLayer
	if ground_layer == null:
		ruler_search_bounds = Rect2()
		return

	var ground_cells := {}
	for cell in ground_layer.get_used_cells():
		ground_cells[cell] = true

	var cliff_cells := {}
	var cliff_layer := layers.get("Cliffs", null) as TileMapLayer
	if cliff_layer != null:
		for cell in cliff_layer.get_used_cells():
			cliff_cells[cell] = true

	var water_cells := {}
	var water_layer := layers.get("Water", null) as TileMapLayer
	if water_layer != null:
		for cell in water_layer.get_used_cells():
			water_cells[cell] = true

	var blocked_cells := {}
	for cell in cliff_cells.keys():
		blocked_cells[cell] = true
	for cell in water_cells.keys():
		if ground_cells.has(cell):
			continue
		blocked_cells[cell] = true

	for cell in ground_cells.keys():
		if blocked_cells.has(cell):
			continue
		_arena_walkable_cell_set[cell] = true
		_arena_walkable_cells.append(cell)

	var debug_payload := {
		"ground_cells": ground_cells.size(),
		"cliff_cells": cliff_cells.size(),
		"water_cells": water_cells.size(),
		"blocked_cells": blocked_cells.size(),
		"walkable_cells": _arena_walkable_cells.size(),
	}
	if not ground_cells.is_empty():
		debug_payload["ground_sample"] = _sample_vector2i_cells(ground_cells.keys(), 3)
	if not blocked_cells.is_empty():
		debug_payload["blocked_sample"] = _sample_vector2i_cells(blocked_cells.keys(), 3)
	if not _arena_walkable_cells.is_empty():
		debug_payload["walkable_sample"] = _sample_vector2i_cells(_arena_walkable_cells, 3)
	log_event("ARENA_WALKABLE_SPACE_COUNTS", debug_payload)

	if _arena_walkable_cells.is_empty():
		ruler_search_bounds = Rect2()
		log_event("ARENA_WALKABLE_SPACE_EMPTY", {
			"ground_cells": ground_cells.size(),
			"blocked_cells": blocked_cells.size(),
			"water_cells": water_cells.size(),
			"cliff_cells": cliff_cells.size(),
		})
		return

	var min_cell := _arena_walkable_cells[0]
	var max_cell := _arena_walkable_cells[0]
	for cell in _arena_walkable_cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)

	var origin := Vector2(min_cell.x * _ENV_TILE_SIZE.x, min_cell.y * _ENV_TILE_SIZE.y)
	var size := Vector2(
		((max_cell.x - min_cell.x) + 1) * _ENV_TILE_SIZE.x,
		((max_cell.y - min_cell.y) + 1) * _ENV_TILE_SIZE.y
	)
	_arena_walkable_rect = Rect2(origin, size)
	ruler_search_bounds = _arena_walkable_rect.grow(_ARENA_BOUND_MARGIN)
	log_event("ARENA_WALKABLE_SPACE_READY", {
		"walkable_cells": _arena_walkable_cells.size(),
		"search_bounds": ruler_search_bounds,
	})

func _apply_start_anchors_to_core_units() -> void:
	if _arena_walkable_cells.is_empty():
		return

	var anchor_points := {
		_START_ANCHOR_PLAYER: _resolve_anchor_point(Vector2(0.50, 0.70)),
		_START_ANCHOR_RULER_RED: _resolve_anchor_point(Vector2(0.22, 0.42)),
		_START_ANCHOR_RULER_GREEN: _resolve_anchor_point(Vector2(0.78, 0.42)),
		_START_ANCHOR_RULER_BLUE: _resolve_anchor_point(Vector2(0.50, 0.83)),
	}

	_assign_unit_to_anchor(get_node_or_null("PlayerUnit") as Unit, anchor_points.get(_START_ANCHOR_PLAYER, Vector2.INF), "PLAYER")

	var ruler_red := get_node_or_null("RulerRed") as Unit
	_assign_unit_to_anchor(ruler_red, anchor_points.get(_START_ANCHOR_RULER_RED, Vector2.INF), "RULER_RED")
	_assign_guards_near_ruler(ruler_red, ["RedGuardA", "RedGuardB"])

	var ruler_green := get_node_or_null("RulerGreen") as Unit
	_assign_unit_to_anchor(ruler_green, anchor_points.get(_START_ANCHOR_RULER_GREEN, Vector2.INF), "RULER_GREEN")
	_assign_guards_near_ruler(ruler_green, ["GreenGuardA", "GreenGuardB"])

	var ruler_blue := get_node_or_null("RulerBlue") as Unit
	_assign_unit_to_anchor(ruler_blue, anchor_points.get(_START_ANCHOR_RULER_BLUE, Vector2.INF), "RULER_BLUE")
	_assign_guards_near_ruler(ruler_blue, ["BlueGuardA", "BlueGuardB"])

func _assign_guards_near_ruler(ruler: Unit, guard_names: Array[String]) -> void:
	if not _is_valid_live_unit(ruler):
		return
	for index in range(guard_names.size()):
		var guard := get_node_or_null(guard_names[index]) as Unit
		if guard == null:
			continue
		var desired: Vector2 = ruler.global_position + _GUARD_NEARBY_OFFSETS[index % _GUARD_NEARBY_OFFSETS.size()]
		var resolved := _resolve_valid_spawn_point(desired)
		if resolved == Vector2.INF:
			resolved = _find_nearest_walkable_world_point(ruler.global_position, 8)
		if resolved == Vector2.INF:
			continue
		guard.global_position = resolved

func _assign_unit_to_anchor(unit: Unit, anchor: Vector2, anchor_name: String) -> void:
	if unit == null or anchor == Vector2.INF:
		return
	unit.global_position = anchor
	log_event("UNIT_START_ANCHORED", {
		"unit": unit.name,
		"anchor": anchor_name,
		"position": anchor,
	})

func _resolve_anchor_point(normalized_position: Vector2) -> Vector2:
	if _arena_walkable_rect.size == Vector2.ZERO:
		return Vector2.INF
	var raw := Vector2(
		lerpf(_arena_walkable_rect.position.x + _ENV_TILE_SIZE.x, _arena_walkable_rect.end.x - _ENV_TILE_SIZE.x, clampf(normalized_position.x, 0.0, 1.0)),
		lerpf(_arena_walkable_rect.position.y + _ENV_TILE_SIZE.y, _arena_walkable_rect.end.y - _ENV_TILE_SIZE.y, clampf(normalized_position.y, 0.0, 1.0))
	)
	return _resolve_valid_spawn_point(raw)

func _get_default_periodic_spawn_anchors() -> Array[Vector2]:
	var anchors: Array[Vector2] = []
	if _arena_walkable_cells.is_empty():
		return anchors
	for normalized in [Vector2(0.14, 0.52), Vector2(0.86, 0.52), Vector2(0.38, 0.20), Vector2(0.62, 0.86)]:
		var anchor := _resolve_anchor_point(normalized)
		if anchor != Vector2.INF:
			anchors.append(anchor)
	return anchors

func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_position.x / float(_ENV_TILE_SIZE.x))),
		int(floor(world_position.y / float(_ENV_TILE_SIZE.y)))
	)

func _is_walkable_cell(cell: Vector2i) -> bool:
	return _arena_walkable_cell_set.has(cell)

func _sample_vector2i_cells(cells: Array, max_count: int) -> Array[Vector2i]:
	var sample: Array[Vector2i] = []
	if max_count <= 0:
		return sample
	for cell in cells:
		if not (cell is Vector2i):
			continue
		sample.append(cell)
		if sample.size() >= max_count:
			break
	return sample

func _is_walkable_world_point(world_position: Vector2) -> bool:
	return _is_walkable_cell(_world_to_cell(world_position))

func _find_nearest_walkable_world_point(world_position: Vector2, max_radius_cells: int = 6) -> Vector2:
	var origin_cell := _world_to_cell(world_position)
	if _is_walkable_cell(origin_cell):
		return world_position

	for radius in range(1, max_radius_cells + 1):
		for y in range(origin_cell.y - radius, origin_cell.y + radius + 1):
			for x in range(origin_cell.x - radius, origin_cell.x + radius + 1):
				if abs(x - origin_cell.x) != radius and abs(y - origin_cell.y) != radius:
					continue
				var candidate_cell := Vector2i(x, y)
				if not _is_walkable_cell(candidate_cell):
					continue
				return Vector2(
					(candidate_cell.x * _ENV_TILE_SIZE.x) + (_ENV_TILE_SIZE.x * 0.5),
					(candidate_cell.y * _ENV_TILE_SIZE.y) + (_ENV_TILE_SIZE.y * 0.5)
				)

	return Vector2.INF

func _snap_initial_units_to_walkable_ground() -> void:
	var checked_units := 0
	var relocated_units := 0

	for unit in _get_live_units():
		if not _should_validate_start_position(unit):
			continue
		checked_units += 1

		if _is_walkable_world_point(unit.global_position):
			continue
		var fallback := _find_nearest_walkable_world_point(unit.global_position, 14)
		if fallback == Vector2.INF:
			log_event("UNIT_START_INVALID_UNRESOLVED", {
				"unit": unit.name,
				"position": unit.global_position,
			})
			continue
		unit.global_position = fallback
		relocated_units += 1
		log_event("UNIT_START_RELOCATED", {
			"unit": unit.name,
			"position": unit.global_position,
		})

	log_event("UNIT_START_VALIDATION", {
		"checked_units": checked_units,
		"relocated_units": relocated_units,
	})

func _should_validate_start_position(unit: Unit) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if unit.is_dead():
		return false
	if unit.is_player_controlled:
		return true
	return unit.role == Unit.UnitRole.RULER or unit.role == Unit.UnitRole.ROYAL_GUARD

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
	var spawn_point := _resolve_valid_spawn_point(spawn_anchor + jitter)
	if spawn_point == Vector2.INF:
		spawn_point = spawn_anchor

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
		_try_register_spawn_point(source_point, "configured")

	for fallback_anchor in _get_default_periodic_spawn_anchors():
		_try_register_spawn_point(fallback_anchor, "arena_anchor")
		if _validated_periodic_free_knight_spawn_points.size() >= _SPAWN_POINT_MIN_POOL_SIZE:
			break

	if _validated_periodic_free_knight_spawn_points.size() < _SPAWN_POINT_MIN_POOL_SIZE:
		log_event("FREE_KNIGHT_SPAWN_POOL_DEGENERATE", {
			"validated_points": _validated_periodic_free_knight_spawn_points.size(),
		})
	else:
		log_event("FREE_KNIGHT_SPAWN_POOL_READY", {
			"validated_points": _validated_periodic_free_knight_spawn_points.size(),
		})

func _try_register_spawn_point(source_point: Vector2, source_kind: String) -> void:
	var validated_spawn_point := _resolve_valid_spawn_point(source_point)
	if validated_spawn_point == Vector2.INF:
		log_event("FREE_KNIGHT_SPAWN_POINT_INVALID", {
			"reason": "invalid_spawn_point",
			"source_kind": source_kind,
			"source_point": source_point,
		})
		return
	if _is_spawn_point_near_duplicate(_validated_periodic_free_knight_spawn_points, validated_spawn_point):
		return
	if _is_spawn_point_too_close(_validated_periodic_free_knight_spawn_points, validated_spawn_point):
		return
	_validated_periodic_free_knight_spawn_points.append(validated_spawn_point)

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
	if _arena_walkable_cells.is_empty():
		return Vector2.INF
	if not ruler_search_bounds.has_point(raw_spawn_point):
		raw_spawn_point = _clamp_to_ruler_search_bounds(raw_spawn_point)
	if _is_walkable_world_point(raw_spawn_point):
		return raw_spawn_point
	return _find_nearest_walkable_world_point(raw_spawn_point, 18)

func _transfer_ruler_identity(dead_ruler: Unit, successor: Unit) -> void:
	if not _is_valid_live_unit(dead_ruler):
		return
	if not _is_valid_live_unit(successor):
		return
	successor.absorb_ruler_identity_from(dead_ruler)
