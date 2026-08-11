## Phase-2 gate for the v2 census — see docs/V2_DESIGN.md §11.2.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/CorpusProbe.gd
##
## Asserts what the corpus claims to be, with the claims ported from
## PlumbTest, VolumeTest and AnatomyTest rather than their constants:
##
##   * **one census** — the schema's resolution is the allocation, every
##     wedge has flesh where the knots put it, and the default build's mass,
##     centre and compartments are pinned to six decimals: the reference
##     constants every later retune re-pins against.
##   * **it is a centre of mass** — counted off the same cells the scales
##     use: a heavier tail moves it aft on a fixed ruler, a heavier skull
##     moves it fore, the dorsal muscle carries it above the chain line, and
##     a body chewed hollow through one haunch carries its weight forward and
##     to the other side the moment the cells stop weighing.
##   * **the anatomy is in the wedges** — the belly fat hangs low, the
##     epaxial ridge rides the back, the paw and the tail tip are bone and
##     skin (sheathed, not censused — no grid floor anywhere), the ribcage
##     wraps the heart and the skull wraps the brain, the throat's vessels
##     are shallow where the trunk's run deep.
##   * **the skeleton is under it** — baked node masses conserve the census
##     total, the standing armature poses its centre inside its own four
##     feet, the posed centre and the built centre agree about the animal,
##     and a wound re-bakes the weight without anyone re-carving anything.
extends SceneTree

const TICK: float = 1.0 / 60.0

## The reference constants: the compiled default cat, pinned to six decimals
## (the v1 lesson — gait tests flip on 0.3% physique drift, so the fixed
## point is asserted, not assumed). A deliberate physique retune re-pins
## these in the same commit; anything else moving them is a broken compiler.
const PINS := {
	"mass": 30523.043797,
	"com_x": 30.110855,
	"com_y": 0.000000,
	"com_z": 25.734169,
	"along": 0.485659,
	"fore_girdle": 1119.393478,
	"hind_girdle": 2242.158273,
	"epaxial": 4540.990644,
	"neck": 814.081993,
	"jaw": 395.969852,
	"trunk_girth": 7.596613,
}
## Six-decimal pins on quantities of very different magnitude: the tolerance
## is relative on the big numbers, absolute on the fractions.
const PIN_EPSILON: float = 0.000002

var failures: Array[String] = []
var notes: Array[String] = []


func _initialize() -> void:
	var spec := BodySpec.new()
	var corpus := Corpus.new()
	corpus.build(spec)

	_check_one_census(corpus)
	_check_the_fixed_point(corpus)
	_check_centre_of_mass(corpus)
	_check_anatomy_in_the_wedges(corpus)
	_check_features(corpus, spec)
	_check_wounds_move_the_weight(spec)
	_check_the_skeleton_is_under_it(spec)
	_finish()


# ------------------------------------------------------------- one census ----

func _check_one_census(c: Corpus) -> void:
	_check(c.columns == BodySchema.column_count(4),
		"the census allocated %d columns against the schema's %d"
		% [c.columns, BodySchema.column_count(4)])
	_check(c.thickness.size() == c.columns * 4 and c.hp.size() == c.columns * 4,
		"the cell arrays do not cover columns x layers")
	var whole: bool = true
	for i in c.hp.size():
		if c.hp[i] != 1.0:
			whole = false
			break
	_check(whole, "a freshly built body is already damaged somewhere")
	# Every column is a real surface: at least the skin wraps every wedge, so
	# there is no column an attack could pass through as if it were air.
	var bare: int = 0
	for chain in c.chains:
		for st in chain.stations:
			for sec in chain.sectors:
				if c.surface_radius(chain.name, st, sec) <= chain.core[st] + 0.01:
					bare += 1
	_check(bare == 0, "%d columns have no flesh over the bone at all" % bare)
	notes.append("%d columns / %d cells, every wedge sheathed"
		% [c.columns, c.columns * 4])


