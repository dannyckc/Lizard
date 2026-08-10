## Headless check that the back half of an animal is one piece of anatomy.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/HindquartersTest.gd
##
## Four systems have an opinion about where a creature's hips are, and every one
## of them used to arrive at it separately. The silhouette read a knot called
## `hip_width` at three quarters of the body; the skeleton bolted a girdle bar
## under the socket, wherever that was; the tissue lattice called a fixed block of
## columns "the pelvis"; and the tail hung off a fraction somebody chose. On the
## default Lizard those four answers spanned a third of the animal — the hind legs
## came out of its waist and the widest part of it was a fifth of a body behind
## them — and on a Cheetah the sockets landed on the *narrowest* cross-section it
## has.
##
## So this file asks the same question of each of them in turn and requires one
## answer. Then it asks what hangs off that answer, because the tail is the part
## with nothing beyond it holding it up: it has to sag under its own weight, it has
## to be limber where it is thin, and it has to follow the body round a corner and
## then stop rather than ringing.
##
## Four groups:
##
##   * **one set of hips** — the silhouette, the girdle, the region and the tail's
##     root all name the same station, on every build, and all four move when the
##     sockets move.
##   * **joined on** — the flesh at the hips is at the height the legs are holding
##     it, the sockets are inside it, and a body with no tail is still clipped
##     behind its pelvis rather than through it.
##   * **limber where it is thin** — a joint's give is read off its own section, so
##     a tail bends further than the back it hangs off and a thick-based tail bends
##     less than a whippy one. Species differences are a consequence, not a setting.
##   * **follows and settles** — resting, walking, turning, jumping and after a
##     reset: the tail trails the body, comes to rest when the body does, and never
##     stretches, coils into the animal or leaves the world.
extends SceneTree

const TICK: float = 1.0 / 60.0
## A spine station is 1/(n-1) of the body, so "within a station" is the finest
## anything addressed by fraction can be asked to agree to.
const STATION_SLACK: float = 1.5
## Below this much travel in a tick the tail tip is at rest. Well under
## perception at 60 Hz, and orders of magnitude under anything actually moving.
const STILL: float = 0.05

var failures: Array[String] = []
var notes: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var player: Creature = main.creature
	_check(player != null, "the habitat did not build a creature")
	if player == null:
		_finish()
		return false
	# Flat, empty ground and no second body. Everything below is a measurement of
	# one animal's own shape; an obstacle or a neighbour would make several of them
	# measurements of the obstacle.
	main.terrain.clear()
	main.target_creature.reset(Vector2(0.0, 9000.0), 0.0)

	_check_one_set_of_hips(player)
	_check_the_hips_move_with_the_sockets(player)
	_check_the_hips_are_joined_on(player)
	_check_a_tailless_body_keeps_its_pelvis(player)
	_check_limber_where_it_is_thin(player)
	_check_species_keep_their_own_tails(player)
	_check_the_tail_follows_and_settles(player)
	_check_every_gait_holds_together(player)
	_stand(player, "Lizard")
	_finish()
	return false


# -------------------------------------------------------- one set of hips ----

