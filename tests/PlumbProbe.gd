## Where every build in the file carries its weight — see Plumb.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/PlumbProbe.gd
##
## A probe rather than a test: it asserts nothing and prints the centre of
## gravity of each preset against the two girdles that have to bracket it, the
## height it hangs at, and how much of its own support the plumb line is inside
## of standing still. What it is for is the question no reading in the game could
## answer before — is this creature's skeleton under its weight — and the answer
## is a column of numbers you can hold a real animal to.
##
## `ALONG` is the one to read first. It is where the centre of gravity sits from
## snout to tail tip, in the same units the girdles are placed in, so a build is
## balanced exactly when it falls between the two columns either side of it.
extends SceneTree

const TICK: float = 1.0 / 60.0

var main: Node
var done: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if done:
		return false
	done = true
	var player: Creature = main.creature
	if player == null:
		print("no creature")
		quit()
		return false
	main.terrain.clear()
	main.target_creature.reset(Vector2(0.0, 9000.0), 0.0)

	print("")
	print("  %-11s %5s %5s %5s  %5s %6s %6s %6s %5s %5s %5s" % [
		"BUILD", "SHLDR", "ALONG", "HIP", "LEGS", "HEIGHT", "MASS", "STEADY",
		"FEET", "BIAS", "CARRY"])
	print("  " + "-".repeat(84))
	for preset in ["(default)", "Lizard", "Cat", "Elephant", "Cheetah",
			"T. rex", "Kangaroo"]:
		_row(player, preset, "" if preset == "(default)" else preset)
	print("")
	print("  SHLDR/HIP  girdle stations, 0 snout to 1 tail tip")
	print("  ALONG      where the centre of gravity is, same units")
	print("  LEGS       share of the whole animal that is limb")
	print("  HEIGHT     how high the centre of gravity hangs, px")
	print("  MASS       density-weighted cells standing")
	print("  STEADY     share of its own support the plumb line is inside")
	print("  FEET       contacts holding it up")
	print("  BIAS       resting foot bias, fore/aft, after the balance floor")
	print("  CARRY      trunk angle carried: species / least that balances")
	print("")
	quit()
	return false


func _row(player: Creature, label: String, preset: String) -> void:
	if preset != "":
		player.params.apply_preset(preset)
	else:
		player.params.copy_from(CreatureParams.new())
	player.rebuild()
	player.reset(Vector2.ZERO, 0.0)
	for i in 240:
		player._physics_process(TICK)

	var pl: Plumb = player.plumb
	var loco: Locomotion = player.locomotion
	var lat: AnatomyLattice = player.anatomy.tissue.lattice
	var limb_cells: float = 0.0
	for key in BodyPlan.LIMB_KEYS:
		limb_cells += float(lat.region_cells(int(player.anatomy.tissue.plan.limb_region[key])))
	print("  %-11s %5.2f %5.2f %5.2f  %4.0f%% %6.1f %6.0f %6.2f %5d %5s %5s" % [
		label,
		player.params.front_limb_t, pl.along, player.params.rear_limb_t,
		100.0 * limb_cells / maxf(float(lat.standing_total), 1.0),
		pl.height, pl.units, pl.steadiness(), pl.feet,
		"%.2f/%.2f" % [loco.foot_bias.x, loco.foot_bias.y],
		"%.0f/%.0f" % [player.params.trunk_lift_deg, loco.carriage_deg]])