func _check_the_fixed_point(c: Corpus) -> void:
	var com: Vector3 = c.com()
	var parts: Dictionary = c.compartments()
	var trunk_girth: float = 0.0
	for st in c.chain(BodySchema.TRUNK).stations:
		trunk_girth += c.girth(BodySchema.TRUNK, st)
	trunk_girth /= float(c.chain(BodySchema.TRUNK).stations)
	var measured := {
		"mass": c.mass(),
		"com_x": com.x, "com_y": com.y, "com_z": com.z,
		"along": c.along(),
		"fore_girdle": parts[&"fore_girdle"], "hind_girdle": parts[&"hind_girdle"],
		"epaxial": parts[&"epaxial"], "neck": parts[&"neck"], "jaw": parts[&"jaw"],
		"trunk_girth": trunk_girth,
	}
	if PINS.is_empty():
		var lines: Array[String] = []
		for key: String in measured:
			lines.append("\t\"%s\": %.6f," % [key, measured[key]])
		failures.append("the reference constants are unpinned — pin these:\n"
			+ "\n".join(lines))
	else:
		for key: String in measured:
			var pin: float = PINS[key]
			var give: float = maxf(absf(pin) * PIN_EPSILON, 0.000002)
			if absf(measured[key] - pin) > give:
				failures.append("%s drifted off its pin: %.6f against %.6f"
					% [key, measured[key], pin])
	notes.append("default cat: mass %.1f, COM (%.2f, %.2f, %.2f), along %.3f"
		% [measured["mass"], com.x, com.y, com.z, measured["along"]])
	notes.append("compartments fore %.0f / hind %.0f / epaxial %.0f / neck %.0f / jaw %.0f"
		% [parts[&"fore_girdle"], parts[&"hind_girdle"], parts[&"epaxial"],
			parts[&"neck"], parts[&"jaw"]])
	# The gate prints the per-station girth so a silhouette retune has its
	# ruler in the transcript.
	var girths: Array[String] = []
	for st in c.chain(BodySchema.TRUNK).stations:
		girths.append("%.2f" % c.girth(BodySchema.TRUNK, st))
	print("  trunk girth by station: " + " ".join(girths))


# ------------------------------------------------- it is a centre of mass ----

func _check_centre_of_mass(c: Corpus) -> void:
	var along: float = c.along()
	_check(along > 0.0 and along < 1.0,
		"the cat's weight is not between its own girdles (%.3f)" % along)
	_check(absf(c.com().y) < 0.001,
		"a flank-symmetric build leans %.3f px to one side" % c.com().y)

	# Weighted against the chain line: the epaxial ridge and the scruff are
	# dorsal, the core rides the axis, so the weighted centre must sit above
	# the axis-only one — the same claim PlumbTest made against the spine.
	var axis_z: float = 0.0
	var total: float = 0.0
	for chain in c.chains:
		var m: Corpus.CensusChain = c.station_moments(chain.name)
		for st in chain.stations:
			axis_z += m.st_mass[st] * chain.centre[st].z
			total += m.st_mass[st]
	axis_z /= maxf(total, 0.0001)
	_check(c.com().z > axis_z + 0.01,
		"the dorsal muscle did not carry the weight above the chain line (%.3f vs %.3f)"
		% [c.com().z, axis_z])
	notes.append("dorsal tissue lifts the centre %.2f px off the chain line"
		% (c.com().z - axis_z))

	# The tail as counterweight, thickened rather than removed so the ruler
	# (the trunk between the girdles) never changes length.
	var heavy_spec := BodySpec.new()
	for layer: int in heavy_spec.tissue_knots[&"tail"]:
		for knot: Array in heavy_spec.tissue_knots[&"tail"][layer]:
			knot[1] *= 2.5
			knot[2] *= 2.5
	var heavy := Corpus.new()
	heavy.build(heavy_spec)
	_check(heavy.along() < along - 0.005,
		"a much heavier tail did not move the weight aft (%.3f -> %.3f)"
		% [along, heavy.along()])
	notes.append("a heavy tail carries the weight %.3f of the trunk aft"
		% (along - heavy.along()))

	# And the skull at the other end, on the same fixed ruler.
	var big_spec := BodySpec.new()
	big_spec.skull_radius *= 1.8
	var big := Corpus.new()
	big.build(big_spec)
	_check(big.along() > along + 0.005,
		"a much bigger skull did not move the weight fore (%.3f -> %.3f)"
		% [along, big.along()])

	# In three dimensions: inside the animal, and pulled below the line of
	# the back by the legs and the hanging tail — the term the old outline
	# reading never had.
	var stance: float = maxf(c.spec.stance_height(true), c.spec.stance_height(false))
	_check(c.com().z > 0.0 and c.com().z < stance + c.girth(BodySchema.TRUNK, 8),
		"the weight sits outside the animal's own height (%.1f px)" % c.com().z)
	var back: float = (c.spec.stance_height(true) + c.spec.stance_height(false)) * 0.5
	_check(c.com().z < back,
		"the legs and tail did not pull the weight below the back line (%.1f vs %.1f)"
		% [c.com().z, back])


