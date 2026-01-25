extends Node3D

@onready var particles = $GPUParticles3D
@onready var audio = $AudioStreamPlayer3D 
@onready var debris = $Debris
@onready var smoke = $Smoke
@onready var fire = $Fire

func _ready():
	print("💥 Eksplozija stvorena na poziciji: ")
	
	if particles:
		particles.one_shot = true
		particles.emitting = true
		debris.emitting = true
		smoke.emitting = true	
		fire.emitting = true
	
	if audio:
		audio.pitch_scale = randf_range(0.8, 1.2) 
		audio.play()
	else:
		print("❌ Nema AudioStreamPlayer3D noda!")

	await get_tree().create_timer(3.0).timeout
	queue_free()
