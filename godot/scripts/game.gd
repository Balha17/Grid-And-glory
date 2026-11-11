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
var selected_option_id := ""
var option_buttons: Dictionary = {}
var matchmaking_panel: PanelContainer
var matchmaking_label: Label
var matchmaking_cancel_button: Button
var join_mode_ai := false

var stadium_root: Node3D
var camera: Camera3D
var ball: MeshInstance3D
var home_player: Node3D
var away_player: Node3D
var home_team: Array[Node3D] = []
var away_team: Array[Node3D] = []
var rendered_home_zone := -999
var rendered_away_zone := -999
var rendered_pitch_status := ""
var hud: CanvasLayer
var match_layer: Control
var home_layer: Control
var menu_title: Label
var menu_subtitle: Label
var menu_feature_label: Label
var menu_footer_label: Label
var result_banner: PanelContainer
var result_banner_label: Label
var navigation_overlay: Control
var navigation_panel: PanelContainer
var navigation_title: Label
var navigation_hint: Label
var navigation_resume_button: Button
var navigation_home_button: Button
var navigation_confirm_box: VBoxContainer
var navigation_confirm_label: Label
var navigation_confirm_yes: Button
var navigation_confirm_no: Button
var navigation_visible := false
var navigation_confirming := false
var home_primary_button: Button
var home_secondary_button: Button
var home_sound_button: Button
var match_sound_button: Button
var sound_muted := false
var title_label: Label
var status_label: Label
var question_label: Label
var clue_label: Label
var question_meta_label: Label
var question_image: TextureRect
var question_image_request: HTTPRequest
var question_image_placeholder: Label
var question_image_generation := 0
var score_label: Label
var timer_label: Label
var countdown_bar: ProgressBar
var countdown_started := 0
var options_box: GridContainer
var action_box: HBoxContainer
var connect_button: Button
var locale_button: Button
var pitch_status: Label
var countdown_deadline := 0
var countdown_duration := 0
var countdown_style_initialized := false
var last_countdown_urgent := false
var connection_deadline := 0
var reconnect_until := 0
var reconnect_next_attempt := 0
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
	get_tree().set_quit_on_go_back(false)
	_show_home()
	set_process(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back_request()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_handle_back_request()
		get_viewport().set_input_as_handled()

func _handle_back_request() -> void:
	# Android may deliver the same back request more than once; never toggle the panel.
	if navigation_visible:
		return
	if phase in ["question_open", "shooting_chance", "round_reveal", "shot_reveal", "kickoff", "round_intro", "half_time"]:
		_open_navigation(false)
	elif phase == "connecting":
		_open_navigation(true)
	elif phase == "ended":
		_show_home()
	else:
		_open_navigation(true)

func _open_navigation(_is_home: bool) -> void:
	navigation_visible = true
	navigation_confirming = false
	navigation_overlay.visible = true
	navigation_confirm_box.visible = false
	var at_home := phase == "home"
	var connecting_now := phase == "connecting"
	navigation_resume_button.visible = true
	navigation_home_button.visible = true
	navigation_resume_button.text = _tr("STAY IN GAME", "البقاء في اللعبة") if at_home else _tr("RESUME MATCH", "استئناف المباراة")
	navigation_home_button.text = _tr("EXIT GAME", "الخروج من اللعبة") if at_home else (_tr("CANCEL SEARCH", "إلغاء البحث") if connecting_now else _tr("LEAVE MATCH", "مغادرة المباراة"))
	navigation_title.text = _tr("EXIT GAME?", "الخروج من اللعبة؟") if at_home else (_tr("MATCHMAKING", "البحث عن منافس") if connecting_now else _tr("MATCH MENU", "قائمة المباراة"))
	navigation_hint.text = _tr("Choose Stay to continue, or Exit Game to close.", "اختر البقاء للمتابعة أو الخروج لإغلاق اللعبة.") if at_home else (_tr("Cancel the search or return to the match.", "ألغِ البحث أو ارجع إلى المباراة.") if connecting_now else _tr("The match clock keeps running while this menu is open.", "وقت المباراة يستمر أثناء فتح هذه القائمة."))

func _close_navigation() -> void:
	navigation_visible = false
	navigation_confirming = false
	if is_instance_valid(navigation_overlay):
		navigation_overlay.visible = false

func _navigation_secondary_action() -> void:
	if phase == "home":
		get_tree().quit()
	elif phase == "connecting":
		_cancel_matchmaking()
		_close_navigation()
	else:
		_ask_leave_match()

func _ask_leave_match() -> void:
	navigation_confirming = true
	navigation_confirm_box.visible = true
	navigation_confirm_label.text = _tr("Leave this match? Your current round will be forfeited.", "هل تريد مغادرة المباراة؟ ستُحتسب الجولة الحالية انسحاباً.")

func _cancel_leave_match() -> void:
	navigation_confirming = false
	navigation_confirm_box.visible = false

func _leave_match_to_home() -> void:
	if connected and not player_id.is_empty():
		_send("queue.leave", {})
	socket.close()
	socket = WebSocketPeer.new()
	connected = false
	player_id = ""
	session_token = ""
	current_token = ""
	countdown_deadline = 0
	connection_deadline = 0
	phase = "home"
	_close_navigation()
	_show_home()

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
		if phase == "connecting" and connection_deadline > 0:
			connection_deadline = 0
			phase = "home"
			_show_matchmaking(false)
			home_primary_button.disabled = false
			home_secondary_button.disabled = false
			menu_subtitle.text = _tr("CONNECTION FAILED • TAP TO RETRY", "فشل الاتصال • اضغط لإعادة المحاولة")
		elif phase not in ["home", "ended"] and not session_token.is_empty():
			var reconnect_now := Time.get_ticks_msec()
			if reconnect_until == 0:
				reconnect_until = reconnect_now + 25000
				reconnect_next_attempt = reconnect_now
				status_label.text = _tr("CONNECTION LOST • RECONNECTING…", "انقطع الاتصال • جارٍ إعادة الاتصال…")
			if reconnect_now >= reconnect_until:
				reconnect_until = 0
				phase = "home"
				_show_home()
				menu_subtitle.text = _tr("MATCH CONNECTION LOST • PLEASE REJOIN", "انقطع الاتصال بالمباراة • أعد الدخول")
			elif reconnect_now >= reconnect_next_attempt:
				socket = WebSocketPeer.new()
				var reconnect_error := socket.connect_to_url(SERVER_URL)
				reconnect_next_attempt = reconnect_now + (2500 if reconnect_error == OK else 1200)
	if phase == "connecting" and connection_deadline > 0:
		var wait_left := maxi(0, int(ceil(float(connection_deadline - Time.get_ticks_msec()) / 1000.0)))
		matchmaking_label.text = _tr("CONNECTING TO MATCH SERVER…\n", "جارٍ الاتصال بالخادم…\n") + str(wait_left) + "s"
	if countdown_deadline > 0 and phase in ["question_open", "shooting_chance"]:
		var now_ms := Time.get_ticks_msec()
		var left := maxi(0, int(ceil(float(countdown_deadline - now_ms) / 1000.0)))
		timer_label.text = str(left) + "s"
		var total_ms := maxi(1, countdown_deadline - countdown_started)
		countdown_bar.value = clampf(float(countdown_deadline - now_ms) / float(total_ms) * 100.0, 0.0, 100.0)
		var urgent := left <= 3
		# Avoid allocating a new StyleBox every frame during the countdown.
		if not countdown_style_initialized or urgent != last_countdown_urgent:
			last_countdown_urgent = urgent
			countdown_style_initialized = true
			timer_label.add_theme_color_override("font_color", Color(1.0,0.28,0.22) if urgent else Color(1.0,0.78,0.25))
			countdown_bar.add_theme_stylebox_override("fill", _panel_style(Color(0.88,0.16,0.15) if urgent else Color(0.96,0.65,0.16), Color(1.0,0.78,0.28), 0))
	else:
		timer_label.text = ""
		if is_instance_valid(countdown_bar):
			countdown_bar.value = 0
	if phase == "connecting" and connection_deadline > 0 and Time.get_ticks_msec() >= connection_deadline:
		connection_deadline = 0
		socket.close()
		connected = false
		phase = "home"
		_show_matchmaking(false)
		home_primary_button.disabled = false
		home_secondary_button.disabled = false
		menu_subtitle.text = _tr("SERVER TIMEOUT • CHECK INTERNET AND RETRY", "انتهت مهلة الاتصال • تحقق من الإنترنت وحاول مجدداً")
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
	camera.position = Vector3(0, 42, 44)
	camera.rotation_degrees = Vector3(-48, 0, 0)
	camera.fov = 54
	stadium_root.add_child(camera)
	camera.current = true

	var stadium_light := DirectionalLight3D.new()
	stadium_light.rotation_degrees = Vector3(-55, -25, 0)
	stadium_light.light_energy = 1.25
	stadium_light.shadow_enabled = false
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
		# Keep the two featured players detailed; reserve players use a low-draw-call model.
		var h := _make_player("HOME_" + str(i+1), Color(0.12, 0.58, 1.0)) if i == 9 else _make_reserve_player("HOME_" + str(i+1), Color(0.12, 0.58, 1.0))
		h.position = home_positions[i]
		stadium_root.add_child(h)
		home_team.append(h)
		var a := _make_player("AWAY_" + str(i+1), Color(1.0, 0.34, 0.19)) if i == 9 else _make_reserve_player("AWAY_" + str(i+1), Color(1.0, 0.34, 0.19))
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
	_add_stadium_details()

func _add_stands() -> void:
	# Keep the stadium silhouette but batch all spectator seats into one mobile-friendly draw call.
	for side in [-1, 1]:
		_box("Stand", Vector3(float(side)*17.2, 2.0, 0), Vector3(5.2, 4.4, 58), Color(0.055, 0.09, 0.14))
		_box("Stand_Roof", Vector3(float(side)*17.2, 6.0, 0), Vector3(6.2, 0.38, 59), Color(0.025, 0.055, 0.095))
		_box("Stand_Fascia", Vector3(float(side)*17.2, 5.55, 0), Vector3(5.8, 0.16, 58), Color(0.08, 0.22, 0.36))
	for end in [-1, 1]:
		_box("End_Stand", Vector3(0, 1.8, float(end)*27.3), Vector3(31, 3.8, 4.0), Color(0.045, 0.075, 0.12))
		_box("End_Stand_Roof", Vector3(0, 4.1, float(end)*27.3), Vector3(32, 0.35, 5.0), Color(0.025, 0.055, 0.095))

	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(0.42, 0.35, 0.42)
	var seat_material := StandardMaterial3D.new()
	seat_material.vertex_color_use_as_albedo = true
	seat_material.roughness = 0.82
	seat_mesh.material = seat_material
	var positions: Array[Vector3] = []
	var palette := [Color(0.08,0.45,0.75), Color(0.9,0.28,0.17), Color(0.88,0.9,0.94)]
	var colors: Array[Color] = []
	for side in [-1, 1]:
		for row in range(4):
			for col in range(20):
				positions.append(Vector3(float(side)*17.2, 3.2 + float(row)*0.72, -25.0 + float(col)*2.6))
				colors.append(palette[(row+col)%3])
	for end in [-1, 1]:
		for row in range(3):
			for col in range(24):
				positions.append(Vector3(-14.0 + float(col)*1.22, 2.0 + float(row)*0.72, float(end)*25.4))
				colors.append(palette[(row*7+col)%3])
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = seat_mesh
	batch.instance_count = positions.size()
	for i in range(positions.size()):
		batch.set_instance_transform(i, Transform3D(Basis(), positions[i]))
		batch.set_instance_color(i, colors[i])
	var seats := MultiMeshInstance3D.new()
	seats.name = "Batched_Stadium_Seats"
	seats.multimesh = batch
	stadium_root.add_child(seats)

func _add_stadium_details() -> void:
	# LED perimeter boards frame the pitch and separate the playing surface from the stands.
	for side in [-1, 1]:
		_box("LED_Perimeter", Vector3(float(side) * 14.65, 0.58, 0), Vector3(0.22, 1.05, 48), Color(0.018, 0.12, 0.24))
		_box("LED_Gold_Trim", Vector3(float(side) * 14.79, 0.58, 0), Vector3(0.035, 0.08, 47.5), Color(0.96, 0.58, 0.12))
		_box("End_Perimeter", Vector3(0, 0.58, float(side) * 24.55), Vector3(28.5, 1.05, 0.22), Color(0.018, 0.12, 0.24))
		_box("End_Gold_Trim", Vector3(0, 0.58, float(side) * 24.69), Vector3(28.2, 0.08, 0.035), Color(0.96, 0.58, 0.12))
	# Four floodlight masts give the stadium a night-match silhouette and real light sources.
	for side in [-1, 1]:
		for end in [-1, 1]:
			var x := float(side) * 19.0
			var z := float(end) * 26.0
			_box("Floodlight_Mast", Vector3(x, 6.8, z), Vector3(0.34, 13.6, 0.34), Color(0.12, 0.17, 0.24))
			_box("Floodlight_Beam", Vector3(x, 13.35, z), Vector3(3.4, 0.24, 0.34), Color(0.16, 0.22, 0.30))
			for lamp_index in range(4):
				var lamp_x := x - 1.2 + float(lamp_index) * 0.8
				_box("Floodlight_Lamp", Vector3(lamp_x, 13.15, z), Vector3(0.48, 0.34, 0.16), Color(0.82, 0.91, 1.0))
	# Corner flags make the field markings read like a complete football ground.
	for side in [-1, 1]:
		for end in [-1, 1]:
			var flag_x := float(side) * 13.8
			var flag_z := float(end) * 23.8
			_box("Corner_Flag_Pole", Vector3(flag_x, 1.05, flag_z), Vector3(0.055, 2.1, 0.055), Color(0.92, 0.94, 0.98))
			_box("Corner_Flag", Vector3(flag_x + float(side) * 0.28, 1.75, flag_z), Vector3(0.55, 0.34, 0.035), Color(0.96, 0.58, 0.12))

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

func _make_reserve_player(label: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = label
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.43
	body_mesh.height = 1.75
	body.mesh = body_mesh
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = color
	body_material.roughness = 0.9
	body.material_override = body_material
	body.position.y = 1.05
	root.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.25
	head_mesh.height = 0.5
	head.mesh = head_mesh
	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = Color(0.67, 0.43, 0.30)
	head_material.roughness = 0.95
	head.material_override = head_material
	head.position.y = 2.12
	root.add_child(head)
	return root

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
	top.anchor_bottom = 0.115
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
	title_label.text = _tr("GRID & GLORY  •  MATCHDAY", "GRID & GLORY  •  يوم المباراة")
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
	match_sound_button = _make_button("SOUND ON  ♪", Color(0.08,0.20,0.36), Color(0.30,0.63,0.92), 32)
	match_sound_button.pressed.connect(_toggle_sound)
	topbox.add_child(match_sound_button)

	var bottom := PanelContainer.new()
	bottom.anchor_left = 0.025
	bottom.anchor_right = 0.975
	bottom.anchor_top = 0.645
	bottom.anchor_bottom = 0.992
	bottom.offset_left = 0
	bottom.offset_right = 0
	bottom.offset_top = 0
	bottom.offset_bottom = 0
	bottom.add_theme_stylebox_override("panel", _panel_style(Color(0.008,0.025,0.065,0.99), Color(0.92,0.68,0.24), 3))
	match_layer.add_child(bottom)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	bottom.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	margin.add_child(content)
	pitch_status = Label.new()
	pitch_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pitch_status.add_theme_color_override("font_color", Color(0.48,0.85,1.0))
	pitch_status.add_theme_font_size_override("font_size", 12)
	pitch_status.add_theme_color_override("font_color", Color(0.55,0.75,0.92))
	content.add_child(pitch_status)
	question_meta_label = Label.new()
	question_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_meta_label.add_theme_color_override("font_color", Color(1.0,0.79,0.34))
	question_meta_label.add_theme_font_size_override("font_size", 12)
	content.add_child(question_meta_label)
	question_label = Label.new()
	question_label.text = "Get ready for the next challenge"
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	question_label.custom_minimum_size = Vector2(0, 68)
	question_label.add_theme_color_override("font_color", Color(0.98,0.98,1.0))
	question_label.add_theme_font_size_override("font_size", 21)
	content.add_child(question_label)
	clue_label = Label.new()
	clue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clue_label.custom_minimum_size = Vector2(0, 30)
	clue_label.add_theme_color_override("font_color", Color(1.0,0.82,0.35))
	clue_label.add_theme_font_size_override("font_size", 19)
	clue_label.visible = false
	content.add_child(clue_label)
	question_image = TextureRect.new()
	question_image.custom_minimum_size = Vector2(0, 92)
	question_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	question_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	question_image.visible = false
	content.add_child(question_image)
	question_image_placeholder = Label.new()
	question_image_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_image_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_image_placeholder.custom_minimum_size = Vector2(0, 38)
	question_image_placeholder.add_theme_color_override("font_color", Color(0.62,0.75,0.88))
	question_image_placeholder.add_theme_font_size_override("font_size", 13)
	question_image_placeholder.text = "IMAGE CLUE"
	question_image_placeholder.visible = false
	content.add_child(question_image_placeholder)
	timer_label = Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_color_override("font_color", Color(1.0,0.78,0.25))
	timer_label.add_theme_font_size_override("font_size", 18)
	content.add_child(timer_label)
	countdown_bar = ProgressBar.new()
	countdown_bar.custom_minimum_size = Vector2(0, 7)
	countdown_bar.show_percentage = false
	countdown_bar.min_value = 0
	countdown_bar.max_value = 100
	countdown_bar.value = 100
	countdown_bar.add_theme_stylebox_override("background", _panel_style(Color(0.08,0.13,0.20), Color(0.13,0.22,0.34), 0))
	countdown_bar.add_theme_stylebox_override("fill", _panel_style(Color(0.96,0.65,0.16), Color(1.0,0.78,0.28), 0))
	content.add_child(countdown_bar)
	options_box = GridContainer.new()
	options_box.columns = 2
	options_box.add_theme_constant_override("h_separation", 8)
	options_box.add_theme_constant_override("v_separation", 5)
	content.add_child(options_box)
	action_box = HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	action_box.add_theme_constant_override("separation", 10)
	content.add_child(action_box)

	# Back/menu overlay. It never pauses the authoritative server timer.
	navigation_overlay = Control.new()
	navigation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	navigation_overlay.visible = false
	navigation_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	match_layer.add_child(navigation_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.002, 0.008, 0.02, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	navigation_overlay.add_child(shade)
	navigation_panel = PanelContainer.new()
	navigation_panel.anchor_left = 0.09
	navigation_panel.anchor_right = 0.91
	navigation_panel.anchor_top = 0.27
	navigation_panel.anchor_bottom = 0.73
	navigation_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.012,0.035,0.085,0.99), Color(0.96,0.68,0.20), 3))
	navigation_overlay.add_child(navigation_panel)
	var nav_margin := MarginContainer.new()
	for side in ["left", "right"]:
		nav_margin.add_theme_constant_override("margin_" + side, 18)
	nav_margin.add_theme_constant_override("margin_top", 16)
	nav_margin.add_theme_constant_override("margin_bottom", 16)
	navigation_panel.add_child(nav_margin)
	var nav_stack := VBoxContainer.new()
	nav_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_stack.add_theme_constant_override("separation", 10)
	nav_margin.add_child(nav_stack)
	navigation_title = Label.new()
	navigation_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	navigation_title.add_theme_font_size_override("font_size", 27)
	navigation_title.add_theme_color_override("font_color", Color(1.0,0.79,0.34))
	nav_stack.add_child(navigation_title)
	navigation_hint = Label.new()
	navigation_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	navigation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	navigation_hint.add_theme_font_size_override("font_size", 14)
	navigation_hint.add_theme_color_override("font_color", Color(0.72,0.83,0.96))
	nav_stack.add_child(navigation_hint)
	navigation_resume_button = _make_button("RESUME MATCH", Color(0.04,0.43,0.19), Color(0.25,0.95,0.45), 52)
	navigation_resume_button.pressed.connect(_close_navigation)
	nav_stack.add_child(navigation_resume_button)
	navigation_home_button = _make_button("LEAVE MATCH", Color(0.36,0.07,0.09), Color(1.0,0.30,0.24), 48)
	navigation_home_button.pressed.connect(_navigation_secondary_action)
	nav_stack.add_child(navigation_home_button)
	navigation_confirm_box = VBoxContainer.new()
	navigation_confirm_box.add_theme_constant_override("separation", 7)
	navigation_confirm_box.visible = false
	nav_stack.add_child(navigation_confirm_box)
	navigation_confirm_label = Label.new()
	navigation_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	navigation_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	navigation_confirm_label.add_theme_color_override("font_color", Color(1.0,0.83,0.68))
	navigation_confirm_box.add_child(navigation_confirm_label)
	var confirm_row := HBoxContainer.new()
	confirm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_row.add_theme_constant_override("separation", 8)
	navigation_confirm_box.add_child(confirm_row)
	navigation_confirm_yes = _make_button("LEAVE", Color(0.42,0.06,0.08), Color(1.0,0.3,0.22), 42)
	navigation_confirm_yes.pressed.connect(_leave_match_to_home)
	confirm_row.add_child(navigation_confirm_yes)
	navigation_confirm_no = _make_button("STAY", Color(0.05,0.29,0.16), Color(0.25,0.9,0.45), 42)
	navigation_confirm_no.pressed.connect(_cancel_leave_match)
	confirm_row.add_child(navigation_confirm_no)

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
	var menu_gradient := Gradient.new()
	menu_gradient.colors = PackedColorArray([Color(0.015,0.045,0.10,0.18), Color(0.005,0.018,0.04,0.92)])
	menu_gradient.offsets = PackedFloat32Array([0.0, 1.0])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = menu_gradient
	gradient_texture.width = 2
	gradient_texture.height = 512
	gradient_texture.fill_from = Vector2(0, 0)
	gradient_texture.fill_to = Vector2(0, 1)
	var gradient_overlay := TextureRect.new()
	gradient_overlay.texture = gradient_texture
	gradient_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	gradient_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home_layer.add_child(gradient_overlay)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 24)
	outer.add_theme_constant_override("margin_bottom", 24)
	home_layer.add_child(outer)
	var menu := VBoxContainer.new()
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 18)
	var menu_card := PanelContainer.new()
	menu_card.custom_minimum_size = Vector2(0, 0)
	menu_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu_card.add_theme_stylebox_override("panel", _panel_style(Color(0.006,0.022,0.052,0.78), Color(0.18,0.48,0.82,0.62), 2))
	outer.add_child(menu_card)
	menu_card.add_child(menu)

	var logo := TextureRect.new()
	logo.texture = load("res://assets/grid_glory_icon.svg")
	logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 112)
	menu.add_child(logo)

	menu_title = Label.new()
	menu_title.text = "GRID & GLORY"
	menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_title.add_theme_color_override("font_color", Color(1.0,0.78,0.30))
	menu_title.add_theme_font_size_override("font_size", 36)
	menu_title.add_theme_color_override("font_shadow_color", Color(0,0,0,0.9))
	menu_title.add_theme_constant_override("shadow_offset_x", 2)
	menu_title.add_theme_constant_override("shadow_offset_y", 3)
	menu.add_child(menu_title)

	menu_subtitle = Label.new()
	menu_subtitle.text = "THE ULTIMATE FOOTBALL QUIZ BATTLE"
	menu_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_subtitle.add_theme_color_override("font_color", Color(0.73,0.86,1.0))
	menu_subtitle.add_theme_font_size_override("font_size", 14)
	menu.add_child(menu_subtitle)

	var feature := PanelContainer.new()
	feature.add_theme_stylebox_override("panel", _panel_style(Color(0.035,0.085,0.17,0.96), Color(0.78,0.55,0.20), 2))
	menu.add_child(feature)
	menu_feature_label = Label.new()
	menu_feature_label.text = "⚽  1v1 FOOTBALL TRIVIA  •  RISE TO LEGEND"
	menu_feature_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_feature_label.add_theme_color_override("font_color", Color(1.0,0.88,0.58))
	menu_feature_label.add_theme_font_size_override("font_size", 13)
	feature.add_child(menu_feature_label)
	result_banner = PanelContainer.new()
	result_banner.add_theme_stylebox_override("panel", _panel_style(Color(0.11,0.075,0.018,0.97), Color(1.0,0.73,0.20), 3))
	result_banner.visible = false
	menu.add_child(result_banner)
	result_banner_label = Label.new()
	result_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_banner_label.add_theme_color_override("font_color", Color(1.0,0.86,0.42))
	result_banner_label.add_theme_font_size_override("font_size", 20)
	result_banner.add_child(result_banner_label)

	home_primary_button = _make_button("▶  PLAY ONLINE", Color(0.045,0.48,0.20), Color(0.28,1.0,0.49), 58)
	home_primary_button.add_theme_color_override("font_color", Color(0.10,0.08,0.04))
	home_primary_button.pressed.connect(_on_menu_primary)
	menu.add_child(home_primary_button)
	home_secondary_button = _make_button("⚔  PLAY VS AI", Color(0.025,0.19,0.42), Color(0.22,0.62,1.0), 54)
	home_secondary_button.pressed.connect(_on_menu_secondary)
	menu.add_child(home_secondary_button)

	var settings_row := HBoxContainer.new()
	settings_row.alignment = BoxContainer.ALIGNMENT_CENTER
	settings_row.add_theme_constant_override("separation", 12)
	menu.add_child(settings_row)
	home_sound_button = _make_button("SOUND ON  ♪", Color(0.08,0.13,0.25), Color(0.28,0.52,0.82), 46)
	home_sound_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_sound_button.pressed.connect(_toggle_sound)
	settings_row.add_child(home_sound_button)
	locale_button = _make_button("العربية / EN", Color(0.08,0.13,0.25), Color(0.28,0.52,0.82), 50)
	locale_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	locale_button.pressed.connect(_toggle_locale)
	settings_row.add_child(locale_button)

	matchmaking_panel = PanelContainer.new()
	matchmaking_panel.anchor_left = 0.08
	matchmaking_panel.anchor_right = 0.92
	matchmaking_panel.anchor_top = 0.39
	matchmaking_panel.anchor_bottom = 0.61
	matchmaking_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.012,0.035,0.085,0.98), Color(0.95,0.67,0.18), 3))
	matchmaking_panel.visible = false
	home_layer.add_child(matchmaking_panel)
	var matchmaking_box := VBoxContainer.new()
	matchmaking_box.add_theme_constant_override("separation", 10)
	matchmaking_panel.add_child(matchmaking_box)
	matchmaking_label = Label.new()
	matchmaking_label.text = _tr("CONNECTING TO MATCH SERVER…", "جارٍ الاتصال بخادم المباراة…")
	matchmaking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	matchmaking_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	matchmaking_label.add_theme_font_size_override("font_size", 20)
	matchmaking_label.add_theme_color_override("font_color", Color(0.96,0.84,0.53))
	matchmaking_box.add_child(matchmaking_label)
	matchmaking_cancel_button = _make_button(_tr("CANCEL", "إلغاء"), Color(0.34,0.09,0.12), Color(0.9,0.28,0.25), 48)
	matchmaking_cancel_button.pressed.connect(_cancel_matchmaking)
	matchmaking_box.add_child(matchmaking_cancel_button)

	menu_footer_label = Label.new()
	menu_footer_label.text = "ONLINE DUELS  •  SMART AI  •  FOOTBALL KNOWLEDGE"
	menu_footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_footer_label.add_theme_color_override("font_color", Color(0.43,0.62,0.82))
	menu_footer_label.add_theme_font_size_override("font_size", 11)
	menu.add_child(menu_footer_label)

	match_layer.visible = false
	home_layer.visible = true
	matchmaking_panel.visible = false

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
	button.pivot_offset = Vector2(0, height / 2.0)
	button.resized.connect(func(): button.pivot_offset = button.size / 2.0)
	button.button_down.connect(func():
		_play_sfx("ui_click")
		var press_tween := button.create_tween()
		press_tween.tween_property(button, "scale", Vector2(0.975, 0.975), 0.07)
	)
	button.button_up.connect(func():
		var release_tween := button.create_tween()
		release_tween.tween_property(button, "scale", Vector2.ONE, 0.10)
	)
	return button

