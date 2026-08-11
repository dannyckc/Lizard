## The feeding slice: what happens to a part of an animal after it has stopped
## being part of that animal.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/FeedingTest.gd
##
## Three claims, and the checks are weighted toward the seams between them rather
## than toward any one:
##
##   * a severed part is *anatomy lying on the ground*, not meat, and nothing
##     converts it until something bites it;
##   * jaws that close on one take it, and whether that reads as carrying it or
##     dragging it is decided by its weight and by nothing else;
##   * biting, chewing and swallowing are three readings of two numbers — where
##     the jaws have hold, and how far the piece reaches from there — so the same
##     code has to produce an Elephant bolting a foot and a Cat gnawing at a
##     thigh without being told which it is doing.
extends SceneTree

const TICK: float = 1.0 / 60.0

var failures: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	_run_checks()
	return false


func _run_checks() -> void:
	var player: Creature = main.creature
	var target: Creature = main.target_creature
	if player == null or target == null:
		_check(false, "no creatures to feed")
		_finish()
		return
	target.alive = true

	_check_a_severed_part_is_not_meat(player, target)
	_check_only_a_bite_makes_scraps(player, target)
	_check_jaws_take_what_they_close_on(player, target)
	_check_weight_decides_carry_or_drag(player, target)
	_check_bite_position_hangs_the_piece(player, target)
	_check_a_mouthful_props_the_jaws_open(player, target)
	_check_chewing_works_a_piece_in(player, target)
	_check_what_fits_goes_down(player, target)
	_check_a_swallow_passes_through_the_body(player, target)
	_check_chewing_through_leaves_two_pieces(player, target)
	_check_you_cannot_eat_yourself(player, target)

	main.queue_free()
	_finish()


# --------------------------------------------------------------- not meat ----

## The headline claim. A leg eaten off at the shoulder enters the world with every
## hit point it was standing with — skin, fat, muscle and bone, in that order, in
## the same cells — and the scrap field, which is where meat goes, gets nothing.
func _check_a_severed_part_is_not_meat(_player: Creature, target: Creature) -> void:
	_clear()
	var part: CarrionField.Part = _sever_limb(target, "RR")
	if part == null:
		_check(false, "severing a limb produced no part at all")
		return
	_check(main.scrap_field.scraps.is_empty(),
		"a severed limb produced %d scraps before anything had bitten it"
			% main.scrap_field.scraps.size())
	_check(part.cells > 4, "a severed limb arrived as only %d cells" % part.cells)
	_check(part.gone_count == 0, "a severed limb arrived with holes already in it")

	var skin: float = _layer(part, TissueGrid.SKIN)
	var muscle: float = _layer(part, TissueGrid.MUSCLE)
	var bone: float = _layer(part, TissueGrid.BONE)
	_check(skin > 0.0 and muscle > 0.0 and bone > 0.0,
		"a severed limb arrived without one of its tissues (skin %.1f muscle %.1f bone %.1f)"
			% [skin, muscle, bone])
	_check(is_equal_approx(part.condition(), 1.0),
		"a severed limb arrived already %.0f%% eaten" % ((1.0 - part.condition()) * 100.0))
	# It weighs a share of the animal it left, in the currency every other mass in
	# the simulation is quoted in — which is what makes dragging it a real question.
	_check(part.mass() > 0.0 and part.mass() < target.physique.mass,
		"a severed limb weighed %.3f against a whole animal's %.3f"
			% [part.mass(), target.physique.mass])


## ...and it stays that way. Nothing in the world converts a part into meat by
## itself: it can lie there indefinitely and it is still a leg.
func _check_only_a_bite_makes_scraps(player: Creature, target: Creature) -> void:
	_clear()
	var part: CarrionField.Part = _sever_limb(target, "RR")
	if part == null:
		return
	var whole: float = part.flesh
	for _i in 240:
		main.carrion.settle(TICK)
	_check(main.carrion.parts.has(part), "a part left alone stopped existing")
	_check(is_equal_approx(part.flesh, whole),
		"a part left alone lost %.1f tissue to nobody" % (whole - part.flesh))
	_check(main.scrap_field.scraps.is_empty(), "a part left alone turned into meat by itself")
	_check(part.settled, "a part never came to rest")

	# And now a mouth. One closing of a set of jaws is the whole difference.
	_park(target)
	_stand_over(player, part.pos)
	_strike(player, false)
	_check(part.flesh < whole,
		"biting a severed part took nothing off it (%.1f -> %.1f)" % [whole, part.flesh])
	_check(not main.scrap_field.scraps.is_empty(),
		"biting a severed part produced no meat")


