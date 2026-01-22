extends Area3D

# --- SIGNALI ZA GAME OVER ---
signal raketa_unistena
signal smrtonosni_pogodak(napadac: String, zrtva: String)
# ----------------------------

# PARAMETRI SIMULACIJE
@export var masa := 20.0             
@export var potisak_sila := 5000.0   # Jacina motora (Newton)
@export var lift_koeficijent := 10.0 # Faktor uzgona 
@export var otpor_koeficijent := 0.01
@export var max_brzina := 300.0      

# Osjetljivost kontrola
@export var turn_speed := 120.0      # Brzina rotacije (stupnjevi/s)

# OSTALO
@export var homing_strength := 5.0   # Koliko agresivno prati metu
@export var explosion_scene: PackedScene
@export var proximity_radius := 15.0 

const GRAVITACIJA := Vector3(0, -9.81, 0)
const MAX_DOLET := 5000.0             

# VARIJABLE STANJA
var velocity: Vector3 = Vector3.ZERO
var tip_rakete := 0                  # 0=Direct, 1=Manual, 2=Homing
var locked_target: Node3D = null
var prijedjena_udaljenost := 0.0
var vlasnik_strijelac: Node = null   # Dodano radi kompatibilnosti

@onready var ray: RayCast3D = $RayCast3D

# INICIJALIZACIJA
func _ready():
	# Kreiranje markera za kameru ako je potrebno
	var cam_marker := Marker3D.new()
	cam_marker.name = "CameraMarker"
	add_child(cam_marker)
	cam_marker.position = Vector3(0, 1.0, 3.0) 
	cam_marker.rotation = Vector3.ZERO

func postavi_pocetnu_brzinu(smjer: Vector3):
	smjer = smjer.normalized()
	velocity = smjer * 80.0 

	if smjer.is_equal_approx(Vector3.UP):
		global_transform.basis = Basis.looking_at(smjer, Vector3.RIGHT)
	else:
		global_transform.basis = Basis.looking_at(smjer, Vector3.UP)
		
	print("🚀 START: Podesen smjer -> ", smjer)

func postavi_raketu(tip: int, meta: Node3D = null):
	tip_rakete = tip
	locked_target = meta
	print("🚀 MOD RADA: ", ["DIRECT", "MANUAL (YAW/PITCH)", "AA HOMING"][tip])

func ignoriraj_strijelca(strijelac: Node):
	if ray: ray.add_exception(strijelac)
	vlasnik_strijelac = strijelac

# PHYSICS PROCESS (Glavna petlja)
func _physics_process(delta):
	
	# 1. UPRAVLJANJE ORIJENTACIJOM
	if tip_rakete == 1: 
		simple_arcade_controls(delta)
	elif tip_rakete == 2 and is_instance_valid(locked_target): 
		homing_attitude_control(delta)
	elif tip_rakete == 0: 
		stabilize_to_velocity(delta)

	# 2. IZRAČUN SILA
	var F_thrust = calculate_thrust()
	var F_lift = calculate_lift() 
	var F_drag = calculate_drag()
	var F_grav = GRAVITACIJA * masa

	var F_total = F_thrust + F_lift + F_drag + F_grav

	# 3. INTEGRACIJA
	var acceleration = F_total / masa
	velocity += acceleration * delta

	if velocity.length() > max_brzina:
		velocity = velocity.normalized() * max_brzina

	# --- KRETANJE I SUDARI ---
	var step = velocity * delta
	var step_len = step.length()
	var current_pos = global_position
	var next_pos = current_pos + step
	
	# B) PROVJERA DOLETA
	if prijedjena_udaljenost > MAX_DOLET:
		detonate(global_position)
		return

	# C) PROVJERA BLIZINE (PROXIMITY)
	if provjeri_proximity(current_pos, next_pos):
		return 

	# D) PROVJERA SUDARA (RAYCAST)
	ray.force_raycast_update()
	
	if ray.is_colliding():
		provjeri_sudar()
		return 

	# E) MICANJE RAKETE
	global_position = next_pos
	prijedjena_udaljenost += step_len
	
	# Vizualna korekcija
	if tip_rakete == 0 and velocity.length() > 1.0:
		visual_align(delta)

