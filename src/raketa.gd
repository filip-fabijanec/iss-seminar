extends Area3D

# --- SIGNALI ---
signal raketa_unistena
signal smrtonosni_pogodak(napadac: String, zrtva: String)

# --- KONFIGURACIJA FIZIKE ---
@export var masa := 20.0             
@export var potisak_sila := 5000.0   # Snaga motora
@export var lift_koeficijent := 10.0 # Koliko krilca dizu raketu (uzgon)
@export var otpor_koeficijent := 0.01 # Air drag
@export var max_brzina := 300.0      

# --- NAVODJENJE ---
@export var turn_speed := 120.0      # Koliko brzo skrece (stupnjevi/sec)
@export var homing_strength := 5.0   # Koliko jako grize za metom

# --- EKSPLOZIJA I SUDARI ---
@export var explosion_scene: PackedScene
@export var proximity_radius := 15.0 # Blizinski upaljac - aktivira se ako pridje blizu mete

const GRAVITACIJA := Vector3(0, -9.81, 0)
const MAX_DOLET := 5000.0              

# --- STATE VARIJABLE (PAMTIMO STANJE) ---
var velocity: Vector3 = Vector3.ZERO
var tip_rakete := 0                  # 0=Ravno, 1=Manualno, 2=Homing
var locked_target: Node3D = null     # Koga ganjamo?
var prijedjena_udaljenost := 0.0
var vlasnik_strijelac: Node = null   # Tko je ispalio (da ne pogodimo sami sebe odmah)

@onready var ray: RayCast3D = $RayCast3D

func _ready():
	# Dodaj marker za kameru na ledja rakete da imamo dobar kut gledanja
	var cam_marker := Marker3D.new()
	cam_marker.name = "CameraMarker"
	add_child(cam_marker)
	cam_marker.position = Vector3(0, 1.0, 3.0) 
	cam_marker.rotation = Vector3.ZERO

func postavi_pocetnu_brzinu(smjer: Vector3):
	# Daj joj pocetni "kick" da ne padne odmah na pod
	smjer = smjer.normalized()
	velocity = smjer * 80.0 

	# Rotiraj model da gleda u smjeru kretanja
	if smjer.is_equal_approx(Vector3.UP):
		global_transform.basis = Basis.looking_at(smjer, Vector3.RIGHT)
	else:
		global_transform.basis = Basis.looking_at(smjer, Vector3.UP)
		
	print("🚀 START: Raketa lansirana, smjer -> ", smjer)

func postavi_raketu(tip: int, meta: Node3D = null):
	# Ovu funkciju zove vojnik kad ispali raketu
	tip_rakete = tip
	locked_target = meta
	print("🚀 MOD RADA: ", ["DIRECT", "MANUAL (YAW/PITCH)", "AA HOMING"][tip])

func ignoriraj_strijelca(strijelac: Node):
	# Dodaj exception na RayCast da ne eksplodira cim izadje iz cijevi
	if ray: ray.add_exception(strijelac)
	vlasnik_strijelac = strijelac

# --- GLAVNA FIZIKA PETLJA ---
func _physics_process(delta):
	
	# 1. UPRAVLJANJE (ROTACIJA)
	if tip_rakete == 1: 
		simple_arcade_controls(delta) # Igrac vozi raketu
	elif tip_rakete == 2 and is_instance_valid(locked_target): 
		homing_attitude_control(delta) # Kompjuter vozi raketu
	elif tip_rakete == 0: 
		stabilize_to_velocity(delta) # Samo prati putanju (kao pikado)

	# 2. ZBRAJANJE SILA
	var F_thrust = calculate_thrust()
	var F_lift = calculate_lift() 
	var F_drag = calculate_drag()
	var F_grav = GRAVITACIJA * masa

	var F_total = F_thrust + F_lift + F_drag + F_grav

	# 3. PRIMJENA SILA (F = m*a)
	var acceleration = F_total / masa
	velocity += acceleration * delta

	# Cap na maksimalnu brzinu
	if velocity.length() > max_brzina:
		velocity = velocity.normalized() * max_brzina

	# --- POMICANJE I DETEKCIJA SUDARA ---
	var step = velocity * delta
	var step_len = step.length()
	var current_pos = global_position
	var next_pos = current_pos + step
	
	# Sigurnosna provjera: ako leti predugo, unisti je
	if prijedjena_udaljenost > MAX_DOLET:
		detonate(global_position)
		return

	# Provjera blizine (Proximity Fuse) - je li prosla blizu aviona?
	if provjeri_proximity(current_pos, next_pos):
		return 

	# Provjera direktnog sudara (RayCast) - je li udarila u zid/tlo?
	ray.force_raycast_update()
	
	if ray.is_colliding():
		provjeri_sudar()
		return 

	# Pomakni raketu na novu poziciju
	global_position = next_pos
	prijedjena_udaljenost += step_len
	
	# Vizualno poravnanje (samo za Direct mode da ne izgleda cudno)
	if tip_rakete == 0 and velocity.length() > 1.0:
		visual_align(delta)

