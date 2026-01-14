extends CharacterBody3D

# --- KONFIGURACIJA KRETANJA ---
const SPEED = 5.0
const MOUSE_SENSITIVITY = 0.3
const ANIMATION_SMOOTHING = 10.0

# --- KONFIGURACIJA ZVUKA KORAKA ---
const STEP_INTERVAL = 0.5 
var step_timer = 0.0
@export var footstep_sounds: Array[AudioStream] 

# --- KONFIGURACIJA KAMERE & CILJANJA ---
const NORMAL_FOV = 75.0
const AIM_FOV = 50.0 
const ZOOM_SPEED = 15.0 
const ADS_LERP_SPEED = 15.0 

const FIKSNA_DUZINA_STAPA = 0.1
const ADS_DUZINA_STAPA = 0.0 

# --- VARIJABLE STANJA ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var anim_blend_position = Vector2.ZERO
var x_rotacija = 0.0

# --- LOGIKA ORUŽJA ---
var is_reloading = false
var is_weapon_empty = false 

# --- KONFIGURACIJA PROJEKTILA (RAKETE) ---
@export var projectile_scene: PackedScene 
@export var visual_rocket_mesh: Node3D

# --- KAMERA PRATI RAKETU ---
var aktivna_raketa: Node3D = null
var missile_cam_aktivna = false

# --- REFERENCE ---
@onready var camera_pivot_node = $vojnik/Rotation
@onready var spring_arm = $vojnik/Rotation/SpringArm3D
@onready var camera = $vojnik/Rotation/SpringArm3D/Camera3D
@onready var anim_tree = $AnimationTree 
@onready var skeleton = $vojnik/GeneralSkeleton
@onready var ruku_pivot = $vojnik/GeneralSkeleton/Leda/RukePivot

# --- TOČKA STVARANJA RAKETE ---
@onready var spawn_point = $vojnik/GeneralSkeleton/Leda/RukePivot/Ruke/MuzzlePoint 

# --- AUDIO REFERENCE ---
@onready var audio_shoot = $ZvukPucanja
@onready var audio_reload = $ZvukReload
@onready var audio_walk = $ZvukKoraci

# --- VIZUALNI EFEKTI ---
@export var muzzle_light: OmniLight3D

# --- ANIMACIJE ---
@export var rpg_animation_player: AnimationPlayer 

# IMENA ANIMACIJA
@export var anim_name_idle: String = "MC_RPG7_idle"        
@export var anim_name_shoot: String = "MC_RPG7_shoot"      
@export var anim_name_after_shoot: String = "MC_RPG7_static_pose_empty" 
@export var anim_name_reload: String = "MC_RPG7_reload"    

# --- METE ZA KAMERU ---
@onready var kamera_target_vrat = $vojnik/GeneralSkeleton/Neck/KameraTarget
@onready var nisan_target = $vojnik/GeneralSkeleton/Leda/RukePivot/Ruke/NisanTarget 

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	anim_tree.active = true
	
	spring_arm.add_excluded_object(self.get_rid())
	spring_arm.collision_mask = 0 
	spring_arm.rotation = Vector3.ZERO
	x_rotacija = 0.0
	
	if muzzle_light:
		muzzle_light.visible = false
	
	sakrij_originalne_ruke()
	
	if visual_rocket_mesh:
		visual_rocket_mesh.visible = true
	
	if rpg_animation_player:
		rpg_animation_player.play(anim_name_idle)
		is_weapon_empty = false

func _input(event):
	# === PREBACIVANJE NA MISSILE CAM (TIPKA G) ===
	if event.is_action_pressed("toggle_missile_cam"):
		toggle_missile_camera()
	
	# Samo primaj miš input ako NIJE aktivna missile cam
	if not missile_cam_aktivna and event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * MOUSE_SENSITIVITY))
		x_rotacija += -event.relative.y * MOUSE_SENSITIVITY
		x_rotacija = clamp(x_rotacija, -80.0, 80.0)
		spring_arm.rotation_degrees.x = x_rotacija

func _physics_process(delta):
	# === AKO JE AKTIVNA MISSILE CAM, BLOKIRAJ KRETANJE ===
	if missile_cam_aktivna:
		return
	
	# 1. GRAVITACIJA
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. KRETANJE
	var input_dir = -Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		
		if is_on_floor():
			step_timer += delta
			if step_timer > STEP_INTERVAL:
				play_footstep()
				step_timer = 0.0 
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		step_timer = STEP_INTERVAL 
	
	# 3. ANIMACIJA TIJELA
	var target_blend = Vector2(input_dir.x, -input_dir.y)
	anim_blend_position = anim_blend_position.lerp(target_blend, delta * ANIMATION_SMOOTHING)
	anim_tree.set("parameters/DonjiDio/Kretanje/blend_position", anim_blend_position)
	
	# 4. ORUŽJE
	handle_weapon_input()
	
	# 5. RUKE PRATE POGLED
	if ruku_pivot:
		var target_arm_rot = -x_rotacija
		ruku_pivot.rotation_degrees.x = lerp(ruku_pivot.rotation_degrees.x, target_arm_rot, delta * 15.0)
		ruku_pivot.rotation_degrees.z = 0 

	# 6. ADS LOGIKA
	aim_logic(delta)

	move_and_slide()