# KONTROLE
func simple_arcade_controls(delta):
	var pitch_input = Input.get_axis("missile_pitch_up", "missile_pitch_down") 
	var yaw_input = Input.get_axis("missile_yaw_right", "missile_yaw_left")    
	
	if abs(pitch_input) > 0.01:
		global_transform.basis = global_transform.basis.rotated(global_transform.basis.x, pitch_input * deg_to_rad(turn_speed) * delta)
	if abs(yaw_input) > 0.01:
		global_transform.basis = global_transform.basis.rotated(global_transform.basis.y, yaw_input * deg_to_rad(turn_speed) * delta)
	global_transform.basis = global_transform.basis.orthonormalized()

# HOMING LOGIKA
func homing_attitude_control(delta):
	var target_velocity = Vector3.ZERO
	if "velocity" in locked_target:
		target_velocity = locked_target.velocity
	elif locked_target is RigidBody3D:
		target_velocity = locked_target.linear_velocity

	var to_target = locked_target.global_position - global_position
	var distance = to_target.length()
	var prediction_speed = max_brzina 
	var time_to_impact = distance / prediction_speed
	
	var predicted_pos = locked_target.global_position + (target_velocity * time_to_impact)
	var target_dir = (predicted_pos - global_position).normalized()
	
	var current_basis = global_transform.basis
	var target_basis = Basis.looking_at(target_dir, Vector3.UP)
	global_transform.basis = current_basis.slerp(target_basis, homing_strength * 2.0 * delta).orthonormalized()

# FIZIKA - SILA
func calculate_thrust() -> Vector3:
	return -global_transform.basis.z * potisak_sila

func calculate_lift() -> Vector3:
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
	return -velocity.normalized() * otpor_koeficijent * velocity.length_squared()

# POMOĆNE FUNKCIJE
func stabilize_to_velocity(delta):
	if velocity.length() > 1.0:
		var target_basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, delta * 5.0)

func visual_align(delta):
	var target_basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, delta * 2.0)

# --- U Projectile.gd ---

# Zamijeni cijelu funkciju aktiviraj_game_over u Projectile.gd ovim:
# --- POPRAVLJENE FUNKCIJE ---

func aktiviraj_game_over(ime_mete, tacka_eksplozije: Vector3):
	print("🏆 POGODAK! Pripremam pobjedu...")
	
	# 1. ZAUSTAVI RAKETU (Vizualno i fizički)
	set_physics_process(false) # Prestani pomicati raketu
	hide() # Sakrij model rakete
	# Isključi sudare da ne pogodi istu metu 100 puta dok čeka
	ray.enabled = false 
	monitoring = false 

	# 2. STVORI EKSPLOZIJU ODMAH (da igrač vidi udarac)
	if explosion_scene:
		var e = explosion_scene.instantiate()
		get_tree().root.add_child(e)
		e.global_position = tacka_eksplozije

	# 3. ZAPIŠI PODATKE
	var gd = get_node_or_null("/root/GameData")
	if gd:
		gd.pobjednik_ime = "VOJNIK"
		print("✅ GameData ažuriran")

	await get_tree().create_timer(0.5).timeout
	
	# 5. PROMIJENI SCENU
	get_tree().change_scene_to_file("res://WinnerScene.tscn")
	
	# 6. TEK SAD UNIŠTI RAKETU
	queue_free()

func provjeri_sudar():
	var hit = ray.get_collider()
	if not hit: return
	
	# 1. PROVJERA: Je li to avion? (Pobjeda)
	if hit.is_in_group("airplane"): 
		print("🎯 DIREKTAN POGODAK U AVION!")
		var point = ray.get_collision_point()
		aktiviraj_game_over("VOJNIK", point) # Pokreće timer i WinnerScene
		
	# 2. PROVJERA: Je li to tlo ili nešto drugo? (Samo eksplozija)
	else:
		print("🌍 Raketa je udarila u tlo/objekt: ", hit.name)
		detonate(ray.get_collision_point()) # Samo eksplozija, nema WinnerScene

func provjeri_proximity(start_pos: Vector3, end_pos: Vector3) -> bool:
	if not is_instance_valid(locked_target): return false
	
	var target_pos = locked_target.global_position
	var closest_point = Geometry3D.get_closest_point_to_segment(target_pos, start_pos, end_pos)
	var dist = closest_point.distance_to(target_pos)
	
	if dist < proximity_radius:
		print("💥 PROXIMITY POGODAK: ", locked_target.name)
		
		aktiviraj_game_over(locked_target.name, closest_point)
		return true 
	return false

# Ovu funkciju sada koristimo samo ako raketa promaši (npr. MAX_DOLET)
func detonate(point):
	emit_signal("raketa_unistena")
	if explosion_scene:
		var e = explosion_scene.instantiate()
		get_tree().root.add_child(e)
		e.global_position = point
	queue_free()
