extends Area3D

# === SIGNAL ZA PLAYER ===
signal raketa_unistena

# === KONFIGURACIJA ===
@export var masa = 10.0
@export var potisak = 5000.0
@export var koeficijent_otpora = 0.15
@export var maksimalna_brzina = 750.0
@export var brzina_rotacije = 1.2
@export var gubitak_brzine_pri_skretanju = 0.92
@export var dodatni_otpor_pri_skretanju = 2.5
@export var explosion_scene: PackedScene

# Homing parametri
@export var homing_speed = 4.0
@export var homing_strength = 0.85

# === VARIJABLE ===
var brzina_vektor = Vector3.ZERO
var ubrzanje = Vector3.ZERO
var inicijalni_smjer_postavljen = false
var trenutno_skretanje = 0.0

var tip_rakete: int = 0  # 0=Dumb, 1=Manual, 2=Homing
var locked_target: Node3D = null

const GRAVITACIJA = Vector3(0, -9.81, 0)
const MAX_DOLET = 8000.0
var prijedjena_udaljenost = 0.0

@onready var ray = $RayCast3D

func _ready():
	# Kreiraj marker za poziciju kamere
	var cam_marker = Marker3D.new()
	cam_marker.name = "CameraMarker"
	add_child(cam_marker)
	cam_marker.position = Vector3(0, 0.5, -2.0)
	cam_marker.rotation_degrees.y = 180.0  # Okreni da gleda prema raketi

func postavi_pocetnu_brzinu(smjer: Vector3):
	brzina_vektor = smjer.normalized() * 100.0
	inicijalni_smjer_postavljen = true
	print("🚀 Raketa startana u smjeru: ", smjer)

func postavi_raketu(tip: int, meta: Node3D = null):
	tip_rakete = tip
	locked_target = meta
	print("🚀 Raketa postavljena - Tip: ", tip)
	if meta:
		print("   Meta: ", meta.name)

func ignoriraj_strijelca(strijelac: Node):
	if ray:
		ray.add_exception(strijelac)

func _physics_process(delta):
	if not inicijalni_smjer_postavljen:
		brzina_vektor = -transform.basis.z * 100.0
		inicijalni_smjer_postavljen = true
	
	# LOGIKA PO TIPU RAKETE
	if tip_rakete == 2 and locked_target and is_instance_valid(locked_target):
		# AA HOMING - Automatski prati metu
		homing_kontrola(delta)
	elif tip_rakete == 1:
		# WIRE GUIDED - Manualna kontrola
		trenutno_skretanje = kontroliraj_orijentaciju(delta)
	# tip 0 (DIRECT) - Bez kontrole, samo leti ravno
	
	# Fizika
	var ukupna_sila = izracunaj_sile()
	ubrzanje = ukupna_sila / masa
	brzina_vektor += ubrzanje * delta
	
	if brzina_vektor.length() > maksimalna_brzina:
		brzina_vektor = brzina_vektor.normalized() * maksimalna_brzina
	
	global_position += brzina_vektor * delta
	prijedjena_udaljenost += brzina_vektor.length() * delta
	
	# Raketa se orijentira prema smjeru leta
	if brzina_vektor.length() > 0.1:
		var target_transform = global_transform.looking_at(global_position + brzina_vektor, Vector3.UP)
		global_transform = global_transform.interpolate_with(target_transform, delta * 5.0)
	
	# Provjera doleta
	if prijedjena_udaljenost > MAX_DOLET:
		print("🚀 Raketa dosegla maksimalni domet")
		emit_signal("raketa_unistena")
		queue_free()
		return
	
	provjeri_sudar()