# --- FUNKCIJA ZA KORAKE ---
func play_footstep():
	if footstep_sounds.is_empty(): return
	var random_sound = footstep_sounds.pick_random()
	audio_walk.stream = random_sound
	audio_walk.pitch_scale = randf_range(0.9, 1.1)
	audio_walk.volume_db = randf_range(-2.0, 2.0)
	audio_walk.play()

func aim_logic(delta):
	var trenutna_meta_pozicija: Vector3
	var ciljana_duzina_stapa: float
	var ciljani_fov: float
	
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		ciljani_fov = AIM_FOV
		ciljana_duzina_stapa = ADS_DUZINA_STAPA 
		if nisan_target: 
			trenutna_meta_pozicija = nisan_target.global_position
		elif kamera_target_vrat:
			trenutna_meta_pozicija = kamera_target_vrat.global_position
	else:
		ciljani_fov = NORMAL_FOV
		ciljana_duzina_stapa = FIKSNA_DUZINA_STAPA
		if kamera_target_vrat:
			trenutna_meta_pozicija = kamera_target_vrat.global_position
	
	if camera_pivot_node:
		camera_pivot_node.global_position = camera_pivot_node.global_position.lerp(trenutna_meta_pozicija, delta * ADS_LERP_SPEED)
	
	camera.fov = lerp(camera.fov, ciljani_fov, delta * ZOOM_SPEED)
	spring_arm.spring_length = lerp(spring_arm.spring_length, ciljana_duzina_stapa, delta * ZOOM_SPEED)

func sakrij_originalne_ruke():
	if not skeleton: return
	var kosti = ["RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand", "Head"]
	for k in kosti:
		var idx = skeleton.find_bone(k)
		if idx != -1:
			skeleton.set_bone_global_pose_override(idx, Transform3D().scaled(Vector3(0.001, 0.001, 0.001)), 1.0, true)

# --- LOGIKA ORUŽJA ---

func handle_weapon_input():
	if is_reloading:
		return

	if Input.is_action_just_pressed("reload"):
		start_reload()

	if Input.is_action_pressed("shoot"):
		if not is_weapon_empty:
			perform_shoot()

func start_reload():
	if not rpg_animation_player: return
	if not is_weapon_empty: return 

	is_reloading = true
	if visual_rocket_mesh:
		visual_rocket_mesh.visible = true
	audio_reload.play()
	rpg_animation_player.play(anim_name_reload)
	
	var anim_length = rpg_animation_player.get_animation(anim_name_reload).length
	
	await get_tree().create_timer(anim_length).timeout
	
	is_reloading = false
	is_weapon_empty = false 
	
	rpg_animation_player.play(anim_name_idle)

func perform_shoot():
	if not rpg_animation_player: return
	
	if rpg_animation_player.current_animation == anim_name_shoot:
		return 

	is_weapon_empty = true 
	
	if visual_rocket_mesh:
		visual_rocket_mesh.visible = false
	
	audio_shoot.pitch_scale = randf_range(0.95, 1.05)
	audio_shoot.play()
	
	trigger_muzzle_flash()
	
	if projectile_scene and spawn_point:
		var rocket = projectile_scene.instantiate()
		
		get_tree().root.add_child(rocket)
		
		if rocket.is_class("Node3D"):
			rocket.set_as_top_level(true)
		
		var muzzle_forward = -spawn_point.global_transform.basis.z
		rocket.global_position = spawn_point.global_position + (muzzle_forward * 0.5)
		
		rocket.global_transform.basis = spawn_point.global_transform.basis
		rocket.rotate_object_local(Vector3.UP, PI)
		
		# === SPREMI REFERENCU NA RAKETU ===
		aktivna_raketa = rocket
		
		# Poveži signal za cleanup
		if rocket.has_signal("raketa_unistena"):
			rocket.raketa_unistena.connect(_on_rocket_destroyed)
		
	rpg_animation_player.play(anim_name_shoot)
	rpg_animation_player.queue(anim_name_after_shoot)

func trigger_muzzle_flash():
	if muzzle_light:
		muzzle_light.visible = true
		await get_tree().create_timer(0.08).timeout 
		muzzle_light.visible = false

# ========================================
# === MISSILE CAMERA FUNKCIJE ===
# ========================================

func toggle_missile_camera():
	"""Prebacuje između FPS kamere i kamere na raketi"""
	
	if not aktivna_raketa or not is_instance_valid(aktivna_raketa):
		print("⚠️ Nema aktivne rakete!")
		return
	
	missile_cam_aktivna = not missile_cam_aktivna
	
	# Pronađi kameru na raketi (pretpostavljam da se zove "Camera3D")
	var rocket_camera = aktivna_raketa.find_child("Camera3D", true, false)
	
	if not rocket_camera:
		print("❌ Raketa nema kameru!")
		missile_cam_aktivna = false
		return
	
	if missile_cam_aktivna:
		print("📹 MISSILE CAM - Pritisnite G za povratak")
		camera.current = false
		rocket_camera.current = true
	else:
		print("👤 FPS CAM - Povratak na igrača")
		rocket_camera.current = false
		camera.current = true

func _on_rocket_destroyed():
	"""Callback kad raketa eksplodira"""
	print("💥 Raketa eksplodirala!")
	
	# Vrati kameru na igrača
	if missile_cam_aktivna:
		missile_cam_aktivna = false
		camera.current = true
		
	aktivna_raketa = null
