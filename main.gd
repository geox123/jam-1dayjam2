extends Node2D

const GameRulesScript = preload("res://game_rules.gd")
const LeaderboardConfigScript = preload("res://leaderboard_config.gd")
const LeaderboardClientScript = preload("res://leaderboard_client.gd")

enum GameState { TITLE, TUTORIAL, RUN, FAILED }
enum HazardKind { TURBULENCE, DEBRIS, VENT }

const VIEW_SIZE := Vector2(960.0, 540.0)
const ARENA := Rect2(60.0, 82.0, 840.0, 400.0)
const BALLOON_RADIUS := 16.0
const MAX_SPEED := 270.0
const ACCELERATION := 720.0
const DRAG := 105.0
const GUST_COOLDOWN := 2.0
const GUST_RADIUS := 150.0

const NAVY := Color("07112f")
const NAVY_LIGHT := Color("101e49")
const PALE := Color("e7f7ff")
const CYAN := Color("63e5f2")
const CYAN_SOFT := Color(0.39, 0.90, 0.95, 0.25)
const ORANGE := Color("ffb454")
const RED := Color("ff647c")

var state := GameState.TITLE
var balloon_position := Vector2(480.0, 282.0)
var balloon_velocity := Vector2.ZERO
var input_direction := Vector2.ZERO
var ambient_current := Vector2.ZERO
var hazards: Array[Dictionary] = []
var elapsed := 0.0
var score := 0.0
var risk_multiplier := 1.0
var high_score := 0.0
var gust_cooldown := 0.0
var gust_pulse := 0.0
var near_miss_flash := 0.0
var failure_flash := 0.0
var tutorial_elapsed := 0.0
var spawn_timer := 0.0
var gust_was_down := false
var rng := RandomNumberGenerator.new()
var font: Font
var audio_player: AudioStreamPlayer
var audio_playback: AudioStreamGeneratorPlayback
var audio_phase := 0.0
var audio_pulse := 0.0
var audio_frequency := 220.0
var title_time := 0.0
var leaderboard: Node
var leaderboard_scores: Array = []
var leaderboard_open := false
var leaderboard_status := ""
var name_input: LineEdit


func _ready() -> void:
	rng.seed = 4815162342
	font = ThemeDB.fallback_font
	if DisplayServer.get_name() != "headless":
		var generator := AudioStreamGenerator.new()
		generator.mix_rate = 22050.0
		generator.buffer_length = 0.2
		audio_player = AudioStreamPlayer.new()
		audio_player.stream = generator
		add_child(audio_player)
		audio_player.play()
		audio_playback = audio_player.get_stream_playback() as AudioStreamGeneratorPlayback
	leaderboard = LeaderboardClientScript.new()
	leaderboard.configure(LeaderboardConfigScript.SUPABASE_URL, LeaderboardConfigScript.SUPABASE_PUBLISHABLE_KEY)
	leaderboard.scores_received.connect(_on_scores_received)
	leaderboard.score_submitted.connect(_on_score_submitted)
	leaderboard.request_failed.connect(_on_leaderboard_failed)
	add_child(leaderboard)
	name_input = LineEdit.new()
	name_input.placeholder_text = "YOUR NAME"
	name_input.text = "PLAYER"
	name_input.max_length = 12
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input.position = Vector2(340, 350)
	name_input.size = Vector2(280, 34)
	name_input.visible = false
	name_input.text_submitted.connect(_submit_current_score)
	add_child(name_input)
	_load_high_score()
	queue_redraw()


func _process(delta: float) -> void:
	title_time += delta
	match state:
		GameState.TITLE:
			queue_redraw()
		GameState.TUTORIAL:
			tutorial_elapsed += delta
			if tutorial_elapsed >= 3.0:
				start_run()
			queue_redraw()
		GameState.RUN:
			_update_run(delta)
			_update_audio(delta)
			queue_redraw()
		GameState.FAILED:
			failure_flash = max(0.0, failure_flash - delta * 2.0)
			_update_audio(delta)
			queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	if state == GameState.TITLE:
		if event.keycode == KEY_L:
			_toggle_leaderboard()
		else:
			_begin_tutorial()
	elif state == GameState.TUTORIAL:
		start_run()
	elif state == GameState.FAILED:
		if event.keycode == KEY_L:
			_toggle_leaderboard()
		elif event.keycode == KEY_ESCAPE:
			leaderboard_open = false
		elif (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER) and not leaderboard_open:
			start_run()
	elif leaderboard_open and event.keycode == KEY_ESCAPE:
		leaderboard_open = false


