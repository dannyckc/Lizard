## Throwaway diagnostic: what each preset actually feels like, in numbers.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/FeelProbe.gd
extends SceneTree

const TICK: float = 1.0 / 60.0

var done: bool = false


func _process(_delta: float) -> bool:
	if done:
		return true
	done = true
	for preset_name in ["Lizard", "Cat", "Elephant", "Camel", "Cheetah", "T. rex", "Kangaroo"]:
		_probe(preset_name)
	quit(0)
	return true


func _probe(preset_name: String) -> void:
	var c := _spawn(preset_name)
	var length: float = c.spine.arc_length()

	# --- top speed and how long it takes to get there -------------------------
	var go := MovementInput.Command.new()
	go.throttle = 1.0
	var t_walk_90: float = -1.0
	var walk_dist: float = 0.0
	for i in 600:
		c.command = go
		c._physics_process(TICK)
		walk_dist += absf(c.speed) * TICK
		if t_walk_90 < 0.0 and absf(c.speed) >= c.params.move_speed * c.size_scale * 0.9:
			t_walk_90 = float(i + 1) * TICK
	var walk_speed: float = absf(c.speed)
	var walk_cycle: float = _cycle(c)
	var walk_swing: float = _swing(c)

	# --- stopping -------------------------------------------------------------
	var stop := MovementInput.Command.new()
	var stop_time: float = -1.0
	var stop_dist: float = 0.0
	for i in 600:
		c.command = stop
		c._physics_process(TICK)
		stop_dist += absf(c.speed) * TICK
		if absf(c.speed) < 1.0:
			stop_time = float(i + 1) * TICK
			break

	# --- sprint ---------------------------------------------------------------
	go.sprint = true
	for _i in 400:
		c.command = go
		c._physics_process(TICK)
	# How far a foot that is supposed to be nailed to the ground actually moves.
	# This is the whole of "sliding on ice", measured: a planted foot belongs to
	# the world, so anything it does per tick is the animal skating over it.
	var was: Dictionary = {}
	var slip: float = 0.0
	var samples: int = 0
	for _i in 200:
		c.command = go
		c._physics_process(TICK)
		for limb in c.gait.limbs:
			if limb.stepping or not limb.bearing:
				was.erase(limb.key)
				continue
			if was.has(limb.key):
				slip += (limb.planted - was[limb.key]).length()
				samples += 1
			was[limb.key] = limb.planted
	var sprint_speed: float = absf(c.speed)
	var sprint_cycle: float = _cycle(c)
	var sprint_swing: float = _swing(c)
	var sprint_sweep: float = _sweep(c)
	var sprint_slip: float = slip / float(maxi(samples, 1))

	# --- standing turn --------------------------------------------------------
	_destroy(c)
	c = _spawn(preset_name)
	var spin := MovementInput.Command.new()
	spin.turn = 1.0
	var swept: float = 0.0
	var prev: float = c.heading
	var t_180: float = -1.0
	var peak_rate: float = 0.0
	for i in 900:
		c.command = spin
		c._physics_process(TICK)
		swept += absf(wrapf(c.heading - prev, -PI, PI))
		prev = c.heading
		peak_rate = maxf(peak_rate, absf(c.ang_vel))
		if t_180 < 0.0 and swept >= PI:
			t_180 = float(i + 1) * TICK
	_destroy(c)

	# --- turn while running ---------------------------------------------------
	c = _spawn(preset_name)
	var run_turn := MovementInput.Command.new()
	run_turn.throttle = 1.0
	for _i in 240:
		c.command = run_turn
		c._physics_process(TICK)
	run_turn.turn = 1.0
	var run_swept: float = 0.0
	prev = c.heading
	for _i in 120:
		c.command = run_turn
		c._physics_process(TICK)
		run_swept += absf(wrapf(c.heading - prev, -PI, PI))
		prev = c.heading
	var run_rate: float = rad_to_deg(run_swept) / 2.0
	var radius: float = absf(c.speed) / maxf(absf(c.ang_vel), 0.0001)
	_destroy(c)

	# --- a body standing still, for the derived descriptors -------------------
	var c2 := _spawn(preset_name)
	for _i in 30:
		c2.command = MovementInput.Command.new()
		c2._physics_process(TICK)

	print("\n=== %s ===  body %.0f px" % [preset_name, length])
	print("  physique  mass %.2f  power %.2f  duty %.2f  accel %.0f px/s2 = %.2f g  turn %.0f deg/s" % [
		c2.physique.mass, c2.locomotion.power, c2.locomotion.duty, c2.locomotion.accel,
		c2.locomotion.accel / 1500.0, rad_to_deg(c2.locomotion.turn_rate)])
	print("  legs      %s" % _limb_report(c2))
	print("  walk      %6.0f px/s = %4.2f body/s | 90%% in %.2f s over %.0f px" % [
		walk_speed, walk_speed / length, t_walk_90, walk_dist])
	print("  sprint    %6.0f px/s = %4.2f body/s" % [sprint_speed, sprint_speed / length])
	print("  stop      %.2f s over %.0f px (%.2f body lengths)" % [
		stop_time, stop_dist, stop_dist / length])
	print("  step      walk %.2f s/cycle (%.1f Hz), swing %.3f s | sprint %.2f s/cycle (%.1f Hz), swing %.3f s" % [
		walk_cycle, 1.0 / maxf(walk_cycle, 0.001), walk_swing,
		sprint_cycle, 1.0 / maxf(sprint_cycle, 0.001), sprint_swing])
	# Ground covered per cycle against the foot's own fore-and-aft envelope. Over
	# one and the feet are being towed rather than placed.
	print("  footing   sprint %.0f px/cycle, envelope %.0f px | planted foot slips %.2f px/tick (%.0f%% of body travel)" % [
		sprint_speed * sprint_cycle, sprint_sweep * 2.0, sprint_slip,
		100.0 * sprint_slip / maxf(sprint_speed * TICK, 0.001)])
	print("  spin      %.0f deg/s peak | 180 deg in %.2f s" % [
		rad_to_deg(peak_rate), t_180])
	print("  run turn  %.0f deg/s | radius %.0f px = %.2f body lengths" % [
		run_rate, radius, radius / length])
	_destroy(c2)


