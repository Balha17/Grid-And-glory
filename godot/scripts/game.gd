extends Node3D

const SERVER_URL := "wss://grid-and-glory.onrender.com/ws"
const FIELD_LENGTH := 48.0
const FIELD_WIDTH := 28.0

var socket := WebSocketPeer.new()
var connected := false
var player_id := ""
var session_token := ""
var sequence := 0
var locale := "en"
var display_name := "Striker"
var current_token := ""
var current_options: Array = []
var match_id := ""
var phase := "home"
var my_zone := 0
var rival_zone := 0
var my_goals := 0
var rival_goals := 0
var you_are_shooting := false
var selected := false

var stadium_root: Node3D
var camera: Camera3D
var ball: MeshInstance3D
var home_player: Node3D
var away_player: Node3D
var home_team: Array[Node3D] = []
var away_team: Array[Node3D] = []
var hud: CanvasLayer
var match_layer: Control
var home_layer: Control
var menu_title: Label
var menu_subtitle: Label
var home_primary_button: Button
var home_secondary_button: Button
var home_sound_button: Button
var match_sound_button: Button
var sound_muted := false
var title_label: Label
var status_label: Label
var question_label: Label
var clue_label: Label
var score_label: Label
var timer_label: Label
var options_box: VBoxContainer
var action_box: HBoxContainer
var connect_button: Button
var locale_button: Button
var pitch_status: Label
var countdown_deadline := 0
var countdown_duration := 0
var audio_players: Dictionary = {}
var audio_requests: Dictionary = {}

func _ready() -> void:
	stadium_root = Node3D.new()
	stadium_root.name = "MatchOnly3DStadium"
	stadium_root.visible = false
	add_child(stadium_root)
	_build_stadium()
	_build_hud()
	_setup_audio()
	_load_settings()
	_show_home()
	set_process(true)

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		connected = true
		while socket.get_available_packet_count() > 0:
			var raw := socket.get_packet().get_string_from_utf8()
			var frame = JSON.parse_string(raw)
			if frame is Dictionary:
				_handle_frame(frame)
	elif state == WebSocketPeer.STATE_CLOSED:
		connected = false
	if countdown_deadline > 0 and phase in ["question_open", "shooting_chance"]:
		var left := maxi(0, int(ceil(float(countdown_deadline - Time.get_ticks_msec()) / 1000.0)))
		timer_label.text = str(left)
		if left == 0:
			timer_label.modulate = Color(1.0, 0.3, 0.25)
	else:
		timer_label.text = ""
	if stadium_root.visible:
		_update_pitch_state()

