class_name Hopper
extends Minion
## A small ground minion that hops toward the player. It crouches before every hop (the tell),
## stretches in the air and splats on landing. If it lands in the spike pit, it dies.

@export var gravity := 2400.0
@export var hop_height := 150.0
@export var hop_speed := 280.0
## Random wait between hops (min, max) in seconds.
@export var hop_interval := Vector2(0.45, 0.95)
## Crouch time before each hop. This is the player's warning.
@export var crouch_time := 0.24

var _wait := 0.4
var _crouch := -1.0


func _behave(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor() or stun > 0.0:
		visual.target_scale = Vector2.ONE
		return
	velocity.x = move_toward(velocity.x, 0.0, 2600.0 * delta)
	if _crouch >= 0.0:
		_crouch -= delta
		visual.target_scale = Vector2(1.28, 0.74)
		if _crouch < 0.0:
			_hop()
	else:
		visual.target_scale = Vector2.ONE
		_wait -= delta
		if _wait <= 0.0 and Game.player and not Game.player.is_dead:
			_crouch = crouch_time


func _hop() -> void:
	var dir := signf(Game.player.global_position.x - global_position.x)
	var height := hop_height * randf_range(0.75, 1.15)
	velocity = Vector2(dir * hop_speed * randf_range(0.8, 1.2), -sqrt(2.0 * gravity * height))
	visual.punch(Vector2(0.68, 1.38), Vector2(4, -8))
	Juice.dust(global_position + Vector2(0, body_art.size.y * 0.5), 4)
	Sfx.play("minion_hop", -14.0, 1.0, 0.15)
	_wait = randf_range(hop_interval.x, hop_interval.y)


func _after_move() -> void:
	if is_on_floor() and not _was_on_floor:
		visual.punch(Vector2(1.35, 0.68), Vector2(6, -10))
		Juice.dust(global_position + Vector2(0, body_art.size.y * 0.5), 5)


func _eye_home() -> Vector2:
	return Vector2(0, -body_art.size.y * 0.5)
