extends Node3D

@onready var particles = $GPUParticles3D
# Pretpostavljam da se čvor zove AudioStreamPlayer3D
@onready var audio = $AudioStreamPlayer3D 
@onready var debris = $Debris
@onready var smoke = $Smoke
@onready var fire = $Fire

func _ready():
	print("💥 Eksplozija stvorena na poziciji: ")
	
	# 1. POKRENI ČESTICE
	if particles:
		particles.one_shot = true
		particles.emitting = true
		debris.emitting = true
		smoke.emitting = true	
		fire.emitting = true
	
	# 2. POKRENI ZVUK
	if audio:
		# Malo variramo zvuk da ne zvuči robotski isto svaki put
		audio.pitch_scale = randf_range(0.8, 1.2) 
		audio.play()
	else:
		print("❌ Nema AudioStreamPlayer3D noda!")

	# 3. ČIŠĆENJE
	# Čekamo malo dulje (npr. 3 sekunde) da budemo sigurni 
	# da je i zvuk i dim gotov prije brisanja.
	await get_tree().create_timer(3.0).timeout
	queue_free()