## The four answers to "where are the hips" are one answer.
##
## The silhouette's rear maximum is the one worth stating plainly, because it is
## the one a player sees: the widest part of the back half of an animal is the
## part its hind legs come out of. Everything else here is the same station
## reached through a different system.
func _check_one_set_of_hips(player: Creature) -> void:
	var readings: Array[String] = []
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_stand(player, name)
		var plan: BodyPlan = player.anatomy.plan
		var hip: float = player.params.rear_limb_t
		var last: int = mini(player.body.last_index, player.spine.size() - 1)
		var socket: int = clampi(int(round(hip * float(last))), 0, last)

		# 1. The silhouette. Searched over the whole back half rather than only
		# behind the socket, so a build whose widest rear station is *ahead* of its
		# legs fails just as loudly as one whose is behind them.
		var peak: int = socket
		for i in range(int(round(0.5 * float(last))), last + 1):
			if player.body.widths[i] > player.body.widths[peak]:
				peak = i
		_check(absf(float(peak - socket)) <= STATION_SLACK,
			"a %s's widest rear cross-section is station %d and its hind legs hang off station %d"
				% [name, peak, socket])
		# ...and nothing behind the hips is wider than the hips, which is the same
		# claim asked without a tolerance: a tail may only ever taper.
		var swollen: int = -1
		for i in range(socket + 2, last + 1):
			if player.body.widths[i] > player.body.widths[socket] + 0.01:
				swollen = i
		_check(swollen < 0,
			"a %s carries station %d behind its hips wider (%.1f px) than the hips themselves (%.1f)"
				% [name, swollen, player.body.widths[maxi(swollen, 0)],
					player.body.widths[socket]])

		# 2. The skeleton: the girdle bar is under the socket. (ArticulationTest
		# owns this as a claim about the bone; here it is one of the four answers
		# that have to agree.)
		var bar: int = int(plan.limb_socket_col["RL"])
		_check(bar == plan.torso_column(hip),
			"a %s's pelvic bar is at column %d and its hip socket at column %d"
				% [name, bar, plan.torso_column(hip)])

		# 3. The lattice: the socket is inside the block of tissue called the
		# pelvis. This is the one that used to be flatly wrong on rear-hipped
		# builds — a Kangaroo hung its hind legs off its own lumbar region.
		_check(plan.region_at(hip) == BodyPlan.PELVIS,
			"a %s's hind limbs hang off its %s, not its pelvis"
				% [name, plan.region_name(plan.region_at(hip))])

		# 4. The tail: it starts behind that block and not inside it.
		var tail: float = BodyPlan.tail_t(hip)
		_check(tail > hip,
			"a %s's tail starts at the hip socket rather than behind the pelvis" % name)
		_check(plan.region_at(tail) == BodyPlan.TAIL,
			"a %s's tail root is in its %s" % [name, plan.region_name(plan.region_at(tail))])
		readings.append("%s hip %.2f peak %.2f" % [name, hip, float(peak) / float(last)])
	notes.append("hips: " + ", ".join(readings))


## ...and all four of them move when the sockets do.
##
## The test the fixed columns could never have passed. Nothing here asserts a
## position: it moves the hind limbs and requires that the widest rear station,
## the girdle bar, the pelvic region and the root of the tail all travel with them.
func _check_the_hips_move_with_the_sockets(player: Creature) -> void:
	var seen: Array = []
	for where in [0.34, 0.62]:
		_stand(player, "Lizard")
		player.params.rear_limb_t = where
		player.rebuild()
		player.reset(Vector2.ZERO, 0.0)
		for _i in 60:
			player._physics_process(TICK)
		var plan: BodyPlan = player.anatomy.plan
		var last: int = mini(player.body.last_index, player.spine.size() - 1)
		var socket: int = clampi(int(round(where * float(last))), 0, last)
		var peak: int = socket
		for i in range(int(round(0.5 * float(last))), last + 1):
			if player.body.widths[i] > player.body.widths[peak]:
				peak = i
		_check(absf(float(peak - socket)) <= STATION_SLACK,
			"hind limbs moved to %.2f and the silhouette's hips stayed at station %d of %d"
				% [where, peak, last])
		_check(plan.region_at(where) == BodyPlan.PELVIS,
			"hind limbs moved to %.2f and the pelvic region did not follow" % where)
		_check(absf(player.droop.anchor - where) < 0.001,
			"hind limbs moved to %.2f and the tail went on hanging from %.2f"
				% [where, player.droop.anchor])
		seen.append(Vector2i(plan.pelvis_col, plan.loin_col))
	_check(seen[0] != seen[1],
		"hips a third and two thirds down the same body both put the pelvis at %s"
			% str(seen[0]))
	notes.append("moving the hips moves the pelvis %s -> %s" % [str(seen[0]), str(seen[1])])


# ---------------------------------------------------------------- joined on ----