func _build_stadium() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.018, 0.035, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.82, 0.94)
	env.ambient_light_energy = 0.8
	world.environment = env
	stadium_root.add_child(world)

	camera = Camera3D.new()
	camera.position = Vector3(0, 34, 38)
	camera.rotation_degrees = Vector3(-41, 0, 0)
	camera.fov = 54
	stadium_root.add_child(camera)
	camera.current = true

	var stadium_light := DirectionalLight3D.new()
	stadium_light.rotation_degrees = Vector3(-55, -25, 0)
	stadium_light.light_energy = 1.25
	stadium_light.shadow_enabled = true
	stadium_root.add_child(stadium_light)

	_box("StadiumBase", Vector3(0, -0.65, 0), Vector3(34, 1.1, 56), Color(0.035, 0.12, 0.11))
	_box("Pitch", Vector3(0, 0, 0), Vector3(FIELD_WIDTH, 0.12, FIELD_LENGTH), Color(0.08, 0.39, 0.22))
	for i in range(8):
		var z := -FIELD_LENGTH / 2.0 + (i + 0.5) * FIELD_LENGTH / 8.0
		_box("MowStripe", Vector3(0, 0.07, z), Vector3(FIELD_WIDTH, 0.025, FIELD_LENGTH / 8.0), Color(0.09 if i % 2 == 0 else 0.075, 0.43 if i % 2 == 0 else 0.37, 0.23))
	_line("TouchlineL", Vector3(-FIELD_WIDTH/2, 0.12, 0), Vector3(0.09, 0.035, FIELD_LENGTH), Color.WHITE)
	_line("TouchlineR", Vector3(FIELD_WIDTH/2, 0.12, 0), Vector3(0.09, 0.035, FIELD_LENGTH), Color.WHITE)
	_line("GoalLineTop", Vector3(0, 0.12, -FIELD_LENGTH/2), Vector3(FIELD_WIDTH, 0.035, 0.09), Color.WHITE)
	_line("GoalLineBottom", Vector3(0, 0.12, FIELD_LENGTH/2), Vector3(FIELD_WIDTH, 0.035, 0.09), Color.WHITE)
	_line("Halfway", Vector3(0, 0.14, 0), Vector3(FIELD_WIDTH, 0.035, 0.09), Color.WHITE)
	_circle("CenterCircle", Vector3(0, 0.15, 0), 5.2, 0.07, Color.WHITE)
	_circle("CenterSpot", Vector3(0, 0.18, 0), 0.22, 0.16, Color.WHITE)
	for zsign in [-1, 1]:
		var z := float(zsign) * (FIELD_LENGTH/2.0 - 6.0)
		var box_z := z - float(zsign)*2.0
		for x in [-7.5, 7.5]:
			_line("PenaltySide", Vector3(x,0.17,box_z), Vector3(0.07,0.035,9), Color.WHITE)
		_line("PenaltyFront", Vector3(0,0.17,z-float(zsign)*4.5), Vector3(15,0.035,0.07), Color.WHITE)
		for x in [-3.5, 3.5]:
			_line("GoalAreaSide", Vector3(x,0.18,z-float(zsign)*1.0), Vector3(0.07,0.035,4), Color.WHITE)
		_line("GoalAreaFront", Vector3(0,0.18,z-float(zsign)*3.0), Vector3(7,0.035,0.07), Color.WHITE)
		_circle("PenaltySpot", Vector3(0, 0.19, z - float(zsign)*4.0), 0.2, 0.12, Color.WHITE)
		_build_goal(zsign)
	var home_positions := [Vector3(0,0,21), Vector3(-10,0,14), Vector3(-3.3,0,15), Vector3(3.3,0,15), Vector3(10,0,14), Vector3(-7,0,5), Vector3(0,0,7), Vector3(7,0,5), Vector3(-8,0,-6), Vector3(0,0,-8), Vector3(8,0,-6)]
	var away_positions := [Vector3(0,0,-21), Vector3(10,0,-14), Vector3(3.3,0,-15), Vector3(-3.3,0,-15), Vector3(-10,0,-14), Vector3(7,0,-5), Vector3(0,0,-7), Vector3(-7,0,-5), Vector3(8,0,6), Vector3(0,0,8), Vector3(-8,0,6)]
	for i in range(11):
		var h := _make_player("HOME_" + str(i+1), Color(0.12, 0.58, 1.0))
		h.position = home_positions[i]
		stadium_root.add_child(h)
		home_team.append(h)
		var a := _make_player("AWAY_" + str(i+1), Color(1.0, 0.34, 0.19))
		a.position = away_positions[i]
		stadium_root.add_child(a)
		away_team.append(a)
	home_player = home_team[9]
	away_player = away_team[9]
	ball = MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.42
	ball_mesh.height = 0.84
	ball.mesh = ball_mesh
	ball.position = Vector3(0, 0.48, 0)
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.97, 0.97, 0.92)
	ball_mat.roughness = 0.35
	ball.material_override = ball_mat
	stadium_root.add_child(ball)
	_add_stands()

func _add_stands() -> void:
	for side in [-1, 1]:
		_box("Stand", Vector3(float(side)*17.2, 2.0, 0), Vector3(5.2, 4.4, 58), Color(0.055, 0.09, 0.14))
		for row in range(4):
			for col in range(20):
				var seat := MeshInstance3D.new()
				var m := BoxMesh.new()
				m.size = Vector3(0.42, 0.35, 0.42)
				seat.mesh = m
				seat.position = Vector3(float(side)*17.2, 3.2 + float(row)*0.72, -25.0 + float(col)*2.6)
				var mat := StandardMaterial3D.new()
				mat.albedo_color = [Color(0.08,0.45,0.75), Color(0.9,0.28,0.17), Color(0.88,0.9,0.94)][(row+col)%3]
				seat.material_override = mat
				stadium_root.add_child(seat)

func _build_goal(sign: int) -> void:
	var z := float(sign) * (FIELD_LENGTH/2.0 + 0.45)
	var frame_color := Color(0.94, 0.96, 1.0)
	for x in [-3.2, 3.2]:
		_box("GoalPost", Vector3(x, 1.45, z), Vector3(0.22, 2.9, 0.22), frame_color)
	_box("GoalBar", Vector3(0, 2.9, z), Vector3(6.6, 0.22, 0.22), frame_color)
	for i in range(1, 8):
		_line("NetVertical", Vector3(-3.1 + float(i)*0.88, 0.2, z + float(sign)*1.7), Vector3(0.035, 2.5, 0.035), Color(0.78,0.86,0.92,0.5))
	for i in range(1, 4):
		_line("NetHorizontal", Vector3(0, float(i)*0.65, z + float(sign)*1.7), Vector3(6.2, 0.025, 0.025), Color(0.78,0.86,0.92,0.5))