# --------------------------------------------------------------- carrying ----

func _check_jaws_take_what_they_close_on(player: Creature, target: Creature) -> void:
	_clear()
	var part: CarrionField.Part = _sever_limb(target, "RR")
	if part == null:
		return
	_park(target)
	_stand_over(player, part.pos)
	_strike(player, true)

	_check(player.mouthful != null, "jaws closed on a severed part and did not take it")
	if player.mouthful == null:
		return
	_check(player.mouthful.part == part, "the jaws took hold of some other piece")
	_check(part.carrier == player, "a part in a creature's jaws did not know whose they were")
	_check(player.is_bite_latched(), "jaws holding meat did not report themselves shut")

	# Carried away, and the piece comes too. This is the whole of "to another
	# location": nothing is teleported and nothing is parented.
	var from: Vector2 = part.pos
	_walk(player, 90)
	_check(player.mouthful != null, "the piece was lost simply by walking with it")
	_check(part.pos.distance_to(from) > 40.0,
		"a carried part moved only %.1f px while the creature walked off with it"
			% part.pos.distance_to(from))
	_check(part.pos.distance_to(player.jaw_point()) < player.gape_radius() * 3.0,
		"a carried part was left %.1f px behind a mouth that was carrying it"
			% part.pos.distance_to(player.jaw_point()))

	# Letting go leaves it where it was let go of, and it settles there.
	player.set_bite_held(false)
	_walk(player, 40)
	_check(player.mouthful == null, "the jaws never opened")
	_check(part.carrier == null, "a dropped part still thought it was being carried")
	for _i in 120:
		main.carrion.settle(TICK)
	_check(part.settled, "a dropped part never came to rest")


## Carrying and dragging are the same code on the same tick. What separates them is
## the piece's weight against the creature's strength and nothing else, so making
## the identical piece heavy has to be enough to turn one into the other.
##
## Measured as how much of a displacement the jaws make up in a single tick, with
## the creature standing still — which is the mechanism with nothing else in front
## of it. A piece the animal can lift is back at its mouth at once; a piece it
## cannot is barely moved, and being barely moved every tick is what dragging is.
func _check_weight_decides_carry_or_drag(player: Creature, target: Creature) -> void:
	_clear()
	var light: CarrionField.Part = _sever_limb(target, "RR")
	if light == null:
		return
	_park(target)
	light.full_mass = 0.001
	_stand_over(player, light.pos)
	_strike(player, true)
	if player.mouthful == null:
		_check(false, "could not take hold of the light piece")
		return
	var free: float = player._haul_factor()
	var lifted: float = _closes(player)
	var carried_travel: float = _travel(player, 60)
	player.set_bite_held(false)
	_walk(player, 5)

	_clear()
	var heavy: CarrionField.Part = _sever_limb(target, "RL")
	if heavy == null:
		return
	_park(target)
	heavy.full_mass = 60.0
	_stand_over(player, heavy.pos)
	_strike(player, true)
	if player.mouthful == null:
		_check(false, "could not take hold of the heavy piece")
		return
	var loaded: float = player._haul_factor()
	var hauled: float = _closes(player)
	var dragged_travel: float = _travel(player, 60)

	_check(lifted > 0.25,
		"a weightless piece took up only %.0f%% of the slack in a tick — nothing is being carried"
			% (lifted * 100.0))
	_check(hauled < lifted * 0.35,
		"a piece 60000x heavier answered the jaws almost as readily (%.2f against %.2f)"
			% [hauled, lifted])
	# ...and the animal on the other end of it pays, in the same currency towing a
	# whole creature is paid in.
	_check(loaded < free * 0.6,
		"hauling a heavy piece cost the creature almost nothing (%.2f -> %.2f)"
			% [free, loaded])
	_check(dragged_travel < carried_travel * 0.5,
		"dragging a heavy piece (%.0f px) barely slowed a creature that carried a light one %.0f px"
			% [dragged_travel, carried_travel])
	# However overmatched, what is in the jaws is in the jaws: the tether is soft
	# up to the mouth's own reach and inextensible past it.
	_check(_lag(player) <= player.gape_radius() + CarrionField.TETHER_SLACK + 0.5,
		"a dragged piece got %.1f px away from a mouth that had hold of it" % _lag(player))
	player.set_bite_held(false)
	_walk(player, 5)