## The flesh at the hips is where the legs are holding it, and the sockets are in
## it.
##
## ArticulationTest asks the second half of this of every build in every pose and
## owns it. What is here is the half that belongs to the hindquarters: the lattice
## station over the pelvis has to be at the height the back is being carried at —
## not sagging with the tail behind it and not riding up with the neck in front —
## because that is what makes the hip joint, the flesh around it and the drawn
## body one object.
func _check_the_hips_are_joined_on(player: Creature) -> void:
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_stand(player, name)
		var back: float = player.stature.reference + player.stature.elevation
		var hip: float = player.params.rear_limb_t
		var patch: TissueGrid.Patch = player.anatomy.tissue.patch(TissueGrid.BODY_KEY)
		var col: int = clampi(player.anatomy.plan.torso_column(hip), 0, patch.mids.size() - 1)
		_check(absf(patch.mids[col] - back) < 1.0,
			"a %s's pelvis sits at %.1f px while its legs hold its back at %.1f"
				% [name, patch.mids[col], back])
		# ...and the same station of the droop profile, which is what the lattice
		# read it from. Everything up to the hips is held; the sag starts after.
		_check(absf(player.droop.at(hip) - back) < 0.5,
			"a %s's back was already hanging at the hip socket" % name)
		_check(player.droop.at(1.0) <= player.droop.at(hip) + 0.001,
			"a %s's tail tip is carried above its own hips" % name)


## A body with no tail is clipped behind its pelvis rather than through it.
##
## The silhouette used to be cut two spine points behind the socket, which on a
## short chain is most of the pelvis: switching the tail off took the hips with it
## and left the hind legs hanging off the cut face. Now the cut is where the tail
## actually begins — see BodyPlan.tail_t, the one statement of it — so what comes
## off is the tail and the animal keeps its hindquarters.
func _check_a_tailless_body_keeps_its_pelvis(player: Creature) -> void:
	for preset in ["Lizard", "Cat", "Kangaroo"]:
		_stand(player, preset)
		var whole: float = player.physique.mass
		player.params.tail_enabled = false
		player.rebuild()
		player.reset(Vector2.ZERO, 0.0)
		for _i in 60:
			player._physics_process(TICK)
		var last: int = player.body.last_index
		var socket: float = player.params.rear_limb_t * float(player.spine.size() - 1)
		_check(float(last) > socket,
			"a tailless %s was clipped at station %d, ahead of its own hip socket at %.1f"
				% [preset, last, socket])
		_check(player.physique.mass < whole,
			"switching a %s's tail off did not make it any lighter" % preset)
		# The hind sockets are still on the body that is left.
		var anchor: Spine.Frame = player.body.anchors["RL"]
		_check(anchor.pos.distance_to(player.spine.points[clampi(int(round(socket)),
			0, last)]) < player.body.widths[clampi(int(round(socket)), 0, last)] + 0.5,
			"a tailless %s's hind socket came off the body with the tail" % preset)
		player.params.tail_enabled = true
		player.rebuild()


# ------------------------------------------------- limber where it is thin ----

## A joint's give is read off its own cross-section, so a back and the tail behind
## it are not the same beam.
##
## One `max_bend_deg` for the whole chain made an Elephant's tail exactly as rigid
## as its back — a ten-degree-a-joint plank — and gave a Lizard's whip and a
## Kangaroo's rudder the same articulation on bodies that taper nothing like each
## other. A vertebra's grip goes with the section it is cut from, which is the same
## sentence Droop says about the vertical, so the two now come out of one reading.
func _check_limber_where_it_is_thin(player: Creature) -> void:
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_stand(player, name)
		var spine: Spine = player.spine
		var limit: float = deg_to_rad(player.params.max_bend_deg)
		var n: int = spine.size()
		var tip: int = n - 2
		# Against the stoutest section this animal has rather than against its chest,
		# because which station that is is itself a species difference: a Kangaroo is
		# widest across the hips and a Lizard across the chest, and the claim being
		# made is about the tail against the sturdiest part of the same back.
		var stoutest: int = 0
		for i in n:
			if spine.section_hold[i] > spine.section_hold[stoutest]:
				stoutest = i
		_check(spine.bend_at(tip, limit) > spine.bend_at(stoutest, limit) * 1.3,
			"a %s's tail tip bends %.1f deg against %.1f at its stoutest — that is one beam"
				% [name, rad_to_deg(spine.bend_at(tip, limit)),
					rad_to_deg(spine.bend_at(stoutest, limit))])
		# Monotone from the stoutest section back: a taper cannot get stiffer as it
		# thins, whatever the profile in front of it is doing.
		var rising: int = -1
		for i in range(stoutest + 1, n):
			if spine.section_hold[i] > spine.section_hold[i - 1] + 0.001:
				rising = i
		_check(rising < 0 or rising <= int(round(player.params.rear_limb_t * float(n - 1))) + 1,
			"a %s stiffens again at station %d, behind its own hips" % [name, rising])
		# ...and the cap holds. A limber tail is still a tail, not a rope: nothing
		# may be granted more than the constant allows.
		_check(spine.bend_at(tip, limit) <= limit * Spine.LIMBER_BEND + 0.0001,
			"a %s's tail was given more bend than the limber cap allows" % name)


