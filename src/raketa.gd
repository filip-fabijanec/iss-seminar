extends Area3D

@export var brzina = 50 # Povećaj brzinu za raketu
@export var explosion_scene: PackedScene 

@onready var ray = $RayCast3D

func _physics_process(delta):
	# 1. Pomakni raketu
	global_position -= transform.basis.z * brzina * delta
	
	# 2. Provjeri sudare
	if ray.is_colliding():
		var pogodjeni_objekt = ray.get_collider()
		
		# --- POPRAVAK OVDJE ---
		# Provjeravamo sadrži li ime "Player" ili "vojnik"
		if "Player" in pogodjeni_objekt.name or "vojnik" in pogodjeni_objekt.name or pogodjeni_objekt.is_in_group("player"):
			
			# OVO JE KLJUČNO: Kažemo RayCastu da ovaj objekt (igrača)
			# doda na listu iznimki. RayCast će od idućeg frame-a
			# prolaziti KROZ igrača kao da ne postoji.
			ray.add_exception(pogodjeni_objekt)
			
			return # Prekini funkciju, nemoj eksplodirati
			
		# Ako nije igrač, onda eksplodiraj
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