# ------------------------------------------------- anatomy in the wedges ----

func _check_anatomy_in_the_wedges(c: Corpus) -> void:
	var trunk: StringName = BodySchema.TRUNK
	# The trunk is not a tube: girth varies along it.
	var least: float = INF
	var most: float = 0.0
	for st in c.chain(trunk).stations:
		var g: float = c.girth(trunk, st)
		least = minf(least, g)
		most = maxf(most, g)
	_check(most - least > 0.5,
		"the trunk's girth is flat end to end (%.2f..%.2f)" % [least, most])

	# Belly fat hangs low; the epaxial ridge rides the back. Both are the
	# ventral-offset half of the compiler doing its work.
	var belly: int = c.station_of(trunk, 0.35)
	var ventral: int = c.sector_of(trunk, PI)
	var dorsal: int = c.sector_of(trunk, 0.0)
	var fat_below: float = c.thickness[c.column(trunk, belly, ventral) * 4
		+ BodySchema.Layer.FAT]
	var fat_above: float = c.thickness[c.column(trunk, belly, dorsal) * 4
		+ BodySchema.Layer.FAT]
	_check(fat_below > fat_above * 2.0,
		"the belly pad does not hang ventral (%.2f below vs %.2f above)"
		% [fat_below, fat_above])
	var loin: int = c.station_of(trunk, 0.3)
	var muscle_up: float = c.thickness[c.column(trunk, loin, dorsal) * 4
		+ BodySchema.Layer.MUSCLE]
	var muscle_down: float = c.thickness[c.column(trunk, loin, ventral) * 4
		+ BodySchema.Layer.MUSCLE]
	_check(muscle_up > muscle_down + 0.3,
		"the epaxial ridge is not dorsal at the loin (%.2f up vs %.2f down)"
		% [muscle_up, muscle_down])

	# Thin parts are all hull, natively: the paw and the tail tip carry less
	# mover than sheath, and nothing anywhere floored a grid to get there.
	for probe: Array in [[&"FL", 5], [&"HR", 5], [BodySchema.TAIL, 7]]:
		var name: StringName = probe[0]
		var st: int = probe[1]
		var col: int = c.column(name, st, 0) * 4
		var mover: float = c.thickness[col + BodySchema.Layer.MUSCLE] \
			+ c.thickness[col + BodySchema.Layer.FAT]
		var sheath: float = c.thickness[col + BodySchema.Layer.SKIN]
		_check(mover < sheath,
			"%s's tip carries %.2f px of mover against %.2f of sheath — not a thin part"
			% [name, mover, sheath])

	# Rear-engined: the thigh columns out-muscle the shoulder's.
	var parts: Dictionary = c.compartments()
	_check(parts[&"hind_girdle"] > parts[&"fore_girdle"] * 1.2,
		"the hindquarters do not dominate (%.0f hind vs %.0f fore)"
		% [parts[&"hind_girdle"], parts[&"fore_girdle"]])
	for key: StringName in parts:
		_check(parts[key] > 0.0, "compartment %s has no muscle at all" % key)

	# Compliance is a material property read off the same wedges: the belly
	# gives, the shin does not.
	var shin: float = c.compliance(&"HL", 4, 0)
	var flank: float = c.compliance(trunk, belly, ventral)
	_check(flank > shin * 2.0,
		"a fat flank (%.3f) is no softer than a bony shin (%.3f)" % [flank, shin])
	notes.append("belly compliance %.2f against shin %.3f" % [flank, shin])


# ---------------------------------------------------------------- features ----