func _begin_tutorial() -> void:
	state = GameState.TUTORIAL
	tutorial_elapsed = 0.0


func start_run() -> void:
	state = GameState.RUN
	balloon_position = ARENA.get_center()
	balloon_velocity = Vector2.ZERO
	hazards.clear()
	elapsed = 0.0
	score = 0.0
	risk_multiplier = 1.0
	gust_cooldown = 0.0
	gust_pulse = 0.0
	near_miss_flash = 0.0
	spawn_timer = 0.45
	gust_was_down = false
	leaderboard_open = false
	if name_input:
		name_input.visible = false


func _update_run(delta: float) -> void:
	input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# The built-in UI actions provide a second path for browser keyboard layouts.
	var ui_direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	input_direction = (input_direction + ui_direction).limit_length(1.0)
	ambient_current = Vector2(sin(elapsed * 0.55), cos(elapsed * 0.41)).normalized() * 22.0
	balloon_velocity += ambient_current * delta
	if input_direction != Vector2.ZERO:
		balloon_velocity = balloon_velocity.move_toward(input_direction * MAX_SPEED, ACCELERATION * delta)
	else:
		balloon_velocity = balloon_velocity.move_toward(Vector2.ZERO, DRAG * delta)
	balloon_position += balloon_velocity * delta
	_keep_balloon_in_room()

	var space_down := Input.is_key_pressed(KEY_SPACE)
	if space_down and not gust_was_down:
		_activate_gust()
	gust_was_down = space_down

	elapsed += delta
	gust_cooldown = max(0.0, gust_cooldown - delta)
	gust_pulse = max(0.0, gust_pulse - delta)
	near_miss_flash = max(0.0, near_miss_flash - delta)
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_hazard()
		spawn_timer = max(0.38, 1.1 - elapsed * 0.006)

	var had_near_miss := false
	for i in range(hazards.size() - 1, -1, -1):
		var hazard := hazards[i]
		hazard["position"] += hazard["velocity"] * delta
		hazard["age"] += delta
		if hazard["kind"] == HazardKind.TURBULENCE:
			_apply_turbulence(hazard, delta)
		var distance := balloon_position.distance_to(hazard["position"])
		var danger_radius: float = hazard["danger_radius"]
		var near_radius: float = danger_radius + 26.0
		if distance <= danger_radius + BALLOON_RADIUS:
			_fail_run()
			return
		if not hazard["near_missed"] and distance <= near_radius and distance > danger_radius + BALLOON_RADIUS:
			hazard["near_missed"] = true
			risk_multiplier = GameRulesScript.multiplier_after_near_miss(risk_multiplier)
			score += 10.0 * risk_multiplier
			near_miss_flash = 0.55
			_trigger_sound(520.0, 0.1)
			had_near_miss = true
		hazards[i] = hazard
		if _should_remove_hazard(hazard):
			hazards.remove_at(i)

	if not had_near_miss:
		risk_multiplier = GameRulesScript.multiplier_after_safe_moment(risk_multiplier, delta)
	score += GameRulesScript.score_for_survival(delta, risk_multiplier)


func _keep_balloon_in_room() -> void:
	var left := ARENA.position.x + BALLOON_RADIUS
	var right := ARENA.end.x - BALLOON_RADIUS
	var top := ARENA.position.y + BALLOON_RADIUS
	var bottom := ARENA.end.y - BALLOON_RADIUS
	if balloon_position.x < left:
		balloon_position.x = left
		balloon_velocity.x = abs(balloon_velocity.x) * 0.35
	elif balloon_position.x > right:
		balloon_position.x = right
		balloon_velocity.x = -abs(balloon_velocity.x) * 0.35
	if balloon_position.y < top:
		balloon_position.y = top
		balloon_velocity.y = abs(balloon_velocity.y) * 0.35
	elif balloon_position.y > bottom:
		balloon_position.y = bottom
		balloon_velocity.y = -abs(balloon_velocity.y) * 0.35