func _show_home() -> void:
	phase = "home"
	_close_navigation()
	stadium_root.visible = false
	match_layer.visible = false
	home_layer.visible = true
	matchmaking_panel.visible = false
	menu_title.text = "GRID & GLORY"
	menu_subtitle.text = "THE ULTIMATE FOOTBALL QUIZ BATTLE"
	result_banner.visible = false
	menu_feature_label.text = _tr("⚽  1v1 FOOTBALL TRIVIA  •  RISE TO LEGEND", "⚽  تحدي كرة القدم  •  كن أسطورة")
	home_primary_button.disabled = false
	home_secondary_button.disabled = false
	home_primary_button.text = "PLAY ONLINE"
	home_secondary_button.text = "PLAY VS AI"
	question_label.text = _tr("Choose your arena", "اختر ساحة المنافسة")
	clue_label.text = ""
	clue_label.visible = false
	_clear_options()
	action_box.visible = true
	status_label.text = _tr("READY FOR KICK-OFF", "استعد لركلة البداية")
	pitch_status.text = _tr("TWO PLAYERS • ONE PITCH • ONE WINNER", "لاعبان • ملعب واحد • فائز واحد")
	_apply_locale()

func _show_match() -> void:
	connection_deadline = 0
	home_primary_button.disabled = false
	home_secondary_button.disabled = false
	home_layer.visible = false
	match_layer.visible = true
	_close_navigation()
	stadium_root.visible = true

