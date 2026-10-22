extends Node
## Developer helpers. Not part of the game.
##   G    – grayscale check (the fight must still read with no color)
##   F12  – save a screenshot to user://screenshots/
##
## Command-line options (after `--`), used for automated checks:
##   --capture-dir=<absolute path>   where screenshots go
##   --capture-at=1.0,2.5,4.0        seconds (real time) to take screenshots, then quit
##   --autoplay[=combat]             drive the player with a scripted input timeline
##   --spawn-x=<x>                   start the player at this x position
##   --boss-attack=<name>            boss repeats one attack (see Boss.force_attack)
##   --boss-phase=<1-3>              boss starts in this phase

## [game time in seconds, action, pressed]
const BOT_TIMELINE := [
	[0.6, "move_right", true], [0.9, "jump", true], [1.05, "jump", false],
	[1.2, "jump", true], [1.3, "jump", false], [1.4, "dash", true], [1.45, "dash", false],
	[1.7, "attack", true], [1.75, "attack", false], [2.0, "attack", true], [2.05, "attack", false],
	[2.3, "move_right", false], [2.4, "attack", true], [3.6, "attack", false],
	[3.8, "move_left", true], [4.3, "jump", true], [4.6, "jump", false], [4.8, "move_left", false],
	[5.0, "attack", true], [5.05, "attack", false], [5.3, "move_down", true], [5.35, "jump", true],
	[7.0, "jump", false], [7.0, "move_down", false],
]
## Starts next to the boss: four swings (earns a heal charge), then a full charge shot.
const COMBAT_TIMELINE := [
	[0.3, "attack", true], [0.35, "attack", false], [0.65, "attack", true], [0.7, "attack", false],
	[1.0, "move_up", true], [1.0, "attack", true], [1.05, "attack", false], [1.1, "move_up", false],
	[1.35, "attack", true], [1.4, "attack", false], [1.7, "attack", true], [2.9, "attack", false],
	[3.2, "jump", true], [3.3, "jump", false], [3.4, "move_down", true], [3.45, "attack", true],
	[3.5, "attack", false], [3.8, "move_down", false],
]

@onready var grayscale: CanvasLayer = $Grayscale

var _capture_dir := ""
var _capture_times: Array[float] = []
var _autoplay := false
var _timeline: Array = BOT_TIMELINE
var _bot_time := 0.0
var _bot_index := 0
var _start := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100  # Before the player reads input.
	grayscale.visible = false
	_start = Time.get_ticks_msec() / 1000.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			_capture_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--capture-at="):
			for t in arg.get_slice("=", 1).split(","):
				_capture_times.append(float(t))
		elif arg.begins_with("--autoplay"):
			_autoplay = true
			if arg == "--autoplay=combat":
				_timeline = COMBAT_TIMELINE
		elif arg.begins_with("--spawn-x="):
			_place_player.call_deferred(float(arg.get_slice("=", 1)))
		elif arg.begins_with("--boss-attack="):
			Game.boss.force_attack = arg.get_slice("=", 1)
		elif arg.begins_with("--boss-phase="):
			Game.boss.phase = int(arg.get_slice("=", 1))
		elif arg == "--grayscale":
			grayscale.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_grayscale"):
		grayscale.visible = not grayscale.visible
	elif event.is_action_pressed("debug_screenshot"):
		DirAccess.make_dir_recursive_absolute("user://screenshots")
		_save_screenshot("user://screenshots/%d.png" % Time.get_unix_time_from_system())


func _process(_delta: float) -> void:
	if _capture_times.is_empty():
		return
	var elapsed := Time.get_ticks_msec() / 1000.0 - _start
	if elapsed >= _capture_times[0]:
		var t: float = _capture_times.pop_front()
		await RenderingServer.frame_post_draw
		_save_screenshot("%s/capture_%05.2f.png" % [_capture_dir, t])
		if _capture_times.is_empty():
			get_tree().quit()


func _physics_process(delta: float) -> void:
	if not _autoplay:
		return
	_bot_time += delta
	while _bot_index < _timeline.size() and _timeline[_bot_index][0] <= _bot_time:
		var step: Array = _timeline[_bot_index]
		if step[2]:
			Input.action_press(step[1])
		else:
			Input.action_release(step[1])
		_bot_index += 1


func _place_player(x: float) -> void:
	Game.player.global_position.x = x
	Game.player.reset_physics_interpolation()


func _save_screenshot(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	# With HDR 2D the viewport holds linear color; convert so the PNG matches the screen.
	image.convert(Image.FORMAT_RGB8)
	if get_viewport().use_hdr_2d:
		image.linear_to_srgb()
	image.save_png(path)
	print("Saved screenshot: ", path)