func _limb_report(c: Creature) -> String:
	var out: String = ""
	for limb in c.gait.limbs:
		var cycle_floor: float = limb.swing_base / maxf(1.0 - c.locomotion.duty, 0.05)
		out += "\n            %-11s bone %5.1f  socket_h %5.1f  sweep %5.1f  stride %5.1f  swing %.3f -> cadence %4.1f Hz, legs give %5.0f px/s" % [
			limb.key, limb.anatomical_length, limb.socket_height, limb.sweep_limit,
			limb.stride, limb.swing_base, 1.0 / cycle_floor, limb.stride / cycle_floor]
	return out


func _cycle(c: Creature) -> float:
	var total: float = 0.0
	var n: int = 0
	for limb in c.gait.limbs:
		if limb.cycle > 0.0:
			total += limb.cycle
			n += 1
	return total / float(n) if n > 0 else 0.0


func _sweep(c: Creature) -> float:
	var least: float = INF
	for limb in c.gait.limbs:
		if limb.bearing:
			least = minf(least, limb.sweep_limit)
	return 0.0 if is_inf(least) else least


func _swing(c: Creature) -> float:
	var total: float = 0.0
	var n: int = 0
	for limb in c.gait.limbs:
		if limb.swing_base > 0.0:
			total += limb.swing_base
			n += 1
	return total / float(n) if n > 0 else 0.0


func _spawn(preset_name: String) -> Creature:
	var c := Creature.new()
	var p := CreatureParams.new()
	p.apply_preset(preset_name)
	c.params = p
	root.add_child(c)
	return c


func _destroy(c: Creature) -> void:
	root.remove_child(c)
	c.free()
