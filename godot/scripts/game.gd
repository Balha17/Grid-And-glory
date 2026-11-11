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

var camera: Camera3D
var ball: MeshInstance3D
var home_player: Node3D
var away_player: Node3D
var home_team: Array[Node3D] = []
var away_team: Array[Node3D] = []
var hud: CanvasLayer
var title_label: Label
var status_label: Label
var question_label: Label
var score_label: Label
var timer_label: Label
var options_box: VBoxContainer
var action_box: HBoxContainer
var connect_button: Button
var locale_button: Button
var pitch_status: Label
var countdown_deadline := 0
var countdown_duration := 0

func _ready() -> void:
	_build_stadium()
	_build_hud()
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
	add_child(world)

	camera = Camera3D.new()
	camera.position = Vector3(0, 39, 42)
	camera.rotation_degrees = Vector3(-43, 0, 0)
	camera.fov = 48
	add_child(camera)
	camera.current = true

	var stadium_light := DirectionalLight3D.new()
	stadium_light.rotation_degrees = Vector3(-55, -25, 0)
	stadium_light.light_energy = 1.25
	stadium_light.shadow_enabled = true
	add_child(stadium_light)

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
		add_child(h)
		home_team.append(h)
		var a := _make_player("AWAY_" + str(i+1), Color(1.0, 0.34, 0.19))
		a.position = away_positions[i]
		add_child(a)
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
	add_child(ball)
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
				add_child(seat)

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
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.62
	capsule.height = 1.9
	body.mesh = capsule
	body.position.y = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.12
	mat.roughness = 0.42
	body.material_override = mat
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.42
	head.mesh = sphere
	head.position.y = 2.12
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.88,0.68,0.52)
	head.material_override = skin
	root.add_child(head)
	return root

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
	add_child(node)

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
	add_child(ring)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(root)
	var top := PanelContainer.new()
	top.position = Vector2(18, 22)
	top.size = Vector2(684, 116)
	root.add_child(top)
	var topbox := VBoxContainer.new()
	top.add_child(topbox)
	title_label = Label.new()
	title_label.text = "GRID & GLORY  •  MATCHDAY"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	topbox.add_child(title_label)
	score_label = Label.new()
	score_label.text = "YOU  0  —  0  RIVAL"
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 28)
	topbox.add_child(score_label)
	status_label = Label.new()
	status_label.text = "3D STADIUM • ONLINE FOOTBALL QUIZ"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	topbox.add_child(status_label)
	var bottom := PanelContainer.new()
	bottom.anchor_left = 0
	bottom.anchor_right = 1
	bottom.anchor_top = 1
	bottom.anchor_bottom = 1
	bottom.offset_left = 18
	bottom.offset_right = -18
	bottom.offset_top = -440
	bottom.offset_bottom = -18
	root.add_child(bottom)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	bottom.add_child(content)
	pitch_status = Label.new()
	pitch_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pitch_status.add_theme_font_size_override("font_size", 18)
	content.add_child(pitch_status)
	question_label = Label.new()
	question_label.text = "Choose your arena"
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.add_theme_font_size_override("font_size", 22)
	content.add_child(question_label)
	timer_label = Label.new()
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 34)
	content.add_child(timer_label)
	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 7)
	content.add_child(options_box)
	action_box = HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(action_box)
	connect_button = Button.new()
	connect_button.text = "PLAY ONLINE"
	connect_button.custom_minimum_size = Vector2(260, 58)
	connect_button.pressed.connect(_on_online_pressed)
	action_box.add_child(connect_button)
	var ai_button := Button.new()
	ai_button.text = "PLAY VS AI"
	ai_button.custom_minimum_size = Vector2(180, 58)
	ai_button.pressed.connect(_on_ai_pressed)
	action_box.add_child(ai_button)
	locale_button = Button.new()
	locale_button.text = "العربية"
	locale_button.pressed.connect(_toggle_locale)
	action_box.add_child(locale_button)
	question_label.text = "A real 3D football arena awaits."
	status_label.text = "3D PITCH  •  STADIUM LIGHTS  •  GOALS"

func _show_home() -> void:
	phase = "home"
	question_label.text = "Choose your arena / اختر ساحة المنافسة"
	_clear_options()
	action_box.visible = true
	status_label.text = "3D STADIUM • GRID & GLORY"
	pitch_status.text = "TWO PLAYERS • ONE PITCH • ONE WINNER"

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
		"match.half":
			phase = "half_time"
			_read_scores(p)
			status_label.text = "HALF TIME"
			question_label.text = "Take a breath. Second half soon."
		"match.end":
			phase = "ended"
			_read_scores(p)
			countdown_deadline = 0
			status_label.text = "VICTORY!" if str(p.get("outcome", "")) == "win" else "FULL TIME"
			question_label.text = "FINAL SCORE  •  " + str(my_goals) + " — " + str(rival_goals)
			_clear_options()
			_add_action_button("PLAY AGAIN", _on_ai_pressed)
			_add_action_button("HOME", _show_home)
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
	question_label.text = str(view.get("prompt", ""))
	_clear_options()
	current_options = view.get("options", [])
	for option in current_options:
		var b := Button.new()
		b.text = str(option.get("text", ""))
		b.custom_minimum_size = Vector2(0, 48)
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
	locale_button.text = "English" if locale == "ar" else "العربية"
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send("queue.leave", {})
		socket.close()
		connected = false
		phase = "home"
		question_label.text = "Reconnect to apply language."
		status_label.text = "LANGUAGE CHANGED"

func _update_pitch_state() -> void:
	if not is_instance_valid(home_player) or not is_instance_valid(away_player):
		return
	var home_shift := float(my_zone) * 2.1
	var away_shift := float(rival_zone) * 2.1
	var home_base := [Vector3(0,0,21),Vector3(-10,0,14),Vector3(-3.3,0,15),Vector3(3.3,0,15),Vector3(10,0,14),Vector3(-7,0,5),Vector3(0,0,7),Vector3(7,0,5),Vector3(-8,0,-6),Vector3(0,0,-8),Vector3(8,0,-6)]
	var away_base := [Vector3(0,0,-21),Vector3(10,0,-14),Vector3(3.3,0,-15),Vector3(-3.3,0,-15),Vector3(-10,0,-14),Vector3(7,0,-5),Vector3(0,0,-7),Vector3(-7,0,-5),Vector3(8,0,6),Vector3(0,0,8),Vector3(-8,0,6)]
	for i in range(home_team.size()):
		var target: Vector3 = home_base[i] + Vector3(0,0,-home_shift)
		home_team[i].position = home_team[i].position.lerp(target, 0.025)
	for i in range(away_team.size()):
		var target: Vector3 = away_base[i] + Vector3(0,0,away_shift)
		away_team[i].position = away_team[i].position.lerp(target, 0.025)
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
