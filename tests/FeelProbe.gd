## Scratch probe: what the walk actually measures, in cat units.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/FeelProbe.gd
extends SceneTree

const TICK: float = 1.0 / 60.0
## v2's cat is 1.59 px per cm (the ruler memory).
const PX_PER_CM: float = 1.59

var main: Node
var done: bool = false


func _initialize() -> void:
	main = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if done:
		return false
	done = true
	var c: Creature2 = main.creature
	main.terrain.clear()
	_geometry(c)
	for throttle in [0.28, 0.6, 1.0]:
		_walk(c, throttle, false)
	_walk(c, 1.0, true)
	_turn(c, 0.0)
	_turn(c, 1.0)
	quit(0)
	return false


func _calm(c: Creature2) -> void:
	c.command.throttle = 0.0
	c.command.turn = 0.0
	c.command.sprint = false
	c.command.jump = false
	c.reset()
	for i in 30:
		c._physics_process(TICK)


func _geometry(c: Creature2) -> void:
	var spec: BodySpec = c.body
	var car: Carriage = c.attitude.active
	print("--- geometry ---")
	print("  trunk %.1f px (%.1f cm), fore leg %.1f, hind leg %.1f"
		% [spec.trunk_length, spec.trunk_length / PX_PER_CM,
			spec.fore_leg_length, spec.hind_leg_length])
	for fore in [true, false]:
		var j: Carriage.Joint = car.of(fore)
		var leg: float = spec.limb_length(fore)
		var exc: float = car.fore_aft_reach(leg, j.stand, spec.stance_width)
		var sweep: float = Footwork.SWING_RATE * leg \
			* (Footwork.TWITCH_FLOOR + Footwork.TWITCH_SPAN * spec.fast_twitch) * j.gear
		print("  %s: excursion %.1f px  trigger %.1f px  clearance %.1f  sweep %.0f px/s"
			% ["fore" if fore else "hind", exc, exc * Footwork.TRIGGER,
				car.stance_clearance(leg, j.stand, spec.stance_width,
					spec.front_foot_bias if fore else spec.rear_foot_bias), sweep])
	print("  wave: %.1f px at gain %.2f  | back_sweep %.0f°  steer lead %.1f°"
		% [c.body.body_wave, car.wave_gain, rad_to_deg(c.armature.back_sweep()),
			rad_to_deg(c.travel._steer_lead(c.armature))])
	print("  move_speed %.0f px/s = %.0f cm/s;  sprint %.0f px/s = %.0f cm/s"
		% [c.body.move_speed, c.body.move_speed / PX_PER_CM,
			c.flat_out(), c.flat_out() / PX_PER_CM])


## One steady walk: cadence, stride, duty factor, wave.
func _walk(c: Creature2, throttle: float, sprint: bool) -> void:
	_calm(c)
	c.command.throttle = throttle
	c.command.sprint = sprint
	for i in 240:
		c._physics_process(TICK)
	var fw: Footwork = c.travel.footwork
	var was: Array[bool] = []
	var lift_at: Array[Vector2] = []
	var strides: Array[float] = []
	for f in fw.feet:
		was.append(f.swinging)
		lift_at.append(f.anchor)
	var lifts: int = 0
	var down_sum: float = 0.0
	var n: int = 300
	var start: Vector2 = c.centre()
	var lateral: float = 0.0
	var roll_lo: float = 0.0
	var roll_hi: float = 0.0
	var roll_sum: float = 0.0
	var com: PackedFloat32Array = PackedFloat32Array()
	var idle_ticks: int = 0
	for i in n:
		c._physics_process(TICK)
		com.append((c.armature.fore_carry + c.armature.hind_carry) * 0.5)
		if c.travel.footwork.planted() == 4:
			idle_ticks += 1
		var down: int = 0
		for j in fw.feet.size():
			var f: Footwork.Foot = fw.feet[j]
			if f.swinging and not was[j]:
				lifts += 1
				lift_at[j] = Vector2(f.lift.x, f.lift.y)
			elif not f.swinging and was[j]:
				strides.append(lift_at[j].distance_to(f.anchor))
			was[j] = f.swinging
			if not f.swinging:
				down += 1
		down_sum += float(down)
		# The wave's own displacement at mid-trunk.
		var a: Armature = c.armature
		var mid: int = a.axial[a.axial.size() / 2]
		lateral = maxf(lateral, a.wave_offset[mid].length())
		roll_lo = minf(roll_lo, c.travel.keel.roll)
		roll_hi = maxf(roll_hi, c.travel.keel.roll)
		roll_sum += c.travel.keel.roll
	var seconds: float = float(n) * TICK
	var per_foot: float = float(lifts) / 4.0 / seconds
	var stride_mean: float = 0.0
	for s in strides:
		stride_mean += s
	stride_mean /= maxf(float(strides.size()), 1.0)
	print("--- walk throttle %.2f%s ---" % [throttle, " sprint" if sprint else ""])
	print("  speed %.1f px/s (%.0f cm/s, %.2f of cruise)"
		% [c.speed, c.speed / PX_PER_CM, c.speed_norm])
	print("  cadence %.2f steps/s per foot (%.2f Hz stride), duty %.2f feet down"
		% [per_foot, per_foot, down_sum / float(n)])
	print("  stride %.1f px (%.1f cm), swing %.0f ms, wave peak %.1f px"
		% [stride_mean, stride_mean / PX_PER_CM,
			fw.feet[0].swing_time * 1000.0, lateral])
	print("  travelled %.0f px in %.1f s, heel %.2f°..%.2f° (mean %.2f°)"
		% [c.centre().distance_to(start), seconds, rad_to_deg(roll_lo),
			rad_to_deg(roll_hi), rad_to_deg(roll_sum / float(n))])
	_com_trace(com, idle_ticks, n)