## And the differences between species come out of their own tails.
##
## Nothing in the presets says how stiff a tail is. A Kangaroo carries a deep tail
## whose base is nearly its hip width and a Lizard carries one that tapers from a
## narrow waist, so the first is much the stiffer at its root — and that falls out
## of `tail_tip_width` and `hip_width` alone.
func _check_species_keep_their_own_tails(player: Creature) -> void:
	var root: Dictionary = {}
	var length: Dictionary = {}
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_stand(player, name)
		var n: int = player.spine.size()
		var hip: int = clampi(int(round(player.params.rear_limb_t * float(n - 1))), 0, n - 1)
		# A third of the way down the tail, which is a station every build has.
		var at: int = clampi(hip + int(round(float(n - 1 - hip) / 3.0)), 0, n - 1)
		root[name] = player.spine.section_hold[at]
		var arc: float = 0.0
		for i in range(hip, n - 1):
			arc += player.spine.points[i].distance_to(player.spine.points[i + 1])
		length[name] = arc / maxf(player.body_length(), 0.001)
	_check(root["Kangaroo"] > root["Lizard"],
		"a Kangaroo's deep tail base (%.3f) is no stiffer than a Lizard's whippy one (%.3f)"
			% [root["Kangaroo"], root["Lizard"]])
	_check(length["Lizard"] > length["Cat"],
		"a Lizard's tail (%.2f of its body) is no longer than a Cat's (%.2f)"
			% [length["Lizard"], length["Cat"]])
	var report: Array[String] = []
	for name in root:
		report.append("%s %.2f/%.0f%%" % [name, root[name], length[name] * 100.0])
	notes.append("tail root stiffness / length: " + ", ".join(report))


# -------------------------------------------------- follows and settles ----

## The tail trails the body round a corner, and then stops.
##
## Three claims in one manoeuvre, because they are three moments of one motion:
## standing still it is not moving at all; through a hard turn it goes somewhere a
## uniformly stiff back would not have taken it; and once the body has stopped it
## keeps going for a moment and then comes to rest. A tail that failed the first
## would be jitter, one that failed the second would be welded on, and one that
## failed the third would be a spring nobody had damped.
##
## The second is measured against the track the animal's own hips laid down, and
## not against its heading or its curvature. A body driven round a tight circle
## curls along its whole length whatever it is made of, so either of those would
## read a hundred degrees with the tail welded solid. What only a trailing tail
## does is leave the line its root has already travelled: towed exactly, the tip
## rides along it; carrying momentum of its own, it swings wide of the corner. Both
## ends of that are checked, because a tail that departed by half a body length
## would not be following anything.
func _check_the_tail_follows_and_settles(player: Creature) -> void:
	for preset in ["Lizard", "Cat", "Cheetah", "Kangaroo"]:
		var run: Dictionary = _corner(player, preset)
		_check(run["idle"] < STILL,
			"a standing %s's tail tip twitched %.3f px a tick" % [preset, run["idle"]])
		_check(run["swing"] > 1.0,
			"a %s's tail held to within %.1f px of its own hips' track round a hard turn — it is welded on"
				% [preset, run["swing"]])
		_check(run["swing"] < player.body_length() * 0.5,
			"a %s's tail left the track its hips laid by %.1f px on a %.0f px body"
				% [preset, run["swing"], player.body_length()])
		_check(run["clear"] > player.body.head_radius,
			"a %s coiled its tail tip into its own head" % preset)
		_check(run["carried"] > STILL,
			"a %s's tail stopped in the same tick its body did (%.3f px)"
				% [preset, run["carried"]])
		_check(run["settled"] >= 0.0,
			"a %s's tail was still swinging four seconds after the body stopped" % preset)
		notes.append("%s tail swings %.0f px off its hips' track and settles in %.2f s"
			% [preset, run["swing"], run["settled"]])


