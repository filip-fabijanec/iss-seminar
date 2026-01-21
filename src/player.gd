extends CharacterBody3D

# Postavke kretanja i kamere
const SPEED = 5.0
const MOUSE_SENSITIVITY = 0.3
const ANIMATION_SMOOTHING = 10.0

# Zvukovi koraka i tajming
const STEP_INTERVAL = 0.5 
var step_timer = 0.0
@export var footstep_sounds: Array[AudioStream] 

# Postavke za ciljanje (ADS)
const NORMAL_FOV = 75.0
const AIM_FOV = 50.0 
const ZOOM_SPEED = 15.0 
const ADS_LERP_SPEED = 15.0 

# Duzina stapa kamere (SpringArm)
const FIKSNA_DUZINA_STAPA = 0.1
const ADS_DUZINA_STAPA = 0.0 

# Varijable za fiziku i animacije
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var anim_blend_position = Vector2.ZERO
var x_rotacija = 0.0  # Vertikalna rotacija kamere (gore/dolje)

# Stanje oruzja
var is_reloading = false
var is_weapon_empty = false

# Postavke projektila
@export var projectile_scene: PackedScene 
@export var visual_rocket_mesh: Node3D

# Varijable za kontrolu rakete i kamere
var aktivna_raketa: Node3D = null
var missile_cam_aktivna = false
var trenutni_tip_projektila: int = 0 # 0=Direct, 1=Manual, 2=Homing
var zakljucana_meta: Node3D = null

# Reference za kameru
var rocket_remote_transform: RemoteTransform3D = null
var viewport_camera: Camera3D = null

# Reference na cvorove unutar scene
@onready var camera_pivot_node = $vojnik/Rotation
@onready var spring_arm = $vojnik/Rotation/SpringArm3D
@onready var camera = $vojnik/Rotation/SpringArm3D/Camera3D
@onready var anim_tree = $AnimationTree 
@onready var skeleton = $vojnik/GeneralSkeleton
@onready var ruku_pivot = $vojnik/GeneralSkeleton/Leda/RukePivot
@onready var remote_transform = $vojnik/Rotation/SpringArm3D/RemoteTransform3D

# Reference za HUD (dohvacamo ih u ready funkciji)
var lbl_mode: Label = null
var lbl_lock: Label = null

# Tocka gdje se stvara raketa
@onready var spawn_point = $vojnik/GeneralSkeleton/Leda/RukePivot/Ruke/MuzzlePoint 

# Audio
@onready var audio_shoot = $ZvukPucanja
@onready var audio_reload = $ZvukReload
@onready var audio_walk = $ZvukKoraci

# Efekti
@export var muzzle_light: OmniLight3D

# Animacije
@export var rpg_animation_player: AnimationPlayer 

@export var anim_name_idle: String = "MC_RPG7_idle"        
@export var anim_name_shoot: String = "MC_RPG7_shoot"        
@export var anim_name_after_shoot: String = "MC_RPG7_static_pose_empty" 
@export var anim_name_reload: String = "MC_RPG7_reload"      

# Tocke za pozicioniranje kamere kod ciljanja
@onready var kamera_target_vrat = $vojnik/GeneralSkeleton/Neck/KameraTarget
@onready var nisan_target = $vojnik/GeneralSkeleton/Leda/RukePivot/Ruke/NisanTarget 

func _ready():
	# Sakrij mis i zarobi ga u prozor
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	anim_tree.active = true
	
	# Podesavanje SpringArm-a da ne udara u samog igraca
	spring_arm.add_excluded_object(self.get_rid())
	spring_arm.collision_mask = 0 
	
	# Inicijalna rotacija
	x_rotacija = 0.0  
	spring_arm.rotation_degrees = Vector3(0.0, 180.0, 0.0) 
	
	# Podesavanje RemoteTransforma da kamera gleda ispravno
	var remote = $vojnik/Rotation/SpringArm3D/RemoteTransform3D
	if remote:
		remote.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		
	# Postavljanje animacija hodanja na loop
	var walk_anim_player = $vojnik/AnimationPlayer 
	if walk_anim_player:
		for anim_name in walk_anim_player.get_animation_list():
			var anim = walk_anim_player.get_animation(anim_name)
			if "walk" in anim_name.to_lower() or "strafe" in anim_name.to_lower():
				anim.loop_mode = Animation.LOOP_LINEAR
	
	# Povezivanje s HUD elementima u glavnoj sceni
	lbl_mode = get_tree().get_first_node_in_group("hud_vojnik_mode")
	lbl_lock = get_tree().get_first_node_in_group("hud_vojnik_lock")
	
	if muzzle_light:
		muzzle_light.visible = false
	
	# Sakrivamo originalne ruke modela jer koristimo posebne FPS ruke
	sakrij_originalne_ruke()
	
	if visual_rocket_mesh:
		visual_rocket_mesh.visible = true
	
	# Resetiranje stanja oruzja
	is_weapon_empty = false 
	is_reloading = false
	
	if rpg_animation_player:
		rpg_animation_player.play(anim_name_idle)
		
	# Trazimo glavnu kameru viewporta
	viewport_camera = get_tree().get_first_node_in_group("vojnik_viewport_camera")

