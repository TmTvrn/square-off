class_name Boss
extends CharacterBody2D
## The arena boss: a big red square with a growing set of readable attacks.
## Its brain (`_brain`) is a plain coroutine, so the fight reads top to bottom like a script:
## reposition → pick an attack → telegraph → commit → recover. Every attack telegraphs with an
## OUTLINE first (warning) and only becomes filled/real when it lands.
##
## Phases: at 66% and 33% health the boss gets faster, telegraphs shorten, and attacks gain extras.

signal health_changed(current: int, maximum: int)
signal phase_changed(phase: int)
signal defeated

enum Move { WALK, HOLD, LUNGE, FLY, SLAM }

const SIZE := Vector2(72, 72)
const PHASE_GLOW := [1.15, 1.45, 1.85]

@export_group("Health")
@export var max_health := 32
@export_range(0.0, 1.0) var phase_2_at := 0.66
@export_range(0.0, 1.0) var phase_3_at := 0.33

@export_group("Brain")
## Turn off to make the boss stand still (practice movement, or run tests).
@export var brain_enabled := true
## Practice mode: always use this attack (lunge, volley, ring_slam, pounce, fan, needle_rain,
## satellites, summon). Leave empty for the normal fight.
@export var force_attack := ""
## Practice mode: start in this phase (1-3).
@export_range(1, 3) var start_phase := 1

@export_group("Arena")
## Inner playable space. The floor is this rect's bottom edge.
@export var arena := Rect2(40, 40, 1840, 940)

@export_group("Movement")
@export var gravity := 2600.0
@export var walk_speed := 230.0
@export var walk_accel := 1800.0
@export var preferred_distance := 520.0
## Speed multiplier per phase (1, 2, 3).
@export var phase_speed: Array[float] = [1.0, 1.15, 1.3]

@export_group("Attacks")
@export var lunge_speed := 1100.0
@export var shot_speed := 640.0
@export var ring_speed := 420.0
@export var shockwave_speed := 620.0
@export var slam_speed := 2100.0
@export var hover_height := 330.0
@export var shot_scene: PackedScene

@export_group("Minions")
@export var hopper_scene: PackedScene
@export var flyer_scene: PackedScene
## The boss won't summon while this many minions are alive.
@export var max_minions := 4

@onready var visual: SquashVisual = $Visual
@onready var body_art: GeoShape = $Visual/Body
@onready var eye: GeoShape = $Visual/Eye
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var contact: Hitbox = $ContactHitbox
@onready var telegraph: BossTelegraph = $Telegraph

var health := 32
var phase := 1
var facing := -1
var is_dead := false

var _move := Move.HOLD
var _walk_dir := 0.0
var _fly_target := Vector2.ZERO
var _hit_wall := false
var _last_attack := ""
var _invulnerable := false


func _ready() -> void:
	health = max_health
	phase = start_phase
	Game.boss = self
	hurtbox.hurt.connect(_on_hurt)
	health_changed.emit.call_deferred(health, max_health)
	_brain()


# --- Brain ------------------------------------------------------------------

func _brain() -> void:
	await _wait(1.2)
	while not is_dead:
		if _player_gone() or not brain_enabled:
			_move = Move.HOLD
			await _wait(0.5)
			continue
		await _reposition()
		if is_dead:
			return
		var attack := force_attack if force_attack != "" else _choose_attack()
		match attack:
			"lunge": await _attack_lunge()
			"volley": await _attack_volley()
			"ring_slam": await _attack_ring_slam()
			"pounce": await _attack_pounce()
			"fan": await _attack_fan()
			"needle_rain": await _attack_needle_rain()
			"satellites": await _attack_satellites()
			"summon": await _attack_summon()
		_last_attack = attack
		await _wait(_by_phase(0.6, 0.42, 0.28))


