extends Node3D

@onready var fire_sound: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var area: Area3D = $Area3D
@export var explosion_scene: PackedScene

var target_pos: Vector3
var speed := 1200.0
var alive := true

func start(from: Vector3, to: Vector3):
	global_position = from
	target_pos = to
	look_at(to, Vector3.UP)

	if fire_sound.stream != null:
		fire_sound.play()

	area.body_entered.connect(_on_body_entered)
	
func _process(delta):
	if not alive:
		return

	var move_vec = -transform.basis.z * speed * delta
	global_translate(move_vec)

	var space = get_world_3d().direct_space_state
	var from = global_position
	var to = global_position + move_vec

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.collision_mask = 1 << 0

	var result = space.intersect_ray(query)
	if result:
		print("TLO POGOĐENO")
		_hit(result.position)

	
func _on_body_entered(body: Node):
	if body.is_in_group("airplane"):
		return

	print("HIT BODY:", body.name)

	if body.is_in_group("ground"):
		print("TLO POGOĐENO")
		_hit(global_position)

func _hit(pos: Vector3):
	alive = false

	if explosion_scene != null:
		var explosion = explosion_scene.instantiate()
		get_tree().get_current_scene().add_child(explosion)
		explosion.global_position = pos
		explosion.explode()
	queue_free()
