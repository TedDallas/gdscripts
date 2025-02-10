extends Node3D

@export var x_tiles : int = 3
@export var y_tiles : int = 3
@export var collision_radius : float = 64.0 
@export var x_size : float = 64
@export var z_size : float = 64
@export var terrain_scale : float = 100
@export var height_mean : float = 1.0
@export var height_std_dev : float = 1.5
@export var hill_frequency : float = 0.1
@export var valley_threshold : float = 0.3
@export var octaves : int = 4
@export var lacunarity : float = 2.0
@export var gain : float = 0.5
@export var terain_color : Color;

class TerrainTask:
	var tile_coords: Vector2
	var terrain_scale: float
	var x_size: float
	var z_size: float
	var material: Material

	func _init(coords: Vector2, t_scale: float, x_s: float, z_s: float, mat: Material):
		tile_coords = coords
		terrain_scale = t_scale
		x_size = x_s
		z_size = z_s
		material = mat

var xr_interface : XRInterface
var noise = FastNoiseLite.new()
var terrain_tiles = {}  # Dictionary to store terrain tiles
var current_center_tile = Vector2.ZERO
var xr_origin : XROrigin3D
var terrain_material : StandardMaterial3D 

const MAX_QUEUE_SIZE = 32

var thread_queue := []
var active_threads := []
const MAX_THREADS := 4
var pending_tiles := {}
var mutex: Mutex

# buffer zone to prevent reaching tile edges
const TILE_BUFFER : float = 0.2  # 20% buffer from edges

func gaussian_random() -> float:
	var u1 = randf()
	var u2 = randf()
	var z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2)
	return z0

func terain_height(x: float, z: float) -> float:
	# Remove any tile-specific modifications to coordinates
	var world_x = x
	var world_z = z
	
	var noise_value = noise.get_noise_2d(world_x, world_z)
	noise_value = (noise_value + 1.0) * 0.5
	
	var detail_noise = noise.get_noise_2d(world_x * 10.0, world_z * 10.0) * 0.1
	noise_value += detail_noise
	
	if noise_value < valley_threshold:
		noise_value = 0.0
	else:
		noise_value = pow((noise_value - valley_threshold) / (1.0 - valley_threshold), 2.0)

	return noise_value * height_mean

func update_collision_states(player_position: Vector3) -> void:
	var player_tile = get_tile_coords(player_position)
	
	for tile_coords in terrain_tiles.keys():
		# Quick check if tile is definitely outside radius
		if (abs(tile_coords.x - player_tile.x) > collision_radius / (x_size * terrain_scale) or 
			abs(tile_coords.y - player_tile.y) > collision_radius / (z_size * terrain_scale)):
			# Disable collision without precise distance check
			for child in terrain_tiles[tile_coords].get_children():
				if child is CollisionShape3D:
					child.disabled = true
			continue
		
		# Precise distance check for tiles that might be in range
		var tile = terrain_tiles[tile_coords]
		var tile_center = Vector3(
			tile_coords.x * x_size * terrain_scale,
			0,
			tile_coords.y * z_size * terrain_scale
		)
		
		var distance = player_position.distance_to(tile_center)
		
		for child in tile.get_children():
			if child is CollisionShape3D:
				child.disabled = distance > collision_radius

func create_noise_texture() -> NoiseTexture2D:
	var noise_texture = NoiseTexture2D.new()
	
	var nz = FastNoiseLite.new()
	nz.seed = randi()
	nz.noise_type = FastNoiseLite.TYPE_PERLIN
	nz.frequency = 0.05
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 4
	nz.fractal_lacunarity = 2.0
	nz.fractal_gain = 0.5
	
	noise_texture.width = 1024  # Increased resolution
	noise_texture.height = 1024
	noise_texture.noise = nz
	noise_texture.seamless = true
	noise_texture.seamless_blend_skirt = 0.25  # Increased blend skirt
	noise_texture.as_normal_map = true  # Enable normal mapping

	return noise_texture

func create_terrain_material() -> StandardMaterial3D:
	var material = StandardMaterial3D.new()

	# Updated material settings
	material.vertex_color_use_as_albedo = true
	material.albedo_color = terain_color #Color(randf(), randf(), randf(), 1.0)
	material.roughness = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.metallic_specular = 0.1
	
	# Improved texture settings
	var noise_texture = create_noise_texture()
	material.albedo_texture = noise_texture
	material.normal_enabled = true
	material.normal_scale = 1.0
	material.roughness_texture = noise_texture
	
	# Enhanced triplanar mapping settings
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE
	
	# Add texture repeat
	material.uv1_scale = Vector3(0.01, 0.01, 0.01)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.texture_repeat = true
	
	return material

