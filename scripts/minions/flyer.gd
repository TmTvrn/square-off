class_name Flyer
extends Minion
## An air minion: a square turned 45 degrees (the diamond silhouette says "flies").
## It hovers above and to the side of the player and fires single shots after a contracting-ring tell.

@export var speed := 260.0
@export var acceleration := 900.0
## Where it tries to hover, relative to the player (x is mirrored to whichever side it's on).
@export var hover_offset := Vector2(280, -230)
## Random time between shots (min, max) in seconds.
@export var fire_interval := Vector2(2.2, 3.2)
@export var tell_time := 0.55
@export var shot_speed := 540.0
@export var shot_scene: PackedScene
@export var arena := Rect2(80, 100, 1760, 700)

var _fire_timer := 1.6
var _tell := -1.0


func _behave(delta: float) -> void:
	var player := Game.player
	if player == null or player.is_dead or stun > 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		return
	var side := signf(global_position.x - player.global_position.x)
	if side == 0.0:
		side = 1.0
	var target := player.global_position + Vector2(side * hover_offset.x, hover_offset.y)
	target = target.clamp(arena.position, arena.end)
	var to_target := target - global_position
	var desired := to_target.limit_length(speed) * clampf(to_target.length() / 90.0, 0.0, 1.0)
	desired.y += sin(_time * 3.0) * 40.0  # gentle bob
	velocity = velocity.move_toward(desired, acceleration * delta)
	visual.target_rotation = clampf(velocity.x / speed, -1.0, 1.0) * 0.35

	if _tell >= 0.0:
		_tell -= delta
		visual.target_scale = Vector2(1.18, 1.18)
		if _tell < 0.0:
			_fire()
	else:
		visual.target_scale = Vector2.ONE
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_tell = tell_time
			Juice.ring(global_position, Palette.color(Palette.Role.THREAT, 1.6), 46.0, 14.0, tell_time, 2.0)
			Sfx.play("boss_telegraph", -16.0, 2.2)


func _fire() -> void:
	var dir := (Game.player.global_position - global_position).normalized()
	var shot := shot_scene.instantiate() as EnemyShot
	shot.velocity = dir * shot_speed
	Game.spawn(shot, global_position + dir * 24.0)
	visual.punch(Vector2(0.8, 0.8))
	visual.nudge(-dir * 10.0)
	velocity -= dir * 120.0
	Sfx.play("boss_shot", -10.0, 1.4)
	_fire_timer = randf_range(fire_interval.x, fire_interval.y)
