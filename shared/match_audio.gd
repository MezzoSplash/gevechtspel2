class_name MatchAudio
extends RefCounted
## Match music and stings (#106): menu loop, round-start sting, tension music near the end or when someone
## is close to winning. Static helpers on the Game autoload `game`; Game keeps the players and state.


## Round-start music, from the end of the intermission into the round.
static func play_round_sting(game: GameState) -> void:
	if game._round_music and game._round_music.stream:
		game._round_music.play()


## Stops the round-start music.
static func stop_round_sting(game: GameState) -> void:
	if game._round_music and game._round_music.playing:
		game._round_music.stop()


## Creates the music players (tension, menu) once.
static func setup_tension_music(game: GameState) -> void:
	game._tension_start_stream = load("res://assets/sounds/music_round_start.wav")
	var fin := load("res://assets/sounds/music_round_final.wav") as AudioStreamWAV
	if fin:
		fin = fin.duplicate() as AudioStreamWAV
		fin.loop_mode = AudioStreamWAV.LOOP_FORWARD
		fin.loop_begin = 0
		fin.loop_end = int(fin.get_length() * fin.mix_rate)
	game._tension_final_stream = fin
	game._tension = AudioStreamPlayer.new()
	game._tension.bus = "Music"
	game.add_child(game._tension)
	var menu := load("res://assets/sounds/music_menu.wav") as AudioStreamWAV
	if menu:
		menu = menu.duplicate() as AudioStreamWAV
		menu.loop_mode = AudioStreamWAV.LOOP_FORWARD
		menu.loop_begin = 0
		menu.loop_end = int(menu.get_length() * menu.mix_rate)
	game._menu_music = AudioStreamPlayer.new()
	game._menu_music.bus = "Music"
	game._menu_music.stream = menu
	game._menu_music.volume_db = -60.0
	game._menu_music.process_mode = Node.PROCESS_MODE_ALWAYS
	game.add_child(game._menu_music)
	# Start now, while main.tscn is still loading, instead of on the first physics tick after it (#62).
	if not game._cli_is_server():
		tick_menu_music(game, true)


## In the menu: fade the calm loop in (resumes where it was); in a match: fade it out and pause.
static func tick_menu_music(game: GameState, boot := false) -> void:
	if game._menu_music == null or game._menu_music.stream == null:
		return
	var want := game.menu_match and not game.is_dedicated
	if want == game._menu_music_on:
		return
	game._menu_music_on = want
	if game._menu_fade and game._menu_fade.is_valid():
		game._menu_fade.kill()
	game._menu_fade = game.create_tween()
	if want:
		if not game._menu_music.playing:
			game._menu_music.play()
		game._menu_music.stream_paused = false
		var t := game.MENU_FADE_IN_BOOT if boot else game.MENU_FADE * 0.6
		game._menu_fade.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		game._menu_fade.tween_property(game._menu_music, "volume_db", game.MENU_MUSIC_DB, t).from(-24.0 if boot else -30.0)
	else:
		game._menu_fade.tween_property(game._menu_music, "volume_db", -60.0, game.MENU_FADE * 0.6)
		game._menu_fade.tween_callback(func() -> void: game._menu_music.stream_paused = true)


## `final`: the looping last-stretch cue; else the one-shot round-start build-up.
static func play_tension(game: GameState, final: bool) -> void:
	if game._tension == null or game.is_dedicated or game.menu_match or game.in_lobby:
		return
	if final:
		game._tension_final = true
	else:
		game._tension_final = false
	var stream := game._tension_final_stream if final else game._tension_start_stream
	if stream == null:
		return
	if game._tension_fade and game._tension_fade.is_valid():
		game._tension_fade.kill()
	game._tension.volume_db = 0.0
	game._tension.stream = stream
	game._tension.play()


## Fades out the tension music.
static func stop_tension(game: GameState) -> void:
	if game._tension == null or not game._tension.playing:
		return
	if game._tension_fade and game._tension_fade.is_valid():
		return
	game._tension_fade = game.create_tween()
	game._tension_fade.tween_property(game._tension, "volume_db", -40.0, game.TENSION_FADE)
	game._tension_fade.tween_callback(game._tension.stop)
	game._tension_fade.tween_callback(func() -> void: game._tension.volume_db = 0.0)


## Highest kill count that counts toward the limit: the leading team (TDM) or player (FFA).
static func leader_kills(game: GameState) -> int:
	if not game.is_ffa():
		return maxi(game.team_score(game.TEAM_A), game.team_score(game.TEAM_B))
	var best := 0
	for id in game.scores:
		best = maxi(best, game.player_score(id))
	return best


## Starts tension music in the last 30 s or when the leader is close to the limit.
static func tick_tension(game: GameState) -> void:
	if game._tension == null:
		return
	var live := game._round_active and not game.round_frozen and not game.menu_match and not game.in_lobby
	if game._tension_live and not live:
		game._tension_final = false
		stop_tension(game) # round over, killcam, leave: fade whatever cue is on
	game._tension_live = live
	if not live or game._tension_final:
		return
	if game._round_timer >= game.TENSION_START_LEN and game._tension.playing and game._tension.stream == game._tension_start_stream:
		stop_tension(game) # the build-up only covers the countdown and the first seconds of the round
	var close_time := game.get_round_time_left() <= game.TENSION_TIME_LEFT
	var close_left := roundi(game.score_limit() * 0.1) if game.is_style_mode() else game.TENSION_KILLS_LEFT # style: last 10%
	var close_kills := game.score_limit() - leader_kills(game) <= close_left
	if close_time or close_kills:
		play_tension(game, true)
