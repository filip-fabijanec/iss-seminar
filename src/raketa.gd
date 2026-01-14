extends Area3D

@export var brzina = 3
@export var brzina_skretanja = 1.5 # Smanjena brzina skretanja
@export var explosion_scene: PackedScene 
@onready var ray = $RayCast3D

const g = 0.7 # Smanjena gravitacija (bilo 1.2)
var je_kontrolirana = true

func _physics_process(delta):
	# 1. Kontrola rakete strelicama
	if je_kontrolirana:
		kontroliraj_raketu(delta)
	
	# 2. Pomakni raketu naprijed
	global_position -= transform.basis.z * brzina * delta
	#global_position -= transform.basis.y * g * delta
	
	# 3. Provjeri sudare
	if ray.is_colliding():
		var pogodjeni_objekt = ray.get_collider()
		
		if "Player" in pogodjeni_objekt.name or "vojnik" in pogodjeni_objekt.name or pogodjeni_objekt.is_in_group("player"):
			ray.add_exception(pogodjeni_objekt)
			return
			
		print("🚧 RayCast detektirao cilj: ", pogodjeni_objekt.name)
		detonate(ray.get_collision_point())

func kontroliraj_raketu(delta):
	# Lijevo-desno (rotacija oko Y osi)
	if Input.is_key_pressed(KEY_LEFT):
		rotate_y(brzina_skretanja * delta)
	if Input.is_key_pressed(KEY_RIGHT):
		rotate_y(-brzina_skretanja * delta)
	
	# Gore-dolje (rotacija oko X osi) - SOFT
	if Input.is_key_pressed(KEY_UP):
		rotate_object_local(Vector3.RIGHT, -brzina_skretanja * delta * 0.7) # Sporije gore
	if Input.is_key_pressed(KEY_DOWN):
		rotate_object_local(Vector3.RIGHT, brzina_skretanja * delta * 0.7) # Sporije dolje
	
	# Ograniči nagib da se ne prevrne
	rotation.x = clamp(rotation.x, -PI/3, PI/3) # Ograniči na ±60°

func detonate(point):
	print("🔥 BOOM!")
	if explosion_scene:
		var expl = explosion_scene.instantiate()
		get_tree().root.add_child(expl)
		expl.global_position = point
	
	queue_free()