func homing_kontrola(delta):
	# Smjer prema meti
	var smjer_do_mete = (locked_target.global_position - global_position).normalized()
	
	# Trenutni smjer leta
	var trenutni_smjer = brzina_vektor.normalized()
	
	# Interpoliraj prema meti
	var novi_smjer = trenutni_smjer.lerp(smjer_do_mete, homing_strength * delta * homing_speed)
	
	# Zadrži brzinu, samo promijeni smjer
	var trenutna_brzina = brzina_vektor.length()
	brzina_vektor = novi_smjer.normalized() * trenutna_brzina
	
	# Debug print svakih 0.5s
	if int(Time.get_ticks_msec()) % 500 < 50:
		var udaljenost = global_position.distance_to(locked_target.global_position)
		print("🎯 Homing: %.0fm do mete" % udaljenost)

func kontroliraj_orijentaciju(delta) -> float:
	var ukupno_skretanje = 0.0
	
	# LIJEVO (F)
	if Input.is_action_pressed("missile_yaw_left"):
		rotate_y(brzina_rotacije * delta)
		brzina_vektor = brzina_vektor.rotated(Vector3.UP, brzina_rotacije * delta)
		ukupno_skretanje += abs(brzina_rotacije * delta)
		
	# DESNO (H)
	if Input.is_action_pressed("missile_yaw_right"):
		rotate_y(-brzina_rotacije * delta)
		brzina_vektor = brzina_vektor.rotated(Vector3.UP, -brzina_rotacije * delta)
		ukupno_skretanje += abs(brzina_rotacije * delta)
	
	# GORE (T)
	if Input.is_action_pressed("missile_pitch_up"):
		rotate_object_local(Vector3.RIGHT, -brzina_rotacije * delta)
		var right = transform.basis.x
		brzina_vektor = brzina_vektor.rotated(right, -brzina_rotacije * delta)
		ukupno_skretanje += abs(brzina_rotacije * delta)
		
	# DOLJE (G)
	if Input.is_action_pressed("missile_pitch_down"):
		rotate_object_local(Vector3.RIGHT, brzina_rotacije * delta)
		var right = transform.basis.x
		brzina_vektor = brzina_vektor.rotated(right, brzina_rotacije * delta)
		ukupno_skretanje += abs(brzina_rotacije * delta)
	
	rotation.x = clamp(rotation.x, deg_to_rad(-80), deg_to_rad(80))
	
	# Gubitak brzine pri skretanju
	if ukupno_skretanje > 0.001:
		var faktor_brzine = brzina_vektor.length() / maksimalna_brzina
		var gubitak = 1.0 - ((1.0 - gubitak_brzine_pri_skretanju) * faktor_brzine * ukupno_skretanje * 10.0)
		gubitak = clamp(gubitak, 0.85, 1.0)
		brzina_vektor *= gubitak
	
	return ukupno_skretanje

func izracunaj_sile() -> Vector3:
	var F_potisak = brzina_vektor.normalized() * potisak if brzina_vektor.length() > 0.01 else Vector3.ZERO
	var F_gravitacija = GRAVITACIJA * masa
	
	var brzina_skalar = brzina_vektor.length()
	var F_otpor = Vector3.ZERO
	if brzina_skalar > 0.01:
		var multiplikator_otpora = 1.0 + (trenutno_skretanje * dodatni_otpor_pri_skretanju * 100.0)
		F_otpor = -brzina_vektor.normalized() * koeficijent_otpora * brzina_skalar * brzina_skalar * multiplikator_otpora
	
	return F_potisak + F_gravitacija + F_otpor

func provjeri_sudar():
	if not ray.is_colliding():
		return
	
	var pogodjeni_objekt = ray.get_collider()
	
	if "Player" in pogodjeni_objekt.name or "vojnik" in pogodjeni_objekt.name or pogodjeni_objekt.is_in_group("player"):
		ray.add_exception(pogodjeni_objekt)
		return
	
	print("🎯 Pogodak! Cilj: ", pogodjeni_objekt.name)
	detonate(ray.get_collision_point())

func detonate(point: Vector3):
	print("💥 EKSPLOZIJA na: ", point)
	emit_signal("raketa_unistena")
	
	if explosion_scene:
		var expl = explosion_scene.instantiate()
		get_tree().root.add_child(expl)
		expl.global_position = point
	
	queue_free()