func build_terrain_tile_threaded(task: TerrainTask) -> Dictionary:
	var st = SurfaceTool.new()
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var x_origin = task.tile_coords.x * x_size * terrain_scale
	var z_origin = task.tile_coords.y * z_size * terrain_scale
	const OVERLAP = 1
	
	var vertices_x = int(x_size) + 1 + (2 * OVERLAP)
	var vertices_z = int(z_size) + 1 + (2 * OVERLAP)
	
	# Generate vertices
	for x in range(vertices_x):
		for z in range(vertices_z):
			var world_x = x_origin + ((x - OVERLAP - x_size/2) * terrain_scale)
			var world_z = z_origin + ((z - OVERLAP - z_size/2) * terrain_scale)
			var height = terain_height(world_x / terrain_scale, world_z / terrain_scale)
			var vertex = Vector3(world_x, height * terrain_scale, world_z)

			var u = (float(x) / (vertices_x - 1))
			var v = (float(z) / (vertices_z - 1))
			st.set_uv(Vector2(u, v))
			
			st.set_color(Color(1.0, 1.0, 1.0))
			st.add_vertex(vertex)

	# Generate triangles
	for x in range(vertices_x - 1):
		for z in range(vertices_z - 1):
			var i = z + x * vertices_z
			
			st.add_index(i)
			st.add_index(i + vertices_z)
			st.add_index(i + 1)
			
			st.add_index(i + 1)
			st.add_index(i + vertices_z)
			st.add_index(i + vertices_z + 1)

	st.generate_normals()
	st.generate_tangents()

	var static_body = StaticBody3D.new()
	var mesh_instance = MeshInstance3D.new()
	
	return {
		"mesh": st.commit(),
		"coords": task.tile_coords
	}

func _create_terrain_node(result: Dictionary) -> void:
	var static_body = StaticBody3D.new()
	var mesh_instance = MeshInstance3D.new()
	
	mesh_instance.mesh = result["mesh"]
	mesh_instance.material_override = terrain_material
	
	var collision_shape = CollisionShape3D.new()
	var shape = ConcavePolygonShape3D.new()
	shape.set_faces(mesh_instance.mesh.get_faces())
	collision_shape.shape = shape

	static_body.add_child(mesh_instance)
	static_body.add_child(collision_shape)
	add_child(static_body)
	
	mutex.lock()
	terrain_tiles[result["coords"]] = static_body
	mutex.unlock()

func _thread_completed(result: Dictionary) -> void:
	call_deferred("_create_terrain_node", result)

func get_tile_priority(tile_coords: Vector2) -> float:
	var distance = tile_coords.distance_to(current_center_tile)
	return -distance  # Higher priority for closer tiles

func _process_thread_queue() -> void:
	mutex.lock()
	var current_thread_count = active_threads.size()
	if current_thread_count >= MAX_THREADS or thread_queue.is_empty():
		mutex.unlock()
		return
		
	# Sort thread queue by priority
	thread_queue.sort_custom(func(a, b): return get_tile_priority(a.tile_coords) > get_tile_priority(b.tile_coords))
	
	var task = thread_queue.pop_front()
	var thread = Thread.new()
	thread.start(build_terrain_tile_threaded.bind(task))
	active_threads.append(thread)
	mutex.unlock()
	
func _cleanup_completed_threads() -> void:
	mutex.lock()
	var i = active_threads.size() - 1
	while i >= 0:
		var thread = active_threads[i]
		if not thread.is_alive():
			var result = thread.wait_to_finish()
			_thread_completed(result)
			active_threads.remove_at(i)
		i -= 1
	mutex.unlock()

func get_tile_coords(position: Vector3) -> Vector2:
	var tile_size = Vector2(x_size * terrain_scale, z_size * terrain_scale)
	return Vector2(
		floor(position.x / tile_size.x + 0.5),
		floor(position.z / tile_size.y + 0.5)
	)