func _show_result() -> void:
	_close_navigation()
	stadium_root.visible = false
	match_layer.visible = false
	home_layer.visible = true
	var won := my_goals > rival_goals
	var drew := my_goals == rival_goals
	menu_title.text = _tr("FULL TIME", "نهاية المباراة")
	menu_subtitle.text = _tr("FINAL SCORE  •  ", "النتيجة النهائية  •  ") + str(my_goals) + " — " + str(rival_goals)
	result_banner_label.text = ("🏆  " + _tr("YOU ARE THE CHAMPION!", "أنت البطل!") if won else ("🤝  " + _tr("A GREAT DRAW!", "تعادل رائع!") if drew else "⚽  " + _tr("KEEP TRAINING, CHAMPION!", "واصل التدريب يا بطل!")))
	result_banner.visible = true
	menu_feature_label.text = _tr("FULL-TIME • MATCH COMPLETE", "نهاية المباراة • اكتملت المواجهة")
	home_primary_button.text = _tr("PLAY AGAIN • VS AI", "العب مجدداً ضد الذكاء الاصطناعي")
	home_secondary_button.text = _tr("RETURN TO MENU", "العودة إلى القائمة")

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
	join_mode_ai = vs_ai
	set_meta("join_ai", vs_ai)
	phase = "connecting"
	connection_deadline = Time.get_ticks_msec() + 20000
	home_primary_button.disabled = true
	home_secondary_button.disabled = true
	_show_matchmaking(true)
	matchmaking_label.text = "CONNECTING TO MATCH SERVER…"
	# A closed WebSocketPeer cannot be reused for a new connection attempt.
	my_goals = 0
	rival_goals = 0
	my_zone = 0
	rival_zone = 0
	match_id = ""
	current_token = ""
	selected_option_id = ""
	selected = false
	var socket_state := socket.get_ready_state()
	if socket_state != WebSocketPeer.STATE_OPEN:
		if socket_state != WebSocketPeer.STATE_CLOSED:
			socket.close()
		socket = WebSocketPeer.new()
		connected = false
	else:
		if not player_id.is_empty() and not session_token.is_empty():
			_send_join_request()
			return
		# Wait for the pending welcome/hello handshake; never send bot.join before hello. 
		return
	var err := socket.connect_to_url(SERVER_URL)
	if err != OK:
		connection_deadline = 0
		phase = "home"
		_show_matchmaking(false)
		home_primary_button.disabled = false
		home_secondary_button.disabled = false
		menu_subtitle.text = _tr("CONNECTION FAILED • TAP TO RETRY", "فشل الاتصال • اضغط لإعادة المحاولة")
		return

