extends CharacterBody3D

# Parametri rakete
@export var rotation_quantum: float = 5.0  # Diskretni skok u stupnjevima
@export var base_speed: float = 50.0
@export var max_speed: float = 200.0
@export var min_speed: float = 10.0
@export var acceleration: float = 20.0
@export var explosion_scene: PackedScene

# Stanje rakete
var pitch: float = 0.0
var yaw: float = 0.0
var roll: float = 0.0
var current_speed: float = 50.0
var flight_time: float = 0.0
var total_distance: float = 0.0
var is_active: bool = true

@onready var ray = $RayCast3D

func _ready():
	current_speed = base_speed

func _physics_process(delta):
	if not is_active:
		return
	
	flight_time += delta
	handle_input()
	apply_rotation()
	
	# Kretanje naprijed
	var forward = -transform.basis.z
	velocity = forward * current_speed
	move_and_slide()
	
	total_distance += current_speed * delta
	
	# Detekcija sudara
	if ray.is_colliding():
		var hit = ray.get_collider()
		if not ("Player" in hit.name or "vojnik" in hit.name or hit.is_in_group("player")):
			detonate(ray.get_collision_point())

func handle_input():
	# Diskretno upravljanje - kvantni skokovi
	if Input.is_action_just_pressed("missile_pitch_up"):
		pitch -= rotation_quantum
	if Input.is_action_just_pressed("missile_pitch_down"):
		pitch += rotation_quantum
	if Input.is_action_just_pressed("missile_yaw_left"):
		yaw += rotation_quantum
	if Input.is_action_just_pressed("missile_yaw_right"):
		yaw -= rotation_quantum
	
	# Kontrola brzine
	if Input.is_action_pressed("missile_accelerate"):
		current_speed = min(current_speed + acceleration * get_physics_process_delta_time(), max_speed)
	if Input.is_action_pressed("missile_decelerate"):
		current_speed = max(current_speed - acceleration * get_physics_process_delta_time(), min_speed)
	
	pitch = clamp(pitch, -89.0, 89.0)

func apply_rotation():
	rotation_degrees = Vector3(pitch, yaw, roll)

func detonate(point: Vector3):
	is_active = false
	if explosion_scene:
		var expl = explosion_scene.instantiate()
		get_tree().root.add_child(expl)
		expl.global_position = point
	queue_free()

# Getter funkcije za UI
func get_altitude() -> float:
	return global_position.y

func get_speed() -> float:
	return current_speed

func get_flight_time() -> float:
	return flight_time

func get_distance() -> float:
	return total_distance

func get_orientation() -> Vector3:
	return Vector3(pitch, yaw, roll)
