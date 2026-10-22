extends Node
## Plays the generated sound effects in res://audio/sfx.
## The sounds themselves are made by code: edit tools/generate_sfx.py and re-run it.

const SOUNDS := [
	"jump", "double_jump", "land", "wall_touch", "drop", "dash", "dash_ready",
	"swing", "hit", "pogo", "deflect", "charge_ready", "charge_max", "shot", "shot_big", "fizzle",
	"hurt", "heal_charge", "heal_done", "heal_gain", "player_death",
	"boss_telegraph", "boss_shot", "boss_ring", "boss_lunge", "boss_hit", "wall_slam", "slam",
	"boss_rise", "phase_shift", "boss_death", "victory", "fan", "needle", "summon",
	"minion_spawn", "minion_hop", "minion_death",
]
const VOICES := 24

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound_name in SOUNDS:
		var path := "res://audio/sfx/%s.wav" % sound_name
		if ResourceLoader.exists(path):
			_streams[sound_name] = load(path)
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


## Plays a sound with a little random pitch variation so repeats don't sound robotic.
func play(sound_name: String, volume_db := 0.0, pitch := 1.0, jitter := 0.05) -> AudioStreamPlayer:
	var stream: AudioStream = _streams.get(sound_name)
	if stream == null:
		push_warning("Missing sound: %s" % sound_name)
		return null
	var player := _players[_next]
	_next = (_next + 1) % VOICES
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(1.0 - jitter, 1.0 + jitter)
	player.play()
	return player


func stop(player: AudioStreamPlayer) -> void:
	if player:
		player.stop()
