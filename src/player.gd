extends CharacterBody3D

const SPEED = 5.0
const MOUSE_SENSITIVITY = 0.3
const ANIMATION_SMOOTHING = 10.0
const CAMERA_FOLLOW_SPEED = 50.0 

# Fiksna dužina
const FIKSNA_DUZINA_STAPA = 1.0 

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var anim_blend_position = Vector2.ZERO

# SADA KREĆEMO OD NULE!
# 0 = Ravno
# -80 = Gore
# 80 = Dolje
var x_rotacija = 0.0

@onready var spring_arm = $SpringArm3D 
@onready var anim_tree = $AnimationTree
@onready var skeleton = $vojnik/GeneralSkeleton
@onready var kamera_target = $vojnik/GeneralSkeleton/Neck/KameraTarget
@onready var ruku_pivot = $vojnik/GeneralSkeleton/Leda/RukePivot

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	anim_tree.active = true
	
	spring_arm.add_excluded_object(self.get_rid())
	spring_arm.collision_mask = 0 
	spring_arm.spring_length = FIKSNA_DUZINA_STAPA
	
	# Inicijalizacija na nulu
	spring_arm.rotation = Vector3.ZERO
	x_rotacija = 0.0
	
	sakrij_originalne_ruke()

func _input(event):
	if event is InputEventMouseMotion:
		# 1. Rotacija lika (Lijevo/Desno)
		rotate_y(deg_to_rad(-event.relative.x * MOUSE_SENSITIVITY))
		
		# 2. Rotacija Kamere (Gore/Dolje)
		x_rotacija += -event.relative.y * MOUSE_SENSITIVITY
		
		# CLAMP SADA RADI OKO NULE (Sigurna zona)
		# Ovo sprječava da ikad dođeš do +/- 180 gdje se događa greška
		x_rotacija = clamp(x_rotacija, -85.0, 85.0)
		
		# Primjenjujemo na SpringArm
		spring_arm.rotation_degrees.x = x_rotacija

func _physics_process(delta):
	# Ispis bi sada trebao biti logičan (npr. Var: -10, SpringArm: -10)
	print("Var: ", snapped(x_rotacija, 0.1), " | SpringArm: ", snapped(spring_arm.rotation_degrees.x, 0.1))

	# 1. GRAVITACIJA
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. KRETANJE
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	
	# 3. ANIMACIJA
	var target_blend = Vector2(input_dir.x, -input_dir.y)
	anim_blend_position = anim_blend_position.lerp(target_blend, delta * ANIMATION_SMOOTHING)
	anim_tree.set("parameters/DonjiDio/Kretanje/blend_position", anim_blend_position)
	
	# 4. KAMERA PRATI VRAT
	if kamera_target:
		spring_arm.global_position = kamera_target.global_position

	# 5. RUKE PRATE POGLED
	if ruku_pivot:
		# Pazi: Ovdje možda trebaš dodati onih -90 ili +90 ovisno kako su ti ruke modelirane
		# Probaj: -x_rotacija - 90
		ruku_pivot.rotation_degrees.x = -x_rotacija - 90.0

	move_and_slide()

func sakrij_originalne_ruke():
	if not skeleton: return
	var kosti = ["RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand", "Head"]
	for k in kosti:
		var idx = skeleton.find_bone(k)
		if idx != -1:
			skeleton.set_bone_global_pose_override(idx, Transform3D().scaled(Vector3(0.001, 0.001, 0.001)), 1.0, true)