func _choose_attack() -> String:
	var distance := absf(Game.player.global_position.x - global_position.x)
	var weights := {
		"lunge": 3.0 if distance < 700.0 else 2.0,
		"volley": 3.0 if distance > 500.0 else 1.5,
		"ring_slam": 2.0,
	}
	weights["fan"] = 2.5 if distance > 350.0 else 1.0
	if _minion_count() < max_minions:
		weights["summon"] = 2.5 if _minion_count() == 0 else 1.0
	if phase >= 2:
		weights["pounce"] = 3.0 if distance < 600.0 else 1.5
		weights["needle_rain"] = 2.0
		weights["satellites"] = 2.5 if distance < 500.0 else 1.5
	if weights.has(_last_attack):
		weights[_last_attack] *= 0.15  # Rarely repeat the same attack twice.
	var total := 0.0
	for w in weights.values():
		total += w
	var roll := randf() * total
	for attack in weights:
		roll -= weights[attack]
		if roll <= 0.0:
			return attack
	return "lunge"


func _reposition() -> void:
	_move = Move.WALK
	var time_left := randf_range(0.4, 0.85) / _speed()
	while time_left > 0.0 and not is_dead:
		var dx := Game.player.global_position.x - global_position.x
		_face(dx)
		var distance := absf(dx)
		if distance > preferred_distance + 100.0:
			_walk_dir = signf(dx)
		elif distance < preferred_distance - 200.0:
			_walk_dir = -signf(dx)
		else:
			_walk_dir = 0.0
		await get_tree().physics_frame
		time_left -= get_physics_process_delta_time()
	_move = Move.HOLD


# --- Attacks ----------------------------------------------------------------

## Crouch, show the lane, then charge into the wall. In phase 3 it ricochets into a second lunge.
func _attack_lunge() -> void:
	var lunges := int(_by_phase(1, 1, 2))
	for n in lunges:
		if n > 0:
			await _until_grounded()
			if is_dead:
				return
		_face(Game.player.global_position.x - global_position.x)
		_move = Move.HOLD
		var wind_up := _by_phase(0.6, 0.46, 0.34) if n == 0 else 0.3
		var lane_start := global_position.x + facing * SIZE.x * 0.5
		var lane_end := arena.end.x if facing > 0 else arena.position.x
		telegraph.lane(Rect2(minf(lane_start, lane_end), global_position.y - SIZE.y * 0.5,
			absf(lane_end - lane_start), SIZE.y), wind_up, facing > 0)
		visual.target_scale = Vector2(1.22, 0.8)
		velocity.x = -facing * 140.0
		eye.size = Vector2(22, 8)
		Sfx.play("boss_telegraph", -4.0, 1.0 if n == 0 else 1.4)
		await _wait(wind_up)
		if is_dead:
			return

		visual.target_scale = Vector2.ONE
		visual.punch(Vector2(1.4, 0.75))
		eye.size = Vector2(18, 18)
		_hit_wall = false
		_move = Move.LUNGE
		Juice.shake(0.15)
		Sfx.play("boss_lunge", -2.0)
		var time_left := 1.4
		while time_left > 0.0 and not _hit_wall and not is_dead:
			Juice.ghost(Rect2(global_position - SIZE * 0.5, SIZE), Palette.color(Palette.Role.BOSS, 1.2, 0.35), 0.2)
			await get_tree().physics_frame
			time_left -= get_physics_process_delta_time()
		if _hit_wall:
			var wall_point := global_position + Vector2(facing * SIZE.x * 0.5, 0)
			visual.punch(Vector2(0.7, 1.28))
			Juice.freeze(0.07)
			Juice.shake(0.55)
			Juice.kick(Vector2(facing * 26.0, 0))
			Juice.sparks(wall_point, Palette.color(Palette.Role.THREAT, 2.0), 18, 700.0, PI if facing > 0 else 0.0, PI)
			Juice.dust(wall_point, 10, Vector2(-facing, 0), PI, 260.0)
			Juice.ripple(wall_point, 420.0, 380.0)
			Sfx.play("wall_slam")
			velocity = Vector2(-facing * 320.0, -380.0)
			if phase >= 3:
				# Debris rains from the impact.
				for i in 3:
					var x := wall_point.x - facing * randf_range(120.0, 520.0)
					_fire(Vector2(x, arena.position.y + 20.0), Vector2(0, shot_speed * 0.9))
		_move = Move.HOLD
	await _wait(_by_phase(0.6, 0.48, 0.36))


