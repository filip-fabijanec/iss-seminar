extends Area3D

# === SIGNAL ZA PLAYER ===
signal raketa_unistena

# === OPCIJA D: Dinamički model s diferencijalnim jednadžbama ===
@export var masa = 10.0
@export var potisak = 5000.0
@export var koeficijent_otpora = 0.15
@export var maksimalna_brzina = 750.0
@export var brzina_rotacije = 1.2
@export var explosion_scene: PackedScene 

var brzina_vektor = Vector3.ZERO
var ubrzanje = Vector3.ZERO
var inicijalni_smjer_postavljen = false  # <--- FLAG

@onready var ray = $RayCast3D

const GRAVITACIJA = Vector3(0, -9.81, 0)
const MAX_DOLET = 8000.0
var prijedjena_udaljenost = 0.0

func _ready():
	# NE postavljaj brzinu ovdje - čekaj poziv iz player skripte
	pass

func postavi_pocetnu_brzinu(smjer: Vector3):
	"""Poziva se iz player skripte odmah nakon spawna"""
	brzina_vektor = smjer.normalized() * 100.0
	inicijalni_smjer_postavljen = true
	print("🚀 Raketa startana u smjeru: ", smjer)

func _physics_process(delta):
	# Ako brzina još nije postavljena, koristi transform kao fallback
	if not inicijalni_smjer_postavljen:
		brzina_vektor = -transform.basis.z * 100.0
		inicijalni_smjer_postavljen = true
	
	kontroliraj_orijentaciju(delta)
	
	var ukupna_sila = izracunaj_sile()
	ubrzanje = ukupna_sila / masa
	brzina_vektor += ubrzanje * delta
	
	if brzina_vektor.length() > maksimalna_brzina:
		brzina_vektor = brzina_vektor.normalized() * maksimalna_brzina
	
	global_position += brzina_vektor * delta
	prijedjena_udaljenost += brzina_vektor.length() * delta
	
	if prijedjena_udaljenost > MAX_DOLET:
		print("🚀 Raketa dosegla maksimalni domet")
		emit_signal("raketa_unistena")
		queue_free()
		return
	
	provjeri_sudar()

func kontroliraj_orijentaciju(delta):
	if Input.is_key_pressed(KEY_LEFT):
		rotate_y(brzina_rotacije * delta)
		# Ažuriraj i brzinu da prati rotaciju
		brzina_vektor = brzina_vektor.rotated(Vector3.UP, brzina_rotacije * delta)
		
	if Input.is_key_pressed(KEY_RIGHT):
		rotate_y(-brzina_rotacije * delta)
		brzina_vektor = brzina_vektor.rotated(Vector3.UP, -brzina_rotacije * delta)
	
	if Input.is_key_pressed(KEY_UP):
		rotate_object_local(Vector3.RIGHT, -brzina_rotacije * delta)
		var right = transform.basis.x
		brzina_vektor = brzina_vektor.rotated(right, -brzina_rotacije * delta)
		
	if Input.is_key_pressed(KEY_DOWN):
		rotate_object_local(Vector3.RIGHT, brzina_rotacije * delta)
		var right = transform.basis.x
		brzina_vektor = brzina_vektor.rotated(right, brzina_rotacije * delta)
	
	rotation.x = clamp(rotation.x, deg_to_rad(-80), deg_to_rad(80))

func izracunaj_sile() -> Vector3:
	# Potisak u smjeru trenutne brzine
	var F_potisak = brzina_vektor.normalized() * potisak if brzina_vektor.length() > 0.01 else Vector3.ZERO
	var F_gravitacija = GRAVITACIJA * masa
	
	var brzina_skalar = brzina_vektor.length()
	var F_otpor = Vector3.ZERO
	if brzina_skalar > 0.01:
		F_otpor = -brzina_vektor.normalized() * koeficijent_otpora * brzina_skalar * brzina_skalar
	
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
