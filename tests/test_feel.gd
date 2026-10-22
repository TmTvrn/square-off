extends Node
## Headless checks that the numbers in player_tuning.tres produce the feel they promise.
## Run:  godot --headless --path . res://tests/test_feel.tscn
## Exits with code 1 if any check fails.

const EXPECTED_CHECKS := 6

var _failures := 0
var _checks := 0
var _main: Node
var _player: Player
var _boss: Boss


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await _load_arena()
	await _test_jump_height()
	await _load_arena()
	await _test_dash_distance()
	await _load_arena()
	await _test_melee_and_determination()
	await _load_arena()
	await _test_heal()
	await _load_arena()
	await _test_minion()
	if _checks != EXPECTED_CHECKS:
		_failures += 1
		print("  FAIL  expected %d checks, ran %d" % [EXPECTED_CHECKS, _checks])
	print("\n%s" % ("ALL CHECKS PASSED" if _failures == 0 else "%d CHECK(S) FAILED" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _load_arena() -> void:
	if _main:
		_main.queue_free()
		await get_tree().process_frame
	for action in InputMap.get_actions():
		Input.action_release(action)
	_main = load("res://scenes/main.tscn").instantiate()
	_boss = _main.get_node("Boss")
	_boss.brain_enabled = false
	_player = _main.get_node("Player")
	add_child(_main)
	await _frames(20)  # settle onto the floor


func _test_jump_height() -> void:
	var tuning := _player.tuning
	var start_y := _player.global_position.y
	var top_y := start_y
	Input.action_press("jump")
	for i in 90:
		await get_tree().physics_frame
		top_y = minf(top_y, _player.global_position.y)
	Input.action_release("jump")
	var height := start_y - top_y
	_check("full jump reaches ~%d px (got %.1f)" % [tuning.jump_height, height],
		height > tuning.jump_height * 0.95 and height < tuning.jump_height * 1.2)


func _test_dash_distance() -> void:
	var tuning := _player.tuning
	var start_x := _player.global_position.x
	Input.action_press("dash")
	await _frames(int(tuning.dash_time * 60.0) + 1)
	Input.action_release("dash")
	var distance := _player.global_position.x - start_x
	var expected := tuning.dash_speed * tuning.dash_time
	_check("dash travels ~%d px (got %.1f)" % [expected, distance],
		absf(distance - expected) < expected * 0.2)


func _test_melee_and_determination() -> void:
	var tuning := _player.tuning
	_player.global_position = _boss.global_position + Vector2(-80, 8)
	_player.reset_physics_interpolation()
	_player.facing = 1
	await _frames(5)
	var start_health := _boss.health
	for i in tuning.hits_per_heal_charge:
		Input.action_press("attack")
		await _frames(2)
		Input.action_release("attack")
		await _frames(int(tuning.attack_cooldown * 60.0) + 4)
	_check("melee hits land (boss %d -> %d)" % [start_health, _boss.health],
		_boss.health == start_health - tuning.hits_per_heal_charge * tuning.melee_damage)
	_check("%d hits earn a heal charge (charges: %d)" % [tuning.hits_per_heal_charge, _player.heal_charges],
		_player.heal_charges == 1)


func _test_heal() -> void:
	var tuning := _player.tuning
	_player.heal_charges = 1
	_player.health = tuning.max_health - 2
	Input.action_press("move_down")
	await _frames(2)
	Input.action_press("jump")
	await _frames(int(tuning.heal_time * 60.0) + 6)
	Input.action_release("jump")
	Input.action_release("move_down")
	_check("holding Down+Jump heals 1 (health %d/%d)" % [_player.health, tuning.max_health],
		_player.health == tuning.max_health - 1 and _player.heal_charges == 0)


func _test_minion() -> void:
	var hopper := (load("res://scenes/minions/hopper.tscn") as PackedScene).instantiate() as Hopper
	var hits_needed := hopper.max_health
	Game.spawn(hopper, _player.global_position + Vector2(70, 0))
	await _frames(int(hopper.spawn_time * 60.0) + 2)
	for i in hopper.max_health:
		if not is_instance_valid(hopper):
			break
		hopper.global_position = _player.global_position + Vector2(70, 0)
		hopper.velocity = Vector2.ZERO
		_player.facing = 1
		Input.action_press("attack")
		await _frames(2)
		Input.action_release("attack")
		await _frames(int(_player.tuning.attack_cooldown * 60.0) + 4)
	_check("a hopper dies after %d hits" % hits_needed, not is_instance_valid(hopper) or hopper.is_dead)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(label: String, passed: bool) -> void:
	_checks += 1
	print(("  PASS  " if passed else "  FAIL  ") + label)
	if not passed:
		_failures += 1
