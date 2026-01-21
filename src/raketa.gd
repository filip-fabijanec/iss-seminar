extends Area3D

signal raketa_unistena

# PARAMETRI SIMULACIJE
@export var masa := 20.0             
@export var potisak_sila := 5000.0   # Jacina motora (Newton)
@export var lift_koeficijent := 10.0 # Faktor uzgona - utjece na to koliko jako raketa skrece
@export var otpor_koeficijent := 0.01
@export var max_brzina := 300.0      

# Osjetljivost kontrola
@export var turn_speed := 120.0      # Brzina rotacije (stupnjevi/s)

# OSTALO
@export var homing_strength := 5.0   # Koliko agresivno prati metu
@export var explosion_scene: PackedScene

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
	# Marker za kameru - postavljam ga malo iza i iznad rakete
	var cam_marker := Marker3D.new()
	cam_marker.name = "CameraMarker"
	add_child(cam_marker)
	cam_marker.position = Vector3(0, 1.0, 3.0) 
	cam_marker.rotation = Vector3.ZERO

func postavi_pocetnu_brzinu(smjer: Vector3):
	smjer = smjer.normalized()
	velocity = smjer * 80.0 # Pocetni impuls

	# Podesavanje orijentacije da nos gleda u smjeru ispaljivanja
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
	
	# 1. UPRAVLJANJE ORIJENTACIJOM (ATTITUDE)
	# Ovdje mijenjamo kuteve rotacije direktno (bez momenta), kako je trazeno u zadatku
	if tip_rakete == 1: # Manualno
		simple_arcade_controls(delta)
	elif tip_rakete == 2 and is_instance_valid(locked_target): 
		homing_attitude_control(delta)
	elif tip_rakete == 0: # Direct (balisticki)
		stabilize_to_velocity(delta)

	# 2. IZRAČUN SILA (Dinamika)
	# F_total = Thrust + Lift + Drag + Gravity
	var F_thrust = calculate_thrust()
	var F_lift = calculate_lift() # Ovo generira aerodinamicku silu za skretanje
	var F_drag = calculate_drag()
	var F_grav = GRAVITACIJA * masa

	var F_total = F_thrust + F_lift + F_drag + F_grav

	# 3. INTEGRACIJA (Eulerova metoda)
	# a = F / m
	# v = v + a * dt
	var acceleration = F_total / masa
	velocity += acceleration * delta

	# Ogranicenje maksimalne brzine
	if velocity.length() > max_brzina:
		velocity = velocity.normalized() * max_brzina

	# x = x + v * dt
	global_position += velocity * delta
	prijedjena_udaljenost += velocity.length() * delta
	
	# Vizualna korekcija - model prati vektor brzine da ljepse izgleda (samo Direct mod)
	if tip_rakete == 0 and velocity.length() > 1.0:
		visual_align(delta)

	# 4. PROVJERA SUDARA I DOLETA
	if prijedjena_udaljenost > MAX_DOLET:
		detonate(global_position)
		return
	provjeri_sudar()

# KONTROLE (YAW / PITCH)
func simple_arcade_controls(delta):
	# W/S = Pitch (Gore/Dolje), A/D = Yaw (Lijevo/Desno)
	var pitch_input = Input.get_axis("missile_pitch_up", "missile_pitch_down") 
	var yaw_input = Input.get_axis("missile_yaw_right", "missile_yaw_left")   
	
	# Rotacija oko X osi (Pitch)
	if abs(pitch_input) > 0.01:
		global_transform.basis = global_transform.basis.rotated(global_transform.basis.x, pitch_input * deg_to_rad(turn_speed) * delta)
		
	# Rotacija oko Y osi (Yaw)
	if abs(yaw_input) > 0.01:
		global_transform.basis = global_transform.basis.rotated(global_transform.basis.y, yaw_input * deg_to_rad(turn_speed) * delta)
	
	# Obavezna ortonormalizacija da se matrica ne deformira s vremenom
	global_transform.basis = global_transform.basis.orthonormalized()

# HOMING LOGIKA
func homing_attitude_control(delta):
	var target_dir = (locked_target.global_position - global_position).normalized()
	
	# Koristim looking_at za izracun ciljane rotacije
	var current_basis = global_transform.basis
	var target_basis = Basis.looking_at(target_dir, Vector3.UP)
	
	# Glatka interpolacija (slerp) prema meti
	global_transform.basis = current_basis.slerp(target_basis, homing_strength * delta).orthonormalized()

# FIZIKA - IZRAČUN SILA
func calculate_thrust() -> Vector3:
	# Potisak uvijek djeluje u smjeru nosa (-Z)
	return -global_transform.basis.z * potisak_sila

func calculate_lift() -> Vector3:
	# Racunanje sile uzgona ovisno o kutu napada (Angle of Attack - AoA)
	# Ova sila omogucuje skretanje kad okrenemo nos rakete
	
	if velocity.length() < 1.0: return Vector3.ZERO
	
	var v_dir = velocity.normalized()
	var nos = -global_transform.basis.z
	
	# Kut izmedju vektora brzine i nosa
	var aoa = v_dir.angle_to(nos)
	if aoa < 0.001: return Vector3.ZERO
	
	# Os rotacije (vektor okomit na ravninu koju cine brzina i nos)
	var axis = v_dir.cross(nos).normalized()
	
	# Smjer sile uzgona (okomito na brzinu, rotirano za 90 stupnjeva oko osi)
	var lift_dir = v_dir.rotated(axis, PI / 2.0)
	
	# Intenzitet sile: proporcionalan kvadratu brzine i sinusu kuta napada
	var dynamic_pressure = 0.5 * velocity.length_squared() * 0.01 
	
	return lift_dir * lift_koeficijent * sin(aoa) * dynamic_pressure

func calculate_drag() -> Vector3:
	# Otpor zraka suprotan smjeru brzine
	return -velocity.normalized() * otpor_koeficijent * velocity.length_squared()

# POMOĆNE FUNKCIJE
func stabilize_to_velocity(delta):
	# U direct modu raketa se ponasa kao strijela (nos prati putanju)
	if velocity.length() > 1.0:
		var target_basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, delta * 5.0)

func visual_align(delta):
	var target_basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, delta * 2.0)

func provjeri_sudar():
	if ray.is_colliding():
		var hit = ray.get_collider()
		# Ignoriramo igraca da se ne sudarimo sami sa sobom pri ispaljivanju
		if not hit.is_in_group("player"):
			detonate(ray.get_collision_point())

func detonate(point):
	emit_signal("raketa_unistena")
	if explosion_scene:
		var e = explosion_scene.instantiate()
		get_tree().root.add_child(e)
		e.global_position = point
	queue_free()
