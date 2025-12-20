extends CharacterBody3D

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const MOUSE_SENSITIVITY = 0.003

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Provjerite jesu li ove putanje točne u vašoj sceni!
@onready var spring_arm = $vojnik/SpringArm3D
@onready var visuals = $vojnik

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion:
		# Rotacija lika lijevo/desno (Ostavili smo minus, to je radilo dobro)
		self.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		
		# POPRAVAK 1: Maknuli smo minus!
		# Sada: Miš dolje (+) = Gledaj dolje (+). Miš gore (-) = Gledaj gore (-).
		spring_arm.rotate_x(event.relative.y * MOUSE_SENSITIVITY)
		
		# POPRAVAK 2: Povećali smo granice (Clamp)
		# -90 stupnjeva = gledanje ravno u nebo (iznad glave)
		# 75 stupnjeva = gledanje u pod (ne 90 da kamera ne prođe kroz pod)
		spring_arm.rotation.x = clamp(spring_arm.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _physics_process(delta):
	# Gravitacija
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Skok
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Kretanje
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	# Ovdje su minusi da poprave obrnuti smjer
	var direction = (transform.basis * Vector3(-input_dir.x, 0, -input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
