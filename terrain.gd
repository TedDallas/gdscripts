extends Node3D

@export var x_size : float = 64
@export var z_size : float = 64
@export var terrain_scale : float = 100
@export var height_mean : float = 1.0
@export var height_std_dev : float = 1.5
@export var hill_frequency : float = 0.1
@export var valley_threshold : float = 0.3
#@export var max_height : float = 5.0
@export var octaves : int = 4
@export var lacunarity : float = 2.0
@export var gain : float = 0.5

var xr_interface : XRInterface
var noise = FastNoiseLite.new()
var terrain_tiles = {}  # Dictionary to store terrain tiles
var current_center_tile = Vector2.ZERO
var xr_origin : XROrigin3D

# Add a buffer zone to prevent reaching tile edges
const TILE_BUFFER : float = 0.2  # 20% buffer from edges

func gaussian_random() -> float:
	var u1 = randf()
	var u2 = randf()
	var z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2)
	return z0

func terain_height(x: float, z: float) -> float:
	var world_x = x * terrain_scale
	var world_z = z * terrain_scale
	
	var noise_value = noise.get_noise_2d(world_x, world_z)
	noise_value = (noise_value + 1.0) * 0.5
	
	var detail_noise = noise.get_noise_2d(world_x * 10.0, world_z * 10.0) * 0.1
	noise_value += detail_noise
	
	if noise_value < valley_threshold:
		noise_value = 0.0
	else:
		noise_value = pow((noise_value - valley_threshold) / (1.0 - valley_threshold), 2.0)

	#var height = noise_value * max_height * height_mean
	var height = noise_value * height_mean
	#return clamp(height, 0.0, max_height)
	return height


func create_noise_texture() -> NoiseTexture2D:
	var noise_texture = NoiseTexture2D.new()
	
	# Create and configure noise
	var noise = FastNoiseLite.new()
	noise.seed = randi()  # Random seed, or use a specific number
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.05
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	
	# Configure the noise texture
	noise_texture.width = 512  # Texture resolution
	noise_texture.height = 512
	noise_texture.noise = noise
	noise_texture.seamless = true  # Important for tiling
	noise_texture.seamless_blend_skirt = 0.1

	return noise_texture

func build_terrain_tile(tile_coords: Vector2) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calculate tile position with proper centering
	var x_origin = tile_coords.x * x_size * terrain_scale
	var z_origin = tile_coords.y * z_size * terrain_scale
	var x_start : float = -x_size / 2
	var x_end : float = x_size / 2
	var z_start : float = -z_size / 2
	var z_end : float = z_size / 2

	# Generate vertices with proper positioning and UVs
	for x in range(x_start, x_end + 1):
		for z in range(z_start, z_end + 1):
			var world_x = x_origin + (x * terrain_scale)
			var world_z = z_origin + (z * terrain_scale)
			var height = terain_height(world_x / terrain_scale, world_z / terrain_scale)
			var vertex = Vector3(world_x, height * terrain_scale, world_z)
			
			# Calculate UV coordinates
			var u = (x - x_start) / float(x_end - x_start)
			var v = (z - z_start) / float(z_end - z_start)
			st.set_uv(Vector2(u, v))
			
			# Calculate vertex color based on height
			var color = Color(1.0, 1.0, 1.0)
			st.set_color(color)
			
			st.add_vertex(vertex)

	# Generate triangles
	for x in range(x_end - x_start):
		for z in range(z_end - z_start):
			var vertex_index = z + x * (z_size + 1)
			
			st.add_index(vertex_index)
			st.add_index(vertex_index + z_size + 1)
			st.add_index(vertex_index + 1)
			
			st.add_index(vertex_index + 1)
			st.add_index(vertex_index + z_size + 1)
			st.add_index(vertex_index + z_size + 2)

	st.generate_normals()
	st.generate_tangents()

	var mesh_instance = MeshInstance3D.new()
	var material = StandardMaterial3D.new()
	
	# Configure material properties
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.roughness = 0.8
	material.metallic_specular = 0.1
	material.albedo_color = Color(1.0, 0.6, 0.3, 1.0)
	
	# Add noise texture to the material
	var noise_texture = create_noise_texture()
	material.albedo_texture = noise_texture
	material.normal_enabled = true
	material.normal_scale = 1.0
	material.roughness_texture = noise_texture	
	
	# Enable triplanar mapping to help with seams
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(1.0 / terrain_scale, 1.0 / terrain_scale, 1.0 / terrain_scale)
	
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = material
	add_child(mesh_instance)
	return mesh_instance


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
	
	# Check if player is near the edge of current tile
	var near_edge = (
		abs(pos_in_tile.x - 0.5) > (0.5 - TILE_BUFFER) or 
		abs(pos_in_tile.y - 0.5) > (0.5 - TILE_BUFFER)
	)
	
	if new_center_tile != current_center_tile or near_edge:
		# Remove old tiles
		var tiles_to_remove = []
		for tile_coords in terrain_tiles.keys():
			if abs(tile_coords.x - new_center_tile.x) > 1 or abs(tile_coords.y - new_center_tile.y) > 1:
				tiles_to_remove.append(tile_coords)
		
		for tile_coords in tiles_to_remove:
			terrain_tiles[tile_coords].queue_free()
			terrain_tiles.erase(tile_coords)
		
		# Add new tiles
		for x in range(new_center_tile.x - 1, new_center_tile.x + 2):
			for y in range(new_center_tile.y - 1, new_center_tile.y + 2):
				var tile_coords = Vector2(x, y)
				if not terrain_tiles.has(tile_coords):
					terrain_tiles[tile_coords] = build_terrain_tile(tile_coords)
		
		current_center_tile = new_center_tile

func _ready() -> void:
	noise.seed = 12345
	noise.frequency = hill_frequency
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = lacunarity
	noise.fractal_gain = gain
	
	xr_origin = get_node("./player/XROrigin3D")
	
	# Generate initial terrain tiles
	for x in range(-1, 2):
		for y in range(-1, 2):
			var tile_coords = Vector2(x, y)
			terrain_tiles[tile_coords] = build_terrain_tile(tile_coords)
	
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = true

func _process(_delta: float) -> void:
	update_terrain_tiles()

