# Square Off

A strictly-2D precision boss fight built in Godot 4.7. Everything is a primitive shape, lit like neon.

**Shape language:** squares are bodies, circles are projectiles, triangles are hazards.
**Fill language:** an outline is a warning; a filled shape is real and can hurt you now.
**Color language:** one hue means one thing. Cyan is you, violet is healing, warm reds are threats.
Press **G** in game to view in grayscale: the fight should still read without color.

## Controls

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Move | Arrows / WASD | Left stick / D-pad |
| Jump (press again in the air to double jump) | X / Space / . | A |
| Attack (hold to charge a shot, release to fire) | C / , | X |
| Dash (8 directions) | Z / / | B / RB |
| Drop through a platform | Down + Jump | |
| Heal (needs a violet charge; earn one every 4 hits) | Hold Down + Jump on the ground | |
| Restart | R | Back |

**The boss** (32 HP, three phases) uses lunge (it ricochets in phase 3), aimed volley, gap-ring slam, fan burst, and summon. From phase 2 it adds pounce, needle rain and orbiting satellites.
**Minions:** Hoppers crouch, then hop at you, and die if they land on spikes. Flyers are diamond-turned squares that hover and fire single shots after a ring tell. Every minion spawns as a harmless outline first.
To practice one attack, select `Boss` and set **Force Attack** / **Start Phase** in the Inspector.

You also get wall slide, wall jump, coyote time, jump buffering, a pogo off enemies, projectiles and spikes (down-attack in the air), and deflecting enemy shots with any swing.

## Running

Open `project.godot` in Godot 4.7+ and press F5.

```bash
godot --headless --path . res://tests/test_feel.tscn   # feel checks (jump height, dash distance, melee, heal)
python3 tools/generate_sfx.py                          # regenerate every sound effect from code
```

## Where things live

| Want to change... | Edit |
| --- | --- |
| How the player feels (speeds, jump height, timings) | `tuning/player_tuning.tres` in the Inspector, or the defaults in `scripts/player/player_tuning.gd` |
| Boss health, phases, attack speeds | Select `Boss` in `scenes/main.tscn` and use the Inspector |
| Colors | `scripts/core/palette.gd` (one place, whole game follows) |
| Level layout | Move or resize the `ArenaBlock` nodes under `Arena` in `scenes/main.tscn` |
| Screen shake, freeze frames, particles | `scripts/autoload/juice.gd` |
| Sounds | Recipes in `tools/generate_sfx.py` |

## License

Public domain ([CC0 1.0](LICENSE)). Use it for anything.
