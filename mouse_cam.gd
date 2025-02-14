extends Camera3D

@export var mouse_sensitivity : float = 0.2
@export var move_speed : float = 3.0
@export var speed_multiplier : float = 4.0
var camera_rotation = Vector2()

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	rotate(Vector3(0.0,0.0,0.0),0.0)

func _process(delta: float) -> void:
	var direction = Vector3()
	
	# Get the camera's forward, right, and up vectors
	var forward = -global_transform.basis.z
	var right = global_transform.basis.x
	var up = global_transform.basis.y
	
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
		direction += up
	if Input.is_key_pressed(KEY_CTRL):
		direction -= up
	
	var tmp_speed : float = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		tmp_speed = move_speed * speed_multiplier
	
	# move camera
	if direction.length() > 0:
		direction = direction.normalized()
		position += direction * tmp_speed * delta

func _input(event):
	if event is InputEventKey:
		if event.keycode == KEY_ESCAPE:  
			get_tree().quit() # press escape to end program

	if event is InputEventMouseMotion:
		camera_rotation.x += deg_to_rad(-event.relative.x * mouse_sensitivity)
		camera_rotation.y += deg_to_rad(-event.relative.y * mouse_sensitivity)
		camera_rotation.y = clamp(camera_rotation.y, deg_to_rad(-89.0), deg_to_rad(89.0))

		var rotation_dir = Vector3(
			cos(camera_rotation.y) * sin(camera_rotation.x),
			sin(camera_rotation.y),
			cos(camera_rotation.y) * cos(camera_rotation.x)
		)

		look_at(global_transform.origin + rotation_dir, Vector3.UP)
