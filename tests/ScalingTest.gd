## Headless check that size is biology — see Physique, Limb and TissueGrid.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/ScalingTest.gd
##
## Mass used to be a plan-view area with a density slider, limbs weighed nothing,
## and a leg's thickness was a fixed fraction of its length. This suite pins the
## replacement: a creature is a *census of cells* — the cell a fixed size on
## every animal, the count growing with the body's honest three-dimensional
## volume, each cell weighing what the tissue standing in it weighs — and the
## limbs are sized to the load that census says they carry.
##
## Five claims, each about a body rather than a control:
##
##   * **a bigger animal is more cells, not bigger ones** — scale every linear
##     dimension and the census grows with the *cube*, not the length and not
##     the footprint; widen one body part and the new cells appear in that part;
##   * **weight is tissue** — fat is real cells at fat's density, so a padded
##     animal is heavier on the same silhouette, and none of that weight is
##     muscle, so it is not stronger for it;
##   * **legs are sized to what they hold up** — a heavier body on the same
##     skeleton demands visibly thicker, broader-footed, more muscular legs,
##     a biped's unloaded arms stay slim while its hind pair thickens, and the
##     thickening is itself weight and muscle in the census;
##   * **legs are part of the animal** — longer limbs alone make it heavier,
##     because a limb is cells like everything else;
##   * **the square-cube law is emergent** — scale a build up isometrically and
##     its strength-per-weight falls by the cube root, because muscle was
##     counted as volume and spent as cross-section, not because a preset said
##     slow.
extends SceneTree

const TICK: float = 1.0 / 60.0

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
	_check(player != null, "the habitat did not build a body")
	if player == null:
		_finish()
		return false
	# Flat empty ground, nobody else nearby: every number below is a measurement
	# of one standing body.
	main.terrain.clear()
	main.target_creature.reset(Vector2(0.0, 9000.0), 0.0)

	_check_more_cells_not_bigger_ones(player)
	_check_a_part_grows_its_own_cells(player)
	_check_weight_is_tissue(player)
	_check_legs_are_sized_to_their_load(player)
	_check_a_biped_thickens_only_what_bears(player)
	_check_limbs_are_weight(player)
	_check_square_cube_is_emergent(player)
	_finish()
	return false


# ------------------------------------------------------------------ growth ----

## Scaling every linear dimension by k multiplies the census by about k³ — the
## cell stayed the same size, so there have to be k³ times as many. Slightly
## *over* k³ is legitimate and checked for separately: the scaled-up body is
## heavier than its muscle is stronger, so its legs must thicken beyond isometry
## to carry it, which is Galileo's argument and the whole reason the elephant leg
## is not a scaled lizard leg.
func _check_more_cells_not_bigger_ones(player: Creature) -> void:
	_apply_default(player)
	var cells_before: float = player.physique.cells
	var mass_before: float = player.physique.mass
	_check(absf(mass_before - 1.0) < 0.05,
		"the reference build no longer weighs 1.0 (%.3f)" % mass_before)
	var total: float = 0.0
	for region in BodyPlan.REGIONS:
		total += player.physique.cells_of(region)
	_check(absf(total - cells_before) < cells_before * 0.01,
		"the region censuses do not add up to the animal")

	const K: float = 1.5
	_apply_default(player, func(p: CreatureParams) -> void:
		p.segment_length *= K
		p.body_width *= K
		p.arm_length *= K
		p.leg_length *= K)
	var grown: float = player.physique.cells / maxf(cells_before, 0.0001)
	var cube: float = K * K * K
	_check(grown > cube * 0.9 and grown < cube * 1.35,
		"scaling lengths by %.1f grew the census %.2fx, not ~%.2fx — cells scaled instead of multiplying"
			% [K, grown, cube])
	_check(player.physique.mass > mass_before * cube * 0.9,
		"mass grew with something weaker than the volume (%.2fx for %.2fx of body)"
			% [player.physique.mass / mass_before, cube])
	notes.append("%.1fx of animal is %.2fx of cells" % [K, grown])