func _make_player(label: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = label
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.67, 0.43, 0.30)
	root.add_child(_player_capsule("Shirt", 0.43, 1.18, color, Vector3(0, 1.48, 0)))
	root.add_child(_player_capsule("Shorts", 0.38, 0.55, Color(0.055,0.075,0.11), Vector3(0, 0.82, 0)))
	root.add_child(_player_sphere("Head", 0.29, skin, Vector3(0, 2.32, 0)))
	var hair := StandardMaterial3D.new()
	hair.albedo_color = Color(0.045,0.035,0.03)
	root.add_child(_player_sphere("Hair", 0.30, hair, Vector3(0, 2.51, -0.015)))
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.name = "ArmL" if side < 0 else "ArmR"
		arm.position = Vector3(float(side)*0.48, 1.86, 0)
		root.add_child(arm)
		arm.add_child(_player_capsule("Sleeve", 0.16, 0.72, color, Vector3(0, -0.30, 0)))
		arm.add_child(_player_sphere("Hand", 0.14, skin, Vector3(0, -0.68, 0)))
		var leg := Node3D.new()
		leg.name = "LegL" if side < 0 else "LegR"
		leg.position = Vector3(float(side)*0.20, 0.72, 0)
		root.add_child(leg)
		leg.add_child(_player_capsule("Sock", 0.14, 0.74, Color(0.91,0.92,0.94), Vector3(0, -0.35, 0)))
		leg.add_child(_player_box("Boot", Vector3(0.26,0.15,0.48), Color(0.035,0.04,0.045), Vector3(0,-0.73,-0.13)))
	return root

