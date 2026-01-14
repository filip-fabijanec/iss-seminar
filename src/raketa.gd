extends Area3D

@export var brzina = 3 # Povećaj brzinu za raketu
@export var explosion_scene: PackedScene 

@onready var ray = $RayCast3D
const g = 1.2

func _physics_process(delta):
	# 1. Pomakni raketu
	global_position -= transform.basis.z * brzina * delta
	global_position -= transform.basis.y * g * delta
	
	# 2. Provjeri sudare
	if ray.is_colliding():
		var pogodjeni_objekt = ray.get_collider()
		
		if "Player" in pogodjeni_objekt.name or "vojnik" in pogodjeni_objekt.name or pogodjeni_objekt.is_in_group("player"):
			ray.add_exception(pogodjeni_objekt)
			
			return
			
		print("🚧 RayCast detektirao cilj: ", pogodjeni_objekt.name)
		detonate(ray.get_collision_point())

func detonate(point):
	print("🔥 BOOM!")
	if explosion_scene:
		var expl = explosion_scene.instantiate()
		get_tree().root.add_child(expl)
		
		# Postavi eksploziju na točku sudara
		expl.global_position = point
	
	queue_free()