func _show_matchmaking(show: bool) -> void:
	if matchmaking_panel:
		matchmaking_panel.visible = show

func _send_join_request() -> void:
	if join_mode_ai:
		matchmaking_label.text = _tr("CREATING YOUR AI MATCH…", "جارٍ تجهيز مباراة الذكاء الاصطناعي…")
		_send("bot.join", {})
	else:
		matchmaking_label.text = _tr("SEARCHING FOR AN OPPONENT…", "جارٍ البحث عن منافس…")
		_send("queue.join", {})

func _cancel_matchmaking() -> void:
	if connected and not player_id.is_empty():
		_send("queue.leave", {})
	socket.close()
	socket = WebSocketPeer.new()
	connected = false
	connection_deadline = 0
	phase = "home"
	player_id = ""
	session_token = ""
	_show_matchmaking(false)
	home_primary_button.disabled = false
	home_secondary_button.disabled = false
	menu_subtitle.text = _tr("THE ULTIMATE FOOTBALL QUIZ BATTLE", "معركة معلومات كرة القدم")


func _handle_frame(frame: Dictionary) -> void:
	var type := str(frame.get("type", ""))
	var payload_value = frame.get("payload", {})
	if not payload_value is Dictionary:
		push_warning("Ignored server frame with a non-object payload.")
		return
	var p: Dictionary = payload_value
	match type:
		"welcome":
			_send("hello", {"deviceId": OS.get_unique_id(), "sessionToken": session_token, "locale": locale, "region": "MENA", "displayName": display_name})
		"hello.ack":
			player_id = str(p.get("playerId", ""))
			session_token = str(p.get("sessionToken", ""))
			if bool(p.get("resumed", false)) and not match_id.is_empty():
				reconnect_until = 0
				reconnect_next_attempt = 0
				status_label.text = _tr("MATCH RECONNECTED • RESTORING QUESTION", "عاد الاتصال • جارٍ استعادة السؤال")
			else:
				_send_join_request()
		"queue.joined":
			matchmaking_label.text = _tr("SEARCHING FOR A PLAYER…\nAI BACKUP IN 15 SECONDS", "نبحث عن لاعب…\nالذكاء الاصطناعي بعد 15 ثانية")
			question_label.text = _tr("Searching for an opponent…", "جارٍ البحث عن منافس…")
			status_label.text = _tr("MATCHMAKING • AI BACKUP AVAILABLE", "بحث عن منافس • بديل الذكاء الاصطناعي متاح")
		"match.found":
			match_id = str(p.get("matchId", ""))
			matchmaking_label.text = _tr("OPPONENT FOUND • PREPARING KICK-OFF", "تم العثور على منافس • نستعد للبداية")
			_show_matchmaking(false)
			question_label.text = _tr("OPPONENT FOUND", "تم العثور على منافس")
			status_label.text = _tr("KICK-OFF INCOMING", "المباراة على وشك الانطلاق")
		"match.start", "match.second_half":
			_show_match()
			_play_sfx("whistle")
			phase = "round_intro"
			_read_scores(p)
			status_label.text = _tr("KICK OFF • HALF ", "انطلاق • الشوط ") + str(p.get("half", 1))
			question_label.text = _tr("Get ready!", "استعد!")
			animate_kickoff()
		"round.intro":
			phase = "round_intro"
			question_label.text = _tr("ROUND ", "الجولة ") + str(p.get("roundNo", "")) + _tr(" • GET READY", " • استعد")
			status_label.text = _tr("THE NEXT QUESTION IS COMING", "السؤال التالي قادم")
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
			countdown_started = Time.get_ticks_msec()
			countdown_deadline = countdown_started + countdown_duration
			status_label.text = _tr("SHOOTING CHANCE!", "فرصة للتسجيل!") if phase == "shooting_chance" else _tr("ANSWER FAST TO WIN THE BALL", "أجب بسرعة للفوز بالكرة")
			animate_attack(you_are_shooting)
			_play_sfx("kick")
		"round.answer_ack":
			status_label.text = _tr("ANSWER LOCKED • WAIT FOR REFEREE", "تم تثبيت إجابتك • انتظر النتيجة")
		"round.opponent_answered":
			status_label.text = _tr("RIVAL HAS ANSWERED", "الخصم أجاب")
		"round.reveal":
			phase = "round_reveal"
			countdown_deadline = 0
			_read_scores(p)
			var outcome := str(p.get("outcome", ""))
			status_label.text = _tr("CORRECT!", "إجابة صحيحة!") if outcome == "correct" else _tr("WRONG!", "إجابة خاطئة!")
			status_label.add_theme_color_override("font_color", Color(0.20, 0.95, 0.43) if outcome == "correct" else Color(1.0, 0.25, 0.22))
			_show_answer_feedback(str(p.get("correctOptionId", "")), outcome == "correct")
			animate_reveal(outcome == "correct")
		"shoot.reveal":
			phase = "shot_reveal"
			_read_scores(p)
			var scored := bool(p.get("scored", false))
			status_label.text = _tr("GOOOOOAL!", "هــــدف!") if scored else _tr("SAVED!", "تصدى لها الحارس!")
			status_label.add_theme_color_override("font_color", Color(0.20, 0.95, 0.43) if scored else Color(1.0, 0.25, 0.22))
			var correct_shot_id := str(p.get("correctOptionId", ""))
			_show_answer_feedback(correct_shot_id, not correct_shot_id.is_empty() and selected_option_id == correct_shot_id, false)
			animate_shot(scored)
			_play_sfx("cheer" if scored else "kick")
		"match.half":
			phase = "half_time"
			_read_scores(p)
			status_label.text = _tr("HALF TIME", "استراحة بين الشوطين")
			question_label.text = _tr("Take a breath. Second half soon.", "استعد للشوط الثاني")
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
			reconnect_until = 0
			reconnect_next_attempt = 0
			_read_scores(p)
			var restored_live: Dictionary = p.get("live", {})
			if not restored_live.is_empty() and restored_live.get("view", {}) is Dictionary:
				var restored_view: Dictionary = restored_live.get("view", {})
				current_token = str(restored_live.get("token", ""))
				selected = not bool(restored_live.get("waitingOnOpponent", true))
				you_are_shooting = bool(restored_live.get("youAreShooting", false))
				phase = "shooting_chance" if str(p.get("phase", "")) == "shooting_chance" else "question_open"
				_show_question(restored_view)
				var server_now := int(p.get("serverNow", Time.get_ticks_msec()))
				var window_end := int(restored_live.get("windowEndsAt", server_now))
				countdown_duration = maxi(0, window_end - server_now)
				countdown_started = Time.get_ticks_msec()
				countdown_deadline = countdown_started + countdown_duration
				if selected:
					for child in options_box.get_children():
						if child is Button:
							child.disabled = true
					status_label.text = _tr("ANSWER ALREADY SENT • WAITING", "تم إرسال الإجابة • ننتظر النتيجة")
			else:
				countdown_deadline = 0
				phase = str(p.get("phase", "round_intro"))
				question_label.text = _tr("Connection restored. Next round loading…", "عاد الاتصال. جارٍ تحميل الجولة التالية…")
				status_label.text = _tr("MATCH RECONNECTED", "تمت استعادة الاتصال بالمباراة")
		"opponent.connection":
			status_label.text = _tr("RIVAL DISCONNECTED", "انقطع اتصال المنافس") if not bool(p.get("connected", true)) else _tr("RIVAL BACK ONLINE", "عاد المنافس إلى الاتصال")
		"error":
			connection_deadline = 0
			phase = "home"
			_show_matchmaking(false)
			home_primary_button.disabled = false
			home_secondary_button.disabled = false
			menu_subtitle.text = _tr("SERVER ERROR • ", "خطأ في الخادم • ") + str(p.get("code", "ERROR"))
			question_label.text = _tr("Server: ", "الخادم: ") + str(p.get("code", "ERROR"))
			status_label.text = _tr("PLEASE TRY AGAIN", "يرجى المحاولة مجدداً")