func _player_capsule(label: String, radius: float, height: float, color: Color, pos: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	node.mesh = mesh
	node.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.68
	node.material_override = material
	return node

func _player_sphere(label: String, radius: float, material: Material, pos: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	return node

func _player_box(label: String, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	node.material_override = material
	return node

func _box(label: String, pos: Vector3, size: Vector3, color: Color, wire := false) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if wire:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.flags_transparent = true
	node.material_override = mat
	stadium_root.add_child(node)

func _line(label: String, pos: Vector3, size: Vector3, color: Color) -> void:
	_box(label, pos, size, color)

func _circle(label: String, pos: Vector3, radius: float, width: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	ring.name = label
	var torus := TorusMesh.new()
	torus.inner_radius = radius - width/2.0
	torus.outer_radius = radius + width/2.0
	ring.mesh = torus
	ring.position = pos
	ring.rotation_degrees.x = 90
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	stadium_root.add_child(ring)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(root)

	match_layer = Control.new()
	match_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(match_layer)

	var top := PanelContainer.new()
	top.anchor_left = 0.025
	top.anchor_right = 0.975
	top.anchor_top = 0.012
	top.anchor_bottom = 0.155
	top.offset_left = 0
	top.offset_right = 0
	top.offset_top = 0
	top.offset_bottom = 0
	top.add_theme_stylebox_override("panel", _panel_style(Color(0.018,0.055,0.12,0.96), Color(0.22,0.62,1.0), 3))
	match_layer.add_child(top)
	var topbox := VBoxContainer.new()
	topbox.add_theme_constant_override("separation", 2)
	top.add_child(topbox)
	title_label = Label.new()
	title_label.text = "GRID & GLORY  •  MATCHDAY"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color(0.96,0.79,0.38))
	title_label.add_theme_font_size_override("font_size", 19)
	topbox.add_child(title_label)
	score_label = Label.new()
	score_label.text = "YOU  0  —  0  RIVAL"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_color_override("font_color", Color.WHITE)
	score_label.add_theme_font_size_override("font_size", 27)
	topbox.add_child(score_label)
	status_label = Label.new()
	status_label.text = "MATCHDAY"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", Color(0.65,0.82,1.0))
	topbox.add_child(status_label)
	match_sound_button = _make_button("SOUND ON  ♪", Color(0.08,0.20,0.36), Color(0.30,0.63,0.92), 40)
	match_sound_button.pressed.connect(_toggle_sound)
	topbox.add_child(match_sound_button)

	var bottom := PanelContainer.new()
	bottom.anchor_left = 0.025
	bottom.anchor_right = 0.975
	bottom.anchor_top = 0.535
	bottom.anchor_bottom = 0.985
	bottom.offset_left = 0
	bottom.offset_right = 0
	bottom.offset_top = 0
	bottom.offset_bottom = 0
	bottom.add_theme_stylebox_override("panel", _panel_style(Color(0.012,0.035,0.085,0.98), Color(0.20,0.57,0.94), 3))
	match_layer.add_child(bottom)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	bottom.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	pitch_status = Label.new()
	pitch_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pitch_status.add_theme_color_override("font_color", Color(0.48,0.85,1.0))
	pitch_status.add_theme_font_size_override("font_size", 15)
	content.add_child(pitch_status)
	clue_label = Label.new()
	clue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clue_label.custom_minimum_size = Vector2(0, 76)
	clue_label.add_theme_color_override("font_color", Color(1.0,0.82,0.35))
	clue_label.add_theme_font_size_override("font_size", 34)
	clue_label.visible = false
	content.add_child(clue_label)
	question_label = Label.new()
	question_label.text = "Get ready for the next challenge"
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	question_label.custom_minimum_size = Vector2(0, 92)
	question_label.add_theme_color_override("font_color", Color(0.98,0.98,1.0))
	question_label.add_theme_font_size_override("font_size", 23)
	content.add_child(question_label)
	timer_label = Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_color_override("font_color", Color(1.0,0.78,0.25))
	timer_label.add_theme_font_size_override("font_size", 29)
	content.add_child(timer_label)
	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 8)
	content.add_child(options_box)
	action_box = HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_box.add_theme_constant_override("separation", 10)
	content.add_child(action_box)

	home_layer = Control.new()
	home_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(home_layer)
	var backdrop := TextureRect.new()
	backdrop.texture = load("res://assets/menu_stadium_bg.svg")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home_layer.add_child(backdrop)
	var glow := ColorRect.new()
	glow.color = Color(0.025,0.13,0.28,0.72)
	glow.anchor_left = 0
	glow.anchor_right = 1
	glow.anchor_top = 0
	glow.anchor_bottom = 0.46
	glow.offset_left = 0
	glow.offset_right = 0
	glow.offset_top = 0
	glow.offset_bottom = 0
	home_layer.add_child(glow)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 28)
	outer.add_theme_constant_override("margin_right", 28)
	outer.add_theme_constant_override("margin_top", 32)
	outer.add_theme_constant_override("margin_bottom", 28)
	home_layer.add_child(outer)
	var menu := VBoxContainer.new()
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 13)
	outer.add_child(menu)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/grid_glory_icon.svg")
	logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 176)
	menu.add_child(logo)

	menu_title = Label.new()
	menu_title.text = "GRID & GLORY"
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title.add_theme_color_override("font_color", Color(1.0,0.78,0.30))
	menu_title.add_theme_font_size_override("font_size", 38)
	menu_title.add_theme_color_override("font_shadow_color", Color(0,0,0,0.9))
	menu_title.add_theme_constant_override("shadow_offset_x", 2)
	menu_title.add_theme_constant_override("shadow_offset_y", 3)
	menu.add_child(menu_title)

	menu_subtitle = Label.new()
	menu_subtitle.text = "THE ULTIMATE FOOTBALL QUIZ BATTLE"
	menu_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_subtitle.add_theme_color_override("font_color", Color(0.73,0.86,1.0))
	menu_subtitle.add_theme_font_size_override("font_size", 16)
	menu.add_child(menu_subtitle)

	var feature := PanelContainer.new()
	feature.add_theme_stylebox_override("panel", _panel_style(Color(0.035,0.085,0.17,0.96), Color(0.78,0.55,0.20), 2))
	menu.add_child(feature)
	var feature_text := Label.new()
	feature_text.text = "⚽  1v1 FOOTBALL TRIVIA  •  RISE TO LEGEND"
	feature_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feature_text.add_theme_color_override("font_color", Color(1.0,0.88,0.58))
	feature_text.add_theme_font_size_override("font_size", 14)
	feature.add_child(feature_text)

	home_primary_button = _make_button("PLAY ONLINE", Color(0.95,0.57,0.08), Color(1.0,0.83,0.30), 76)
	home_primary_button.add_theme_color_override("font_color", Color(0.10,0.08,0.04))
	home_primary_button.pressed.connect(_on_menu_primary)
	menu.add_child(home_primary_button)
	home_secondary_button = _make_button("PLAY VS AI", Color(0.035,0.27,0.65), Color(0.23,0.66,1.0), 66)
	home_secondary_button.pressed.connect(_on_menu_secondary)
	menu.add_child(home_secondary_button)

	var settings_row := HBoxContainer.new()
	settings_row.alignment = BoxContainer.ALIGNMENT_CENTER
	settings_row.add_theme_constant_override("separation", 12)
	menu.add_child(settings_row)
	home_sound_button = _make_button("SOUND ON  ♪", Color(0.08,0.13,0.25), Color(0.28,0.52,0.82), 50)
	home_sound_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_sound_button.pressed.connect(_toggle_sound)
	settings_row.add_child(home_sound_button)
	locale_button = _make_button("العربية / EN", Color(0.08,0.13,0.25), Color(0.28,0.52,0.82), 50)
	locale_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	locale_button.pressed.connect(_toggle_locale)
	settings_row.add_child(locale_button)

	var footer := Label.new()
	footer.text = "ONLINE DUELS  •  SMART AI  •  FOOTBALL KNOWLEDGE"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Color(0.43,0.62,0.82))
	footer.add_theme_font_size_override("font_size", 11)
	menu.add_child(footer)

	match_layer.visible = false
	home_layer.visible = true

