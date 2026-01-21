extends Area3D

signal raketa_unistena

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
@export var proximity_radius := 15.0 # Povećao sam malo radijus radi sigurnosti

const GRAVITACIJA := Vector3(0, -9.81, 0)
const MAX_DOLET := 5000.0             

# VARIJABLE STANJA
var velocity: Vector3 = Vector3.ZERO
var tip_rakete := 0                  # 0=Direct, 1=Manual, 2=Homing
var locked_target: Node3D = null
var prijedjena_udaljenost := 0.0

@onready var ray: RayCast3D = $RayCast3D

# INICIJALIZACIJA
func _ready():
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

	# --- OVDJE JE POPRAVLJENA LOGIKA KRETANJA I SUDARA ---
	
	# A) Izračunaj korak (gdje bi bili na kraju ovog framea)
	var step = velocity * delta
	var step_len = step.length()
	var current_pos = global_position
	var next_pos = current_pos + step
	
	# B) PROVJERA DOLETA
	if prijedjena_udaljenost > MAX_DOLET:
		detonate(global_position)
		return

	# C) PROVJERA BLIZINE (PROXIMITY) - Prije micanja!
	# Provjeravamo liniju od trenutne do iduće pozicije
	if provjeri_proximity(current_pos, next_pos):
		return # Ako je eksplodirala, prekidamo

	# D) PROVJERA SUDARA (RAYCAST) - Prije micanja!
	# Postavljamo raycast da gleda točno onoliko koliko putujemo naprijed (-Z)
	#ray.target_position = Vector3(0, 0, -step_len)
	ray.force_raycast_update()
	
	if ray.is_colliding():
		provjeri_sudar()
		return # Ako je udarila, prekidamo

	# E) MICANJE RAKETE (Samo ako nismo ništa pogodili)
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
	
	# Vratio sam clamp jer je bitan da raketa ne poludi na velikim udaljenostima
	# time_to_impact = clamp(time_to_impact, 0.0, 1.0) 
	
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

func provjeri_sudar():
	# Ova se funkcija zove samo ako je ray.is_colliding() true
	var hit = ray.get_collider()
	
	if not hit.is_in_group("player"):
		print("💥 POGODAK (Direct)! Raketa je udarila u: ", hit.name)
		print("Tip objekta: ", hit.get_class())
		
		# Dodao sam i ovdje provjeru štete
		if hit.has_method("take_damage"):
			hit.take_damage(100) # Direktan pogodak radi više štete
			
		detonate(ray.get_collision_point())
			
func provjeri_proximity(start_pos: Vector3, end_pos: Vector3) -> bool:
	if not is_instance_valid(locked_target):
		return false
		
	var target_pos = locked_target.global_position
	
	# Matematika: točka na liniji kretanja najbliža meti
	var closest_point = Geometry3D.get_closest_point_to_segment(target_pos, start_pos, end_pos)
	var dist = closest_point.distance_to(target_pos)
	
	if dist < proximity_radius:
		print("💥 PROXIMITY AKTIVIRAN! Meta: ", locked_target.name, " | Udaljenost: ", dist)
		
		if locked_target.has_method("take_damage"):
			locked_target.take_damage(50) # Proximity radi manje štete
			
		detonate(closest_point)
		return true 
		
	return false

func detonate(point):
	emit_signal("raketa_unistena")
	if explosion_scene:
		var e = explosion_scene.instantiate()
		get_tree().root.add_child(e)
		e.global_position = point
	queue_free()
