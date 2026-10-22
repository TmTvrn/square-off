extends Node2D
## Wires the boss room together: references, restart, and the win/lose beats.

@onready var player: Player = $Player
@onready var boss: Boss = $Boss
@onready var hud: Hud = $HudLayer/Hud


func _ready() -> void:
	Juice.reset()
	Game.projectiles = $Projectiles
	Game.enemies = $Enemies
	hud.bind(player, boss)
	player.died.connect(_on_player_died)
	boss.defeated.connect(_on_boss_defeated)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		Juice.reset()
		get_tree().reload_current_scene()
	elif event.is_action_pressed("quit"):
		get_tree().quit()


func _on_player_died() -> void:
	await get_tree().create_timer(1.2, true, false, true).timeout
	hud.show_end("SQUARED AWAY", Palette.color(Palette.Role.BOSS))


func _on_boss_defeated() -> void:
	await get_tree().create_timer(1.6, true, false, true).timeout
	Sfx.play("victory", -2.0)
	hud.show_end("VICTORY", Palette.color(Palette.Role.PLAYER))