func _panel_style(fill: Color, edge: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0,0,0,0.55)
	style.shadow_size = 12
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _make_button(label: String, fill: Color, edge: Color, height: float) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", 20 if height > 60 else 16)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var normal := _panel_style(fill, edge, 2)
	normal.set_corner_radius_all(16)
	normal.shadow_size = 7
	button.add_theme_stylebox_override("normal", normal)
	var hover := _panel_style(fill.lightened(0.12), edge.lightened(0.1), 3)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", _panel_style(fill.darkened(0.16), edge, 2))
	button.add_theme_stylebox_override("focus", _panel_style(fill, edge.lightened(0.25), 3))
	return button

func _show_home() -> void:
	phase = "home"
	stadium_root.visible = false
	match_layer.visible = false
	home_layer.visible = true
	menu_title.text = "GRID & GLORY"
	menu_subtitle.text = "THE ULTIMATE FOOTBALL QUIZ BATTLE"
	home_primary_button.text = "PLAY ONLINE"
	home_secondary_button.text = "PLAY VS AI"
	question_label.text = "Choose your arena / اختر ساحة المنافسة"
	clue_label.text = ""
	clue_label.visible = false
	_clear_options()
	action_box.visible = true
	status_label.text = "READY FOR KICK-OFF"
	pitch_status.text = "TWO PLAYERS • ONE PITCH • ONE WINNER"

func _show_match() -> void:
	home_layer.visible = false
	match_layer.visible = true
	stadium_root.visible = true

func _show_result() -> void:
	stadium_root.visible = false
	match_layer.visible = false
	home_layer.visible = true
	menu_title.text = "FULL TIME"
	menu_subtitle.text = "FINAL SCORE  •  " + str(my_goals) + " — " + str(rival_goals)
	home_primary_button.text = "PLAY AGAIN • VS AI"
	home_secondary_button.text = "RETURN TO MENU"

func _on_menu_primary() -> void:
	if phase == "ended":
		_on_ai_pressed()
	else:
		_on_online_pressed()

func _on_menu_secondary() -> void:
	if phase == "ended":
		_show_home()
	else:
		_on_ai_pressed()

func _on_online_pressed() -> void:
	_start_connection(false)

func _on_ai_pressed() -> void:
	_start_connection(true)

func _start_connection(vs_ai: bool) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if vs_ai:
			_send("bot.join", {})
		else:
			_send("queue.join", {})
		return
	phase = "connecting"
	question_label.text = "Connecting to match server…"
	status_label.text = "SECURE WEBSOCKET • WSS"
	var err := socket.connect_to_url(SERVER_URL)
	if err != OK:
		question_label.text = "Could not connect. Check internet and retry."
		phase = "home"
		return
	set_meta("join_ai", vs_ai)

