extends CanvasLayer

# @onready varijable - PAZI da su imena GlavniUI i VBoxContainer točna!
@onready var label_winner = $GlavniUI/VBoxContainer/LabelWinner
@onready var btn_restart = $GlavniUI/VBoxContainer/BtnRestart
@onready var btn_quit = $GlavniUI/VBoxContainer/BtnQuit
@onready var btn_menu = $GlavniUI/VBoxContainer/BtnMenu

func _ready():
	print("✅ WinnerScene: _ready() pokrenut")
	
	# 1. Oslobodi miš (obavezno!)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# 2. Direktno čitamo iz Autoloada (puno sigurnije)
	# GameData je ime koje si upisao u Autoload tabu
	var ime = GameData.pobjednik_ime
	
	if ime == "": ime = "VOJNIK" # Sigurnosni backup ako je prazno
	
	print("🏆 Pobjednik iz GameData: ", ime)
	
	if label_winner:
		label_winner.text = ime + " JE POBIJEDIO!"
		# Postavi bijelu boju i veličinu da se vidi preko sivila
		label_winner.add_theme_color_override("font_color", Color.WHITE)
	else:
		print("❌ GREŠKA: LabelWinner nije nađen na putanji!")

	# 3. Povezivanje signala
	btn_restart.pressed.connect(_on_restart_pressed)
	btn_menu.pressed.connect(_on_menu_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)

func _on_restart_pressed():
	# Vraća direktno u akciju
	get_tree().change_scene_to_file("res://node_3d.tscn")

func _on_menu_pressed():
	# Vraća na početni ekran s kontrolama
	get_tree().change_scene_to_file("res://MainScene.tscn")

func _on_quit_pressed():
	get_tree().quit()