func _input(event):
	# Ako kliknemo misem, ponovno zarobi kursor
	if event is InputEventMouseButton:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Rotacija kamere i igraca misem
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Lijevo-desno rotira cijelo tijelo
		rotate_y(deg_to_rad(-event.relative.x * MOUSE_SENSITIVITY))
		
		# Gore-dolje rotira samo kameru (SpringArm)
		x_rotacija -= event.relative.y * MOUSE_SENSITIVITY
		x_rotacija = clamp(x_rotacija, -89.0, 89.0)
		spring_arm.rotation_degrees.x = x_rotacija
	
	# Izlazak iz igre ili oslobadjanje misa
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Promjena moda paljbe (ciklicki)
	if event.is_action_pressed("promijeni_mod"):
		trenutni_tip_projektila += 1
		if trenutni_tip_projektila > 2:
			trenutni_tip_projektila = 0
		update_hud()

	# Rucno biranje modova brojevima
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1: 
			trenutni_tip_projektila = 0
			update_hud()
		if event.keycode == KEY_2: 
			trenutni_tip_projektila = 1
			update_hud()
		if event.keycode == KEY_3: 
			trenutni_tip_projektila = 2
			update_hud()

	# Pokusaj zakljucavanja mete (Lock-on)
	if event.is_action_pressed("lock_on"):
		pokusaj_lock_on()
		
	# Prebacivanje kamere na raketu
	if event.is_action_pressed("toggle_missile_cam"):
		toggle_missile_camera()

func _physics_process(delta):
	# Osiguraj da je mis zarobljen osim ako ne pratimo raketu
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and not missile_cam_aktivna:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Ako pratimo raketu, ne micemo vojnika
	if missile_cam_aktivna:
		return
	
	# Primjena gravitacije
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Kretanje igraca (WASD)
	var input_dir = -Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		
		# Zvuk koraka
		if is_on_floor():
			step_timer += delta
			if step_timer > STEP_INTERVAL:
				play_footstep()
				step_timer = 0.0 
	else:
		# Zaustavljanje
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		step_timer = STEP_INTERVAL 
	
	# Blendanje animacija hodanja/trcanja
	var target_blend = Vector2(input_dir.x, -input_dir.y)
	anim_blend_position = anim_blend_position.lerp(target_blend, delta * ANIMATION_SMOOTHING)
	anim_tree.set("parameters/DonjiDio/Kretanje/blend_position", anim_blend_position)
	
	# Logika oruzja (pucanje/reload)
	handle_weapon_input()
	
	# Pivot ruku prati vertikalni pogled kamere
	if ruku_pivot:
		var target_arm_rot = -x_rotacija
		ruku_pivot.rotation_degrees.x = lerp(ruku_pivot.rotation_degrees.x, target_arm_rot, delta * 15.0)
		ruku_pivot.rotation_degrees.z = 0.0

	# ADS (Aim Down Sights) logika zumiranja
	aim_logic(delta)

	move_and_slide()
	update_hud()
	
func update_hud():
	var tekst = ""
	match trenutni_tip_projektila:
		0: tekst = "RPG-7 (DIRECT)"
		1: tekst = "WIRE GUIDED"
		2: tekst = "AA HOMING"
	
	if lbl_mode: 
		lbl_mode.text = tekst
	
	# Prikaz lock statusa samo za Homing mod
	if lbl_lock:
		if trenutni_tip_projektila == 2:
			if zakljucana_meta and is_instance_valid(zakljucana_meta):
				lbl_lock.text = "\n[ LOCKED ]"
				lbl_lock.modulate = Color(1, 0, 0) # Crvena
			else:
				lbl_lock.text = "\nSEARCHING..."
				lbl_lock.modulate = Color(1, 1, 1, 0.5) # Prozirno
		else:
			lbl_lock.text = ""

func pokusaj_lock_on():
	if trenutni_tip_projektila != 2:
		return
	
	var svi_avioni = get_tree().get_nodes_in_group("airplane")
	if svi_avioni.is_empty():
		return
	
	var najblizi_avion: Node3D = null
	var najbliza_udaljenost = 99999.0
	var max_udaljenost = 2000.0 
	
	# Trazimo avion koji je najblizi i unutar vidnog polja
	for avion in svi_avioni:
		if not is_instance_valid(avion):
			continue
		
		var udaljenost = global_position.distance_to(avion.global_position)
		if udaljenost > max_udaljenost:
			continue
		
		# Provjera je li avion ispred nas (dot product)
		var smjer_do_aviona = (avion.global_position - viewport_camera.global_position).normalized()
		var forward = -viewport_camera.global_transform.basis.z
		var dot = smjer_do_aviona.dot(forward)
		
		if dot > 0.5 and udaljenost < najbliza_udaljenost:
			najbliza_udaljenost = udaljenost
			najblizi_avion = avion
	
	if najblizi_avion:
		zakljucana_meta = najblizi_avion
		print("🎯 META ZAKLJUČANA: ", najblizi_avion.name)
	else:
		zakljucana_meta = null