func _activate_gust() -> void:
	if gust_cooldown > 0.0:
		return
	gust_cooldown = GUST_COOLDOWN
	gust_pulse = 0.24
	_trigger_sound(220.0, 0.12)
	var boost_direction := balloon_velocity.normalized()
	if boost_direction == Vector2.ZERO:
		boost_direction = Vector2.UP
	balloon_velocity += boost_direction * 125.0
	for i in hazards.size():
		var hazard := hazards[i]
		var offset: Vector2 = hazard["position"] - balloon_position
		if offset.length() > GUST_RADIUS:
			continue
		var push_direction := offset.normalized()
		if push_direction == Vector2.ZERO:
			push_direction = Vector2.UP
		hazard["velocity"] += push_direction * 260.0
		hazards[i] = hazard


func _spawn_hazard() -> void:
	var phase := GameRulesScript.phase_for_time(elapsed)
	var kind := HazardKind.DEBRIS
	if phase == 1:
		kind = HazardKind.TURBULENCE if rng.randf() < 0.45 else HazardKind.DEBRIS
	elif phase == 2:
		kind = rng.randi_range(HazardKind.TURBULENCE, HazardKind.VENT)
	else:
		kind = rng.randi_range(HazardKind.TURBULENCE, HazardKind.VENT)

	var position := _edge_position()
	var velocity := Vector2.ZERO
	var radius := 18.0
	var danger_radius := 18.0
	if kind == HazardKind.TURBULENCE:
		position = Vector2(rng.randf_range(170.0, 790.0), rng.randf_range(165.0, 415.0))
		radius = 62.0
		danger_radius = 25.0
	elif kind == HazardKind.DEBRIS:
		velocity = (ARENA.get_center() - position).normalized() * rng.randf_range(90.0, 145.0) * (1.0 + elapsed / 150.0)
		radius = 18.0
		danger_radius = 18.0
	else:
		velocity = (ARENA.get_center() - position).normalized() * (210.0 + elapsed * 1.2)
		radius = 26.0
		danger_radius = 23.0
	hazards.append({
		"kind": kind,
		"position": position,
		"velocity": velocity,
		"radius": radius,
		"danger_radius": danger_radius,
		"age": 0.0,
		"near_missed": false,
	})


func _edge_position() -> Vector2:
	var side := rng.randi_range(0, 3)
	if side == 0:
		return Vector2(ARENA.position.x - 35.0, rng.randf_range(ARENA.position.y, ARENA.end.y))
	if side == 1:
		return Vector2(ARENA.end.x + 35.0, rng.randf_range(ARENA.position.y, ARENA.end.y))
	if side == 2:
		return Vector2(rng.randf_range(ARENA.position.x, ARENA.end.x), ARENA.position.y - 35.0)
	return Vector2(rng.randf_range(ARENA.position.x, ARENA.end.x), ARENA.end.y + 35.0)


func _apply_turbulence(hazard: Dictionary, delta: float) -> void:
	var offset: Vector2 = hazard["position"] - balloon_position
	if offset.length() < hazard["radius"]:
		var force := offset.normalized() * 38.0
		balloon_velocity += force * delta


func _should_remove_hazard(hazard: Dictionary) -> bool:
	return hazard["age"] > 9.0 or not ARENA.grow(100.0).has_point(hazard["position"])


func _fail_run() -> void:
	state = GameState.FAILED
	failure_flash = 1.0
	_trigger_sound(95.0, 0.3)
	if name_input:
		name_input.visible = true
		name_input.grab_focus()
	if score > high_score:
		high_score = score
		_save_high_score()


func _submit_current_score(player_name: String) -> void:
	if state != GameState.FAILED or player_name.strip_edges().is_empty():
		return
	name_input.visible = false
	leaderboard_status = "SUBMITTING SCORE..."
	leaderboard.submit_score(player_name, int(score), elapsed)


func _toggle_leaderboard() -> void:
	leaderboard_open = not leaderboard_open
	if leaderboard_open:
		leaderboard_status = "LOADING ARCADE SCORES..."
		leaderboard.load_scores()


func _on_scores_received(scores: Array) -> void:
	leaderboard_scores = scores
	leaderboard_status = ""


func _on_score_submitted() -> void:
	leaderboard_status = "SCORE POSTED  /  PRESS L TO VIEW"


func _on_leaderboard_failed(message: String) -> void:
	leaderboard_status = message.to_upper()


