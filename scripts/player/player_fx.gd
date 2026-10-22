class_name PlayerFx
extends Node2D
## Effects attached to the player, drawn additively in the player's local space:
##   - the slash crescent (alternates direction each swing, so combos read as combos)
##   - the charge: a ring that tightens, then a rotating square once a shot is ready
##   - the heal swirl: motes spiral inward (speeding up as they close in) while a ring closes on the body.
##     The heal is done when the ring reaches you, so it needs no UI bar.

const SLASH_TIME := 0.12
const SLASH_RADIUS := 80.0
const SLASH_THICKNESS := 24.0
const SLASH_ARC := 2.88  # radians, about 165 degrees

@onready var player: Player = get_parent()

var _slash_age := -1.0
var _slash_angle := 0.0
var _slash_flip := false
var _motes: Array[Dictionary] = []
var _spin := 0.0
var _burst_age := -1.0


func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func start_slash(direction: Player.Swing, facing: int) -> void:
	_slash_age = 0.0
	_slash_flip = not _slash_flip
	match direction:
		Player.Swing.SIDE:
			_slash_angle = 0.0 if facing > 0 else PI
		Player.Swing.UP:
			_slash_angle = -PI * 0.5
		Player.Swing.DOWN:
			_slash_angle = PI * 0.5


func heal_burst() -> void:
	_burst_age = 0.0
	_motes.clear()


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_spin += delta
	if _slash_age >= 0.0:
		_slash_age += delta
		if _slash_age > SLASH_TIME:
			_slash_age = -1.0
	if _burst_age >= 0.0:
		_burst_age += delta
		if _burst_age > 0.35:
			_burst_age = -1.0

	if player.is_healing:
		_spawn_motes(lerpf(40.0, 160.0, player.heal_progress) * delta, Palette.Role.HEAL, 130.0)
	elif player.is_charging and player.charge_time > 0.12:
		_spawn_motes((24.0 + 16.0 * player.charge_level) * delta, Palette.Role.PLAYER, 54.0)

	var i := _motes.size() - 1
	while i >= 0:
		var m := _motes[i]
		m.prev = Vector2.from_angle(m.angle) * m.radius
		# Angular speed grows as the radius shrinks (like water down a drain).
		m.angle += m.swirl * delta * clampf(m.start_radius / maxf(m.radius, 10.0), 1.0, 6.0)
		m.radius -= m.inward * delta
		if m.radius < 10.0:
			_motes.remove_at(i)
		i -= 1
	queue_redraw()


func _spawn_motes(expected: float, role: Palette.Role, radius: float) -> void:
	var count := int(expected) + (1 if randf() < fmod(expected, 1.0) else 0)
	for k in count:
		var r := radius * randf_range(0.8, 1.15)
		_motes.append({
			"angle": randf() * TAU, "radius": r, "start_radius": r, "prev": Vector2.ZERO,
			"swirl": randf_range(2.2, 3.2), "inward": randf_range(140.0, 220.0), "role": role,
		})


func _draw() -> void:
	_draw_motes()
	if player.is_healing:
		_draw_heal(player.heal_progress)
	if player.is_charging and player.charge_time > 0.12:
		_draw_charge()
	if _slash_age >= 0.0:
		_draw_slash(_slash_age / SLASH_TIME)
	if _burst_age >= 0.0:
		var t := _burst_age / 0.35
		var c := Palette.color(Palette.Role.HEAL, 3.0, 1.0 - t)
		_draw_square_outline(lerpf(40.0, 160.0, ease(t, 0.4)), PI * 0.25 + t, c, 6.0 * (1.0 - t) + 1.0)


func _draw_motes() -> void:
	for m in _motes:
		var pos: Vector2 = Vector2.from_angle(m.angle) * m.radius
		var closeness: float = 1.0 - m.radius / m.start_radius
		var c := Palette.color(m.role, 1.4 + 2.0 * closeness, 0.3 + 0.7 * closeness)
		draw_line(m.prev, pos, c, 1.5 + 2.0 * closeness, true)


