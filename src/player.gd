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
var x_rotacija = 0.0  # Vertikalna rotacija (pitch)

# --- LOGIKA ORUŽJA ---
var is_reloading = false
var is_weapon_empty = false

# --- KONFIGURACIJA PROJEKTILA (RAKETE) ---
@export var projectile_scene: PackedScene 
@export var visual_rocket_mesh: Node3D

# --- KAMERA PRATI RAKETU ---
var aktivna_raketa: Node3D = null
var missile_cam_aktivna = false
var trenutni_tip_projektila: int = 0 # 0=Dumb, 1=Manual, 2=Homing
var zakljucana_meta: Node3D = null

var rocket_remote_transform: RemoteTransform3D = null
# Na vrhu player.gd zamijeni:
var original_viewport_camera_path: NodePath

# SA:
var viewport_camera: Camera3D = null

# --- REFERENCE ---
@onready var camera_pivot_node = $vojnik/Rotation
@onready var spring_arm = $vojnik/Rotation/SpringArm3D
@onready var camera = $vojnik/Rotation/SpringArm3D/Camera3D
@onready var anim_tree = $AnimationTree 
@onready var skeleton = $vojnik/GeneralSkeleton
@onready var ruku_pivot = $vojnik/GeneralSkeleton/Leda/RukePivot
@onready var remote_transform = $vojnik/Rotation/SpringArm3D/RemoteTransform3D

# --- HUD REFERENCE (Tražit ćemo ih u _ready) ---
var lbl_mode: Label = null
var lbl_lock: Label = null

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
	
	# === POSTAVKE ROTACIJE KAMERE ===
	x_rotacija = 0.0  
	spring_arm.rotation_degrees = Vector3(0.0, 180.0, 0.0) 
	
	# Postavljamo RemoteTransform (kako si tražio)
	var remote = $vojnik/Rotation/SpringArm3D/RemoteTransform3D
	if remote:
		remote.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	
	# === POVEZIVANJE HUD-A (SPLIT SCREEN FIX) ===
	# Tražimo labele u Glavnoj sceni koje imaju ove grupe
	lbl_mode = get_tree().get_first_node_in_group("hud_vojnik_mode")
	lbl_lock = get_tree().get_first_node_in_group("hud_vojnik_lock")
	
	if not lbl_mode: print("⚠️ UPOZORENJE: Nisam našao HUD labelu 'hud_vojnik_mode'!")
	if not lbl_lock: print("⚠️ UPOZORENJE: Nisam našao HUD labelu 'hud_vojnik_lock'!")
	
	if muzzle_light:
		muzzle_light.visible = false
	
	sakrij_originalne_ruke()
	
	if visual_rocket_mesh:
		visual_rocket_mesh.visible = true
	
	# === POKRENI S RAKETOM ===
	is_weapon_empty = false 
	is_reloading = false
	
	if rpg_animation_player:
		rpg_animation_player.play(anim_name_idle)
		
	viewport_camera = get_tree().get_first_node_in_group("vojnik_viewport_camera")
	
	if viewport_camera:
		print("✅ Viewport kamera pronađena: ", viewport_camera.name)
		print("   Pozicija: ", viewport_camera.global_position)
	else:
		print("❌ KRITIČNO: Viewport kamera nije pronađena!")
		print("   Provjeri je li kamera u grupi 'vojnik_viewport_camera'")
		

func _input(event):
	# Zarobi miš ako se klikne
	if event is InputEventMouseButton:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# === MIŠ ROTIRA IGRAČA I KAMERU ===
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Horizontalna rotacija
		rotate_y(deg_to_rad(-event.relative.x * MOUSE_SENSITIVITY))
		
		# Vertikalna rotacija
		x_rotacija -= event.relative.y * MOUSE_SENSITIVITY
		x_rotacija = clamp(x_rotacija, -89.0, 89.0)
		
		spring_arm.rotation_degrees.x = x_rotacija
	
	# ESC za pauzu
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# === NOVO: PROMJENA MODA JEDNOM TIPKOM (Ciklički) ===
	# Obavezno dodaj akciju "promijeni_mod" u Input Map (npr. slovo "B" ili "F")
	if event.is_action_pressed("promijeni_mod"):
		trenutni_tip_projektila += 1
		
		# Ako smo prešli zadnji mod (2), vrati na prvi (0)
		if trenutni_tip_projektila > 2:
			trenutni_tip_projektila = 0
			
		print("Ciklus Mod: ", trenutni_tip_projektila)
		update_hud() # Odmah ažuriraj tekst na ekranu

	# === STARO: DIREKTNO BIRANJE BROJEVIMA ===
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1: 
			trenutni_tip_projektila = 0
			print("Mod: Direct")
			update_hud()
			
		if event.keycode == KEY_2: 
			trenutni_tip_projektila = 1
			print("Mod: Manual")
			update_hud()
			
		if event.keycode == KEY_3: 
			trenutni_tip_projektila = 2
			print("Mod: Homing")
			update_hud()

	# Lock-on
	if event.is_action_pressed("lock_on"):
		pokusaj_lock_on()
		
	if event.is_action_pressed("toggle_missile_cam"):
		toggle_missile_camera()