func _load_high_score() -> void:
	var config := ConfigFile.new()
	if config.load("user://airebound.cfg") == OK:
		high_score = float(config.get_value("scores", "high_score", 0.0))


func _save_high_score() -> void:
	var config := ConfigFile.new()
	config.set_value("scores", "high_score", high_score)
	config.save("user://airebound.cfg")


func _trigger_sound(frequency: float, duration: float) -> void:
	audio_frequency = frequency
	audio_pulse = max(audio_pulse, duration)


func _update_audio(delta: float) -> void:
	if audio_playback == null:
		return
	audio_phase += delta
	audio_pulse = max(0.0, audio_pulse - delta)
	var wind_amount: float = clampf(balloon_velocity.length() / MAX_SPEED, 0.0, 1.0)
	var frames: int = audio_playback.get_frames_available()
	for frame in frames:
		var frame_time: float = float(frame) / 22050.0
		var wind: float = sin((audio_phase + frame_time) * (55.0 + wind_amount * 30.0)) * (0.018 + wind_amount * 0.025)
		var pulse: float = sin((audio_phase + frame_time) * audio_frequency) * audio_pulse * 0.22
		var sample: float = wind + pulse
		audio_playback.push_frame(Vector2(sample, sample))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), NAVY)
	_draw_atmosphere()
	_draw_header()
	_draw_arena()
	if state == GameState.TITLE:
		_draw_title()
	elif state == GameState.TUTORIAL:
		_draw_tutorial()
	else:
		for hazard in hazards:
			_draw_hazard(hazard)
		_draw_balloon()
		_draw_hud()
		if state == GameState.FAILED:
			_draw_failure()
	if leaderboard_open:
		_draw_leaderboard()


func _draw_header() -> void:
	draw_line(Vector2(60, 56), Vector2(900, 56), Color(0.39, 0.90, 0.95, 0.22), 1.0)
	draw_circle(Vector2(43, 34), 4.0, ORANGE)
	draw_string(font, Vector2(60, 42), "AIREBOUND", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, PALE)
	draw_string(font, Vector2(0, 40), "AIR / ONE-DAY JAM", HORIZONTAL_ALIGNMENT_RIGHT, VIEW_SIZE.x, 13, Color(0.55, 0.72, 0.86, 0.8))


func _draw_atmosphere() -> void:
	# A restrained cockpit-like backdrop makes the air currents readable as data.
	for i in range(9):
		var x := 24.0 + i * 114.0
		draw_line(Vector2(x, 70), Vector2(x, 490), Color(0.20, 0.42, 0.66, 0.08), 1.0)
	for i in range(5):
		var y := 104.0 + i * 92.0
		draw_line(Vector2(24, y), Vector2(936, y), Color(0.20, 0.42, 0.66, 0.07), 1.0)
	draw_arc(Vector2(480, 282), 270.0, -2.7, -0.45, 36, Color(0.39, 0.90, 0.95, 0.10), 2.0)
	draw_arc(Vector2(480, 282), 310.0, 0.45, 2.7, 36, Color(1.0, 0.71, 0.33, 0.08), 2.0)


