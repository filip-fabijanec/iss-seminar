extends Control

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	$VBoxContainer/BtnStart.pressed.connect(_on_start_pressed)
	$VBoxContainer/BtnQuit.pressed.connect(_on_quit_pressed)

func _on_start_pressed():
	print("⚔️ KREĆEMO U BITKU!")
	get_tree().change_scene_to_file("res://node_3d.tscn") 

func _on_quit_pressed():
	get_tree().quit()