## Gather, then fire aimed shots.
func _attack_volley() -> void:
	_move = Move.HOLD
	var count: int = int(_by_phase(3, 5, 7))
	var interval := _by_phase(0.2, 0.15, 0.11)
	visual.target_scale = Vector2(0.9, 1.12)
	telegraph.ring(global_position, 60.0, _by_phase(0.5, 0.42, 0.32))
	Sfx.play("boss_telegraph", -6.0, 1.3)
	await _wait(_by_phase(0.5, 0.42, 0.32))
	for i in count:
		if is_dead or _player_gone():
			break
		_face(Game.player.global_position.x - global_position.x)
		var target := Game.player.global_position
		if phase >= 3:
			target += Game.player.velocity * 0.25  # Leads the target in the last phase.
		var dir := (target - global_position).normalized()
		_fire(global_position + dir * 46.0, dir * shot_speed * _speed())
		visual.punch(Vector2(1.12, 0.9))
		visual.nudge(-dir * 8.0)
		Sfx.play("boss_shot", -4.0)
		await _wait(interval)
	visual.target_scale = Vector2.ONE
	await _wait(0.35)


## Rise to the middle, fire rings with a visible gap, then slam down onto the player.
func _attack_ring_slam() -> void:
	_fly_target = Vector2(clampf(Game.player.global_position.x, arena.position.x + 300.0, arena.end.x - 300.0),
		hover_height)
	_move = Move.FLY
	visual.punch(Vector2(0.75, 1.3))
	Sfx.play("boss_rise", -4.0)
	await _wait(0.55)
	var rings: int = int(_by_phase(1, 2, 3))
	var bullets: int = int(_by_phase(14, 16, 18))
	var gap_angle := randf_range(PI * 0.3, PI * 0.7)
	for r in rings:
		if is_dead:
			return
		var gap_size := TAU / bullets * 3.0
		var warn := _by_phase(0.55, 0.42, 0.34)
		telegraph.ring(global_position, 70.0, warn, gap_angle, gap_size)
		visual.target_scale = Vector2(1.15, 0.88)
		Sfx.play("boss_telegraph", -8.0, 1.6)
		await _wait(warn)
		if is_dead:
			return
		_fire_ring(bullets, gap_angle, gap_size, ring_speed * _speed())
		visual.target_scale = Vector2.ONE
		visual.punch(Vector2(1.3, 1.3))
		Juice.shake(0.22)
		Juice.ring(global_position, Palette.color(Palette.Role.THREAT, 2.0), 30.0, 120.0, 0.25, 4.0)
		Sfx.play("boss_ring", -2.0)
		gap_angle += randf_range(-1.0, 1.0)
		await _wait(0.35)

	# Track the player, show the landing zone, then drop.
	var track := _by_phase(0.5, 0.4, 0.3)
	var landing := Rect2(0, arena.end.y - 18.0, SIZE.x + 40.0, 18.0)
	while track > 0.0 and not is_dead:
		_fly_target.x = clampf(Game.player.global_position.x, arena.position.x + 60.0, arena.end.x - 60.0)
		landing.position.x = global_position.x - landing.size.x * 0.5
		telegraph.clear()
		telegraph.marker(landing, 0.04)
		await get_tree().physics_frame
		track -= get_physics_process_delta_time()
	telegraph.clear()
	if is_dead:
		return
	_move = Move.SLAM
	visual.punch(Vector2(0.8, 1.3))
	await _until_grounded()
	_slam_impact()
	_move = Move.HOLD
	await _wait(_by_phase(0.7, 0.55, 0.42))