## Where the jaws closed decides how the piece hangs, because the pull on it is
## split between shifting it and turning it by the lever the hold gives — the same
## split a real rigid body makes. Nothing poses a carried limb.
func _check_bite_position_hangs_the_piece(player: Creature, target: Creature) -> void:
	_clear()
	var part: CarrionField.Part = _sever_limb(target, "RR")
	if part == null:
		return
	_park(target)
	_stand_over(player, part.pos)
	_strike(player, true)
	if player.mouthful == null:
		_check(false, "could not take hold of the piece")
		return

	# Taken by one end: the far end of it is behind the jaws, because there is
	# nothing else for it to do.
	player.mouthful.hold = _far_cell(part)
	player.mouthful.part.full_mass = 4.0
	# Long enough for the carry to settle, and it takes longer than it used to for
	# a reason that is a movement rather than a delay: a strike throws the whole
	# animal now, so the second after a bite is spent drawing the body back over
	# its own feet — see Creature.HAUL_HOME — and only after that is the creature
	# walking off with the thing in its mouth. A piece is swung into line by being
	# towed, so the towing has to have started.
	_walk(player, 240)
	var behind: Vector2 = player.spine.forwards[0]
	var tail: Vector2 = part.to_world(-player.mouthful.hold)
	var along: float = (tail - player.jaw_point()).normalized().dot(behind)
	_check(along < 0.35,
		"a piece held by one end trailed at %.2f of straight ahead rather than behind the jaws"
			% along)
	player.set_bite_held(false)
	_walk(player, 5)


# ---------------------------------------------------------------- the mouth ----

## A mouthful too big to close on holds the jaws open by exactly as much of it as
## will not go in. That is a division rather than an animation, which is why the
## same read produces a gaping mouth around a thigh and a shut one around an ankle.
func _check_a_mouthful_props_the_jaws_open(player: Creature, target: Creature) -> void:
	_clear()
	# A donor with legs long enough that one of them is unambiguously more than a
	# mouthful. Said out loud rather than inherited from whatever the habitat's
	# second body happens to be built like: what is under test is the division of
	# a piece by a gape, and a piece that only just loses to the gape it is divided
	# by tests the fixture instead.
	var leg: float = target.params.leg_length
	target.params.leg_length = leg * 1.8
	var part: CarrionField.Part = _sever_limb(target, "RR")
	target.params.leg_length = leg
	if part == null:
		return
	_park(target)
	_stand_over(player, part.pos)
	_strike(player, true)
	if player.mouthful == null:
		_check(false, "could not take hold of the piece")
		return
	_walk(player, 30)

	var gape: float = player.gape_radius()
	var big: float = player.mouth_gape()
	_check(player.mouthful.reach() > gape,
		"the test's piece (%.1f px) was not actually bigger than the mouth (%.1f px)"
			% [player.mouthful.reach(), gape])
	_check(big > 0.25,
		"a mouth with a piece too big for it in it was only %.2f open" % big)

	# The same mouth on the same piece, held somewhere that leaves almost nothing
	# sticking out of it. Nothing was told the piece got smaller.
	player.mouthful.hold = _mid_cell(part)
	_eat_to_nothing_but(player, part, 2)
	_walk(player, 30)
	if player.mouthful != null:
		_check(player.mouth_gape() < big,
			"chewing a mouthful down did not let the jaws close on it (%.2f -> %.2f)"
				% [big, player.mouth_gape()])
	player.set_bite_held(false)
	_walk(player, 5)


