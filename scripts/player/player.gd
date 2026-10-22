class_name Player
extends CharacterBody2D
## The player square.
## Feel lives in `tuning` (res://tuning/player_tuning.tres), so numbers can be changed in the Inspector.
## Each physics tick: read input → timers → state (heal / dash / normal) → attack → move → react.

signal health_changed(current: int, maximum: int)
signal heal_charges_changed(charges: int, determination: int)
signal died

enum Swing { SIDE, UP, DOWN }

const SIZE := Vector2(40, 40)
const BODY_GLOW := 1.35

@export var tuning: PlayerTuning
@export var shot_scene: PackedScene

@onready var visual: SquashVisual = $Visual
@onready var body_art: GeoShape = $Visual/Body
@onready var eye: GeoShape = $Visual/Eye
@onready var hurtbox: Area2D = $Hurtbox
@onready var swing_area: Area2D = $Swing
@onready var swing_shape: CollisionShape2D = $Swing/Shape
@onready var player_fx: PlayerFx = $PlayerFx

# --- State that other nodes read (HUD, PlayerFx) ---
var health := 5
var facing := 1
var heal_charges := 0
var determination := 0
var is_dead := false
var is_healing := false
var heal_progress := 0.0
var is_charging := false
var charge_time := 0.0
var charge_level := 0
var is_wall_sliding := false
var dash_time_left := 0.0
var invulnerable_time := 0.0

var _dash_direction := Vector2.ZERO
var _dash_ready := true
var _dash_cooldown := 0.0
var _ghost_timer := 0.0

var _swing_dir := Swing.SIDE
var _swing_time_left := 0.0
var _attack_cooldown := 0.0
var _swing_hits: Array[Area2D] = []
var _swing_pogoed := false

var _coyote := 0.0
var _jump_buffer := 0.0
var _dash_buffer := 0.0
var _attack_buffer := 0.0
var _air_jumps := 1
var _can_cut_jump := false

var _wall_side := 0       # -1 = wall on the left, 1 = wall on the right, 0 = none
var _last_wall_side := 0
var _wall_coyote := 0.0
var _control_lock := 0.0
var _hurt_lock := 0.0
var _drop_time := 0.0
var _on_one_way := false
var _peak_fall_speed := 0.0
var _air_time := 0.0
var _heal_sound: AudioStreamPlayer


class FrameInput:
	var move := Vector2.ZERO
	var jump_held := false
	var jump_released := false
	var attack_held := false


func _ready() -> void:
	if tuning == null:
		tuning = PlayerTuning.new()
	health = tuning.max_health
	Game.player = self
	health_changed.emit.call_deferred(health, tuning.max_health)
	heal_charges_changed.emit.call_deferred(heal_charges, determination)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	var input := _read_input()
	_tick_timers(delta)

	if is_healing:
		_update_heal(input, delta)
	elif dash_time_left > 0.0:
		_update_dash(delta)
	else:
		_update_run(input, delta)
		_update_gravity(input, delta)
		_try_jump(input)
		_try_dash(input)
	_update_attack(input, delta)

	var was_on_floor := is_on_floor()
	var fall_speed := velocity.y
	move_and_slide()
	_after_move(was_on_floor, fall_speed, delta)
	_check_hurtbox()
	_update_visual(input, delta)


# --- Input & timers ---------------------------------------------------------

func _read_input() -> FrameInput:
	var input := FrameInput.new()
	input.move = Vector2(
		signf(Input.get_axis("move_left", "move_right")),
		signf(Input.get_axis("move_up", "move_down")))
	input.jump_held = Input.is_action_pressed("jump")
	input.jump_released = Input.is_action_just_released("jump")
	input.attack_held = Input.is_action_pressed("attack")
	# Buffers: a press counts for a short window, so slightly-early inputs still happen.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = tuning.jump_buffer
	if Input.is_action_just_pressed("dash"):
		_dash_buffer = tuning.dash_buffer
	if Input.is_action_just_pressed("attack"):
		_attack_buffer = tuning.attack_buffer
	return input