func _check_features(c: Corpus, spec: BodySpec) -> void:
	var chest: Array[Dictionary] = c.features_in(BodySchema.TRUNK, Vector2(0.72, 0.95))
	var names: Array = chest.map(func(f: Dictionary) -> String: return f["name"])
	for expected in ["heart", "lung_left", "lung_right"]:
		_check(expected in names, "the thoracic window is missing its %s" % expected)

	# The ribcage wraps the heart: the bone ring at the heart's stations is a
	# multiple of the waist's sheath, at the very sector the heart sits under.
	var heart_st: int = c.station_of(BodySchema.TRUNK, 0.84)
	var waist_st: int = c.station_of(BodySchema.TRUNK, 0.47)
	var ventral: int = c.sector_of(BodySchema.TRUNK, PI)
	var rib: float = c.thickness[c.column(BodySchema.TRUNK, heart_st, ventral) * 4
		+ BodySchema.Layer.BONE]
	var waist: float = c.thickness[c.column(BodySchema.TRUNK, waist_st, ventral) * 4
		+ BodySchema.Layer.BONE]
	_check(rib > waist * 1.5,
		"the ribcage does not enclose the heart (%.2f of bone vs %.2f at the waist)"
		% [rib, waist])

	# The skull wraps the brain the same way.
	var skull: float = c.thickness[c.column(BodySchema.NECK,
		c.station_of(BodySchema.NECK, 0.96), 0) * 4 + BodySchema.Layer.BONE]
	var throat: float = c.thickness[c.column(BodySchema.NECK,
		c.station_of(BodySchema.NECK, 0.5), 0) * 4 + BodySchema.Layer.BONE]
	_check(skull > throat * 2.0,
		"the skull does not protect the brain (%.2f vs %.2f of bone)" % [skull, throat])

	# Why throat bites kill, as geometry: the carotids run shallow, the aorta
	# runs deep, and the difference is in the table rather than in a rule.
	var carotid_d: float = 1.0
	var aorta_d: float = 0.0
	for f: Dictionary in spec.features:
		if f["name"] == "carotid_left":
			carotid_d = f["path"][0][2]
		elif f["name"] == "aorta":
			aorta_d = f["path"][0][2]
	_check(carotid_d < 0.5 and aorta_d > 0.7,
		"the carotid (%.2f deep) and the aorta (%.2f) are not layered for the throat bite"
		% [carotid_d, aorta_d])

	var thigh: Array[Dictionary] = c.features_in(&"HL", Vector2(0.0, 0.4))
	var thigh_names: Array = thigh.map(func(f: Dictionary) -> String: return f["name"])
	_check("femoral_left" in thigh_names and "sciatic_left" in thigh_names,
		"the inner thigh is missing its vessel or its nerve (%s)" % [thigh_names])
	notes.append("%d features authored, layered for the throat and the ribcage"
		% spec.features.size())


# ------------------------------------------------ wounds move the weight ----

func _check_wounds_move_the_weight(spec: BodySpec) -> void:
	var c := Corpus.new()
	c.build(spec)
	var mass: float = c.mass()
	var along: float = c.along()

	# One wedge first: what is hit is what is displayed, as arithmetic — the
	# surface radius drops by exactly the flesh that came away, because the
	# ring and the wound are the same cells.
	var before_r: float = c.surface_radius(BodySchema.TRUNK, 2, 2)
	var taken: float = c.gouge(BodySchema.TRUNK, 2, 2, 3.0)
	var after_r: float = c.surface_radius(BodySchema.TRUNK, 2, 2)
	_check(absf((before_r - after_r) - taken) < 0.0001,
		"a %.2f px gouge dented the surface %.2f px — the ring and the census disagree"
		% [taken, before_r - after_r])
	_check(taken > 2.9, "three px of bite took only %.2f px of flesh" % taken)

	# Then the haunch, chewed hollow down the right flank: lighter, weight
	# fore, weight to the other side — the tick the cells stop weighing.
	for st in range(0, 3):
		for sec in range(1, 4):
			c.gouge(BodySchema.TRUNK, st, sec, 8.0)
	_check(c.mass() < mass - 1.0,
		"eating the haunch did not make the body lighter (%.1f -> %.1f)"
		% [mass, c.mass()])
	_check(c.along() > along + 0.002,
		"a chewed-out haunch did not move the weight fore (%.4f -> %.4f)"
		% [along, c.along()])
	_check(c.com().y < -0.01,
		"a right-flank wound did not lean the weight left (%.3f)" % c.com().y)
	notes.append("a chewed haunch sheds %.0f mass and moves the weight %.3f fore, %.2f px across"
		% [mass - c.mass(), c.along() - along, -c.com().y])