## Chewing works the piece in. Each closing takes what is in the jaws and re-seats
## them a step deeper, so what is left reaches less far than it did — which is what
## makes a long piece eaten end-first rather than gnawed forever at one spot.
func _check_chewing_works_a_piece_in(player: Creature, target: Creature) -> void:
	_clear()
	# The same donor the division check uses, and for the same reason said there:
	# what is under test is chewing, and chewing only happens to a piece that will
	# not go down whole. Off the habitat's own legs the piece lands within a
	# fraction of a pixel of the gape's swallow limit, so which side of it falls
	# is decided by a cell here or there rather than by anything this check is
	# about — and a run where it fits swallows the piece on the first closing and
	# reports that chewing did nothing.
	var leg: float = target.params.leg_length
	target.params.leg_length = leg * 1.8
	var part: CarrionField.Part = _sever_limb(target, "RR")
	target.params.leg_length = leg
	if part == null:
		return
	_park(target)
	_stand_over(player, part.pos)
	_strike(player, true)
	if player.mouthful == null:
		_check(false, "could not take hold of the piece")
		return
	player.mouthful.hold = _far_cell(part)
	_check(not player.mouthful.fits(player.gape_radius()),
		"the piece staged for the chewing check goes down whole (%.1f px of reach against a %.1f px throat)"
			% [player.mouthful.reach(), player.gape_radius() * Mouthful.SWALLOW_SPAN])

	var reach: float = player.mouthful.reach()
	var flesh: float = part.flesh
	var scraps: int = main.scrap_field.scraps.size()
	var chews: int = 0
	for _i in 40:
		if player.mouthful == null or player.mouthful.going_down >= 0.0:
			break
		_chew(player)
		chews += 1
	_check(chews > 0, "the jaws never closed again on what they were holding")
	_check(main.scrap_field.scraps.size() > scraps,
		"chewing a piece of meat produced no meat")
	_check(part.flesh < flesh,
		"chewing a piece took nothing off it (%.1f -> %.1f)" % [flesh, part.flesh])
	if player.mouthful != null:
		_check(player.mouthful.reach() < reach - 1.0,
			"chewing did not work the piece in — it still reaches %.1f px of the %.1f it did"
				% [player.mouthful.reach(), reach])
	player.set_bite_held(false)
	_walk(player, 5)


## What will pass the mouth goes down it, and what goes down feeds the animal by
## the tissue actually in it. The comparison is the only decision in the feature.
func _check_what_fits_goes_down(player: Creature, target: Creature) -> void:
	_clear()
	var part: CarrionField.Part = _sever_foot(target, "FL")
	if part == null:
		_check(false, "cutting through a shin produced no foot")
		return
	_park(target)
	# A big mouth on a small piece: it goes down whole, first closing, because it
	# fits. Nothing anywhere decides that a foot is a mouthful and a leg is not.
	player.params.apply_preset("Elephant")
	_stand_over(player, part.pos)
	_strike(player, true)
	if player.mouthful == null:
		_check(false, "an Elephant could not take hold of a Lizard's foot")
		player.params.apply_preset("Lizard")
		return
	_check(player.mouthful.fits(player.gape_radius()),
		"a Lizard's foot (%.1f px) did not fit an Elephant's mouth (%.1f px)"
			% [player.mouthful.reach(), player.gape_radius()])

	var fed: int = player.food_eaten
	var held: int = main.carrion.parts.size()
	_chew(player)
	_check(player.mouthful != null and player.mouthful.going_down >= 0.0,
		"a piece that fitted was chewed instead of swallowed")
	_walk(player, 60)
	_check(player.mouthful == null, "the swallow never finished")
	_check(player.food_eaten > fed,
		"swallowing a foot fed the creature nothing (%d -> %d)" % [fed, player.food_eaten])
	_check(main.carrion.parts.size() == held - 1,
		"a swallowed piece was still lying in the world")
	_check(not main.carrion.parts.has(part), "the creature swallowed the wrong piece")
	player.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	_walk(player, 2)


## A swallow is visible in the body it passes through: the throat distends around
## the piece, the swelling travels back with it, and the tissue closes again
## behind it. Written into the width profile, so the lattice, the silhouette and
## the creature's own weight all bulge together.
func _check_a_swallow_passes_through_the_body(player: Creature, target: Creature) -> void:
	_clear()
	var part: CarrionField.Part = _sever_foot(target, "FL")
	if part == null:
		return
	_park(target)
	player.params.apply_preset("Elephant")
	_stand_over(player, part.pos)
	_strike(player, true)
	if player.mouthful == null:
		player.params.apply_preset("Lizard")
		return
	var rest: float = player.body.widths[1]
	_chew(player)

	var widest: float = 0.0
	var furthest: float = 0.0
	var travelled: bool = false
	var last_at: float = -1.0
	for _i in 40:
		if player.mouthful == null:
			break
		_walk(player, 1)
		widest = maxf(widest, player.body.widths[1])
		if player.body.swallow_size > 0.0:
			if player.body.swallow_at > last_at:
				travelled = true
			last_at = player.body.swallow_at
			furthest = maxf(furthest, player.body.swallow_at)
	_walk(player, 20)

	_check(widest > rest * 1.02,
		"a mouthful going down did not distend the throat it went down (%.2f -> %.2f)"
			% [rest, widest])
	_check(travelled and furthest > 0.05,
		"the swelling never travelled back along the body (reached %.3f)" % furthest)
	_check(is_equal_approx(player.body.swallow_size, 0.0)
			and absf(player.body.widths[1] - rest) < 0.01,
		"the body stayed distended after the piece had gone down")
	player.params.apply_preset("Lizard")
	player.reset(Vector2.ZERO, 0.0)
	_walk(player, 2)