func play_footstep():
	if footstep_sounds.is_empty():
		return
	audio_walk.stream = footstep_sounds.pick_random()
	audio_walk.play()

func aim_logic(delta):
	var trenutna_meta_pozicija: Vector3
	var ciljana_duzina_stapa: float
	
	# Desni klik za ciljanje
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		ciljana_duzina_stapa = ADS_DUZINA_STAPA 
		if nisan_target: 
			trenutna_meta_pozicija = nisan_target.global_position
		elif kamera_target_vrat:
			trenutna_meta_pozicija = kamera_target_vrat.global_position
	else:
		ciljana_duzina_stapa = FIKSNA_DUZINA_STAPA
		if kamera_target_vrat:
			trenutna_meta_pozicija = kamera_target_vrat.global_position
	
	# Glatko pomicanje kamere prema nisanu ili vratu
	if camera_pivot_node:
		camera_pivot_node.global_position = camera_pivot_node.global_position.lerp(trenutna_meta_pozicija, delta * ADS_LERP_SPEED)
	
	spring_arm.spring_length = lerp(spring_arm.spring_length, ciljana_duzina_stapa, delta * ZOOM_SPEED)

func sakrij_originalne_ruke():
	# Skalira originalne kosti ruku na 0 da se ne vide (jer imamo FPS ruke)
	if not skeleton: return
	var kosti = ["RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand", "Head"]
	for k in kosti:
		var idx = skeleton.find_bone(k)
		if idx != -1:
			skeleton.set_bone_global_pose_override(idx, Transform3D().scaled(Vector3(0.001, 0.001, 0.001)), 1.0, true)

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
	
	if not is_weapon_empty:
		return
	
	if is_reloading:
		return

	is_reloading = true
	
	# Prikazi raketu na modelu tijekom reloada
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
	if is_weapon_empty or is_reloading: 
		return
		
	trigger_muzzle_flash()
	
	# Oznaci da je oruzje prazno i sakrij vizualnu raketu
	is_weapon_empty = true
	if visual_rocket_mesh: 
		visual_rocket_mesh.visible = false
	
	# Stvori instancu rakete
	var rocket = projectile_scene.instantiate()
	get_tree().root.add_child(rocket)
	rocket.global_transform = spawn_point.global_transform

	audio_shoot.play()
	
	# Izracunaj smjer pucanja prema onome gdje kamera gleda
	var smjer = -viewport_camera.global_transform.basis.z
	smjer = smjer.normalized()
	
	rocket.look_at(rocket.global_position + smjer, Vector3.UP)

	# Inicijalizacija rakete s parametrima
	if rocket.has_method("postavi_pocetnu_brzinu"):
		rocket.postavi_pocetnu_brzinu(smjer)
	
	if rocket.has_method("ignoriraj_strijelca"):
		rocket.ignoriraj_strijelca(self)
	
	if rocket.has_method("postavi_raketu"):
		rocket.postavi_raketu(trenutni_tip_projektila, zakljucana_meta)
	
	# Povezivanje signala za unistenje
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
		return
	
	var rocket_marker = aktivna_raketa.find_child("CameraMarker", true, false)
	
	if not rocket_marker or not viewport_camera or not remote_transform:
		return
	
	missile_cam_aktivna = not missile_cam_aktivna
	
	if missile_cam_aktivna:
		print("📹 Kamera prebacena na raketu")
		
		# Iskljuci transform s vojnika
		remote_transform.remote_path = NodePath("")
		
		# Kreiraj transform na raketi i povezi ga na kameru
		if not rocket_remote_transform:
			rocket_remote_transform = RemoteTransform3D.new()
			rocket_marker.add_child(rocket_remote_transform)
		
		rocket_remote_transform.remote_path = rocket_remote_transform.get_path_to(viewport_camera)
		rocket_remote_transform.update_position = true
		rocket_remote_transform.update_rotation = true
		
	else:
		print("👤 Kamera vracena na vojnika")
		
		# Unisti transform na raketi
		if rocket_remote_transform and is_instance_valid(rocket_remote_transform):
			rocket_remote_transform.queue_free()
			rocket_remote_transform = null
		
		# Vrati transform na vojnika
		remote_transform.remote_path = remote_transform.get_path_to(viewport_camera)

func _on_rocket_destroyed():
	if missile_cam_aktivna:
		missile_cam_aktivna = false
		
		if rocket_remote_transform and is_instance_valid(rocket_remote_transform):
			rocket_remote_transform.queue_free()
			rocket_remote_transform = null
		
		if remote_transform and viewport_camera:
			remote_transform.remote_path = remote_transform.get_path_to(viewport_camera)
		
	aktivna_raketa = null
