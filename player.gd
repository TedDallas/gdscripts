extends CharacterBody3D

@export var speed = 5.0
@export var deadzone = 0.2  # Adjust deadzone threshold as needed

func _physics_process(delta):
    var input_vector = Vector2.ZERO
    
    # Get raw stick input
    input_vector.x = Input.get_axis("left_stick_left", "left_stick_right")
    input_vector.y = Input.get_axis("left_stick_up", "left_stick_down")
    
    # Apply deadzone
    if input_vector.length() < deadzone:
        input_vector = Vector2.ZERO
    
    input_vector = input_vector.normalized()
    
    var direction = Vector3.ZERO
    direction.x = input_vector.x
    direction.z = input_vector.y
    
    # Apply movement with smooth acceleration/deceleration
    if direction != Vector3.ZERO:
        velocity = velocity.lerp(direction * speed, 0.15)
    else:
        velocity = velocity.lerp(Vector3.ZERO, 0.15)
    
    move_and_slide()