# --- LOGIKA UPRAVLJANJA ---
func simple_arcade_controls(delta):
	# Citanje inputa za wire-guided mod
	var pitch_input = Input.get_axis("missile_pitch_up", "missile_pitch_down") 
	var yaw_input = Input.get_axis("missile_yaw_right", "missile_yaw_left")     
	
	if abs(pitch_input) > 0.01:
		global_transform.basis = global_transform.basis.rotated(global_transform.basis.x, pitch_input * deg_to_rad(turn_speed) * delta)
	if abs(yaw_input) > 0.01:
		global_transform.basis = global_transform.basis.rotated(global_transform.basis.y, yaw_input * deg_to_rad(turn_speed) * delta)
	global_transform.basis = global_transform.basis.orthonormalized()

func homing_attitude_control(delta):
	# Proportional Navigation (osnovna verzija)
	var target_velocity = Vector3.ZERO
	if "velocity" in locked_target:
		target_velocity = locked_target.velocity
	elif locked_target is RigidBody3D:
		target_velocity = locked_target.linear_velocity

	# Predvidjanje gdje ce meta biti (Intercept Point)
	var to_target = locked_target.global_position - global_position
	var distance = to_target.length()
	var prediction_speed = max_brzina 
	var time_to_impact = distance / prediction_speed
	
	var predicted_pos = locked_target.global_position + (target_velocity * time_to_impact)
	var target_dir = (predicted_pos - global_position).normalized()
	
	# Lagano okreci raketu prema predvidjenoj tocki
	var current_basis = global_transform.basis
	var target_basis = Basis.looking_at(target_dir, Vector3.UP)
	global_transform.basis = current_basis.slerp(target_basis, homing_strength * 2.0 * delta).orthonormalized()

# --- AERODINAMIKA ---
func calculate_thrust() -> Vector3:
	# Sila gura prema naprijed (-Z os modela)
	return -global_transform.basis.z * potisak_sila

func calculate_lift() -> Vector3:
	# Racuna uzgon ovisno o kutu napada (Angle of Attack)
	if velocity.length() < 1.0: return Vector3.ZERO
	var v_dir = velocity.normalized()
	var nos = -global_transform.basis.z
	var aoa = v_dir.angle_to(nos)
	
	if aoa < 0.001: return Vector3.ZERO
	
	var axis = v_dir.cross(nos).normalized()
	var lift_dir = v_dir.rotated(axis, PI / 2.0)
	var dynamic_pressure = 0.5 * velocity.length_squared() * 0.01 
	
	return lift_dir * lift_koeficijent * sin(aoa) * dynamic_pressure

func calculate_drag() -> Vector3:
	# Otpor zraka uvijek djeluje suprotno od brzine
	return -velocity.normalized() * otpor_koeficijent * velocity.length_squared()

# --- HELPERI ---
func stabilize_to_velocity(delta):
	# Ako nema inputa, raketa se poravnava s vjetrom
	if velocity.length() > 1.0:
		var target_basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, delta * 5.0)

func visual_align(delta):
	var target_basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, delta * 2.0)

# --- GAME OVER / POBJEDA LOGIKA ---

func aktiviraj_game_over(ime_mete, tacka_eksplozije: Vector3):
	print("🏆 POGODAK! Pripremam pobjedu...")
	
	# 1. Smrzni raketu da ne radi gluposti
	set_physics_process(false) 
	hide() 
	ray.enabled = false 
	monitoring = false 

	# 2. Bum! (Instanciraj eksploziju)
	if explosion_scene:
		var e = explosion_scene.instantiate()
		get_tree().root.add_child(e)
		e.global_position = tacka_eksplozije

	# 3. Zapisi pobjednika u globalnu skriptu
	var gd = get_node_or_null("/root/GameData")
	if gd:
		gd.pobjednik_ime = "VOJNIK"
		print("✅ GameData ažuriran")

	# 4. Kratka pauza za dramski efekt
	await get_tree().create_timer(0.5).timeout
	
	# 5. Prebaci na Winner Screen
	get_tree().change_scene_to_file("res://WinnerScene.tscn")
	
	# 6. Bye bye raketa
	queue_free()

func provjeri_sudar():
	var hit = ray.get_collider()
	if not hit: return
	
	# SLUCAJ A: Pogodili smo avion (Cilj)
	if hit.is_in_group("airplane"): 
		print("🎯 DIREKTAN POGODAK U AVION!")
		var point = ray.get_collision_point()
		aktiviraj_game_over("VOJNIK", point)
		
	# SLUCAJ B: Pogodili smo pod ili zgradu (Fail)
	else:
		print("🌍 Raketa je udarila u tlo/objekt: ", hit.name)
		detonate(ray.get_collision_point()) 

func provjeri_proximity(start_pos: Vector3, end_pos: Vector3) -> bool:
	# Matematika za provjeru je li raketa prosla "tik do" mete
	if not is_instance_valid(locked_target): return false
	
	var target_pos = locked_target.global_position
	var closest_point = Geometry3D.get_closest_point_to_segment(target_pos, start_pos, end_pos)
	var dist = closest_point.distance_to(target_pos)
	
	if dist < proximity_radius:
		print("💥 PROXIMITY POGODAK: ", locked_target.name)
		aktiviraj_game_over(locked_target.name, closest_point)
		return true 
	return false

func detonate(point):
	# Obicna eksplozija (nismo pobijedili)
	emit_signal("raketa_unistena")
	if explosion_scene:
		var e = explosion_scene.instantiate()
		get_tree().root.add_child(e)
		e.global_position = point
	queue_free()