## Stands the animal, holds it still, drives it hard round a corner and then stops
## it dead.
func _corner(player: Creature, preset: String) -> Dictionary:
	_stand(player, preset)
	var n: int = player.spine.size()
	var hip: int = clampi(int(round(player.params.rear_limb_t * float(n - 1))), 1, n - 2)
	var out := {"idle": 0.0, "curl": 0.0, "swing": 0.0, "clear": INF,
		"carried": 0.0, "settled": -1.0}
	var trail := PackedVector2Array()
	var laid: float = 0.0
	var tail_stations := PackedVector2Array()

	for _i in 90:
		var was: Vector2 = player.spine.points[n - 1]
		player._physics_process(TICK)
		out["idle"] = maxf(out["idle"], was.distance_to(player.spine.points[n - 1]))

	var turn := MovementInput.Command.new()
	turn.throttle = 1.0
	turn.turn = 1.0
	for _i in 150:
		player.command = turn
		player._physics_process(TICK)
		out["curl"] = maxf(out["curl"], _curl(player.spine, hip))
		tail_stations = player.spine.points.slice(hip)
		out["clear"] = minf(out["clear"],
			player.spine.points[n - 1].distance_to(player.spine.points[0]))
		# How far the tip is from the track its own hips have already laid down. A
		# tail that is simply towed rides along that track; one with momentum of its
		# own swings off it and cuts the corner wide. Not asked until the hips have
		# travelled a tail's length, because before that the track does not reach
		# back as far as the tip and the answer would be the tail's own length.
		var span: float = 0.0
		for i in range(1, tail_stations.size()):
			span += tail_stations[i - 1].distance_to(tail_stations[i])
		if not trail.is_empty():
			laid += trail[trail.size() - 1].distance_to(player.spine.points[hip])
		trail.append(player.spine.points[hip])
		if laid > span:
			var away: float = INF
			for at in trail:
				away = minf(away, at.distance_to(player.spine.points[n - 1]))
			out["swing"] = maxf(out["swing"], away)

	player.command = MovementInput.Command.new()
	for i in 240:
		var was: Vector2 = player.spine.points[n - 1]
		player._physics_process(TICK)
		var moved: float = was.distance_to(player.spine.points[n - 1])
		if i < 20:
			out["carried"] = maxf(out["carried"], moved)
		if moved < STILL:
			if out["settled"] < 0.0:
				out["settled"] = float(i) * TICK
		else:
			out["settled"] = -1.0
	return out


## Total turn along the tail, hip to tip, in radians. How much of itself the tail
## has bent — not where it is, so a body simply carried round a circle does not
## register.
func _curl(spine: Spine, hip: int) -> float:
	var total: float = 0.0
	for i in range(maxi(hip, 1), spine.size() - 1):
		var a: float = (spine.points[i] - spine.points[i - 1]).angle()
		var b: float = (spine.points[i + 1] - spine.points[i]).angle()
		total += absf(wrapf(b - a, -PI, PI))
	return total


