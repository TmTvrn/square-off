class_name Minion
extends CharacterBody2D
## Shared minion behavior: the spawn-in warning, taking hits, dying, and contact damage.
## Subclasses only decide how to move, in `_behave(delta)`.
##
## Spawn language: a minion first appears as an OUTLINE (harmless, can't be hit), blinks,
## then fills in and becomes real. Same rule as every telegraph in the game.

@export var max_health := 2
## How hard a hit shoves the minion away from the attacker.
@export var knockback := 420.0
## Seconds spent as a harmless outline before becoming real.
@export var spawn_time := 0.7

@onready var visual: SquashVisual = $Visual
@onready var body_art: GeoShape = $Visual/Body
@onready var eye: GeoShape = $Visual/Eye
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var contact: Hitbox = $ContactHitbox

var health := 2
var is_dead := false
## Seconds left where the minion is reeling from a hit and its own movement is suspended.
var stun := 0.0

var _spawn_left := 0.0
var _was_on_floor := false
var _time := 0.0


func _ready() -> void:
	health = max_health
	add_to_group("minions")
	hurtbox.hurt.connect(_on_hurt)
	_spawn_left = spawn_time
	contact.active = false
	hurtbox.vulnerable = false
	body_art.filled = false
	body_art.outline_width = 2.0


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_time += delta
	if _spawn_left > 0.0:
		_update_spawn(delta)
		return
	stun = maxf(0.0, stun - delta)
	_behave(delta)
	_was_on_floor = is_on_floor()
	move_and_slide()
	_after_move()
	_check_hazards()
	body_art.flash = move_toward(body_art.flash, 0.0, delta * 9.0)
	if Game.player:
		var look := (Game.player.global_position - global_position).normalized() * body_art.size.x * 0.18
		eye.position = eye.position.lerp(_eye_home() + look, 1.0 - exp(-14.0 * delta))


## Override: set `velocity` for this tick.
func _behave(_delta: float) -> void:
	pass


## Override: react after moving (landing, walls).
func _after_move() -> void:
	pass


## Where the eye sits when looking straight ahead, in Visual space.
func _eye_home() -> Vector2:
	return Vector2.ZERO


func _update_spawn(delta: float) -> void:
	_spawn_left -= delta
	var p := 1.0 - _spawn_left / spawn_time
	body_art.glow = 0.6 + 1.2 * p
	visual.modulate.a = 1.0 if p > 0.7 or fmod(_time, 0.12) < 0.08 else 0.35
	if _spawn_left <= 0.0:
		_materialize()


func _materialize() -> void:
	visual.modulate.a = 1.0
	body_art.filled = true
	body_art.outline_width = 0.0
	body_art.glow = 1.0
	body_art.flash = 1.0
	contact.active = true
	hurtbox.vulnerable = true
	visual.punch(Vector2(1.35, 0.7), Vector2(-6, 8))
	Juice.ring(global_position, Palette.color(Palette.Role.BOSS, 2.0), 8.0, body_art.size.x * 1.4, 0.22, 3.0)
	Sfx.play("minion_spawn", -10.0)


func _on_hurt(damage: int, source_position: Vector2) -> void:
	if is_dead:
		return
	health -= damage
	body_art.flash = 1.0
	var away := (global_position - source_position).normalized()
	velocity = Vector2(away.x * knockback, minf(away.y * knockback, -knockback * 0.45))
	stun = 0.28
	visual.punch(Vector2(0.75, 1.25))
	visual.nudge(away * 8.0)
	Juice.shards(global_position, Palette.color(Palette.Role.BOSS, 1.5), 3, 300.0, 5.0, 0.4, away.angle(), PI)
	if health <= 0:
		die()
	else:
		Sfx.play("boss_hit", -8.0, 1.5)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	contact.active = false
	hurtbox.vulnerable = false
	Juice.freeze(0.035)
	Juice.shake(0.2)
	Juice.impact(global_position, Palette.color(Palette.Role.BOSS, 2.2), 1.1)
	Juice.shards(global_position, Palette.color(Palette.Role.BOSS, 1.8), 10, 520.0, 7.0, 0.7)
	Juice.ripple(global_position, 220.0, 220.0)
	Sfx.play("minion_death", -4.0)
	queue_free()


func _check_hazards() -> void:
	for area in hurtbox.get_overlapping_areas():
		var hitbox := area as Hitbox
		if hitbox and hitbox.is_hazard:
			die()
			return