func _draw_heal(p: float) -> void:
	var e := p * p * (3.0 - 2.0 * p)
	var violet := Palette.color(Palette.Role.HEAL, 1.6 + 2.0 * p, 0.35 + 0.65 * p)
	# The closing ring.
	draw_arc(Vector2.ZERO, lerpf(130.0, 30.0, e), 0.0, TAU, 72, violet, 2.0 + 4.0 * p, true)
	# Two counter-rotating squares tightening around the body.
	_draw_square_outline(lerpf(110.0, 46.0, e), _spin * 2.4, violet, 1.5 + 2.0 * p)
	_draw_square_outline(lerpf(80.0, 38.0, e), -_spin * 1.6 + PI * 0.25, Palette.color(Palette.Role.HEAL, 1.2 + p, 0.3 + 0.5 * p), 1.5)


func _draw_charge() -> void:
	var tuning := player.tuning
	var cyan := Palette.color(Palette.Role.PLAYER, 1.5, 0.8)
	if player.charge_level == 0:
		var p := clampf(player.charge_time / tuning.charge_level_1_time, 0.0, 1.0)
		draw_arc(Vector2.ZERO, lerpf(40.0, 28.0, p), 0.0, TAU, 48, Palette.color(Palette.Role.PLAYER, 1.3, p * 0.5), 1.5, true)
		return
	var p2 := clampf((player.charge_time - tuning.charge_level_1_time)
		/ (tuning.charge_level_2_time - tuning.charge_level_1_time), 0.0, 1.0)
	_draw_square_outline(34.0, _spin * 3.0, cyan, 1.5)
	if player.charge_level == 1:
		# Progress toward the big shot, drawn as an arc filling clockwise.
		draw_arc(Vector2.ZERO, 30.0, -PI * 0.5, -PI * 0.5 + TAU * p2, 48, cyan, 2.0, true)
	else:
		var pulse := 0.5 + 0.5 * sin(_spin * 22.0)
		var hot := Palette.color(Palette.Role.PLAYER, 1.9 + 0.6 * pulse)
		draw_arc(Vector2.ZERO, 30.0 + pulse * 2.0, 0.0, TAU, 48, hot, 2.5, true)
		_draw_square_outline(42.0, -_spin * 4.0 + PI * 0.25, hot, 1.5)


func _draw_slash(t: float) -> void:
	var start := _slash_angle - SLASH_ARC * 0.5
	var end := _slash_angle + SLASH_ARC * 0.5
	if _slash_flip:
		var swap := start
		start = end
		end = swap
	# The head races ahead, the tail chases it: a crescent that sweeps and then dissolves.
	var head := 1.0 - pow(1.0 - clampf(t / 0.55, 0.0, 1.0), 3.0)
	var tail := pow(clampf((t - 0.2) / 0.8, 0.0, 1.0), 2.0)
	var a0 := lerpf(start, end, tail)
	var a1 := lerpf(start, end, head)
	if absf(a1 - a0) < 0.05:
		return
	var center := Vector2.from_angle(_slash_angle) * 12.0
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var steps := 16
	for k in steps + 1:
		var u := float(k) / steps
		var a := lerpf(a0, a1, u)
		var thickness := SLASH_THICKNESS * sin(PI * u) * (1.0 - t * 0.5) + 1.0
		outer.append(center + Vector2.from_angle(a) * SLASH_RADIUS)
		inner.append(center + Vector2.from_angle(a) * (SLASH_RADIUS - thickness))
	inner.reverse()
	var body := Palette.color(Palette.Role.PLAYER, 2.2, 1.0 - t * 0.7)
	draw_colored_polygon(outer + inner, body)
	draw_polyline(outer, Palette.color(Palette.Role.FLASH, 2.4, 1.0 - t), 2.0, true)


func _draw_square_outline(size: float, angle: float, color: Color, width: float) -> void:
	draw_set_transform(Vector2.ZERO, angle, Vector2.ONE)
	draw_rect(Rect2(-size * 0.5, -size * 0.5, size, size), color, false, width)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