## Widening the chest puts the new cells in the chest. The spline eases the new
## width into its neighbours, so the claim is about where the growth lands, not
## that it lands nowhere else — but a tail knot nobody touched must stay a tail.
func _check_a_part_grows_its_own_cells(player: Creature) -> void:
	_apply_default(player)
	var thorax_before: float = player.physique.cells_of(BodyPlan.THORAX)
	var tail_before: float = player.physique.cells_of(BodyPlan.TAIL)
	_apply_default(player, func(p: CreatureParams) -> void:
		p.chest_width *= 1.8)
	_check(player.physique.cells_of(BodyPlan.THORAX) > thorax_before * 1.5,
		"widening the chest by 1.8 did not grow the thorax census (%.0f -> %.0f)"
			% [thorax_before, player.physique.cells_of(BodyPlan.THORAX)])
	_check(absf(player.physique.cells_of(BodyPlan.TAIL) - tail_before) < tail_before * 0.3,
		"widening the chest rebuilt the tail")


# ------------------------------------------------------------------ tissue ----

## Fat is cells, so a padded build outweighs a lean one on the same silhouette —
## and none of those cells are muscle, so the strength stays put and the animal
## is slower per kilo for carrying them. That pair is the whole difference
## between growing and merely fattening.
func _check_weight_is_tissue(player: Creature) -> void:
	_apply_default(player, func(p: CreatureParams) -> void:
		p.fat_reserve = 0.0)
	var lean_mass: float = player.physique.mass
	var lean_strength: float = player.physique.strength
	_apply_default(player, func(p: CreatureParams) -> void:
		p.fat_reserve = 3.0)
	_check(player.physique.mass > lean_mass * 1.08,
		"three reserves of fat weighed nothing (%.3f -> %.3f)"
			% [lean_mass, player.physique.mass])
	_check(absf(player.physique.strength - lean_strength) < lean_strength * 0.05,
		"fat came out as muscle: strength moved %.3f -> %.3f"
			% [lean_strength, player.physique.strength])
	_check(player.locomotion.power < lean_strength / lean_mass,
		"a fattened animal kept its power-to-weight")
	notes.append("fat weighs %.0f%% and pulls nothing"
		% ((player.physique.mass / lean_mass - 1.0) * 100.0))


# -------------------------------------------------------------------- legs ----

## A heavier body on the same bones demands thicker legs and more leg — the
## girth is not a fraction of the length any more, it is asked of the load. And
## the thickening is itself tissue: the leg's own census grows, most of it
## muscle, which is where "a heavier body needs more muscle" stops being a
## sentence and becomes arithmetic.
func _check_legs_are_sized_to_their_load(player: Creature) -> void:
	_apply_default(player)
	var limb: Limb = _limb_of(player, Limb.REAR)
	var girth_before: float = limb.girth(player.size_scale)
	var leg_cells_before: float = player.physique.cells_of(BodyPlan.RL)
	_apply_default(player, func(p: CreatureParams) -> void:
		p.density = 3.0)
	limb = _limb_of(player, Limb.REAR)
	var girth_after: float = limb.girth(player.size_scale)
	_check(girth_after > girth_before * 1.4,
		"a body three times as dense stands on the same legs (girth %.1f -> %.1f)"
			% [girth_before, girth_after])
	_check(player.physique.cells_of(BodyPlan.RL) > leg_cells_before * 1.5,
		"the thicker leg was not more cells (%.0f -> %.0f)"
			% [leg_cells_before, player.physique.cells_of(BodyPlan.RL)])
	notes.append("3x the weight thickens a leg %.1fx" % (girth_after / girth_before))