func get_position_in_tile(position: Vector3) -> Vector2:
	var tile_size = Vector2(x_size * terrain_scale, z_size * terrain_scale)
	var tile_coords = get_tile_coords(position)
	var tile_origin = Vector2(
		(tile_coords.x - 0.5) * tile_size.x,
		(tile_coords.y - 0.5) * tile_size.y
	)
	return Vector2(
		(position.x - tile_origin.x) / tile_size.x,
		(position.z - tile_origin.y) / tile_size.y
	)

func update_terrain_tiles() -> void:
	var xr_position = xr_origin.global_position
	var new_center_tile = get_tile_coords(xr_position)
	var pos_in_tile = get_position_in_tile(xr_position)

	var near_edge = (
		abs(pos_in_tile.x - 0.5) > (0.5 - TILE_BUFFER) or 
		abs(pos_in_tile.y - 0.5) > (0.5 - TILE_BUFFER)
	)
	
	if new_center_tile != current_center_tile or near_edge:
		# Calculate the range of tiles that should exist
		var required_tiles = {}
		for x in range(new_center_tile.x - x_tiles/2, new_center_tile.x + x_tiles/2 + 1):
			for y in range(new_center_tile.y - y_tiles/2, new_center_tile.y + y_tiles/2 + 1):
				required_tiles[Vector2(x, y)] = true

		mutex.lock()
		# Remove tiles that are too far away
		var tiles_to_remove = []
		for tile_coords in terrain_tiles.keys():
			if not required_tiles.has(tile_coords):
				tiles_to_remove.append(tile_coords)
		
		for tile_coords in tiles_to_remove:
			if terrain_tiles.has(tile_coords):
				terrain_tiles[tile_coords].queue_free()
				terrain_tiles.erase(tile_coords)
				
		# Queue new required tiles
		if thread_queue.size() < MAX_QUEUE_SIZE:
			for tile_coords in required_tiles:
				if not terrain_tiles.has(tile_coords) and not pending_tiles.has(tile_coords):
					pending_tiles[tile_coords] = true
					var task = TerrainTask.new(tile_coords, terrain_scale, x_size, z_size, terrain_material)
					thread_queue.append(task)
		mutex.unlock()

	current_center_tile = new_center_tile
		
func setup_sky():
	var environment = Environment.new()
	environment.fog_enabled = true
	environment.fog_density = 0.0075  
	environment.fog_light_color = terain_color 
	environment.fog_light_energy = 0.1
	environment.fog_sun_scatter = 0.0  # Light scattering amount	
	
	var sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()
	
	sky_material.sky_top_color = Color.BLACK
	sky_material.sky_horizon_color = terain_color
	
	sky.sky_material = sky_material
	
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	
	get_viewport().world_3d.environment = environment

func _ready() -> void:
	mutex = Mutex.new()
	
	noise.seed = 12345
	noise.frequency = hill_frequency
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = lacunarity
	noise.fractal_gain = gain
	
	terrain_material = create_terrain_material()
	
	xr_origin = get_node("./player/XROrigin3D")
	
	setup_sky()
	
	# Generate initial terrain tiles
	var half_x = x_tiles / 2
	var half_y = y_tiles / 2
	
	# Queue initial terrain tiles for generation
	for x in range(-half_x, half_x + 1):
		for y in range(-half_y, half_y + 1):
			var tile_coords = Vector2(x, y)
			mutex.lock()
			if not terrain_tiles.has(tile_coords) and not pending_tiles.has(tile_coords):
				pending_tiles[tile_coords] = true
				var task = TerrainTask.new(tile_coords, terrain_scale, x_size, z_size, terrain_material)
				thread_queue.append(task)
			mutex.unlock()
	
	# Process initial terrain generation
	while not thread_queue.is_empty() or not active_threads.is_empty():
		_process_thread_queue()
		_cleanup_completed_threads()
		# Add a small delay to prevent blocking
		await get_tree().create_timer(0.01).timeout
	
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

func cleanup_pending_tiles() -> void:
	mutex.lock()
	var tiles_to_remove = []
	for tile_coords in pending_tiles.keys():
		if abs(tile_coords.x - current_center_tile.x) > x_tiles/2 or \
			abs(tile_coords.y - current_center_tile.y) > y_tiles/2:
			tiles_to_remove.append(tile_coords)
	
	for tile_coords in tiles_to_remove:
		pending_tiles.erase(tile_coords)
	mutex.unlock()

func _process(_delta: float) -> void:
	_process_thread_queue()
	_cleanup_completed_threads()
	cleanup_pending_tiles()
	update_terrain_tiles()
	update_collision_states(xr_origin.global_position)
