## Throwaway: that fibre composition genuinely reaches the gait and the leap —
## a fast-twitch Cat swings sooner and charges quicker than a slow-twitch one,
## and the mixed default is bit-for-bit the old animal.
extends SceneTree

var main: Node
var frames: int = 0
var readings: Array = []
var twitches: Array = [0.5, 0.0, 1.0]


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	var player: Creature = main.get_node("Creature")
	if frames == 3:
		player.params.apply_preset("Cat")
		player.reset(Vector2.ZERO, 0.0)
	var step: int = frames - 4
	if step >= 0 and step % 4 == 0:
		var pick: int = step / 4
		if pick < twitches.size():
			player.params.fast_twitch = twitches[pick]
		else:
			for r in readings:
				print(r)
			quit(0)
			return false
	elif step >= 0 and step % 4 == 3:
		player._physics_process(1.0 / 60.0)
		readings.append("twitch %.1f (loco sees %.1f, power %.3f): swing %.4f s, leap charge %.4f s" % [
			player.params.fast_twitch,
			player.locomotion.twitch,
			player.locomotion.power,
			player.locomotion.swing_time(100.0),
			player.leap.charge_time,
		])
	return false