func _send(kind: String, payload: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	sequence += 1
	socket.send_text(JSON.stringify({"v": 1, "type": kind, "seq": sequence, "ts": Time.get_unix_time_from_system()*1000, "payload": payload}))

func _show_question(view: Dictionary) -> void:
	# Clear every visual from the previous question before validating the new payload.
	clue_label.text = ""
	clue_label.visible = false
	question_image.visible = false
	question_image.texture = null
	question_image_placeholder.visible = false
	question_image_generation += 1
	if is_instance_valid(question_image_request):
		question_image_request.cancel_request()
		question_image_request.queue_free()
		question_image_request = null
	current_options.clear()
	option_buttons.clear()
	var prompt := str(view.get("prompt", "")).strip_edges()
	var incoming_options: Array = view.get("options", [])
	if prompt.is_empty() or incoming_options.size() < 2:
		question_label.text = _tr("Question unavailable. Waiting for the next round…", "السؤال غير متاح. ننتظر الجولة التالية…")
		_clear_options()
		action_box.visible = false
		push_warning("Rejected incomplete question view from server.")
		return
	for option in incoming_options:
		if not (option is Dictionary) or str(option.get("id", "")).is_empty() or str(option.get("text", "")).strip_edges().is_empty():
			question_label.text = _tr("Question unavailable. Waiting for the next round…", "السؤال غير متاح. ننتظر الجولة التالية…")
			_clear_options()
			action_box.visible = false
			push_warning("Rejected question with an incomplete answer option.")
			return
	question_label.text = prompt
	question_label.text_direction = Control.TEXT_DIRECTION_AUTO
	question_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	options_box.columns = 2 if incoming_options.size() >= 4 and get_viewport().get_visible_rect().size.x >= 600.0 else 1
	options_box.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	clue_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	selected_option_id = ""
	status_label.add_theme_color_override("font_color", Color(0.65,0.82,1.0))
	clue_label.add_theme_font_size_override("font_size", 19)
	clue_label.add_theme_color_override("font_color", Color(1.0,0.82,0.35))
	var difficulty := int(view.get("difficulty", 1))
	var difficulty_stars := "★".repeat(clampi(difficulty, 1, 5))
	question_meta_label.text = _tr("THE MILLION-POINT CHALLENGE", "تحدي المليون") + "   •   " + _tr("LEVEL ", "المستوى ") + str(difficulty) + "/5"
	var image_path := str(view.get("imagePath", "")).strip_edges()
	if image_path.is_empty():
		var media_items: Array = view.get("media", [])
		if not media_items.is_empty() and media_items[0] is Dictionary:
			image_path = str(media_items[0].get("url", "")).strip_edges()
	var expects_image := str(view.get("format", "")) == "blur_reveal" or not image_path.is_empty()
	if expects_image:
		question_image_placeholder.visible = true
		question_image_placeholder.text = _tr("LOADING IMAGE…", "جارٍ تحميل الصورة…")
		if image_path.begins_with("user://"):
			var local_image := Image.new()
			if local_image.load(image_path) == OK:
				question_image.texture = ImageTexture.create_from_image(local_image)
				question_image.visible = true
				question_image_placeholder.visible = false
			else:
				question_image_placeholder.text = _tr("IMAGE NOT FOUND", "لم يتم العثور على الصورة")
		elif image_path.begins_with("res://"):
			if ResourceLoader.exists(image_path):
				var local_texture := load(image_path) as Texture2D
				if local_texture:
					question_image.texture = local_texture
					question_image.visible = true
					question_image_placeholder.visible = false
				else:
					question_image_placeholder.text = _tr("IMAGE UNAVAILABLE", "الصورة غير متاحة")
			else:
				question_image_placeholder.text = _tr("IMAGE NOT FOUND", "لم يتم العثور على الصورة")
		elif image_path.begins_with("https://") or image_path.begins_with("http://"):
			question_image_request = HTTPRequest.new()
			question_image_request.timeout = 12.0
			add_child(question_image_request)
			var request_generation := question_image_generation
			question_image_request.request_completed.connect(_on_question_image_loaded.bind(request_generation))
			if question_image_request.request(image_path) != OK:
				question_image_request.queue_free()
				question_image_request = null
				question_image_placeholder.text = _tr("IMAGE UNAVAILABLE", "الصورة غير متاحة")
		else:
			question_image_placeholder.text = _tr("INVALID IMAGE PATH", "مسار الصورة غير صالح")
	if expects_image and image_path.is_empty():
		question_image_placeholder.text = _tr("IMAGE NOT CONFIGURED", "لم يتم إعداد صورة لهذا السؤال")
	# Render format-specific clues: the old client showed only the prompt and
	# answer buttons, silently dropping emoji, career-path and statistics data.
	var format_data: Dictionary = view.get("formatData", {})
	var format_type := str(format_data.get("type", view.get("format", "mc")))
	clue_label.text = ""
	clue_label.visible = false
	if format_type == "emoji_story":
		# Android Godot fonts do not reliably contain flag/emoji glyphs; use bundled vector artwork.
		var clue_id := str(view.get("questionId", ""))
		var clue_path := "res://assets/question_clues/" + clue_id + ".svg"
		if ResourceLoader.exists(clue_path):
			question_image.texture = load(clue_path) as Texture2D
			question_image.visible = question_image.texture != null
			question_image_placeholder.visible = false
		else:
			clue_label.text = str(format_data.get("emoji", "")).replace("\u2066", "").replace("\u2069", "")
			clue_label.add_theme_font_size_override("font_size", 34)
			clue_label.visible = not clue_label.text.strip_edges().is_empty()
	elif format_type == "career_path":
		var career_clubs: Array = format_data.get("clubs", [])
		var club_names: Array[String] = []
		for club in career_clubs:
			if club is Dictionary and not str(club.get("name", "")).is_empty():
				club_names.append(str(club.get("name", "")))
		clue_label.text = "   →   ".join(club_names)
		clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		clue_label.custom_minimum_size = Vector2(0, 48)
		clue_label.add_theme_font_size_override("font_size", 13)
		clue_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.40))
		clue_label.visible = not club_names.is_empty()
	elif format_type == "stat_highlow":
		clue_label.text = str(format_data.get("statLabel", ""))
		clue_label.add_theme_font_size_override("font_size", 24)
		clue_label.visible = not clue_label.text.is_empty()
	_clear_options()
	selected_option_id = ""
	option_buttons.clear()
	current_options = incoming_options
	for index in range(current_options.size()):
		var option: Dictionary = current_options[index]
		var letter: String = ["A", "B", "C", "D", "E", "F"][index % 6]
		var b := _make_button(letter + "     " + str(option.get("text", "")), Color(0.018,0.075,0.16), Color(0.82,0.61,0.25), 56)
		b.add_theme_font_size_override("font_size", 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text_direction = Control.TEXT_DIRECTION_AUTO
		var option_id := str(option.get("id", ""))
		b.set_meta("option_id", option_id)
		b.pressed.connect(func(): _submit_answer(option_id))
		options_box.add_child(b)
		option_buttons[option_id] = b
	action_box.visible = false

func _on_question_image_loaded(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, generation: int) -> void:
	if generation != question_image_generation:
		return
	if is_instance_valid(question_image_request):
		question_image_request.queue_free()
		question_image_request = null
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or body.is_empty():
		question_image_placeholder.text = _tr("IMAGE UNAVAILABLE", "الصورة غير متاحة")
		return
	var image := Image.new()
	var error := image.load_webp_from_buffer(body)
	if error != OK:
		error = image.load_png_from_buffer(body)
	if error != OK:
		error = image.load_jpg_from_buffer(body)
	if error != OK:
		question_image_placeholder.text = _tr("UNSUPPORTED IMAGE FORMAT", "صيغة الصورة غير مدعومة")
		push_warning("Question media could not be decoded.")
		return
	question_image.texture = ImageTexture.create_from_image(image)
	question_image.visible = true
	question_image_placeholder.visible = false

func _tr(en: String, ar: String) -> String:
	return ar if locale == "ar" else en

func _apply_locale() -> void:
	if is_instance_valid(locale_button):
		locale_button.text = "English" if locale == "ar" else "العربية"
	if is_instance_valid(menu_title):
		menu_title.text = "GRID & GLORY"
	if is_instance_valid(title_label):
		title_label.text = _tr("GRID & GLORY  •  MATCHDAY", "GRID & GLORY  •  يوم المباراة")
		menu_title.layout_direction = Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(menu_feature_label):
		menu_feature_label.text = _tr("⚽  1v1 FOOTBALL TRIVIA  •  RISE TO LEGEND", "⚽  تحدي كرة القدم  •  كن أسطورة")
		menu_feature_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(menu_footer_label):
		menu_footer_label.text = _tr("ONLINE DUELS  •  SMART AI  •  FOOTBALL KNOWLEDGE", "مواجهات مباشرة  •  ذكاء اصطناعي  •  ثقافة كروية")
		menu_footer_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(question_label):
		question_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(status_label):
		status_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(score_label):
		score_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(pitch_status):
		pitch_status.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(clue_label):
		clue_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(matchmaking_label):
		matchmaking_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if locale == "ar" else Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(menu_subtitle) and phase == "home":
		menu_subtitle.text = "معركة معلومات كرة القدم" if locale == "ar" else "THE ULTIMATE FOOTBALL QUIZ BATTLE"
	if is_instance_valid(home_primary_button) and phase != "ended":
		home_primary_button.text = "العب عبر الإنترنت" if locale == "ar" else "PLAY ONLINE"
	if is_instance_valid(home_secondary_button) and phase != "ended":
		home_secondary_button.text = "العب ضد الذكاء الاصطناعي" if locale == "ar" else "PLAY VS AI"
	if is_instance_valid(match_sound_button):
		match_sound_button.text = _tr("SOUND OFF  ×", "الصوت مغلق  ×") if sound_muted else _tr("SOUND ON  ♪", "الصوت يعمل  ♪")
	if is_instance_valid(home_sound_button):
		home_sound_button.text = _tr("SOUND OFF  ×", "الصوت مغلق  ×") if sound_muted else _tr("SOUND ON  ♪", "الصوت يعمل  ♪")

func _submit_answer(option_id: String) -> void:
	if selected or current_token.is_empty():
		return
	selected = true
	selected_option_id = option_id
	_send("round.answer", {"token": current_token, "optionId": option_id, "clientMs": Time.get_ticks_msec()})
	for child in options_box.get_children():
		if child is Button:
			child.disabled = true
			if str(child.get_meta("option_id", "")) == option_id:
				child.add_theme_stylebox_override("normal", _panel_style(Color(0.34,0.22,0.055), Color(1.0,0.72,0.18), 2))
				child.add_theme_color_override("font_color", Color.WHITE)
	status_label.text = _tr("ANSWER SENT • WAITING FOR RESULT", "تم إرسال الإجابة • ننتظر النتيجة")

func _show_answer_feedback(correct_id: String, was_correct: bool, update_status := true) -> void:
	for option in current_options:
		if not (option is Dictionary):
			continue
		var oid := str(option.get("id", ""))
		var button: Button = option_buttons.get(oid)
		if not is_instance_valid(button):
			continue
		var is_right := not correct_id.is_empty() and oid == correct_id
		var is_selected := oid == selected_option_id
		if is_right:
			button.add_theme_stylebox_override("normal", _panel_style(Color(0.025,0.38,0.16), Color(0.18,0.95,0.40), 2))
			button.add_theme_color_override("font_color", Color.WHITE)
		elif is_selected and not was_correct:
			button.add_theme_stylebox_override("normal", _panel_style(Color(0.40,0.045,0.06), Color(1.0,0.22,0.20), 2))
			button.add_theme_color_override("font_color", Color.WHITE)
		button.disabled = true
	if update_status:
		status_label.text = _tr("CORRECT", "إجابة صحيحة") if was_correct else _tr("WRONG", "إجابة خاطئة")

func _paint_answer_result(correct_id: String) -> void:
	for child in options_box.get_children():
		if not child is Button:
			continue
		var option_button := child as Button
		var option_id := str(option_button.get_meta("option_id", ""))
		if option_id == correct_id:
			option_button.add_theme_stylebox_override("normal", _panel_style(Color(0.035, 0.34, 0.16), Color(0.20, 0.95, 0.43), 3))
			option_button.add_theme_stylebox_override("hover", _panel_style(Color(0.035, 0.34, 0.16), Color(0.20, 0.95, 0.43), 3))
		elif option_id == selected_option_id:
			option_button.add_theme_stylebox_override("normal", _panel_style(Color(0.40, 0.055, 0.07), Color(1.0, 0.25, 0.22), 3))
			option_button.add_theme_stylebox_override("hover", _panel_style(Color(0.40, 0.055, 0.07), Color(1.0, 0.25, 0.22), 3))

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
	score_label.text = _tr("YOU  ", "أنت  ") + str(my_goals) + "  —  " + str(rival_goals) + _tr("  RIVAL", "  الخصم")

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
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not player_id.is_empty():
		_send("queue.leave", {})
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	socket = WebSocketPeer.new()
	connected = false
	player_id = ""
	session_token = ""
	connection_deadline = 0
	countdown_deadline = 0
	selected = false
	current_token = ""
	phase = "home"
	_show_home()
	_apply_locale()
	_save_settings()

func _toggle_sound() -> void:
	sound_muted = not sound_muted
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, sound_muted)
	if is_instance_valid(home_sound_button):
		home_sound_button.text = _tr("SOUND OFF  ×", "الصوت مغلق  ×") if sound_muted else _tr("SOUND ON  ♪", "الصوت يعمل  ♪")
	if is_instance_valid(match_sound_button):
		match_sound_button.text = _tr("SOUND OFF  ×", "الصوت مغلق  ×") if sound_muted else _tr("SOUND ON  ♪", "الصوت يعمل  ♪")
	_save_settings()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		sound_muted = bool(config.get_value("audio", "muted", false))
		locale = str(config.get_value("game", "locale", "en"))
		if locale not in ["en", "ar"]:
			locale = "en"
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_mute(bus, sound_muted)
	_toggle_sound_label()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "muted", sound_muted)
	config.set_value("game", "locale", locale)
	config.save("user://settings.cfg")