## Phase 2+: a telegraphed leap that lands where the player is standing.
func _attack_pounce() -> void:
	_move = Move.HOLD
	var target_x := clampf(Game.player.global_position.x, arena.position.x + 60.0, arena.end.x - 60.0)
	_face(target_x - global_position.x)
	var wind_up := _by_phase(0.5, 0.4, 0.3)
	telegraph.marker(Rect2(target_x - SIZE.x * 0.5 - 20.0, arena.end.y - 18.0, SIZE.x + 40.0, 18.0), wind_up + 0.6)
	visual.target_scale = Vector2(1.25, 0.78)
	Sfx.play("boss_telegraph", -5.0, 0.8)
	await _wait(wind_up)
	if is_dead:
		return
	visual.target_scale = Vector2.ONE
	visual.punch(Vector2(0.72, 1.35))
	var air_time := 0.62
	velocity = Vector2((target_x - global_position.x) / air_time, -gravity * air_time * 0.5)
	Juice.dust(global_position + Vector2(0, SIZE.y * 0.5), 8)
	Sfx.play("boss_rise", -6.0, 1.4)
	await _wait(0.1)
	await _until_grounded()
	telegraph.clear()
	_slam_impact()
	_move = Move.HOLD
	await _wait(_by_phase(0.6, 0.5, 0.4))


## A fan of shots aimed at the player. The rays show every path before it fires.
func _attack_fan() -> void:
	_move = Move.HOLD
	var count := int(_by_phase(5, 7, 9))
	var spread := deg_to_rad(_by_phase(50.0, 64.0, 80.0))
	var waves := int(_by_phase(1, 1, 2))
	for w in waves:
		if is_dead or _player_gone():
			return
		var to_player := Game.player.global_position - global_position
		_face(to_player.x)
		var aim := to_player.angle()
		var angles: Array[float] = []
		for i in count:
			angles.append(aim - spread * 0.5 + spread * i / (count - 1))
		var warn := _by_phase(0.55, 0.42, 0.32)
		telegraph.rays(global_position, angles, 260.0, warn)
		visual.target_scale = Vector2(1.12, 0.9)
		Sfx.play("boss_telegraph", -7.0, 1.2)
		await _wait(warn)
		if is_dead:
			return
		for a in angles:
			var dir := Vector2.from_angle(a)
			_fire(global_position + dir * 46.0, dir * shot_speed * 0.85 * _speed())
		visual.target_scale = Vector2.ONE
		visual.punch(Vector2(1.25, 0.82))
		visual.nudge(-Vector2.from_angle(aim) * 12.0)
		Juice.shake(0.2)
		Sfx.play("fan", -3.0)
		await _wait(0.3)
	await _wait(0.3)


## Phase 2+: a stomp marks columns across the arena, then needles rain down them.
## The player's current column is always one of them, so standing still is never safe.
func _attack_needle_rain() -> void:
	_move = Move.HOLD
	visual.target_scale = Vector2(1.2, 0.8)
	Sfx.play("boss_telegraph", -6.0, 0.9)
	await _wait(0.3)
	if is_dead:
		return
	var feet := global_position + Vector2(0, SIZE.y * 0.5)
	visual.target_scale = Vector2.ONE
	visual.punch(Vector2(1.4, 0.65))
	Juice.shake(0.3)
	Juice.ripple(feet, 300.0, 400.0)
	Sfx.play("slam", -8.0, 1.3)

	var slot_width := 120.0
	var slots := int(arena.size.x / slot_width)
	var player_slot := clampi(int((Game.player.global_position.x - arena.position.x) / slot_width), 0, slots - 1)
	var order := range(slots)
	order.shuffle()
	var picked: Array[int] = [player_slot]
	for slot: int in order:
		if picked.size() >= int(_by_phase(5, 6, 8)):
			break
		if slot != player_slot:
			picked.append(slot)

	var warn := _by_phase(0.8, 0.7, 0.55)
	for slot in picked:
		telegraph.column(Rect2(arena.position.x + slot * slot_width + 38.0, arena.position.y,
			slot_width - 76.0, arena.size.y), warn)
	await _wait(warn)
	for wave in 3:
		if is_dead:
			return
		for slot in picked:
			var x := arena.position.x + (slot + 0.5) * slot_width
			var needle := _fire(Vector2(x, arena.position.y + 12.0), Vector2(0, 1000.0))
			needle.art.size = Vector2(18, 18)
			needle.stretch_factor = 3.0
		Sfx.play("needle", -6.0)
		await _wait(0.1)
	await _wait(0.45)