func _tick_timers(delta: float) -> void:
	_coyote = maxf(0.0, _coyote - delta)
	_wall_coyote = maxf(0.0, _wall_coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	_dash_buffer = maxf(0.0, _dash_buffer - delta)
	_attack_buffer = maxf(0.0, _attack_buffer - delta)
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	_control_lock = maxf(0.0, _control_lock - delta)
	_hurt_lock = maxf(0.0, _hurt_lock - delta)
	invulnerable_time = maxf(0.0, invulnerable_time - delta)
	if _drop_time > 0.0:
		_drop_time -= delta
		if _drop_time <= 0.0:
			set_collision_mask_value(2, true)


# --- Movement ---------------------------------------------------------------

func _update_run(input: FrameInput, delta: float) -> void:
	var target := input.move.x * tuning.run_speed
	var grounded := is_on_floor()
	var time: float
	if input.move.x != 0.0:
		time = tuning.ground_accel_time if grounded else tuning.air_accel_time
	else:
		time = tuning.ground_stop_time if grounded else tuning.air_stop_time
	var rate := tuning.run_speed / maxf(time, 0.001)
	if input.move.x != 0.0 and signf(input.move.x) != signf(velocity.x) and absf(velocity.x) > 1.0:
		rate *= tuning.turn_boost
	# Over-speed from dashes, wall jumps and knockback bleeds off instead of snapping to run speed.
	if absf(velocity.x) > tuning.run_speed and signf(target) == signf(velocity.x):
		rate = minf(rate, 2200.0)
	if _control_lock > 0.0:
		rate *= 0.12
	if _hurt_lock > 0.0:
		rate = 700.0
		target = 0.0
	velocity.x = move_toward(velocity.x, target, rate * delta)
	if input.move.x != 0.0 and _hurt_lock <= 0.0 and _control_lock <= 0.0:
		facing = int(input.move.x)


func _update_gravity(input: FrameInput, delta: float) -> void:
	if input.jump_released and velocity.y < 0.0 and _can_cut_jump:
		velocity.y *= tuning.jump_cut
		_can_cut_jump = false

	var gravity := tuning.rise_gravity()
	var max_fall := tuning.max_fall_speed
	if velocity.y > 0.0:
		gravity *= tuning.fall_gravity_multiplier
	if absf(velocity.y) < tuning.apex_threshold and input.jump_held and not is_on_floor():
		gravity *= tuning.apex_gravity_multiplier
	if input.move.y > 0.0 and velocity.y > 0.0:
		max_fall = tuning.fast_fall_speed
		gravity *= 1.25

	is_wall_sliding = not is_on_floor() and velocity.y > 0.0 and _wall_side != 0 \
		and int(input.move.x) == _wall_side
	if is_wall_sliding:
		max_fall = tuning.wall_slide_speed

	if velocity.y > max_fall:
		velocity.y = move_toward(velocity.y, max_fall, 5000.0 * delta)
	else:
		velocity.y = minf(velocity.y + gravity * delta, max_fall)


func _try_jump(input: FrameInput) -> void:
	if _jump_buffer <= 0.0:
		return
	if input.move.y > 0.0 and is_on_floor() and _on_one_way:
		_drop_through()
	elif input.move.y > 0.0 and is_on_floor() and _can_start_heal():
		_start_heal()
	elif _coyote > 0.0:
		_jump(tuning.jump_velocity())
		Juice.dust(global_position + Vector2(0, SIZE.y * 0.5), 6)
		Sfx.play("jump", -4.0)
	elif _wall_coyote > 0.0:
		_wall_jump()
	elif _air_jumps > 0:
		_air_jumps -= 1
		_jump(tuning.velocity_for_height(tuning.double_jump_height))
		var feet := global_position + Vector2(0, SIZE.y * 0.5)
		Juice.ring(feet, Palette.color(Palette.Role.PLAYER, 2.2), 12.0, 58.0, 0.24, 4.0, 0.3)
		Juice.ring(feet, Palette.color(Palette.Role.PLAYER, 1.4), 6.0, 34.0, 0.2, 2.0, 0.3)
		Sfx.play("double_jump", -4.0)
	else:
		return  # Nothing to do yet: keep the press buffered.
	_jump_buffer = 0.0


func _jump(speed: float) -> void:
	velocity.y = -speed
	_coyote = 0.0
	_wall_coyote = 0.0
	_can_cut_jump = true
	visual.punch(Vector2(0.76, 1.26), Vector2(4, -6))


func _wall_jump() -> void:
	var side := _last_wall_side
	velocity.x = -side * tuning.wall_jump_push
	_jump(tuning.velocity_for_height(tuning.wall_jump_height))
	_control_lock = tuning.wall_jump_control_lock
	facing = -side
	var wall_point := global_position + Vector2(side * SIZE.x * 0.5, 0)
	Juice.dust(wall_point, 7, Vector2(-side, 0), PI * 0.6, 220.0)
	Sfx.play("jump", -4.0, 1.12)


func _drop_through() -> void:
	set_collision_mask_value(2, false)
	_drop_time = tuning.drop_through_time
	position.y += 3.0
	velocity.y = maxf(velocity.y, 160.0)
	visual.punch(Vector2(0.88, 1.12))
	Sfx.play("drop", -8.0)


func _try_dash(input: FrameInput) -> void:
	if _dash_buffer <= 0.0 or not _dash_ready or _dash_cooldown > 0.0:
		return
	var dir := Vector2(input.move.x, input.move.y)
	if is_on_floor() and dir.y > 0.0:
		dir.y = 0.0
	if dir == Vector2.ZERO:
		dir.x = facing
	dir = dir.normalized()
	if dir.x != 0.0:
		facing = int(signf(dir.x))

	_dash_buffer = 0.0
	_dash_ready = false
	_dash_cooldown = tuning.dash_cooldown
	dash_time_left = tuning.dash_time
	_dash_direction = dir
	_ghost_timer = 0.0
	velocity = dir * tuning.dash_speed
	is_wall_sliding = false

	visual.punch(Vector2(1.38, 0.7) if absf(dir.x) >= absf(dir.y) else Vector2(0.7, 1.38))
	Juice.kick(dir * 6.0)
	Juice.sparks(global_position, Palette.color(Palette.Role.PLAYER, 1.8), 8, 420.0, (-dir).angle(), 0.9, 0.22, 2.0)
	Sfx.play("dash", -3.0)


func _update_dash(delta: float) -> void:
	dash_time_left -= delta
	velocity = _dash_direction * tuning.dash_speed
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = 0.016
		var s := SIZE * visual.scale
		Juice.ghost(Rect2(global_position + Vector2(-s.x * 0.5, SIZE.y * 0.5 - s.y), s),
			Palette.color(Palette.Role.PLAYER, 1.3, 0.45), 0.18)
	if dash_time_left <= 0.0:
		_end_dash()


func _end_dash() -> void:
	dash_time_left = 0.0
	velocity.x *= tuning.dash_exit_keep
	velocity.y *= 0.25 if _dash_direction.y < 0.0 else 0.5


# --- Attacks ----------------------------------------------------------------

func _update_attack(input: FrameInput, delta: float) -> void:
	if _swing_time_left > 0.0:
		_swing_time_left -= delta
		_resolve_swing_hits()

	if _attack_buffer > 0.0 and _attack_cooldown <= 0.0 and not is_healing:
		_start_swing(input)

	if not is_charging:
		return
	if input.attack_held and not is_healing:
		charge_time += delta
		var level := 0
		if charge_time >= tuning.charge_level_2_time:
			level = 2
		elif charge_time >= tuning.charge_level_1_time:
			level = 1
		if level > charge_level:
			charge_level = level
			_on_charge_level(level)
	else:
		_release_charge(input)


func _start_swing(input: FrameInput) -> void:
	_attack_buffer = 0.0
	_attack_cooldown = tuning.attack_cooldown
	_swing_time_left = tuning.attack_active_time
	_swing_hits.clear()
	_swing_pogoed = false

	if input.move.y < 0.0:
		_swing_dir = Swing.UP
	elif input.move.y > 0.0 and not is_on_floor():
		_swing_dir = Swing.DOWN
	else:
		_swing_dir = Swing.SIDE

	var shape := swing_shape.shape as RectangleShape2D
	match _swing_dir:
		Swing.SIDE:
			shape.size = Vector2(100, 72)
			swing_shape.position = Vector2(facing * 58, -4)
			visual.punch(Vector2(1.12, 0.9), Vector2(facing * 3.0, 1.5))
		Swing.UP:
			shape.size = Vector2(80, 100)
			swing_shape.position = Vector2(0, -62)
			visual.punch(Vector2(0.88, 1.14), Vector2(1.5, -4))
		Swing.DOWN:
			shape.size = Vector2(80, 96)
			swing_shape.position = Vector2(0, 60)
			visual.punch(Vector2(0.9, 1.1), Vector2(1.5, 4))

	is_charging = true
	charge_time = 0.0
	charge_level = 0
	player_fx.start_slash(_swing_dir, facing)
	Sfx.play("swing", -6.0, 1.0, 0.1)


func _resolve_swing_hits() -> void:
	for area in swing_area.get_overlapping_areas():
		if area in _swing_hits:
			continue
		if area is Hurtbox:
			_swing_hits.append(area)
			_on_swing_hit_enemy(area as Hurtbox)
		elif area is EnemyShot:
			_swing_hits.append(area)
			_on_swing_hit_shot(area as EnemyShot)
		elif area is Hitbox and (area as Hitbox).is_hazard and _swing_dir == Swing.DOWN:
			_swing_hits.append(area)
			_pogo(global_position + Vector2(0, SIZE.y * 0.5 + 10))


func _on_swing_hit_enemy(target: Hurtbox) -> void:
	if not target.receive_hit(tuning.melee_damage, global_position):
		return
	var swing_center := swing_area.global_position + swing_shape.position
	var contact := swing_center.lerp(target.global_position, 0.5)
	var away := (target.global_position - global_position).angle()
	Juice.freeze(0.055)
	Juice.shake(0.22)
	Juice.kick(Vector2.from_angle(away) * 8.0)
	Juice.impact(contact, Palette.color(Palette.Role.PLAYER, 2.0), 1.0, away, PI * 0.9)
	Juice.ripple(contact, 170.0, 200.0)
	Sfx.play("hit", -2.0)
	_gain_determination()
	match _swing_dir:
		Swing.SIDE:
			velocity.x = -facing * tuning.hit_recoil
			_control_lock = 0.08
			if not is_on_floor():
				velocity.y = minf(velocity.y, -90.0)
		Swing.DOWN:
			_pogo(contact)


func _on_swing_hit_shot(shot: EnemyShot) -> void:
	shot.deflect()
	Juice.freeze(0.03)
	Juice.shake(0.1)
	Sfx.play("deflect", -4.0)
	_gain_determination()
	if _swing_dir == Swing.DOWN:
		_pogo(shot.global_position)


func _pogo(at: Vector2) -> void:
	if _swing_pogoed:
		return
	_swing_pogoed = true
	velocity.y = -tuning.velocity_for_height(tuning.pogo_height)
	_can_cut_jump = true
	_air_jumps = 1
	_refresh_dash()
	visual.punch(Vector2(0.84, 1.2), Vector2(0, -4))
	Juice.ring(at, Palette.color(Palette.Role.PLAYER, 2.0), 8.0, 46.0, 0.2, 4.0, 0.45)
	Juice.shake(0.14)
	Sfx.play("pogo", -4.0)


func _on_charge_level(level: int) -> void:
	if level == 1:
		Juice.ring(global_position, Palette.color(Palette.Role.PLAYER, 1.6), 34.0, 20.0, 0.16, 2.0)
		Sfx.play("charge_ready", -8.0)
	else:
		visual.punch(Vector2(1.16, 0.86), Vector2(-6, 6))
		Juice.ring(global_position, Palette.color(Palette.Role.PLAYER, 2.2), 44.0, 22.0, 0.2, 3.0)
		Juice.sparks(global_position, Palette.color(Palette.Role.PLAYER, 1.8), 8, 260.0, 0.0, TAU, 0.2, 2.0)
		Juice.shake(0.12)
		Sfx.play("charge_max", -6.0)


func _release_charge(input: FrameInput) -> void:
	is_charging = false
	var level := charge_level
	charge_level = 0
	if level == 0:
		if charge_time > 0.2:
			Juice.sparks(global_position, Palette.color(Palette.Role.PLAYER, 1.2), 6, 160.0, 0.0, TAU, 0.2, 1.5)
			Sfx.play("fizzle", -12.0)
		return

	var dir := Vector2(input.move.x, 0.0)
	if input.move.y < 0.0:
		dir.y = -1.0
	elif input.move.y > 0.0 and not is_on_floor():
		dir.y = 1.0
	if dir == Vector2.ZERO:
		dir.x = facing
	dir = dir.normalized()

	var big := level == 2
	var shot := shot_scene.instantiate() as PlayerShot
	shot.setup(level, dir,
		tuning.shot_2_damage if big else tuning.shot_1_damage,
		tuning.shot_2_speed if big else tuning.shot_1_speed)
	Game.spawn(shot, global_position + dir * 30.0)

	var recoil := tuning.shot_2_recoil if big else tuning.shot_1_recoil
	velocity -= dir * recoil
	if not is_on_floor():
		velocity.y -= 150.0 if big else 70.0
	_control_lock = 0.24 if big else 0.14
	visual.punch(Vector2(0.88, 1.12) if big else Vector2(0.95, 1.05), Vector2(10, -10))
	visual.spin(-dir.x * (12.0 if big else 5.0))
	var muzzle := global_position + dir * 30.0
	Juice.sparks(muzzle, Palette.color(Palette.Role.PLAYER, 2.4), 12 if big else 6, 600.0, dir.angle(), 0.8, 0.2)
	Juice.ring(muzzle, Palette.color(Palette.Role.FLASH, 2.0), 6.0, 40.0 if big else 24.0, 0.14, 4.0)
	Juice.kick(-dir * (12.0 if big else 4.0))
	if big:
		Juice.freeze(0.045)
		Juice.shake(0.3)
		Sfx.play("shot_big", -2.0)
	else:
		Juice.shake(0.08)
		Sfx.play("shot", -5.0)


# --- Heal -------------------------------------------------------------------

func _can_start_heal() -> bool:
	return heal_charges > 0 and health < tuning.max_health


func _start_heal() -> void:
	is_healing = true
	heal_progress = 0.0
	is_charging = false
	charge_level = 0
	velocity.x = 0.0
	visual.punch(Vector2(1.15, 0.85))
	_heal_sound = Sfx.play("heal_charge", -6.0, 1.3 / tuning.heal_time, 0.0)


func _update_heal(input: FrameInput, delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 4000.0 * delta)
	velocity.y = minf(velocity.y + tuning.rise_gravity() * delta, tuning.max_fall_speed)
	if not (input.jump_held and input.move.y > 0.0) or not is_on_floor():
		_cancel_heal()
		return
	heal_progress += delta / tuning.heal_time
	if Engine.get_physics_frames() % 6 == 0:
		Juice.shake(0.02 + 0.06 * heal_progress)
	if heal_progress >= 1.0:
		_complete_heal()


func _complete_heal() -> void:
	is_healing = false
	heal_progress = 0.0
	health = mini(health + 1, tuning.max_health)
	heal_charges -= 1
	health_changed.emit(health, tuning.max_health)
	heal_charges_changed.emit(heal_charges, determination)
	body_art.flash = 1.0
	visual.punch(Vector2(0.8, 1.25), Vector2(6, -12))
	var violet := Palette.color(Palette.Role.HEAL, 2.6)
	Juice.freeze(0.07)
	Juice.shake(0.45)
	Juice.ring(global_position, violet, 20.0, 170.0, 0.45, 6.0)
	Juice.ring(global_position, Palette.color(Palette.Role.PLAYER, 2.2), 10.0, 110.0, 0.35, 3.0)
	Juice.sparks(global_position, violet, 26, 700.0, 0.0, TAU, 0.45, 3.0)
	Juice.shards(global_position, Palette.color(Palette.Role.HEAL, 2.0), 10, 520.0)
	Juice.ripple(global_position, -260.0, 320.0)
	player_fx.heal_burst()
	Sfx.stop(_heal_sound)
	Sfx.play("heal_done", -3.0)


func _cancel_heal() -> void:
	if not is_healing:
		return
	is_healing = false
	heal_progress = 0.0
	Sfx.stop(_heal_sound)
	Juice.sparks(global_position, Palette.color(Palette.Role.HEAL, 1.6), 10, 260.0, 0.0, TAU, 0.25, 2.0)
	Sfx.play("fizzle", -8.0)


func _gain_determination() -> void:
	if heal_charges >= tuning.max_heal_charges:
		return
	determination += 1
	if determination >= tuning.hits_per_heal_charge:
		determination = 0
		heal_charges += 1
		Juice.ring(global_position, Palette.color(Palette.Role.HEAL, 2.2), 50.0, 20.0, 0.25, 3.0)
		Sfx.play("heal_gain", -6.0)
	heal_charges_changed.emit(heal_charges, determination)


# --- After moving -----------------------------------------------------------

func _after_move(was_on_floor: bool, fall_speed: float, delta: float) -> void:
	var grounded := is_on_floor()
	_on_one_way = false
	if grounded:
		for i in get_slide_collision_count():
			var hit := get_slide_collision(i)
			var block := hit.get_collider() as ArenaBlock
			if block and block.kind == ArenaBlock.Kind.ONE_WAY and hit.get_normal().y < -0.5:
				_on_one_way = true
		_coyote = tuning.coyote_time
		_air_jumps = 1
		_refresh_dash()
		if not was_on_floor:
			_land(_peak_fall_speed)
		_peak_fall_speed = 0.0
		_air_time = 0.0
	else:
		_air_time += delta
		_peak_fall_speed = maxf(_peak_fall_speed, fall_speed)

	if is_on_ceiling() and fall_speed < -200.0:
		visual.punch(Vector2(1.12, 0.88))

	var previous_wall := _wall_side
	_wall_side = 0
	if not grounded:
		if test_move(global_transform, Vector2(-2, 0)):
			_wall_side = -1
		elif test_move(global_transform, Vector2(2, 0)):
			_wall_side = 1
	if _wall_side != 0:
		_last_wall_side = _wall_side
		_wall_coyote = tuning.wall_coyote_time
		_air_jumps = 1
		_refresh_dash()
		if previous_wall == 0:
			_touch_wall()
		elif is_wall_sliding and Engine.get_physics_frames() % 3 == 0:
			var contact := global_position + Vector2(_wall_side * SIZE.x * 0.5, SIZE.y * 0.4)
			Juice.sparks(contact, Palette.color(Palette.Role.PLAYER, 1.6), 1, 120.0, -PI * 0.5, 0.8, 0.25, 2.0)

	if dash_time_left > 0.0 and is_on_wall():
		_end_dash()


func _land(speed: float) -> void:
	var t := clampf((speed - 200.0) / (tuning.max_fall_speed - 200.0), 0.0, 1.0)
	if t <= 0.02 and _air_time < 0.15:
		return
	var f := 0.3 * t + 0.7 * t * t
	var feet := global_position + Vector2(0, SIZE.y * 0.5)
	visual.punch(Vector2(1.08 + 0.3 * f, 0.92 - 0.3 * f), Vector2(8.0 * f, -14.0 * f))
	velocity.x *= 1.0 - 0.4 * f
	Juice.dust(feet, 4 + int(8 * f), Vector2.UP, PI * 0.95, 140.0 + 160.0 * f)
	Sfx.play("land", lerpf(-16.0, -2.0, f))
	if f > 0.5:
		Juice.shake(0.15 * f)
		Juice.ripple(feet, 140.0 * f, 180.0)


func _touch_wall() -> void:
	visual.punch(Vector2(0.8, 1.2))
	var wall_point := global_position + Vector2(_wall_side * SIZE.x * 0.5, 0)
	Juice.dust(wall_point, 4, Vector2(-_wall_side, 0), PI * 0.7, 140.0)
	Sfx.play("wall_touch", -12.0)


func _refresh_dash() -> void:
	if not _dash_ready:
		_dash_ready = true
		if dash_time_left <= 0.0:
			body_art.flash = 0.5
			Sfx.play("dash_ready", -14.0)


# --- Damage -----------------------------------------------------------------

func _check_hurtbox() -> void:
	if invulnerable_time > 0.0 or is_dead:
		return
	for area in hurtbox.get_overlapping_areas():
		var hitbox := area as Hitbox
		if hitbox and hitbox.active:
			take_hit(hitbox.damage, hitbox.global_position, hitbox.is_hazard)
			if hitbox is EnemyShot:
				(hitbox as EnemyShot).pop()
			return


func take_hit(damage: int, source: Vector2, from_hazard: bool) -> void:
	health = maxi(0, health - damage)
	invulnerable_time = tuning.invulnerable_time
	_hurt_lock = tuning.hurt_control_lock
	_cancel_heal()
	is_charging = false
	charge_level = 0
	dash_time_left = 0.0

	if from_hazard:
		velocity = Vector2(velocity.x * 0.4, -tuning.velocity_for_height(tuning.spike_bounce_height))
		visual.punch(Vector2(0.55, 1.45), Vector2(10, -15))
	else:
		var away := signf(global_position.x - source.x)
		if away == 0.0:
			away = -facing
		velocity = Vector2(away * tuning.knockback.x, -tuning.knockback.y)
		facing = int(-away)
		visual.punch(Vector2(1.35, 0.72), Vector2(-8, 10))
		visual.spin(away * 10.0)

	body_art.flash = 1.0
	var push_dir := (global_position - source).normalized()
	Juice.freeze(0.1)
	Juice.slowmo(0.5, 0.18)
	Juice.shake(0.6)
	Juice.kick(push_dir * 20.0)
	Juice.impact(global_position, Palette.color(Palette.Role.BOSS, 2.0), 1.4)
	Juice.shards(global_position, Palette.color(Palette.Role.PLAYER, 1.6), 8, 480.0)
	Juice.ripple(global_position, 260.0, 260.0)
	Sfx.play("hurt", -2.0)
	health_changed.emit(health, tuning.max_health)
	if health <= 0:
		_die()


func _die() -> void:
	is_dead = true
	velocity = Vector2.ZERO
	visual.visible = false
	player_fx.visible = false
	collision_layer = 0
	hurtbox.set_deferred("monitoring", false)
	Juice.freeze(0.2)
	Juice.slowmo(0.3, 0.9)
	Juice.shake(1.0)
	Juice.ring(global_position, Palette.color(Palette.Role.PLAYER, 2.5), 10.0, 260.0, 0.6, 6.0)
	Juice.shards(global_position, Palette.color(Palette.Role.PLAYER, 1.8), 28, 900.0, 11.0, 1.2)
	Juice.sparks(global_position, Palette.color(Palette.Role.FLASH, 2.5), 30, 1100.0, 0.0, TAU, 0.5)
	Juice.ripple(global_position, 600.0, 520.0)
	Sfx.play("player_death")
	died.emit()


# --- Visuals ----------------------------------------------------------------

func _update_visual(input: FrameInput, delta: float) -> void:
	body_art.flash = move_toward(body_art.flash, 0.0, delta * 8.0)
	# Invulnerability flicker, so you can always see your safe window.
	visual.modulate.a = 0.3 if invulnerable_time > 0.0 and fmod(invulnerable_time, 0.12) < 0.06 else 1.0

	# Held shapes are decided here, in one place, so nothing overwrites anything else.
	var target := Vector2.ONE
	if is_wall_sliding:
		target = Vector2(0.86, 1.14)
	elif is_healing:
		var breathe := sin(Time.get_ticks_msec() * 0.018) * 0.03 * heal_progress
		target = Vector2(1.06 + breathe, 0.94 - breathe)
	elif not is_on_floor() and dash_time_left <= 0.0:
		# Stretch along vertical speed so arcs read as motion, not a sliding block.
		var k := clampf(absf(velocity.y) / tuning.jump_velocity(), 0.0, 1.0) * tuning.air_stretch
		target = Vector2(1.0 - k, 1.0 + k)
	elif is_charging and charge_level > 0:
		var pulse := sin(Time.get_ticks_msec() * 0.03) * 0.025 * charge_level
		target = Vector2(1.0 - pulse, 1.0 + pulse)
	visual.target_scale = target

	if is_on_floor():
		visual.target_rotation = input.move.x * 0.1
	else:
		visual.target_rotation = clampf(velocity.x / tuning.run_speed, -1.0, 1.0) * 0.07

	body_art.glow = BODY_GLOW + 0.15 * charge_level
	body_art.tint = Palette.color(Palette.Role.HEAL, 1.0, 0.6 * heal_progress) if is_healing else Color(0, 0, 0, 0)

	# The eye looks where you're going or aiming.
	var look := Vector2(facing * 7.0, 0.0)
	if input.move.y < 0.0:
		look.y = -8.0
	elif input.move.y > 0.0:
		look.y = 6.0
	var eye_target := Vector2(0, -SIZE.y * 0.5) + look
	eye.position = eye.position.lerp(eye_target, 1.0 - exp(-25.0 * delta))