func _toggle_sound_label() -> void:
	var label := _tr("SOUND OFF  ×", "الصوت مغلق  ×") if sound_muted else _tr("SOUND ON  ♪", "الصوت يعمل  ♪")
	if is_instance_valid(home_sound_button):
		home_sound_button.text = label
	if is_instance_valid(match_sound_button):
		match_sound_button.text = label

func _update_pitch_state() -> void:
	if not is_instance_valid(home_player) or not is_instance_valid(away_player):
		return
	# Reposition the 22 players only when the authoritative zone changes.
	if rendered_home_zone != my_zone:
		rendered_home_zone = my_zone
		var home_base := [Vector3(0,0,21),Vector3(-10,0,14),Vector3(-3.3,0,15),Vector3(3.3,0,15),Vector3(10,0,14),Vector3(-7,0,5),Vector3(0,0,7),Vector3(7,0,5),Vector3(-8,0,-6),Vector3(0,0,-8),Vector3(8,0,-6)]
		var shift := float(my_zone) * 2.1
		for i in range(home_team.size()):
			home_team[i].position = home_base[i] + Vector3(0,0,-shift)
	if rendered_away_zone != rival_zone:
		rendered_away_zone = rival_zone
		var away_base := [Vector3(0,0,-21),Vector3(10,0,-14),Vector3(3.3,0,-15),Vector3(-3.3,0,-15),Vector3(-10,0,-14),Vector3(7,0,-5),Vector3(0,0,-7),Vector3(-7,0,-5),Vector3(8,0,6),Vector3(0,0,8),Vector3(-8,0,6)]
		var shift := float(rival_zone) * 2.1
		for i in range(away_team.size()):
			away_team[i].position = away_base[i] + Vector3(0,0,shift)
	# Animate only the two featured players; reserve players remain static.
	var gait := float(Time.get_ticks_msec()) * 0.012
	_animate_player(home_player, gait)
	_animate_player(away_player, -gait)
	var next_status := _tr("ATTACKING • ZONE ", "هجوم • المنطقة ") + str(my_zone) if my_zone > rival_zone else _tr("DEFENDING • WIN THE BALL", "دفاع • استعد الكرة")
	if rendered_pitch_status != next_status:
		rendered_pitch_status = next_status
		pitch_status.text = next_status

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
	# All game sounds are synthesized locally: no downloads, permissions or network dependency.
	_create_audio_player("ambience", true, -24.0)
	_create_audio_player("cheer", false, -5.0)
	_create_audio_player("whistle", false, -8.0)
	_create_audio_player("kick", false, -10.0)
	_create_audio_player("ui_click", false, -12.0)
	_create_ui_click_sound()
	_create_match_sounds()
	if audio_players["ambience"].stream:
		audio_players["ambience"].play()

