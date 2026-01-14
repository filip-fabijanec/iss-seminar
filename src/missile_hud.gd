extends Control

# Reference to the missile
var missile: CharacterBody3D = null

# UI labels
@onready var speed_label = $VBoxContainer/SpeedLabel
@onready var altitude_label = $VBoxContainer/AltitudeLabel
@onready var pitch_label = $VBoxContainer/PitchLabel
@onready var yaw_label = $VBoxContainer/YawLabel
@onready var time_label = $VBoxContainer/TimeLabel
@onready var distance_label = $VBoxContainer/DistanceLabel
@onready var position_label = $VBoxContainer/PositionLabel

func _ready():
	# Try to find the missile in the scene
	find_missile()

func _process(_delta):
	if missile and is_instance_valid(missile):
		update_hud()
	else:
		# Try to find missile again
		find_missile()

func find_missile():
	# Look for RaketaManual node in the scene
	var root = get_tree().root
	missile = find_node_by_type(root, "RaketaManual")

func find_node_by_type(node: Node, type_name: String) -> Node:
	if node.name == type_name:
		return node
	for child in node.get_children():
		var result = find_node_by_type(child, type_name)
		if result:
			return result
	return null

func update_hud():
	# Get data from missile
	var speed = missile.get_speed()
	var altitude = missile.get_altitude()
	var orientation = missile.get_orientation()
	var flight_time = missile.get_flight_time()
	var distance = missile.get_distance()
	var pos = missile.global_position
	
	# Update labels
	speed_label.text = "Brzina: %.1f m/s" % speed
	altitude_label.text = "Visina: %.1f m" % altitude
	pitch_label.text = "Pitch: %.1f°" % orientation.x
	yaw_label.text = "Yaw: %.1f°" % orientation.y
	time_label.text = "Vrijeme: %.1f s" % flight_time
	distance_label.text = "Udaljenost: %.1f m" % distance
	position_label.text = "Pozicija: (%.1f, %.1f, %.1f)" % [pos.x, pos.y, pos.z]

func set_missile(m: CharacterBody3D):
	missile = m