## A piece chewed through comes apart, on the same rule that made it: cells still
## joined to each other are one thing and cells that are not are another. The jaws
## keep what is in them and the rest falls where it was.
func _check_chewing_through_leaves_two_pieces(player: Creature, target: Creature) -> void:
	_clear()
	var part: CarrionField.Part = _sever_limb(target, "RR")
	if part == null:
		return
	_park(target)
	_stand_over(player, part.pos)
	_strike(player, true)
	if player.mouthful == null:
		_check(false, "could not take hold of the piece")
		return
	player.mouthful.hold = _mid_cell(part)
	var before: int = main.carrion.parts.size()

	# Chew at the middle without ever working the hold along, so what gives way is
	# the piece rather than one end of it.
	var split_off: bool = false
	for _i in 30:
		if player.mouthful == null:
			break
		var at: Vector2 = player.mouthful.hold
		_chew(player)
		if main.carrion.parts.size() > before:
			split_off = true
			break
		if player.mouthful != null:
			player.mouthful.hold = at
	_check(split_off,
		"chewing straight through the middle of a piece never divided it")
	if split_off:
		_check(player.mouthful != null and main.carrion.parts.has(player.mouthful.part),
			"the jaws lost the half they were holding when the piece came apart")
	player.set_bite_held(false)
	_walk(player, 5)


## Meat is still your own meat after it has been through two mouths. The rule that
## stops being bitten from feeding you survives a leg being severed, carried across
## the world by somebody else and chewed into scraps there.
func _check_you_cannot_eat_yourself(player: Creature, target: Creature) -> void:
	_clear()
	var part: CarrionField.Part = _sever_limb(player, "RR")
	if part == null:
		_check(false, "could not take a leg off the player")
		return
	_park(target)
	_check(part.source_id == player.get_instance_id(),
		"a severed leg did not know which animal it came off")
	_stand_over(player, part.pos)
	_strike(player, false)
	_check(not main.scrap_field.scraps.is_empty(),
		"biting the piece produced no scraps to test with")
	var mine: int = main.scrap_field.consume(part.pos, 400.0, player)
	_check(mine == 0, "a creature ate %d scraps chewed off its own severed leg" % mine)
	var theirs: int = main.scrap_field.consume(part.pos, 400.0, target)
	_check(theirs > 0, "nobody else could eat them either")
	player.anatomy.reset()
	player.reset(Vector2.ZERO, 0.0)
	_walk(player, 2)


# ----------------------------------------------------------------- helpers ----

func _clear() -> void:
	main.carrion.clear()
	main.scrap_field.clear()


## Puts a creature somewhere it cannot be part of the next test.
func _park(c: Creature) -> void:
	c.reset(Vector2(9000.0, 9000.0), 0.0)
	c._physics_process(TICK)


## Eats a limb off at the socket, through the real erosion path, and returns the
## part it became.
func _sever_limb(c: Creature, key: String) -> CarrionField.Part:
	c.alive = true
	c.anatomy.reset()
	c.reset(c.spawn_position, c.spawn_heading)
	c._physics_process(TICK)
	for row in BodyPlan.LIMB_ROWS:
		_bite_cell(c, key, row, 6.0, 8)
	c._physics_process(TICK)
	c._physics_process(TICK)
	return main.carrion.parts[-1] if not main.carrion.parts.is_empty() else null


## The same, cut through the shin instead, so what comes off is a foot — a much
## smaller piece of the same animal.
func _sever_foot(c: Creature, key: String) -> CarrionField.Part:
	c.alive = true
	c.anatomy.reset()
	c.reset(c.spawn_position, c.spawn_heading)
	c._physics_process(TICK)
	for row in BodyPlan.LIMB_ROWS:
		_bite_cell(c, key, 4 * BodyPlan.LIMB_ROWS + row, 6.0, 14)
	c._physics_process(TICK)
	c._physics_process(TICK)
	return main.carrion.parts[-1] if not main.carrion.parts.is_empty() else null