## Phase 2+: shots orbit the boss while it chases you, then fling outward.
## Swings destroy them, and a down-swing pogos off them.
func _attack_satellites() -> void:
	_move = Move.HOLD
	var count := int(_by_phase(3, 3, 4))
	var radius := 110.0
	telegraph.ring(global_position, radius, 0.45)
	visual.target_scale = Vector2(0.85, 1.18)
	Sfx.play("boss_rise", -6.0, 1.2)
	await _wait(0.45)
	if is_dead:
		return
	visual.target_scale = Vector2.ONE
	var spin := 3.2 if randf() < 0.5 else -3.2
	var satellites: Array[EnemyShot] = []
	for i in count:
		var shot := _fire(global_position, Vector2.ZERO)
		shot.orbit(self, TAU * i / count, radius, spin)
		shot.life = 8.0
		satellites.append(shot)

	# Float just high enough that the orbit clears the floor, and drift after the player.
	_fly_target = Vector2(global_position.x, arena.end.y - radius - 50.0)
	_move = Move.FLY
	var chase := _by_phase(2.4, 2.8, 3.2)
	while chase > 0.0 and not is_dead and not _player_gone():
		var delta := get_physics_process_delta_time()
		_face(Game.player.global_position.x - global_position.x)
		_fly_target.x = move_toward(_fly_target.x, Game.player.global_position.x, walk_speed * 1.3 * _speed() * delta)
		await get_tree().physics_frame
		chase -= delta
	_move = Move.HOLD
	for shot in satellites:
		if is_instance_valid(shot):
			shot.release(ring_speed * 1.2)
	visual.punch(Vector2(1.3, 1.3))
	Juice.shake(0.2)
	Sfx.play("boss_ring", -4.0, 1.2)
	await _wait(0.4)


## Calls in minions. They appear as outlines first (harmless), then fill in.
func _attack_summon() -> void:
	_move = Move.HOLD
	visual.target_scale = Vector2(0.82, 1.22)
	eye.size = Vector2(24, 24)
	Juice.ring(global_position, Palette.color(Palette.Role.BOSS, 2.2), 30.0, 180.0, 0.4, 4.0)
	Sfx.play("summon", -3.0)
	var plan: Array[PackedScene] = []
	match phase:
		1: plan = [hopper_scene, hopper_scene]
		2: plan = [hopper_scene, flyer_scene]
		_: plan = [hopper_scene, flyer_scene, flyer_scene]
	for scene in plan:
		if _minion_count() >= max_minions:
			break
		var minion := scene.instantiate() as Minion
		Game.spawn(minion, _minion_spawn_point(minion is Flyer))
		await _wait(0.15)
	await _wait(0.35)
	visual.target_scale = Vector2.ONE
	eye.size = Vector2(18, 18)
	visual.punch(Vector2(1.2, 0.85))
	await _wait(0.4)