func _draw_arena() -> void:
	draw_rect(ARENA, NAVY_LIGHT, true)
	draw_rect(ARENA.grow(6.0), Color(0.39, 0.90, 0.95, 0.06), false, 8.0)
	draw_rect(ARENA, Color(0.30, 0.57, 0.72, 0.55), false, 2.0)
	var bracket_color := Color(0.39, 0.90, 0.95, 0.72)
	for corner in [ARENA.position, Vector2(ARENA.end.x, ARENA.position.y), Vector2(ARENA.position.x, ARENA.end.y), ARENA.end]:
		var sx := -1.0 if corner.x > ARENA.get_center().x else 1.0
		var sy := -1.0 if corner.y > ARENA.get_center().y else 1.0
		draw_line(corner, corner + Vector2(18.0 * sx, 0), bracket_color, 2.0)
		draw_line(corner, corner + Vector2(0, 18.0 * sy), bracket_color, 2.0)
	for i in range(7):
		var y := ARENA.position.y + 48.0 + i * 54.0
		var wave := sin(Time.get_ticks_msec() * 0.0016 + i * 0.7) * 18.0
		var start := Vector2(105.0 + wave, y)
		var finish := Vector2(270.0 + wave, y - 20.0)
		draw_line(start, finish, CYAN_SOFT, 2.0)
		draw_line(finish, finish - Vector2(10, -5), CYAN_SOFT, 2.0)
		draw_line(finish, finish - Vector2(10, 5), CYAN_SOFT, 2.0)
	for i in range(6):
		var x := 650.0 + i * 34.0
		var drift := sin(Time.get_ticks_msec() * 0.0012 + i) * 12.0
		draw_line(Vector2(x, 120 + drift), Vector2(x - 28, 180 + drift), Color(0.39, 0.90, 0.95, 0.16), 2.0)
	var current_direction := ambient_current.normalized()
	if current_direction == Vector2.ZERO:
		current_direction = Vector2.RIGHT
	var current_origin := ARENA.get_center()
	var current_tip := current_origin + current_direction * 56.0
	draw_line(current_origin - current_direction * 56.0, current_tip, Color(0.39, 0.90, 0.95, 0.32), 3.0)
	draw_line(current_tip, current_tip - current_direction.rotated(0.55) * 14.0, Color(0.39, 0.90, 0.95, 0.32), 3.0)
	draw_line(current_tip, current_tip - current_direction.rotated(-0.55) * 14.0, Color(0.39, 0.90, 0.95, 0.32), 3.0)


func _draw_balloon() -> void:
	if state == GameState.FAILED:
		return
	if gust_pulse > 0.0:
		var pulse_radius := GUST_RADIUS * (1.0 - gust_pulse / 0.24)
		draw_arc(balloon_position, pulse_radius, 0.0, TAU, 48, Color(0.39, 0.90, 0.95, gust_pulse * 2.0), 3.0)
	draw_circle(balloon_position + Vector2(3, 4), BALLOON_RADIUS + 5.0, Color(0.01, 0.04, 0.13, 0.75))
	draw_circle(balloon_position, BALLOON_RADIUS + 3.0, Color(0.39, 0.90, 0.95, 0.16))
	draw_circle(balloon_position, BALLOON_RADIUS, Color("b9f5f1"))
	draw_circle(balloon_position - Vector2(5, 5), 5.0, Color(1, 1, 1, 0.82))
	draw_arc(balloon_position, BALLOON_RADIUS, 0.0, TAU, 32, CYAN, 2.0)
	draw_line(balloon_position + Vector2(-5, 15), balloon_position + Vector2(0, 23), ORANGE, 2.0)
	draw_line(balloon_position + Vector2(5, 15), balloon_position + Vector2(0, 23), ORANGE, 2.0)


func _draw_hazard(hazard: Dictionary) -> void:
	var position: Vector2 = hazard["position"]
	var radius: float = hazard["radius"]
	var kind: int = hazard["kind"]
	if kind == HazardKind.TURBULENCE:
		draw_circle(position, radius, Color(1.0, 0.39, 0.49, 0.09))
		draw_arc(position, radius, 0.0, TAU, 40, Color(1.0, 0.39, 0.49, 0.42), 2.0)
		draw_arc(position, radius * 0.56, Time.get_ticks_msec() * 0.001, Time.get_ticks_msec() * 0.001 + 4.8, 24, RED, 2.0)
	elif kind == HazardKind.DEBRIS:
		draw_circle(position, radius, ORANGE)
		draw_circle(position, radius * 0.5, Color("f57d54"))
		draw_line(position - Vector2(radius, 0), position + Vector2(radius, 0), Color(1, 0.9, 0.6, 0.7), 2.0)
	else:
		draw_circle(position, radius, Color(1.0, 0.39, 0.49, 0.18))
		draw_arc(position, radius, 0.0, TAU, 24, RED, 3.0)
		draw_line(position - Vector2(8, 0), position + Vector2(8, 0), RED, 3.0)
		draw_line(position - Vector2(0, 8), position + Vector2(0, 8), RED, 3.0)


func _draw_hud() -> void:
	draw_string(font, Vector2(72, 516), "SCORE  %06d" % int(score), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PALE)
	draw_string(font, Vector2(330, 516), "RISK  x%.1f" % risk_multiplier, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ORANGE if risk_multiplier > 1.0 else PALE)
	draw_string(font, Vector2(650, 516), "GUST  READY" if gust_cooldown <= 0.0 else "GUST  %.1fs" % gust_cooldown, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, CYAN if gust_cooldown <= 0.0 else Color(0.55, 0.72, 0.86, 0.8))