func _bite_cell(c: Creature, patch_key: String, cell: int, depth: float, times: int) -> void:
	var tissue: TissueGrid = c.anatomy.tissue
	var patch: TissueGrid.Patch = tissue.patch(patch_key)
	var shed: Array = []
	for _i in times:
		tissue.bite(BiteMark.mouthful(patch.centre_of(cell), Vector2.RIGHT, 0.8, depth), shed)


## Places a creature so that its jaws arrive on `at` at the apex of a strike.
## Converges rather than solves, because the jaw point is downstream of a spine
## solve and a lunge that have no closed form.
func _stand_over(c: Creature, at: Vector2) -> void:
	c.alive = true
	c.command = MovementInput.Command.new()
	c.reset(at, 0.0)
	c._physics_process(TICK)
	for _i in 4:
		var reach: float = c.params.bite_reach * c.size_scale
		var aim: Vector2 = c.jaw_point() + c.spine.forwards[0] * reach
		c.reset(c.head_pos + (at - aim), 0.0)
		c._physics_process(TICK)


## One strike, driven all the way through the lunge to the hit frame.
func _strike(c: Creature, hold: bool) -> void:
	c.set_bite_held(hold)
	c.request_bite(c.jaw_point())
	for _i in 24:
		c._physics_process(TICK)
		if c.mouthful != null:
			return


## One chew: the button worked while the jaws are already shut.
func _chew(c: Creature) -> void:
	c._chew_cooldown = 0.0
	c.set_bite_held(false)
	c.set_bite_held(true)
	c._physics_process(TICK)


func _walk(c: Creature, ticks: int) -> void:
	var cmd := MovementInput.Command.new()
	cmd.throttle = 1.0
	c.command = cmd
	for _i in ticks:
		c._physics_process(TICK)
		main.carrion.settle(TICK)
	c.command = MovementInput.Command.new()


## Chews until only `spare` cells of the piece are left, or the jaws lose it.
func _eat_to_nothing_but(c: Creature, part: CarrionField.Part, spare: int) -> void:
	for _i in 60:
		if c.mouthful == null or part.cells - part.gone_count <= spare:
			return
		if c.mouthful.going_down >= 0.0:
			return
		_chew(c)


## Shoves the held piece away from the jaws and reports what fraction of that the
## jaws take back in one tick, with the creature standing still.
func _closes(c: Creature) -> float:
	if c.mouthful == null:
		return 0.0
	c.command = MovementInput.Command.new()
	c.mouthful.part.pos += c.spine.forwards[0] * (c.gape_radius() * 0.5)
	var before: float = _lag(c)
	c._physics_process(TICK)
	return clampf((before - _lag(c)) / maxf(before, 0.0001), 0.0, 1.0)


## How far the creature actually gets in `ticks` at full throttle.
func _travel(c: Creature, ticks: int) -> float:
	var from: Vector2 = c.head_pos
	_walk(c, ticks)
	return from.distance_to(c.head_pos)


## How far the piece has lagged behind the jaws holding it.
func _lag(c: Creature) -> float:
	if c.mouthful == null:
		return 0.0
	return c.mouthful.part.to_world(c.mouthful.hold).distance_to(c.jaw_point())


## A cell out at one end of the piece, in its own frame.
func _far_cell(part: CarrionField.Part) -> Vector2:
	var far := Vector2.ZERO
	for cell in part.cells:
		if part.gone[cell] != 0:
			continue
		var at: Vector2 = part.local_centre_of(cell)
		if at.length() > far.length():
			far = at
	return far


## A cell near the middle of it.
func _mid_cell(part: CarrionField.Part) -> Vector2:
	var near := Vector2.ZERO
	var best: float = INF
	for cell in part.cells:
		if part.gone[cell] != 0:
			continue
		var at: Vector2 = part.local_centre_of(cell)
		if at.length() < best:
			best = at.length()
			near = at
	return near


func _layer(part: CarrionField.Part, layer: int) -> float:
	var total: float = 0.0
	for cell in part.cells:
		total += part.hp[cell * TissueGrid.LAYERS + layer]
	return total


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("FEEDING FAIL — %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("feeding OK — a severed part is anatomy until something bites it, "
			+ "and what a mouth does with one falls out of its weight and its size")
	else:
		print("FEEDING: %d failure(s)" % failures.size())
	quit(1 if failures.size() > 0 else 0)