func _handle_frame(frame: Dictionary) -> void:
	var type := str(frame.get("type", ""))
	var p: Dictionary = frame.get("payload", {})
	match type:
		"welcome":
			_send("hello", {"deviceId": OS.get_unique_id(), "locale": locale, "region": "MENA", "displayName": display_name})
		"hello.ack":
			player_id = str(p.get("playerId", ""))
			session_token = str(p.get("sessionToken", ""))
			if bool(get_meta("join_ai", false)):
				_send("bot.join", {})
			else:
				_send("queue.join", {})
		"queue.joined":
			question_label.text = "Searching for an opponent…"
			status_label.text = "MATCHMAKING • AI BACKUP AVAILABLE"
		"match.found":
			match_id = str(p.get("matchId", ""))
			question_label.text = "OPPONENT FOUND"
			status_label.text = "KICK-OFF INCOMING"
		"match.start", "match.second_half":
			_show_match()
			_play_sfx("whistle")
			phase = "round_intro"
			_read_scores(p)
			status_label.text = "KICK OFF • HALF " + str(p.get("half", 1))
			question_label.text = "Get ready!"
			animate_kickoff()
		"round.intro":
			phase = "round_intro"
			question_label.text = "ROUND " + str(p.get("roundNo", "")) + " • GET READY"
			status_label.text = "THE NEXT QUESTION IS COMING"
		"round.question", "shoot.question":
			phase = "shooting_chance" if type == "shoot.question" else "question_open"
			current_token = str(p.get("token", ""))
			selected = false
			you_are_shooting = bool(p.get("youAreShooting", false))
			var view: Dictionary = p.get("view", {})
			_show_question(view)
			var server_now := int(p.get("serverNow", Time.get_ticks_msec()))
			var end_at := int(p.get("windowEndsAt", server_now + 9000))
			countdown_duration = end_at - server_now
			countdown_deadline = Time.get_ticks_msec() + countdown_duration
			status_label.text = "SHOOTING CHANCE!" if phase == "shooting_chance" else "ANSWER FAST TO WIN THE BALL"
			animate_attack(you_are_shooting)
			_play_sfx("kick")
		"round.answer_ack":
			status_label.text = "ANSWER LOCKED • WAIT FOR REFEREE"
		"round.opponent_answered":
			status_label.text = "RIVAL HAS ANSWERED"
		"round.reveal":
			phase = "round_reveal"
			countdown_deadline = 0
			_read_scores(p)
			var outcome := str(p.get("outcome", ""))
			status_label.text = "CORRECT!" if outcome == "correct" else "NOT THIS TIME"
			question_label.text = str(p.get("correctOptionText", "")) + "\n" + str(p.get("explainer", ""))
			_clear_options()
			animate_reveal(outcome == "correct")
		"shoot.reveal":
			phase = "shot_reveal"
			_read_scores(p)
			var scored := bool(p.get("scored", false))
			status_label.text = "GOOOOOAL!" if scored else "SAVED!"
			question_label.text = str(p.get("explainer", ""))
			_clear_options()
			animate_shot(scored)
			_play_sfx("cheer" if scored else "kick")
		"match.half":
			phase = "half_time"
			_read_scores(p)
			status_label.text = "HALF TIME"
			question_label.text = "Take a breath. Second half soon."
		"match.end":
			phase = "ended"
			_read_scores(p)
			countdown_deadline = 0
			_play_sfx("whistle")
			if str(p.get("outcome", "")) == "win":
				_play_sfx("cheer")
			_clear_options()
			_show_result()
		"state.sync":
			status_label.text = "MATCH RECONNECTED"
			_read_scores(p)
		"opponent.connection":
			status_label.text = "RIVAL DISCONNECTED" if not bool(p.get("connected", true)) else "RIVAL BACK ONLINE"
		"error":
			question_label.text = "Server: " + str(p.get("code", "ERROR"))
			status_label.text = "PLEASE TRY AGAIN"

