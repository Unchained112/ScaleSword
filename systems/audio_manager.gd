class_name AudioManager
extends Node

enum MusicContext {
	MENU,
	COMBAT,
	BOSS,
	UPGRADE,
	RESULT,
}

const MUSIC_STREAMS := [
	preload("res://audio/music/Week 1 - Retro Lounge BASE.ogg"),
	preload("res://audio/music/Week 1 - Retro Lounge MELODY.ogg"),
	preload("res://audio/music/Week 4 - Cloak of Darkness STAGE 1.ogg"),
	preload("res://audio/music/Week 4 - Cloak of Darkness STAGE 2.ogg"),
]
const UI_HOVER := preload("res://audio/sfx/ui/mouse_hover.ogg")
const UI_CLICK := preload("res://audio/sfx/ui/click1.ogg")
const GAME_STREAMS := {
	&"walk": preload("res://audio/sfx/game/human_walk.wav"),
	&"dodge": preload("res://audio/sfx/game/human_dash.wav"),
	&"charge": preload("res://audio/sfx/game/human_charging_1_loop.wav"),
	&"swing_light": preload("res://audio/sfx/game/human_atk_sword_1.wav"),
	&"swing_heavy": preload("res://audio/sfx/game/human_atk_sword_2.wav"),
	&"hit_light": preload("res://audio/sfx/game/sword_hit_1.wav"),
	&"hit_heavy": preload("res://audio/sfx/game/sword_hit_2.wav"),
	&"enemy_move": preload("res://audio/sfx/game/enemy_move.wav"),
	&"enemy_dash": preload("res://audio/sfx/game/enemy_dash.wav"),
	&"enemy_spell": preload("res://audio/sfx/game/enemy_spell.wav"),
}
const RATE_LIMITS_MSEC := {
	&"hit_light": 45,
	&"hit_heavy": 55,
	&"enemy_move": 180,
	&"enemy_dash": 90,
	&"enemy_spell": 90,
}
const WALK_VOLUME_DB := 12.0
const CHARGE_START_VOLUME_DB := 3.0
const CHARGE_FULL_VOLUME_DB := 9.0
const CHARGE_START_PITCH := 0.85
const CHARGE_FULL_PITCH := 1.25

var _music_players: Array[AudioStreamPlayer] = []
var _music_context := MusicContext.MENU
var _music_tween: Tween
var _charge_player: AudioStreamPlayer
var _walk_player: AudioStreamPlayer
var _last_played_msec: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("audio_manager")
	_build_music_players()
	_charge_player = _create_loop_player(
		GAME_STREAMS[&"charge"],
		"SFX",
		CHARGE_START_VOLUME_DB
	)
	_walk_player = _create_loop_player(
		GAME_STREAMS[&"walk"],
		"SFX",
		WALK_VOLUME_DB
	)
	get_tree().node_added.connect(_on_node_added)
	_wire_existing_buttons()
	set_music_context(MusicContext.MENU, true)


func set_music_context(context: MusicContext, immediate := false) -> void:
	_music_context = context
	var targets := [-60.0, -60.0, -60.0, -60.0]
	match context:
		MusicContext.MENU:
			targets[0] = -10.0
		MusicContext.COMBAT:
			targets[2] = -9.0
		MusicContext.BOSS:
			targets[3] = -8.0
		MusicContext.UPGRADE, MusicContext.RESULT:
			targets[0] = -12.0
			targets[1] = -12.0
	if is_instance_valid(_music_tween):
		_music_tween.kill()
	if immediate:
		for index in _music_players.size():
			_music_players[index].volume_db = targets[index]
		return
	_music_tween = create_tween()
	_music_tween.set_ignore_time_scale(true)
	_music_tween.set_parallel(true)
	for index in _music_players.size():
		_music_tween.tween_property(_music_players[index], "volume_db", targets[index], 0.60)


func play_game_sfx(event_id: StringName, _world_position := Vector2.ZERO, pitch := 1.0) -> void:
	if event_id == &"charge_start":
		start_charge()
		return
	if event_id == &"charge_stop":
		stop_charge()
		return
	if not GAME_STREAMS.has(event_id):
		return
	var now := Time.get_ticks_msec()
	var limit := int(RATE_LIMITS_MSEC.get(event_id, 0))
	if now - int(_last_played_msec.get(event_id, -100000)) < limit:
		return
	_last_played_msec[event_id] = now
	var player := AudioStreamPlayer.new()
	player.stream = GAME_STREAMS[event_id]
	player.bus = &"SFX"
	player.pitch_scale = pitch
	player.volume_db = -7.0 if event_id in [&"swing_heavy", &"hit_heavy", &"enemy_dash"] else -10.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func update_charge(progress: float) -> void:
	if _charge_player.playing:
		var safe_progress := clampf(progress, 0.0, 1.0)
		_charge_player.pitch_scale = lerpf(
			CHARGE_START_PITCH,
			CHARGE_FULL_PITCH,
			safe_progress
		)
		_charge_player.volume_db = lerpf(
			CHARGE_START_VOLUME_DB,
			CHARGE_FULL_VOLUME_DB,
			safe_progress
		)


func start_charge() -> void:
	_charge_player.stop()
	_charge_player.pitch_scale = CHARGE_START_PITCH
	_charge_player.volume_db = CHARGE_START_VOLUME_DB
	_charge_player.play()


func stop_charge() -> void:
	if _charge_player.playing:
		_charge_player.stop()


func set_player_walking(moving: bool) -> void:
	if moving and not _walk_player.playing:
		_walk_player.play()
	elif not moving and _walk_player.playing:
		_walk_player.stop()


func play_ui_hover() -> void:
	_play_ui(UI_HOVER, -10.0)


func play_ui_confirm() -> void:
	_play_ui(UI_CLICK, -7.0)


func stop_continuous_sfx() -> void:
	stop_charge()
	_walk_player.stop()


func _build_music_players() -> void:
	for stream in MUSIC_STREAMS:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = &"Music"
		player.volume_db = -60.0
		add_child(player)
		player.play()
		_music_players.append(player)


func _create_loop_player(stream: AudioStream, bus_name: StringName, volume: float) -> AudioStreamPlayer:
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus_name
	player.volume_db = volume
	add_child(player)
	return player


func _play_ui(stream: AudioStream, volume: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"UI"
	player.volume_db = volume
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _wire_existing_buttons() -> void:
	for node in get_tree().get_nodes_in_group("audio_button"):
		_wire_button(node as Button)
	_wire_buttons_recursive(get_tree().root)


func _wire_buttons_recursive(node: Node) -> void:
	if node is Button:
		_wire_button(node as Button)
	for child in node.get_children():
		_wire_buttons_recursive(child)


func _on_node_added(node: Node) -> void:
	if node is Button:
		_wire_button.call_deferred(node as Button)


func _wire_button(button: Button) -> void:
	if not is_instance_valid(button):
		return
	var hover_callable := Callable(self, "play_ui_hover")
	var click_callable := Callable(self, "play_ui_confirm")
	if not button.mouse_entered.is_connected(hover_callable):
		button.mouse_entered.connect(hover_callable)
	if not button.pressed.is_connected(click_callable):
		button.pressed.connect(click_callable)
