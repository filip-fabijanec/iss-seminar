extends CanvasLayer

@export var aircraft: RigidBody3D

@onready var airspeed_label: Label = $Airspeed
@onready var altitude_label: Label = $Altitude
@onready var throttle_label: Label = $Throttle
const MAP_MIN_HEIGHT := 0.0

func _process(delta):
	if aircraft == null:
		return
	var speed_mps := aircraft.linear_velocity.length()
	var speed_kmh := speed_mps * 3.6


	# ======================
	# AIRSPEED (km/h)
	# ======================
	if speed_kmh < 140.0:
		airspeed_label.modulate = Color.RED
	else:
		airspeed_label.modulate = Color.WHITE
	
	

	airspeed_label.text = "AIRSPEED: %d km/h" % int(speed_kmh)

	# ======================
	# ALTITUDE (QNH)
	# ======================
	var altitude := aircraft.global_position.y - MAP_MIN_HEIGHT
	altitude_label.text = "ALTITUDE: %d m" % int(altitude)
	
	# ======================
	# THROTTLE (%)
	# ======================
	var throttle_percent := int(aircraft.throttle * 100.0)
	throttle_label.text = "THROTTLE: %d %%" % throttle_percent
