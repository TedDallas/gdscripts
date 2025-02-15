extends Camera3D

@export var mouse_sensitivity : float = 0.2
@export var move_speed : float = 3.0
@export var speed_multiplier : float = 4.0
var camera_rotation = Vector2()

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta: float) -> void:
	var direction = Vector3()
	
	# Get the camera's forward, right, and up vectors
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	
	# Remove any vertical component for forward/backward movement
	forward = forward.slide(Vector3.UP).normalized()
	right = right.normalized()
	
	# Apply vectors to direction
	if Input.is_key_pressed(KEY_W):
		direction += forward
	if Input.is_key_pressed(KEY_S):
		direction -= forward
	if Input.is_key_pressed(KEY_A):
		direction -= right
	if Input.is_key_pressed(KEY_D):
		direction += right
	if Input.is_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL):
		direction -= Vector3.UP
	
	var tmp_speed : float = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		tmp_speed = move_speed * speed_multiplier
	
	# move camera
	if direction.length() > 0:
		direction = direction.normalized()
		position += direction * tmp_speed * delta

func _input(event):
	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed:  
			get_tree().quit()

	if event is InputEventMouseMotion:
		# Update camera_rotation
		camera_rotation.x -= event.relative.x * mouse_sensitivity * 0.01
		camera_rotation.y -= event.relative.y * mouse_sensitivity * 0.01
		
		# Clamp the vertical rotation
		camera_rotation.y = clamp(camera_rotation.y, deg_to_rad(-89), deg_to_rad(89))
		
		# Apply rotations
		basis = Basis()  # Reset rotation
		rotate_object_local(Vector3.UP, camera_rotation.x)  # First rotate around Y
		rotate_object_local(Vector3.RIGHT, camera_rotation.y)  # Then rotate around X