## A biped's whole weight goes through its hind pair, so those thicken while the
## arms — which hold up nothing — stay built to their own length. Nothing states
## it: the load split follows from which limbs bear, and the girth follows from
## the load.
func _check_a_biped_thickens_only_what_bears(player: Creature) -> void:
	_apply_preset(player, "T. rex")
	var fore: Limb = _limb_of(player, Limb.FRONT)
	var hind: Limb = _limb_of(player, Limb.REAR)
	_check(player.physique.limb_load.x == 0.0 and player.physique.limb_load.y > 0.0,
		"a biped's arms are carrying the body")
	_check(hind.girth(player.size_scale) > fore.girth(player.size_scale) * 2.0,
		"the hind pair carrying everything is not markedly thicker than the arms carrying nothing")
	# The hind girth is the load term in charge, well clear of the slenderness
	# floor a bone of that length would be built to if nothing stood on it.
	_check(hind.girth(player.size_scale) > hind.anatomical_length * Limb.GIRTH_ASPECT * 1.2,
		"a heavy biped's leg is no thicker than an unloaded bone of its length")


## Limbs are cells, so lengthening them alone makes the animal heavier — the
## trunk untouched.
func _check_limbs_are_weight(player: Creature) -> void:
	_apply_default(player)
	var mass_before: float = player.physique.mass
	var limb_cells_before: float = player.physique.cells_of(BodyPlan.RL)
	_apply_default(player, func(p: CreatureParams) -> void:
		p.arm_length *= 1.6
		p.leg_length *= 1.6)
	_check(player.physique.mass > mass_before * 1.02,
		"longer limbs weighed nothing (%.3f -> %.3f)" % [mass_before, player.physique.mass])
	_check(player.physique.cells_of(BodyPlan.RL) > limb_cells_before * 1.3,
		"a longer leg did not census as more leg")


# ------------------------------------------------------------- square-cube ----

## Scale a build isometrically and its power-to-weight falls close to the cube
## root of the growth: muscle was counted with the volume and spent as a
## cross-section, so the ratio comes out of the counting with nothing tuned.
func _check_square_cube_is_emergent(player: Creature) -> void:
	_apply_default(player)
	var power_small: float = player.locomotion.power
	const K: float = 1.5
	_apply_default(player, func(p: CreatureParams) -> void:
		p.segment_length *= K
		p.body_width *= K
		p.arm_length *= K
		p.leg_length *= K)
	var ratio: float = player.locomotion.power / maxf(power_small, 0.0001)
	# Isometry says (k³)^(-1/3) = 1/k ≈ 0.67. The legs thickening past isometry
	# to carry the growth claws a little of it back, so the honest band sits
	# around that figure rather than exactly on it.
	_check(ratio < 0.9,
		"a creature %.1fx the size kept its power-to-weight (x%.2f)" % [K, ratio])
	_check(ratio > 0.5,
		"scaling up crushed the power-to-weight far past the square-cube law (x%.2f)" % ratio)
	notes.append("%.1fx of animal keeps %.0f%% of its power" % [K, ratio * 100.0])


# ----------------------------------------------------------------- fixture ----

func _limb_of(player: Creature, pair: int) -> Limb:
	for limb in player.gait.limbs:
		if limb.pair == pair:
			return limb
	return null


func _apply_preset(creature: Creature, preset: String) -> void:
	creature.params.apply_preset(preset)
	creature.command = MovementInput.Command.new()
	creature.reset(Vector2.ZERO, 0.0)
	for _t in 30:
		creature._physics_process(TICK)


## The default build with one deliberate change, settled long enough for the
## physique to be a reading of a standing body.
func _apply_default(creature: Creature, tweak: Callable = Callable()) -> void:
	creature.params.apply_preset("Lizard")
	if tweak.is_valid():
		tweak.call(creature.params)
	creature.command = MovementInput.Command.new()
	creature.reset(Vector2.ZERO, 0.0)
	for _t in 30:
		creature._physics_process(TICK)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("scaling OK — a body is a census of cells: %s" % " · ".join(notes))
		quit(0)
	else:
		for failure in failures:
			print("SCALING FAIL — ", failure)
		quit(1)