func _minion_spawn_point(flying: bool) -> Vector2:
	var player_x := Game.player.global_position.x
	for attempt in 12:
		var x := randf_range(arena.position.x + 80.0, arena.end.x - 80.0)
		if not flying and x > 660.0 and x < 1260.0:
			continue  # Not over the spike pit.
		if absf(x - player_x) < 280.0:
			continue  # Never on top of the player.
		var y := randf_range(200.0, 380.0) if flying else arena.end.y - 14.0
		return Vector2(x, y)
	return Vector2(arena.position.x + 120.0 if player_x > 960.0 else arena.end.x - 120.0,
		300.0 if flying else arena.end.y - 14.0)


func _minion_count() -> int:
	return get_tree().get_nodes_in_group("minions").size()


func _slam_impact() -> void:
	var feet := global_position + Vector2(0, SIZE.y * 0.5)
	velocity = Vector2.ZERO
	visual.punch(Vector2(1.5, 0.6), Vector2(-10, 12))
	Juice.freeze(0.08)
	Juice.shake(0.7)
	Juice.kick(Vector2(0, 22))
	Juice.dust(feet, 16, Vector2.UP, PI, 320.0)
	Juice.sparks(feet, Palette.color(Palette.Role.THREAT, 2.0), 16, 640.0, -PI * 0.5, PI * 0.9)
	Juice.ripple(feet, 520.0, 460.0)
	Sfx.play("slam")
	if phase >= 2:
		# Shockwaves roll along the floor both ways: jump them, or pogo off them.
		for dir in [-1.0, 1.0]:
			var shot := _fire(Vector2(feet.x + dir * 50.0, arena.end.y - 16.0),
				Vector2(dir * shockwave_speed * _speed(), 0))
			shot.art.size = Vector2(30, 30)


# --- Physics ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	match _move:
		Move.WALK:
			velocity.x = move_toward(velocity.x, _walk_dir * walk_speed * _speed(), walk_accel * delta)
			velocity.y += gravity * delta
		Move.HOLD:
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0.0, 2400.0 * delta)
			velocity.y += gravity * delta
		Move.LUNGE:
			velocity.x = facing * lunge_speed * _speed()
			velocity.y += gravity * delta
		Move.FLY:
			var to_target := _fly_target - global_position
			velocity = (to_target * 7.0).limit_length(1500.0)
			velocity.y += sin(Time.get_ticks_msec() * 0.006) * 30.0
		Move.SLAM:
			velocity = Vector2(0, slam_speed)
	velocity.y = minf(velocity.y, 2400.0)
	move_and_slide()
	if _move == Move.LUNGE and is_on_wall():
		_hit_wall = true
		_move = Move.HOLD
	_update_visual(delta)


func _update_visual(delta: float) -> void:
	body_art.flash = move_toward(body_art.flash, 0.0, delta * 9.0)
	body_art.glow = lerpf(body_art.glow, PHASE_GLOW[phase - 1], 1.0 - exp(-4.0 * delta))
	visual.target_rotation = clampf(velocity.x / 1500.0, -1.0, 1.0) * 0.12 if not is_on_floor() else 0.0
	if Game.player and not is_dead:
		var look := (Game.player.global_position - global_position).normalized() * 13.0
		eye.position = eye.position.lerp(Vector2(0, -SIZE.y * 0.5) + look, 1.0 - exp(-12.0 * delta))


# --- Damage -----------------------------------------------------------------

func _on_hurt(damage: int, source_position: Vector2) -> void:
	if is_dead or _invulnerable:
		return
	health = maxi(0, health - damage)
	body_art.flash = 1.0
	var from_dir := (global_position - source_position).normalized()
	visual.punch(Vector2(0.9, 1.1))
	visual.nudge(from_dir * 10.0)
	Juice.shards(global_position - from_dir * 20.0, Palette.color(Palette.Role.BOSS, 1.6), 4, 360.0, 6.0, 0.5,
		from_dir.angle(), PI)
	Sfx.play("boss_hit", -4.0)
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()
		return
	var fraction := float(health) / max_health
	if phase == 1 and fraction <= phase_2_at:
		_enter_phase(2)
	elif phase == 2 and fraction <= phase_3_at:
		_enter_phase(3)