# ------------------------------------------- the skeleton is under it ----

func _check_the_skeleton_is_under_it(spec: BodySpec) -> void:
	var armature := Armature.new()
	armature.build(spec, Vector2.ZERO, 0.0)
	var corpus := Corpus.new()
	corpus.build(spec)
	var poise := Poise.new()
	_check(poise.bake(corpus, armature), "the first bake did no work")
	_check(not poise.bake(corpus, armature),
		"an unchanged census was baked twice — the revision key is dead")

	# The bake conserves the census: the armature's nodes carry exactly the
	# mass the corpus counted, nothing invented, nothing dropped.
	var carried: float = 0.0
	for m in armature.mass:
		carried += m
	_check(absf(carried - corpus.mass()) < corpus.mass() * 0.001,
		"the baked nodes carry %.1f against the census's %.1f" % [carried, corpus.mass()])

	for _i in 90:
		armature.step(TICK)
	poise.pose(armature)
	poise.stand(armature)
	_check(poise.posed, "a standing body never posed its centre")
	_check(poise.feet == 4, "a standing cat is on %d feet" % poise.feet)
	_check(poise.clearance > 0.0,
		"the cat stands with its weight %.1f px outside its own feet" % -poise.clearance)
	_check(poise.steadiness() > 0.0 and poise.steadiness() <= 1.0,
		"steadiness came out at %.2f" % poise.steadiness())
	_check(poise.height > 0.0 and poise.height < armature.fore_stance + 10.0,
		"the posed weight hangs at %.1f px" % poise.height)
	_check(absf(poise.centre.y) < 0.5,
		"a symmetric standing cat carries its weight %.2f px off its own midline"
		% poise.centre.y)

	# The posed centre and the built centre agree about the animal: project
	# the world point back onto the pelvis-withers axis and it must land at
	# the census's own fraction.
	var pelvis: Vector3 = armature.pos[armature.pelvis_index()]
	var withers: Vector3 = armature.pos[armature.withers_index()]
	var axis := Vector2(withers.x - pelvis.x, withers.y - pelvis.y)
	var posed_along: float = (poise.centre - Vector2(pelvis.x, pelvis.y)).dot(
		axis.normalized()) / corpus.trunk_length
	_check(absf(posed_along - corpus.along()) < 0.05,
		"the posed centre and the built centre disagree (%.3f vs %.3f)"
		% [posed_along, corpus.along()])
	notes.append("stands on 4 feet, weight %.1f px up, %.1f px inside them, steadiness %.2f"
		% [poise.height, poise.clearance, poise.steadiness()])

	# A wound re-bakes the weight — no carve, no mirror, one bake: the same
	# haunch bite as above, taken standing, moves the posed centre fore and
	# across, and the armature's own nodes get lighter where the flesh left.
	var pelvis_mass: float = armature.mass[armature.pelvis_index()]
	var centre_before: Vector2 = poise.centre
	for st in range(0, 3):
		for sec in range(1, 4):
			corpus.gouge(BodySchema.TRUNK, st, sec, 8.0)
	_check(poise.bake(corpus, armature), "a wound did not invalidate the bake")
	for _i in 10:
		armature.step(TICK)
	poise.pose(armature)
	var shift: Vector2 = poise.centre - centre_before
	_check(shift.x > 0.05,
		"a chewed haunch moved the posed weight %.3f px fore — it should lead the body"
		% shift.x)
	_check(shift.y < -0.01,
		"a right-flank wound shifted the posed weight %.3f px across" % shift.y)
	_check(armature.mass[armature.pelvis_index()] < pelvis_mass - 1.0,
		"the pelvis node kept its mass through the wound (%.1f -> %.1f)"
		% [pelvis_mass, armature.mass[armature.pelvis_index()]])
	notes.append("the haunch bite re-bakes once and shifts the posed weight (%.2f, %.2f) px"
		% [shift.x, shift.y])


# ------------------------------------------------------------------ helpers ----

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("corpus OK — one census, weighed and pinned: %s" % " · ".join(notes))
	else:
		print("CORPUS FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