func _send(kind: String, payload: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	sequence += 1
	socket.send_text(JSON.stringify({"v": 1, "type": kind, "seq": sequence, "ts": Time.get_unix_time_from_system()*1000, "payload": payload}))

func _show_question(view: Dictionary) -> void:
	var prompt := str(view.get("prompt", "")).strip_edges()
	var incoming_options: Array = view.get("options", [])
	if prompt.is_empty() or incoming_options.size() < 2:
		question_label.text = "Question unavailable. Waiting for the next round…"
		_clear_options()
		action_box.visible = false
		push_warning("Rejected incomplete question view from server.")
		return
	for option in incoming_options:
		if not (option is Dictionary) or str(option.get("id", "")).is_empty() or str(option.get("text", "")).strip_edges().is_empty():
			question_label.text = "Question unavailable. Waiting for the next round…"
			_clear_options()
			action_box.visible = false
			push_warning("Rejected question with an incomplete answer option.")
			return
	question_label.text = prompt
	question_label.text_direction = Control.TEXT_DIRECTION_AUTO
	# Render format-specific clues: the old client showed only the prompt and
	# answer buttons, silently dropping emoji, career-path and statistics data.
	var format_data: Dictionary = view.get("formatData", {})
	var format_type := str(format_data.get("type", view.get("format", "mc")))
	clue_label.text = ""
	clue_label.visible = false
	if format_type == "emoji_story":
		clue_label.text = str(format_data.get("emoji", ""))
		clue_label.add_theme_font_size_override("font_size", 48)
		clue_label.visible = not clue_label.text.strip_edges().is_empty()
	elif format_type == "career_path":
		var career_clubs: Array = format_data.get("clubs", [])
		var club_names: Array[String] = []
		for club in career_clubs:
			if club is Dictionary and not str(club.get("name", "")).is_empty():
				club_names.append(str(club.get("name", "")))
		clue_label.text = "  →  ".join(club_names)
		clue_label.add_theme_font_size_override("font_size", 22)
		clue_label.visible = not club_names.is_empty()
	elif format_type == "stat_highlow":
		clue_label.text = str(format_data.get("statLabel", ""))
		clue_label.add_theme_font_size_override("font_size", 24)
		clue_label.visible = not clue_label.text.is_empty()
	_clear_options()
	current_options = incoming_options
	for index in range(current_options.size()):
		var option: Dictionary = current_options[index]
		var b := _make_button(str(option.get("text", "")), Color(0.035,0.12,0.24), Color(0.18,0.43,0.68), 56)
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text_direction = Control.TEXT_DIRECTION_AUTO
		var option_id := str(option.get("id", ""))
		b.pressed.connect(func(): _submit_answer(option_id))
		options_box.add_child(b)
	action_box.visible = false

func _submit_answer(option_id: String) -> void:
	if selected or current_token.is_empty():
		return
	selected = true
	_send("round.answer", {"token": current_token, "optionId": option_id, "clientMs": Time.get_ticks_msec()})
	for child in options_box.get_children():
		if child is Button:
			child.disabled = true
	status_label.text = "ANSWER SENT • WAITING FOR RESULT"

func _read_scores(p: Dictionary) -> void:
	var zones: Dictionary = p.get("zones", {})
	var goals: Dictionary = p.get("goals", {})
	if not zones.is_empty():
		my_zone = int(zones.get(player_id, my_zone))
		for key in zones:
			if str(key) != player_id:
				rival_zone = int(zones[key])
	if not goals.is_empty():
		my_goals = int(goals.get(player_id, my_goals))
		for key in goals:
			if str(key) != player_id:
				rival_goals = int(goals[key])
	score_label.text = "YOU  " + str(my_goals) + "  —  " + str(rival_goals) + "  RIVAL"

func _clear_options() -> void:
	for child in options_box.get_children():
		child.queue_free()

func _add_action_button(label: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(150, 50)
	b.pressed.connect(callback)
	action_box.visible = true
	action_box.add_child(b)

func _toggle_locale() -> void:
	locale = "ar" if locale == "en" else "en"
	locale_button.text = "ENGLISH" if locale == "ar" else "العربية"
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send("queue.leave", {})
		socket.close()
		connected = false
		_show_home()
	menu_subtitle.text = "معركة معلومات كرة القدم" if locale == "ar" else "THE ULTIMATE FOOTBALL QUIZ BATTLE"

func _toggle_sound() -> void:
	sound_muted = not sound_muted
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, sound_muted)
	var label := "SOUND OFF  ×" if sound_muted else "SOUND ON  ♪"
	if is_instance_valid(home_sound_button):
		home_sound_button.text = label
	if is_instance_valid(match_sound_button):
		match_sound_button.text = label
	_save_settings()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		sound_muted = bool(config.get_value("audio", "muted", false))
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, sound_muted)
	_toggle_sound_label()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "muted", sound_muted)
	config.save("user://settings.cfg")

func _toggle_sound_label() -> void:
	var label := "SOUND OFF  ×" if sound_muted else "SOUND ON  ♪"
	if is_instance_valid(home_sound_button):
		home_sound_button.text = label
	if is_instance_valid(match_sound_button):
		match_sound_button.text = label

func _update_pitch_state() -> void:
	if not is_instance_valid(home_player) or not is_instance_valid(away_player):
		return
	var home_shift := float(my_zone) * 2.1
	var away_shift := float(rival_zone) * 2.1
	var home_base := [Vector3(0,0,21),Vector3(-10,0,14),Vector3(-3.3,0,15),Vector3(3.3,0,15),Vector3(10,0,14),Vector3(-7,0,5),Vector3(0,0,7),Vector3(7,0,5),Vector3(-8,0,-6),Vector3(0,0,-8),Vector3(8,0,-6)]
	var away_base := [Vector3(0,0,-21),Vector3(10,0,-14),Vector3(3.3,0,-15),Vector3(-3.3,0,-15),Vector3(-10,0,-14),Vector3(7,0,-5),Vector3(0,0,-7),Vector3(-7,0,-5),Vector3(8,0,6),Vector3(0,0,8),Vector3(-8,0,6)]
	var gait := float(Time.get_ticks_msec()) * 0.012
	for i in range(home_team.size()):
		var target: Vector3 = home_base[i] + Vector3(0,0,-home_shift)
		home_team[i].position = home_team[i].position.lerp(target, 0.025)
		_animate_player(home_team[i], gait + float(i)*0.55)
	for i in range(away_team.size()):
		var target: Vector3 = away_base[i] + Vector3(0,0,away_shift)
		away_team[i].position = away_team[i].position.lerp(target, 0.025)
		_animate_player(away_team[i], -gait + float(i)*0.55)
	pitch_status.text = "ATTACKING • ZONE " + str(my_zone) if my_zone > rival_zone else "DEFENDING • WIN THE BALL"