func _create_match_sounds() -> void:
	audio_players["ambience"].stream = _make_synth_stream("ambience", 3.0, true)
	audio_players["cheer"].stream = _make_synth_stream("cheer", 1.65, false)
	audio_players["whistle"].stream = _make_synth_stream("whistle", 0.72, false)
	audio_players["kick"].stream = _make_synth_stream("kick", 0.24, false)

func _make_synth_stream(kind: String, duration: float, looping: bool) -> AudioStreamWAV:
	var sample_rate := 22050
	var count := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var smooth_noise := 0.0
	for i in range(count):
		var t := float(i) / float(sample_rate)
		var progress := float(i) / float(maxi(1, count - 1))
		var sample := 0.0
		if kind == "whistle":
			var envelope := minf(1.0, t * 22.0) * exp(-2.1 * t)
			var frequency := lerpf(1780.0, 1320.0, progress)
			sample = sin(TAU * frequency * t) * envelope * 0.42
		elif kind == "kick":
			var envelope := exp(-24.0 * t)
			sample = (sin(TAU * lerpf(105.0, 42.0, progress) * t) * 0.72 + randf_range(-1.0, 1.0) * 0.28) * envelope * 0.78
		elif kind == "cheer":
			var fade := minf(1.0, t * 5.0) * minf(1.0, (duration - t) * 2.5)
			smooth_noise = smooth_noise * 0.91 + randf_range(-1.0, 1.0) * 0.09
			var chant := sin(TAU * 118.0 * t) * 0.16 + sin(TAU * 176.0 * t) * 0.10
			sample = (smooth_noise * 0.72 + chant) * fade * 0.62
		else:
			smooth_noise = smooth_noise * 0.96 + randf_range(-1.0, 1.0) * 0.04
			var crowd_hum := sin(TAU * 83.0 * t) * 0.025 + sin(TAU * 127.0 * t) * 0.018
			sample = smooth_noise * 0.11 + crowd_hum
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
	return stream

func _create_ui_click_sound() -> void:
	# A tiny synthesized UI tick: no external file, network request or third-party license.
	var sample_rate := 22050
	var sample_count := int(sample_rate * 0.055)
	var samples := PackedByteArray()
	samples.resize(sample_count * 2)
	for i in range(sample_count):
		var t := float(i) / float(sample_count)
		var frequency := lerpf(980.0, 520.0, t)
		var envelope := exp(-42.0 * t)
		var sample := sin(TAU * frequency * t) * envelope * 0.16
		samples.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = samples
	audio_players["ui_click"].stream = stream

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
