class_name ShakeCamera
extends Camera2D
## Trauma-based screen shake: shake strength = trauma², sampled from smooth noise (not random jitter),
## so small hits tap and big hits rumble. Plus directional kicks that spring back.

@export var max_offset := Vector2(34, 26)
@export var max_roll := 0.02
## Trauma lost per second.
@export var trauma_decay := 1.7
@export var noise_speed := 55.0
@export var kick_recovery := 14.0

var trauma := 0.0
var _kick := Vector2.ZERO
var _noise := FastNoiseLite.new()
var _time := 0.0


func _ready() -> void:
	Juice.camera = self
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.05


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func kick(amount: Vector2) -> void:
	_kick += amount


func _process(delta: float) -> void:
	_time += delta
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	var s := trauma * trauma
	var t := _time * noise_speed
	offset = Vector2(
		max_offset.x * s * _noise.get_noise_2d(t, 0.0),
		max_offset.y * s * _noise.get_noise_2d(0.0, t)) + _kick
	rotation = max_roll * s * _noise.get_noise_2d(t, 100.0)
	_kick = _kick.lerp(Vector2.ZERO, 1.0 - exp(-kick_recovery * delta))