func _physics_process(delta):
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and not missile_cam_aktivna:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
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
	
	# 5. RUKE PRATE CILJANJE
	if ruku_pivot:
		var target_arm_rot = -x_rotacija
		ruku_pivot.rotation_degrees.x = lerp(ruku_pivot.rotation_degrees.x, target_arm_rot, delta * 15.0)
		ruku_pivot.rotation_degrees.z = 0.0

	# 6. ADS LOGIKA
	aim_logic(delta)

	move_and_slide()
	
	# Ažuriraj HUD u svakom frameu
	update_hud()
	
func update_hud():
	# 1. Ispis Moda
	var tekst = ""
	match trenutni_tip_projektila:
		0: tekst = "RPG-7 (DIRECT)"
		1: tekst = "WIRE GUIDED"
		2: tekst = "AA HOMING"
	
	if lbl_mode: 
		lbl_mode.text = tekst
	
	# 2. Ispis Lock-a (Samo za AA mod)
	if lbl_lock:
		if trenutni_tip_projektila == 2:
			if zakljucana_meta and is_instance_valid(zakljucana_meta):
				lbl_lock.text = "
				[ LOCKED ]"
				lbl_lock.modulate = Color(1, 0, 0) # Crvena
			else:
				lbl_lock.text = "
				SEARCHING..."
				lbl_lock.modulate = Color(1, 1, 1, 0.5) # Prozirno bijela
		else:
			lbl_lock.text = "" # Prazno

func pokusaj_lock_on():
	if trenutni_tip_projektila != 2:
		print("⚠️ Lock-on dostupan samo u AA HOMING modu!")
		return
	
	# Nađi sve avione u sceni
	var svi_avioni = get_tree().get_nodes_in_group("airplane")
	
	if svi_avioni.is_empty():
		print("❌ Nema aviona u sceni!")
		return
	
	# Nađi najbližeg u vidnom polju
	var najblizi_avion: Node3D = null
	var najbliza_udaljenost = 99999.0
	var max_udaljenost = 2000.0  # Lock-on range
	
	for avion in svi_avioni:
		if not is_instance_valid(avion):
			continue
		
		var udaljenost = global_position.distance_to(avion.global_position)
		
		# Provjeri je li u rangu
		if udaljenost > max_udaljenost:
			continue
		
		# Provjeri je li u vidnom polju (koristimo viewport kameru)
		var smjer_do_aviona = (avion.global_position - viewport_camera.global_position).normalized()
		var forward = -viewport_camera.global_transform.basis.z
		var dot = smjer_do_aviona.dot(forward)
		
		# dot > 0.5 znači unutar ~60° konusa (lakše zaključavanje)
		if dot > 0.5 and udaljenost < najbliza_udaljenost:
			najbliza_udaljenost = udaljenost
			najblizi_avion = avion
	
	if najblizi_avion:
		zakljucana_meta = najblizi_avion
		print("🎯 META ZAKLJUČANA: ", najblizi_avion.name, " (%.0fm)" % najbliza_udaljenost)
	else:
		zakljucana_meta = null
		print("❌ Nema aviona u vidnom polju")

# Pomoćna funkcija za raycast
func raycast_at_point(screen_pos: Vector2, cam: Camera3D) -> Node3D:
	var from = cam.project_ray_origin(screen_pos)
	var to = from + cam.project_ray_normal(screen_pos) * 2000.0
	
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = get_world_3d().direct_space_state.intersect_ray(query)
	
	if result and result.collider.is_in_group("avion"):
		return result.collider
	
	return null

func play_footstep():
	if footstep_sounds.is_empty():
		print("⚠️ Nema zvukova koraka!")
		return
		
	var random_sound = footstep_sounds.pick_random()
	audio_walk.stream = random_sound
	audio_walk.pitch_scale = randf_range(0.9, 1.1)
	audio_walk.volume_db = randf_range(-2.0, 2.0)
	audio_walk.play()
	
	print("🔊 Puštam zvuk koraka: ", audio_walk.playing)

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
	
	# Može se reloadati samo ako je prazno
	if not is_weapon_empty:
		print("⚠️ RPG već ima raketu!")
		return
	
	if is_reloading:
		print("⚠️ Već reloadaš!")
		return

	is_reloading = true
	
	if visual_rocket_mesh:
		visual_rocket_mesh.visible = true
	
	audio_reload.play()
	rpg_animation_player.play(anim_name_reload)
	
	var anim_length = rpg_animation_player.get_animation(anim_name_reload).length
	
	await get_tree().create_timer(anim_length).timeout
	
	is_reloading = false
	is_weapon_empty = false  # Sada IMA raketu
	
	rpg_animation_player.play(anim_name_idle)
	print("✅ RPG natovareno!")