func _draw_title() -> void:
	draw_rect(Rect2(190, 145, 580, 240), Color(0.02, 0.05, 0.15, 0.93), true)
	var title_bob := sin(title_time * 1.8) * 3.0
	var title_glow := 0.72 + sin(title_time * 2.4) * 0.12
	draw_string(font, Vector2(0, 220 + title_bob), "AIREBOUND", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 52, PALE)
	draw_string(font, Vector2(0, 258 + title_bob), "SURVIVE THE AIR", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 18, Color(CYAN, title_glow))
	draw_string(font, Vector2(0, 318), "ARROWS  /  STEER", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 17, Color(0.72, 0.84, 0.92, 0.9))
	draw_string(font, Vector2(0, 350), "SPACE  /  GUST", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 17, Color(0.72, 0.84, 0.92, 0.9))
	var prompt_alpha := 0.65 + (sin(title_time * 3.0) + 1.0) * 0.15
	draw_string(font, Vector2(0, 385), "PRESS ANY KEY TO BEGIN", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 14, Color(ORANGE, prompt_alpha))


func _draw_tutorial() -> void:
	draw_rect(Rect2(190, 145, 580, 240), Color(0.02, 0.05, 0.15, 0.85), true)
	draw_string(font, Vector2(0, 205), "THE ROOM IS MOVING", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 24, PALE)
	draw_string(font, Vector2(0, 253), "ARROWS", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 22, CYAN)
	draw_string(font, Vector2(0, 280), "float through the currents", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 16, Color(0.72, 0.84, 0.92, 0.9))
	draw_string(font, Vector2(0, 326), "SPACE", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 22, ORANGE)
	draw_string(font, Vector2(0, 353), "push the danger away", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 16, Color(0.72, 0.84, 0.92, 0.9))


func _draw_failure() -> void:
	draw_rect(Rect2(220, 174, 520, 184), Color(0.02, 0.04, 0.12, 0.94), true)
	draw_string(font, Vector2(0, 226), "AIR PRESSURE LOST", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 28, RED)
	draw_string(font, Vector2(0, 270), "SCORE  %06d" % int(score), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 20, PALE)
	draw_string(font, Vector2(0, 298), "BEST   %06d" % int(high_score), HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 16, Color(0.72, 0.84, 0.92, 0.9))
	draw_string(font, Vector2(0, 334), "TYPE NAME + ENTER  /  L FOR ARCADE", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 14, ORANGE)
	if not leaderboard_status.is_empty():
		draw_string(font, Vector2(0, 370), leaderboard_status, HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 12, Color(0.55, 0.72, 0.86, 0.85))


func _draw_leaderboard() -> void:
	draw_rect(Rect2(170, 96, 620, 350), Color(0.015, 0.035, 0.11, 0.98), true)
	draw_rect(Rect2(170, 96, 620, 350), CYAN, false, 2.0)
	draw_string(font, Vector2(0, 140), "AIREBOUND ARCADE", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 28, PALE)
	draw_string(font, Vector2(0, 166), "TOP TEN AIRWALKERS", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 13, CYAN)
	if leaderboard_scores.is_empty():
		draw_string(font, Vector2(0, 255), leaderboard_status if not leaderboard_status.is_empty() else "NO SCORES YET", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 16, Color(0.72, 0.84, 0.92, 0.9))
	else:
		for index in leaderboard_scores.size():
			var row: Dictionary = leaderboard_scores[index]
			var y := 210.0 + index * 21.0
			var name := str(row.get("player_name", "PLAYER"))
			var remote_score := int(row.get("score", 0))
			draw_string(font, Vector2(230, y), "%02d" % (index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ORANGE if index == 0 else Color(0.72, 0.84, 0.92, 0.9))
			draw_string(font, Vector2(280, y), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, PALE)
			draw_string(font, Vector2(670, y), "%06d" % remote_score, HORIZONTAL_ALIGNMENT_RIGHT, 80, 14, PALE)
	draw_string(font, Vector2(0, 425), "L / ESC  CLOSE", HORIZONTAL_ALIGNMENT_CENTER, VIEW_SIZE.x, 12, Color(0.55, 0.72, 0.86, 0.8))
