extends Node3D

@export var x_size : float = 64
@export var z_size : float = 64
@export var terrain_scale : float = 100
@export var height_mean : float = 1.0
@export var height_std_dev : float = 1.5
@export var hill_frequency : float = 0.1
@export var valley_threshold : float = 0.3
@export var max_height : float = 5.0

var noise = FastNoiseLite.new()
var mesh_instance : MeshInstance3D
var st = SurfaceTool.new()

func gaussian_random() -> float:
	var u1 = randf()
	var u2 = randf()
	var z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2)
	return z0

func terain_height(x: float, z: float) -> float:
	var noise_value = noise.get_noise_2d(x, z)
	noise_value = (noise_value + 1.0) * 0.5

	if noise_value < valley_threshold:
		noise_value = 0.0
	else:
		noise_value = pow((noise_value - valley_threshold) / (1.0 - valley_threshold), 2.0)

	var random_factor = gaussian_random() * height_std_dev * 0.2
	var height = (noise_value * max_height + random_factor) * height_mean
	return clamp(height, 0.0, max_height)

func build_terrain(x_origin: float, z_origin: float) -> void:
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var x_start : float = x_origin - x_size / 2
	var x_end : float = x_origin + x_size / 2
	var z_start : float = z_origin - z_size / 2
	var z_end : float = z_origin + z_size / 2

	# Create vertex array
	var vertices = []
	var indices = []
	
	# Generate vertices
	for x in range(x_start, x_end + 1):
		for z in range(z_start, z_end + 1):
			var vertex = Vector3(x, terain_height(x, z), z) * terrain_scale
			vertices.append(vertex)

	# Generate indices for triangles (top face)
	for x in range(x_end - x_start):
		for z in range(z_end - z_start):
			var vertex_index = z + x * (z_size + 1)
			
			# First triangle
			indices.append(vertex_index)
			indices.append(vertex_index + z_size + 1)
			indices.append(vertex_index + 1)
			
			# Second triangle
			indices.append(vertex_index + 1)
			indices.append(vertex_index + z_size + 1)
			indices.append(vertex_index + z_size + 2)

	# Add vertices and indices to SurfaceTool
	for vertex in vertices:
		st.add_vertex(vertex)

	# Add indices
	for i in range(0, indices.size(), 3):
		st.add_index(indices[i])
		st.add_index(indices[i + 1])
		st.add_index(indices[i + 2])

	# Create or update mesh instance
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		
		var material = StandardMaterial3D.new()
		material.cull_mode = BaseMaterial3D.CULL_BACK
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		material.roughness = 0.8  # Add some roughness
		material.metallic_specular = 0.1  # Reduce specular reflection
		material.albedo_color = Color(1.0, 0.6, 0.3, 1.0)
		mesh_instance.material_override = material
		add_child(mesh_instance)

	st.generate_normals()
	mesh_instance.mesh = st.commit()

func _ready() -> void:
	# Initialize noise
	noise.seed = randi()
	noise.frequency = hill_frequency
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	
	# Generate initial terrain    
	build_terrain(0, 0)

func _process(_delta: float) -> void:
	pass