func perform_shoot():
	if is_weapon_empty or is_reloading: 
		print("⚠️ Nema rakete ili se reloada!")
		return
	
	is_weapon_empty = true
	if visual_rocket_mesh: 
		visual_rocket_mesh.visible = false
	
	var rocket = projectile_scene.instantiate()
	get_tree().root.add_child(rocket)
	rocket.global_transform = spawn_point.global_transform
	
	# ✅ ROTIRAJ RAKETU ZA 180° oko Y osi
	rocket.rotate_y(deg_to_rad(180))
	
	var smjer = spawn_point.global_transform.basis.z
	
	if rocket.has_method("postavi_pocetnu_brzinu"):
		rocket.postavi_pocetnu_brzinu(smjer)
	
	if rocket.has_method("ignoriraj_strijelca"):
		rocket.ignoriraj_strijelca(self)
	
	if rocket.has_method("postavi_raketu"):
		rocket.postavi_raketu(trenutni_tip_projektila, zakljucana_meta)
	
	aktivna_raketa = rocket
	rocket.raketa_unistena.connect(_on_rocket_destroyed)
	
	rpg_animation_player.play(anim_name_shoot)
	print("🚀 Raketa ispaljena!")

func trigger_muzzle_flash():
	if muzzle_light:
		muzzle_light.visible = true
		await get_tree().create_timer(0.08).timeout 
		muzzle_light.visible = false

func toggle_missile_camera():
	if not aktivna_raketa or not is_instance_valid(aktivna_raketa):
		print("⚠️ Nema aktivne rakete!")
		return
	
	var rocket_marker = aktivna_raketa.find_child("CameraMarker", true, false)
	
	if not rocket_marker:
		print("❌ Raketa nema CameraMarker!")
		return
	
	if not viewport_camera:
		print("❌ Viewport kamera nije pronađena u _ready()!")
		return
	
	if not remote_transform:
		print("❌ RemoteTransform nije pronađen!")
		return
	
	missile_cam_aktivna = not missile_cam_aktivna
	
	if missile_cam_aktivna:
		print("📹 MISSILE CAM - Lijevi prikaz prati raketu")
		
		# ✅ DEBUG - Provjeri pozicije
		print("   Raketa pozicija: ", aktivna_raketa.global_position)
		print("   Marker pozicija: ", rocket_marker.global_position)
		print("   Marker rotacija: ", rocket_marker.global_rotation_degrees)
		print("   Viewport kamera pozicija PRIJE: ", viewport_camera.global_position)
		
		# Isključi RemoteTransform vojnika
		remote_transform.remote_path = NodePath("")
		
		# Kreiraj RemoteTransform NA raketi
		if not rocket_remote_transform:
			rocket_remote_transform = RemoteTransform3D.new()
			rocket_marker.add_child(rocket_remote_transform)
		
		# Poveži ga direktno na viewport kameru
		rocket_remote_transform.remote_path = rocket_remote_transform.get_path_to(viewport_camera)
		rocket_remote_transform.update_position = true
		rocket_remote_transform.update_rotation = true
		
		print("   RemoteTransform path: ", rocket_remote_transform.remote_path)
		
		# ✅ Čekaj jedan frame da se transform primijeni
		await get_tree().process_frame
		print("   Viewport kamera pozicija POSLIJE: ", viewport_camera.global_position)
		print("   Viewport kamera rotacija POSLIJE: ", viewport_camera.global_rotation_degrees)
		
	else:
		print("👤 VOJNIK CAM - Povratak na normalni prikaz")
		
		# Ukloni raketa RemoteTransform
		if rocket_remote_transform and is_instance_valid(rocket_remote_transform):
			rocket_remote_transform.queue_free()
			rocket_remote_transform = null
		
		# Vrati vojnik RemoteTransform
		remote_transform.remote_path = remote_transform.get_path_to(viewport_camera)

func _on_rocket_destroyed():
	print("💥 Raketa eksplodirala!")
	
	if missile_cam_aktivna:
		missile_cam_aktivna = false
		
		# Ukloni raketa RemoteTransform
		if rocket_remote_transform and is_instance_valid(rocket_remote_transform):
			rocket_remote_transform.queue_free()
			rocket_remote_transform = null
		
		# Vrati vojnik RemoteTransform
		if remote_transform and viewport_camera:
			remote_transform.remote_path = remote_transform.get_path_to(viewport_camera)
		
	aktivna_raketa = null