func animate_kickoff() -> void:
	var tween := create_tween()
	tween.tween_property(ball, "position", Vector3(0, 0.48, 0), 0.45)
	tween.parallel().tween_property(home_player, "position", Vector3(-2,0,5), 0.6)
	tween.parallel().tween_property(away_player, "position", Vector3(2,0,-5), 0.6)

func animate_attack(shooting: bool) -> void:
	var target := Vector3(0, 0.48, -FIELD_LENGTH/2 + 5) if shooting else Vector3(0, 0.48, -8)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ball, "position", target, 0.8)
	tween.parallel().tween_property(home_player, "position", Vector3(0,0, target.z+2.5), 0.9)
	tween.parallel().tween_property(away_player, "position", Vector3(1.8,0,target.z-3.5), 0.9)

func animate_reveal(correct: bool) -> void:
	var target := Vector3(0, 0.48, -FIELD_LENGTH/2 + 3) if correct else Vector3(0,0.48,4)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ball, "position", target, 0.65)
	if correct:
		tween.parallel().tween_property(home_player, "rotation:y", TAU, 0.65)

func animate_shot(scored: bool) -> void:
	var goal_z := -FIELD_LENGTH/2 - 0.2
	var target := Vector3(0, 1.2, goal_z) if scored else Vector3(2.4, 1.0, goal_z+2)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(ball, "position", target, 0.7)
	if scored:
		tween.parallel().tween_property(camera, "fov", 54.0, 0.35)
		tween.tween_property(camera, "fov", 48.0, 0.35)

func _animate_player(player: Node3D, gait: float) -> void:
	var moving := phase in ["round_intro", "question_open", "shooting_chance", "round_reveal", "shot_reveal"]
	var amount := 0.22 if moving else 0.035
	for limb_name in ["LegL", "LegR", "ArmL", "ArmR"]:
		var limb := player.get_node_or_null(limb_name) as Node3D
		if limb:
			var side := -1.0 if limb_name.ends_with("L") else 1.0
			var multiplier := 1.0 if limb_name.begins_with("Leg") else -0.72
			limb.rotation.x = sin(gait) * amount * side * multiplier

func _setup_audio() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://audio"))
	_create_audio_player("ambience", true, -18.0)
	_create_audio_player("cheer", false, -4.0)
	_create_audio_player("whistle", false, -7.0)
	_create_audio_player("kick", false, -9.0)
	_load_or_download_audio("ambience", "stadium-crowd-03.mp3", "https://sfxmint.com/dl/stadium-crowd-03.mp3")
	_load_or_download_audio("cheer", "stadium-crowd-02.mp3", "https://sfxmint.com/dl/stadium-crowd-02.mp3")
	_load_or_download_audio("whistle", "instrument-whistle-11.mp3", "https://sfxmint.com/dl/instrument-whistle-11.mp3")
	_load_or_download_audio("kick", "impact-thud-42.mp3", "https://sfxmint.com/dl/impact-thud-42.mp3")

func _create_audio_player(key: String, looping: bool, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.name = "Audio_" + key
	player.volume_db = volume_db
	add_child(player)
	audio_players[key] = player
	player.set_meta("looping", looping)

func _load_or_download_audio(key: String, filename: String, url: String) -> void:
	var path := "user://audio/" + filename
	if FileAccess.file_exists(path):
		_apply_audio_data(key, FileAccess.get_file_as_bytes(path))
		return
	var request := HTTPRequest.new()
	request.timeout = 20.0
	add_child(request)
	audio_requests[key] = request
	request.request_completed.connect(_on_audio_download_completed.bind(key, path))
	var error := request.request(url)
	if error != OK:
		push_warning("Audio download could not start: " + key)

func _on_audio_download_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, key: String, path: String) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		push_warning("Audio download failed: " + key)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(body)
	_apply_audio_data(key, body)

func _apply_audio_data(key: String, bytes: PackedByteArray) -> void:
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	stream.loop = bool(audio_players[key].get_meta("looping", false))
	var player: AudioStreamPlayer = audio_players[key]
	player.stream = stream
	if key == "ambience":
		player.play()

func _play_sfx(key: String) -> void:
	if audio_players.has(key):
		var player: AudioStreamPlayer = audio_players[key]
		if player.stream:
			player.play()

func _exit_tree() -> void:
	for request in audio_requests.values():
		if is_instance_valid(request):
			request.cancel_request()
