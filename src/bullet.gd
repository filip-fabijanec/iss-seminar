extends Node3D

@onready var fire_sound: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var area: Area3D = $Area3D
@export var explosion_scene: PackedScene

# --- NOVO: Parametri za blizinu ---
@export var proximity_radius := 15.0 # Ako padne unutar 15m od vojnika, avion pobjeđuje
var meta_vojnik: Node3D = null

var target_pos: Vector3
var speed := 1200.0
var alive := true

func _ready():
	# Automatski pronađi vojnika (mora biti u grupi "player")
	var igrači = get_tree().get_nodes_in_group("player")
	if igrači.size() > 0:
		meta_vojnik = igrači[0]

func start(from: Vector3, to: Vector3):
	global_position = from
	target_pos = to
	look_at(to, Vector3.UP)
	if fire_sound.stream != null:
		fire_sound.play()
	area.body_entered.connect(_on_body_entered)
	
func _process(delta):
	if not alive: return

	# 1. PROVJERA BLIZINE (Proximity check)
	# Ako je raketa dovoljno blizu vojnika, aktiviraj pobjedu odmah
	if is_instance_valid(meta_vojnik):
		var udaljenost = global_position.distance_to(meta_vojnik.global_position)
		if udaljenost < proximity_radius:
			print("💥 AVION PROXIMITY POGODAK! Udaljenost: ", udaljenost)
			aktiviraj_game_over("AVION", global_position)
			return

	# 2. KRETANJE
	var move_vec = -transform.basis.z * speed * delta
	global_translate(move_vec)

	# 3. RAYCAST SUDAR (Direktan udarac)
	var space = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + move_vec)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var result = space.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider.is_in_group("player"):
			aktiviraj_game_over("AVION", result.position)
		else:
			# Ako pogodiš tlo, provjeri još jednom je li vojnik bio u radijusu eksplozije
			provjeri_eksploziju_u_blizini(result.position)
			_hit(result.position)

func provjeri_eksploziju_u_blizini(pos_udarca: Vector3):
	if is_instance_valid(meta_vojnik):
		if pos_udarca.distance_to(meta_vojnik.global_position) < proximity_radius:
			print("💥 TLO POGOĐENO, ALI JE VOJNIK BLIZU! Priznajem pobjedu.")
			aktiviraj_game_over("AVION", pos_udarca)

func _on_body_entered(body: Node):
	if not alive: return
	if body.is_in_group("airplane"): return

	if body.is_in_group("player"):
		aktiviraj_game_over("AVION", global_position)
	else:
		_hit(global_position)

func aktiviraj_game_over(pobjednik: String, tacka: Vector3):
	if not alive: return # Osiguranje da se ne pokrene dvaput
	
	print("✈️ AVION JE POBJEDIO!")
	alive = false 
	hide()

	if explosion_scene:
		var e = explosion_scene.instantiate()
		get_tree().get_current_scene().add_child(e)
		e.global_position = tacka
		if e.has_method("explode"): e.explode()

	var gd = get_node_or_null("/root/GameData")
	if gd:
		gd.pobjednik_ime = "AVION"

	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://WinnerScene.tscn")
	queue_free()

func _hit(pos: Vector3):
	alive = false
	if explosion_scene != null:
		var explosion = explosion_scene.instantiate()
		get_tree().get_current_scene().add_child(explosion)
		explosion.global_position = pos
		if explosion.has_method("explode"):
			explosion.explode()
	queue_free()