func _enter_phase(new_phase: int) -> void:
	phase = new_phase
	phase_changed.emit(phase)
	_invulnerable = true
	hurtbox.vulnerable = false
	visual.punch(Vector2(1.5, 0.6), Vector2(-14, 18))
	Juice.freeze(0.18)
	Juice.slowmo(0.35, 0.5)
	Juice.shake(0.85)
	Juice.ring(global_position, Palette.color(Palette.Role.BOSS, 2.6), 40.0, 520.0, 0.7, 8.0)
	Juice.ring(global_position, Palette.color(Palette.Role.FLASH, 2.0), 20.0, 300.0, 0.4, 4.0)
	Juice.sparks(global_position, Palette.color(Palette.Role.BOSS, 2.4), 40, 1000.0, 0.0, TAU, 0.5)
	Juice.ripple(global_position, 700.0, 700.0)
	Sfx.play("phase_shift")
	await _wait(0.9)
	_invulnerable = false
	hurtbox.vulnerable = true


func _die() -> void:
	is_dead = true
	_move = Move.HOLD
	contact.active = false
	hurtbox.vulnerable = false
	telegraph.clear()
	Juice.freeze(0.25)
	Juice.slowmo(0.25, 1.6)
	Juice.shake(1.0)
	Sfx.play("boss_death")
	for i in 5:
		var at := global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		Juice.impact(at, Palette.color(Palette.Role.BOSS, 2.4), 1.4)
		Juice.shards(at, Palette.color(Palette.Role.BOSS, 1.8), 6, 500.0)
		body_art.flash = 1.0
		visual.punch(Vector2(1.2 + randf() * 0.2, 0.8))
		Juice.shake(0.5)
		await _wait(0.16)
	visual.visible = false
	Juice.ring(global_position, Palette.color(Palette.Role.FLASH, 3.0), 20.0, 900.0, 0.9, 10.0)
	Juice.ring(global_position, Palette.color(Palette.Role.BOSS, 2.6), 10.0, 600.0, 0.8, 6.0)
	Juice.shards(global_position, Palette.color(Palette.Role.BOSS, 2.0), 40, 1100.0, 12.0, 1.4)
	Juice.sparks(global_position, Palette.color(Palette.Role.FLASH, 2.5), 50, 1400.0, 0.0, TAU, 0.6)
	Juice.ripple(global_position, 1200.0, 1100.0)
	Juice.shake(1.0)
	for minion in get_tree().get_nodes_in_group("minions"):
		(minion as Minion).die()
	for child in Game.projectiles.get_children():
		if child is EnemyShot:
			(child as EnemyShot).pop()
	defeated.emit()


# --- Helpers ----------------------------------------------------------------

func _fire(at: Vector2, shot_velocity: Vector2) -> EnemyShot:
	var shot := shot_scene.instantiate() as EnemyShot
	shot.velocity = shot_velocity
	Game.spawn(shot, at)
	return shot


func _fire_ring(count: int, gap_angle: float, gap_size: float, speed: float) -> void:
	for i in count:
		var a := TAU * i / count
		if absf(angle_difference(a, gap_angle)) < gap_size * 0.5:
			continue
		var dir := Vector2.from_angle(a)
		_fire(global_position + dir * 46.0, dir * speed)


func _face(dx: float) -> void:
	if dx != 0.0:
		facing = int(signf(dx))


func _speed() -> float:
	return phase_speed[phase - 1]


func _by_phase(one: float, two: float, three: float) -> float:
	return [one, two, three][phase - 1]


func _player_gone() -> bool:
	return Game.player == null or Game.player.is_dead


## Waits in game time, so freeze frames and slow motion pause the boss too.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false, true).timeout


func _until_grounded() -> void:
	var timeout := 2.0
	while not is_on_floor() and timeout > 0.0 and not is_dead:
		await get_tree().physics_frame
		timeout -= get_physics_process_delta_time()
