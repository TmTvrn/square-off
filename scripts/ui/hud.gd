class_name Hud
extends Control
## Minimal HUD in the game's own shape language:
##   top-left   – health squares (cyan), heal charges (violet) with a determination meter
##   top-center – one boss bar with a white "recent damage" trail and phase notches

const PIP := 22.0
const PIP_GAP := 10.0
const BAR_WIDTH := 720.0
const BAR_HEIGHT := 10.0

var _health := 5
var _max_health := 5
var _heal_charges := 0
var _determination := 0
var _hits_per_charge := 4
var _max_charges := 3
var _boss_fraction := 1.0
var _boss_trail := 1.0
var _trail_delay := 0.0
var _boss_phase_marks: Array[float] = []
var _pip_pop: Array[float] = []
var _shake := 0.0
var _last_time := 0.0

@onready var end_title: Label = $EndTitle
@onready var end_hint: Label = $EndHint


func bind(player: Player, boss: Boss) -> void:
	_hits_per_charge = player.tuning.hits_per_heal_charge
	_max_charges = player.tuning.max_heal_charges
	_boss_phase_marks = [boss.phase_2_at, boss.phase_3_at]
	player.health_changed.connect(_on_health_changed)
	player.heal_charges_changed.connect(_on_heal_charges_changed)
	boss.health_changed.connect(_on_boss_health_changed)
	end_title.visible = false
	end_hint.visible = false


func show_end(title: String, color: Color) -> void:
	end_title.text = title
	end_title.modulate = color
	end_title.visible = true
	end_hint.visible = true
	end_title.pivot_offset = end_title.size * 0.5
	end_title.scale = Vector2(1.6, 1.6)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_ignore_time_scale(true)
	tween.tween_property(end_title, "scale", Vector2.ONE, 0.45)


func _on_health_changed(current: int, maximum: int) -> void:
	if current < _health:
		_shake = 1.0
	_pip_pop.resize(maximum)
	for i in range(mini(current, _health), maxi(current, _health)):
		if i < _pip_pop.size():
			_pip_pop[i] = 1.0
	_health = current
	_max_health = maximum


func _on_heal_charges_changed(charges: int, determination: int) -> void:
	_heal_charges = charges
	_determination = determination


func _on_boss_health_changed(current: int, maximum: int) -> void:
	_boss_fraction = float(current) / maximum
	_trail_delay = 0.45


func _process(_delta: float) -> void:
	# The HUD animates in real time so it keeps moving during freeze frames and slow motion.
	var now := Time.get_ticks_usec() / 1_000_000.0
	var real_delta := minf(now - _last_time, 0.1)
	_last_time = now
	_shake = move_toward(_shake, 0.0, real_delta * 4.0)
	for i in _pip_pop.size():
		_pip_pop[i] = move_toward(_pip_pop[i], 0.0, real_delta * 3.0)
	if _trail_delay > 0.0:
		_trail_delay -= real_delta
	else:
		_boss_trail = move_toward(_boss_trail, _boss_fraction, real_delta * 0.5)
	queue_redraw()


func _draw() -> void:
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 6.0 * _shake
	var origin := Vector2(48, 44) + jitter

	for i in _max_health:
		var pop: float = _pip_pop[i] if i < _pip_pop.size() else 0.0
		var s := PIP * (1.0 + 0.5 * pop)
		var center := origin + Vector2(i * (PIP + PIP_GAP) + PIP * 0.5, PIP * 0.5)
		var rect := Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s))
		if i < _health:
			draw_rect(rect, Palette.color(Palette.Role.PLAYER).lerp(Color.WHITE, pop))
		else:
			draw_rect(rect, Palette.color(Palette.Role.ARENA_EDGE).lerp(Palette.color(Palette.Role.BOSS), pop), false, 2.0)

	var charge_origin := origin + Vector2(0, PIP + 14.0)
	for i in _max_charges:
		var rect := Rect2(charge_origin + Vector2(i * 22.0, 0), Vector2(12, 12))
		if i < _heal_charges:
			draw_rect(rect, Palette.color(Palette.Role.HEAL))
		else:
			draw_rect(rect, Palette.color(Palette.Role.HEAL, 0.6, 0.6), false, 1.5)
	if _heal_charges < _max_charges:
		var meter := Rect2(charge_origin + Vector2(0, 18), Vector2(_max_charges * 22.0 - 10.0, 3))
		draw_rect(meter, Palette.color(Palette.Role.ARENA_EDGE))
		meter.size.x *= float(_determination) / _hits_per_charge
		draw_rect(meter, Palette.color(Palette.Role.HEAL))

	var bar := Rect2(Vector2((size.x - BAR_WIDTH) * 0.5, 48), Vector2(BAR_WIDTH, BAR_HEIGHT))
	draw_rect(bar.grow(3.0), Palette.color(Palette.Role.ARENA))
	var trail := bar
	trail.size.x *= _boss_trail
	draw_rect(trail, Palette.color(Palette.Role.FLASH, 1.0, 0.85))
	var fill := bar
	fill.size.x *= _boss_fraction
	draw_rect(fill, Palette.color(Palette.Role.BOSS))
	for mark in _boss_phase_marks:
		var x := bar.position.x + bar.size.x * mark
		draw_line(Vector2(x, bar.position.y - 4), Vector2(x, bar.end.y + 4), Palette.color(Palette.Role.VOID), 3.0)
