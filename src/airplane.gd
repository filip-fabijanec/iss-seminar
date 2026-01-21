extends RigidBody3D

@onready var stall_warning: AudioStreamPlayer3D = $StallWarning
@onready var engine_sound: AudioStreamPlayer3D = $EngineSound
@onready var gun_muzzle: Node3D = $Gun
@export var bullet_scene: PackedScene

var throttle := 0.8
const MASS := 1200.0
const MAX_THRUST := 50000.0
const THROTTLE_RATE := 0.6
const AIR_DENSITY := 1.225
const WING_AREA := 16.2
const CD := 0.03
const CL0 := 0.4
const CL_ALPHA := 5.5
const MAX_ALPHA := deg_to_rad(25)
const PITCH_RATE := 1.2
const ROLL_RATE := 1.5
const YAW_RATE := 0.8
const GRAVITY := Vector3(0, -9.81, 0)

func _ready():
	mass = MASS
	gravity_scale = 0.0
	global_position.y = 100.0
	global_position.x = 400
	global_position.z = 400

	var initial_speed := 200.0 / 3.6  
	var forward := -global_transform.basis.z
	linear_velocity = forward * initial_speed

func _get_ground_target() -> Vector3:
	var space := get_world_3d().direct_space_state
	var from := gun_muzzle.global_position
	var dir := -global_transform.basis.z
	var to := from + dir * 5000.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := space.intersect_ray(query)

	if result:
		return result.position
	else:
		return to

func _physics_process(delta):
	_read_input(delta)
	_apply_flight_forces()


func _read_input(delta):
	if Input.is_action_pressed("throttle_up"):
		throttle = clamp(throttle + THROTTLE_RATE * delta, 0.0, 1.0)
	if Input.is_action_pressed("throttle_down"):
		throttle = clamp(throttle - THROTTLE_RATE * delta, 0.0, 1.0)

	var pitch := 0.0
	var roll := 0.0
	var yaw := 0.0

	if Input.is_action_pressed("pitch_up"):
		pitch = 1.0
	if Input.is_action_pressed("pitch_down"):
		pitch = -1.0
	if Input.is_action_pressed("roll_left"):
		roll = 1.0
	if Input.is_action_pressed("roll_right"):
		roll = -1.0
	if Input.is_action_pressed("yaw_left"):
		yaw = 1.0
	if Input.is_action_pressed("yaw_right"):
		yaw = -1.0
	if Input.is_action_just_pressed("fire"):
		print("Input detected!")
		_fire_gun()

	var local_ang_vel := Vector3(
		pitch * PITCH_RATE,
		yaw * YAW_RATE,
		roll * ROLL_RATE
	)
	
	angular_velocity = global_transform.basis * local_ang_vel

func _fire_gun():
	print("Firing!")
	if bullet_scene == null:
		print("No bullet scene assigned!")
		return

	var bullet = bullet_scene.instantiate()
	bullet.owner = self
	get_tree().get_current_scene().add_child(bullet)

	var target := _get_ground_target()
	bullet.start(gun_muzzle.global_position, target)

func _apply_flight_forces():
	var velocity := linear_velocity
	var speed := velocity.length()

	var forward := -global_transform.basis.z
	var up := global_transform.basis.y

	var thrust_force := forward * throttle * MAX_THRUST
	apply_central_force(thrust_force)

	apply_central_force(MASS * GRAVITY)

	var v_body := global_transform.basis.inverse() * velocity

	var alpha := atan2(v_body.y, -v_body.z)
	alpha = clamp(alpha, -MAX_ALPHA, MAX_ALPHA)

	var CL := CL0 + CL_ALPHA * alpha
	var lift_mag := 0.5 * AIR_DENSITY * speed * speed * WING_AREA * CL

	lift_mag = clamp(lift_mag, 0.0, MASS * 9.81 * 1.3)

	apply_central_force(up * lift_mag)

	if speed > 0.1:
		var drag_force := -velocity.normalized() \
			* 0.5 * AIR_DENSITY * speed * speed * WING_AREA * CD
		apply_central_force(drag_force)
		
	var speed_kmh := speed * 3.6


	engine_sound.volume_db = lerp(-20.0, 0.0, throttle)
	engine_sound.pitch_scale = lerp(0.8, 1.3, throttle)
	if speed_kmh < 140.0:
		if not stall_warning.playing:
			stall_warning.play()
	else:
		if stall_warning.playing:
			stall_warning.stop()