## The user-visible truth of the rhythm: the carried weight's vertical trace.
## A flowing gait bobs like a sine at the step frequency; a pausing one parks
## flat between spikes, and a snapping one has cuts. Reported as the share of
## the trace's variance a single sinusoid explains (R² at the best-fit
## frequency), its amplitude, the worst one-tick jump, and how much of the
## run had every foot planted.
func _com_trace(com: PackedFloat32Array, idle_ticks: int, n: int) -> void:
	var mean: float = 0.0
	for x in com:
		mean += x
	mean /= float(n)
	var var_sum: float = 0.0
	for x in com:
		var_sum += (x - mean) * (x - mean)
	var best_r2: float = 0.0
	var best_hz: float = 0.0
	var hz: float = 0.4
	while hz <= 8.0:
		var w: float = TAU * hz * TICK
		var a_s: float = 0.0
		var a_c: float = 0.0
		for i in n:
			a_s += (com[i] - mean) * sin(w * i)
			a_c += (com[i] - mean) * cos(w * i)
		var power: float = (a_s * a_s + a_c * a_c) * 2.0 / float(n)
		var r2: float = power / maxf(var_sum, 0.0001)
		if r2 > best_r2:
			best_r2 = r2
			best_hz = hz
		hz += 0.05
	var jump: float = 0.0
	var lo: float = INF
	var hi: float = -INF
	for i in n:
		if i > 0:
			jump = maxf(jump, absf(com[i] - com[i - 1]))
		lo = minf(lo, com[i])
		hi = maxf(hi, com[i])
	print("  COM: bob %.1f px at %.1f Hz, sine R² %.2f, worst cut %.2f px/tick, all-planted %.0f%%"
		% [hi - lo, best_hz, best_r2, jump, float(idle_ticks) / float(n) * 100.0])


func _turn(c: Creature2, throttle: float) -> void:
	_calm(c)
	c.command.throttle = throttle
	for i in 90:
		c._physics_process(TICK)
	c.command.turn = 1.0
	var a: Armature = c.armature
	var lead_max: float = 0.0
	var was: float = c.heading
	var start: Vector2 = c.centre()
	for i in 120:
		c._physics_process(TICK)
		lead_max = maxf(lead_max, absf(wrapf(a.fwd[a.withers_index()].angle()
			- a.fwd[a.pelvis_index()].angle(), -PI, PI)))
	var swung: float = absf(wrapf(c.heading - was, -PI, PI))
	print("--- turn at throttle %.2f ---" % throttle)
	print("  swung %.0f° in 2 s (%.0f °/s), max back bend %.0f°, moved %.0f px"
		% [rad_to_deg(swung), rad_to_deg(swung) / 2.0, rad_to_deg(lead_max),
			c.centre().distance_to(start)])