## And none of it comes apart in any of the states a body is actually in.
##
## Resting, walking, turning, winding a jump, in the air, landing and then reset —
## every build in the file, with the invariants asked on every tick. What is
## checked is deliberately the boring set, because a limber tail is exactly the
## sort of change that would break one of them somewhere nobody was looking: the
## chain stays the length it is, the pelvis stays under the sockets, the axial line
## stays out of the floor, and no number ever stops being a number.
func _check_every_gait_holds_together(player: Creature) -> void:
	for preset in CreatureParams.PRESETS:
		var name: String = str(preset)
		_stand(player, preset)
		var worst_stretch: float = 0.0
		var worst_bend: float = 0.0
		var under: float = 0.0
		var nan_seen: bool = false
		var socket_gap: float = 0.0
		var airborne: bool = false
		var walk := MovementInput.Command.new()
		for tick in 600:
			# Rest, walk, turn, wind a jump, fly, land — then do it again after a
			# reset, so the state a body is put back into is under test too.
			walk.throttle = 0.0
			walk.turn = 0.0
			walk.climb = 0.0
			if tick == 300:
				player.reset(Vector2.ZERO, 0.0)
			var phase: int = tick % 300
			if phase >= 60 and phase < 140:
				walk.throttle = 1.0
			elif phase >= 140 and phase < 220:
				walk.throttle = 1.0
				walk.turn = -1.0
			elif phase >= 220 and phase < 245:
				walk.climb = 1.0
			player.command = walk
			player._physics_process(TICK)
			if player.elevation.is_airborne():
				airborne = true

			var spine: Spine = player.spine
			var rest: float = player.segment_rest()
			var limit: float = deg_to_rad(player.params.max_bend_deg)
			for i in spine.size():
				if is_nan(spine.points[i].x) or is_nan(spine.points[i].y):
					nan_seen = true
			for i in range(1, spine.size()):
				worst_stretch = maxf(worst_stretch, absf(
					spine.points[i - 1].distance_to(spine.points[i]) - rest) / rest)
			for i in range(1, spine.size() - 1):
				var a: float = (spine.points[i] - spine.points[i - 1]).angle()
				var b: float = (spine.points[i + 1] - spine.points[i]).angle()
				worst_bend = maxf(worst_bend,
					absf(wrapf(b - a, -PI, PI)) - spine.bend_at(i, limit))
			# The axial line may lie on the ground and may not go through it. The
			# flesh around it reaches below, exactly as a foot's does — this is the
			# claim about the line the tail's own solve clamps.
			for h in player.droop.heights:
				under = maxf(under, -h)
			# ...and the hind sockets stay on the flesh they hang from, in the plane.
			for key in ["RL", "RR"]:
				var frame: Spine.Frame = player.body.anchors[key]
				var station: int = clampi(int(round(player.params.rear_limb_t
					* float(spine.size() - 1))), 0, player.body.last_index)
				socket_gap = maxf(socket_gap,
					frame.pos.distance_to(spine.points[station])
						- player.body.widths[station])
		_check(not nan_seen, "a %s's spine went to NaN" % name)
		_check(worst_stretch < 0.01,
			"a %s stretched its back by %.1f%% somewhere in the run"
				% [name, worst_stretch * 100.0])
		_check(worst_bend < 0.001,
			"a %s exceeded its own per-joint bend limit by %.4f rad" % [name, worst_bend])
		_check(under < 0.001, "a %s's back hung %.2f px through the floor" % [name, under])
		_check(socket_gap <= 0.0,
			"a %s's hind socket sat %.2f px off its own flank" % [name, socket_gap])
		_check(player.alive, "a %s did not survive walking, turning and jumping" % name)
		if not airborne:
			notes.append("%s never left the ground" % name)


# ----------------------------------------------------------------- helpers ----

## A live creature of this species, standing still on flat ground and settled onto
## its own legs. Everything measured above is measured off one of these.
func _stand(c: Creature, preset: String) -> void:
	c.alive = true
	c.ragdoll = null
	c.balance.reset()
	c.params.apply_preset(preset)
	c.rebuild()
	c.anatomy.reset()
	c.reset(Vector2.ZERO, 0.0)
	c.command = MovementInput.Command.new()
	for _i in 90:
		c._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("hindquarters OK — one set of hips, and a tail that hangs off them: %s"
			% " · ".join(notes))
	else:
		print("HINDQUARTERS FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
