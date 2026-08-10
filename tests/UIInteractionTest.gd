## Focused interaction smoke test for the designed HUD.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/UIInteractionTest.gd
extends SceneTree

var failures: Array[String] = []
var main: Node
var checked: bool = false
## What the anatomy tab actually read off the creature, printed so a pass is
## evidence the panel is quoting a body rather than quietly reporting nothing.
var summary: String = "anatomy not reached"
## The same, for the creation menu: what it read off the animal it had just made.
var summary_creator: String = "creation menu not reached"


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true

	var hud: EvolutionHUD = main.hud
	_check(hud != null, "HUD was not created")
	_check(hud.creator != null, "the creature creation menu was not created")
	if hud == null or hud.creator == null:
		_finish()
		return false

	_check_creator(hud)
	hud.set_creator_open(false)
	_check_anatomy(hud)

	_finish()
	return false


## The Creature Creation menu: one page carrying the species, the parameters and
## the animal both of them describe.
##
## Checked as the *joined* thing it was made to be rather than as three widgets
## that happen to sit together — that picking a species reaches the creature, that
## moving a slider reaches the same creature, that the menu can say how far the
## two have come apart and put them back, and that the specimen on the slab is
## that creature and not a picture of one.
func _check_creator(hud: EvolutionHUD) -> void:
	var creator: CreatureCreator = hud.creator
	_check(not creator.visible, "the creation menu was open before anything asked for it")

	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	main._unhandled_input(f1)
	_check(creator.visible, "F1 did not open the creation menu")
	main._unhandled_input(f1)
	_check(not creator.visible, "F1 did not close the creation menu again")
	hud.set_creator_open(true)
	_check(creator.visible, "the creation menu would not open on request")

	# A species is a set of these sliders written down, so choosing one has to
	# arrive at the creature exactly as moving them does.
	hud.select_species("Cat")
	_check(creator.active_species() == "Cat", "the rail did not follow the species chosen")
	_check(main.creature.params.segment_count == 12, "the Cat row did not apply its preset")
	_check(main.creature.posture.kind == Posture.SEMI_UPRIGHT,
		"choosing the Cat did not rebuild the creature into its own posture")
	_check(main.creature.spine.size() == 12, "a species change did not rebuild the creature")
	_check(creator.edited_count() == 0,
		"a creature that had just been made its species read as edited")

	# One slider, through the control rather than around it. The notch under the
	# track is the species' own value, which is the whole reason the presets and
	# the sliders belong on one page.
	var track: MinimalSlider = creator._sliders["segment_count"]
	_check(is_equal_approx(track.reference, 12.0),
		"the track was not notched with the species' own value: %f" % track.reference)
	track._set_value(18.0, true)
	_check(main.creature.params.segment_count == 18, "a slider did not reach the parameters")
	_check(creator.edited_count() == 1,
		"an edited parameter was not counted against its species: %d" % creator.edited_count())
	creator.revert_to_preset()
	_check(main.creature.params.segment_count == 12,
		"reverting did not put the creature back to the species it says it is")
	_check(creator.edited_count() == 0, "a reverted creature still read as edited")

	# The parameters a body is *built* out of rather than solved with. Nothing
	# else on the page needs the animal grown again; these are useless without it,
	# and before the creation menu existed the stance slider silently did nothing.
	creator._sliders["posture"]._set_value(float(Posture.COLUMNAR), true)
	_check(main.creature.posture.kind == Posture.COLUMNAR,
		"moving the stance slider did not stand the animal up")
	var knee: float = main.creature.articulation.hind.stand_angle
	creator._sliders["hind_flex_deg"]._set_value(
		main.creature.params.hind_flex_deg + 24.0, true)
	_check(main.creature.articulation.hind.stand_angle < knee,
		"flexing the hind joint did not reach the skeleton: %f then %f"
			% [knee, main.creature.articulation.hind.stand_angle])
	creator.revert_to_preset()
	_check(main.creature.posture.kind == Posture.SEMI_UPRIGHT,
		"reverting did not put the stance back")

	# The specimen is the creature being tuned, standing in the pose it is in.
	var stage: AnatomyView = creator.view
	_check(stage.creature == main.creature,
		"the creation menu was not looking at the creature it is editing")
	stage.size = Vector2(520.0, 340.0)
	for _step in 8:
		stage._settle(1.0)
	_check(stage.fitted(), "the creation menu never framed its specimen")
	var snout: Vector2 = stage.to_panel(main.creature.body.head.pos)
	_check(Rect2(Vector2.ZERO, stage.size).has_point(snout),
		"the specimen was framed off the creation menu's stage")
	_check(snout.y < stage.to_panel(main.creature.body.tail_tip).y,
		"the creation menu did not present its specimen snout-up")

	# ...and it can be opened up on the spot, which is the point of putting it
	# here rather than making the player leave to look at the body they are making.
	var outlined: bool = stage.show_lattice
	creator._on_layer_chip_input(_click(), AnatomyPanel.ROWS.size())
	_check(stage.show_lattice != outlined, "a layer chip did not reach the specimen")
	creator._on_layer_chip_input(_click(), AnatomyPanel.ROWS.size())
	_check(stage.show_lattice == outlined, "a layer chip would not switch back on")

	# What the body reports about itself. Read off the creature rather than
	# authored here, so the failure worth catching is a tile quoting a plausible
	# constant: the Cat and the Elephant must not agree about how heavy they are.
	var light: String = creator._tiles["MASS"].text
	var stance: String = creator._tiles["STANCE"].text
	hud.select_species("Elephant")
	_check(creator._tiles["MASS"].text != light,
		"the body report gave two different animals the same mass: " + light)
	_check(creator._tiles["STANCE"].text != stance,
		"the body report gave two different animals the same stance: " + stance)
	_check(creator._tiles["BEARING"].text == "4 LEGS",
		"a quadruped was not reported as walking on four: " + creator._tiles["BEARING"].text)
	hud.select_species("T. rex")
	# Nothing anywhere says the T. rex is bipedal — its arms are simply too short
	# to reach the floor — so the menu is reading the same measurement the
	# simulation walks on.
	_check(creator._tiles["BEARING"].text == "2 LEGS",
		"an animal with arms too short to stand on was not reported as two-legged: "
			+ creator._tiles["BEARING"].text)

	hud.select_species("Lizard")
	summary_creator = "%s · mass %s · stands %s · %s · %s" % [
		creator._species_note.text, creator._tiles["MASS"].text,
		creator._tiles["STANDS"].text, creator._tiles["GAIT"].text,
		creator._tiles["TURN RATE"].text,
	]


## A plain left-click, for the chip rows that read their own input.
static func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


## The anatomy tab. Checked as a *view of a creature* rather than as a widget:
## that it comes up on the body the world handed it, that pointing it at another
## body re-points the specimen with it, and that peeling a layer changes what the
## specimen is showing rather than only what the row says.
func _check_anatomy(hud: EvolutionHUD) -> void:
	var panel: AnatomyPanel = hud.anatomy
	_check(panel != null, "anatomy panel was not created")
	if panel == null:
		return

	_check(not panel.visible, "the anatomy drawer was out while the field view was up")
	hud.set_view(EvolutionHUD.VIEW_ANATOMY)
	_check(panel.visible, "the anatomy tab did not open its drawer")
	_check(not hud.creator.visible, "the creation menu stayed out under the specimen")
	_check(panel.creature() == main.creature,
		"the anatomy tab did not open on the creature the world gave it")

	# The specimen has to be *this* creature. Framed, upright, and made of the
	# lattice the creature is standing in — not of a drawing of a lizard.
	var view: AnatomyView = panel.view
	view.creature = main.creature
	view.size = Vector2(340.0, 326.0)
	view._settle(1.0)
	_check(view.fitted(), "the anatomy view never framed the creature")
	var snout: Vector2 = view.to_panel(main.creature.body.head.pos)
	var tail: Vector2 = view.to_panel(main.creature.body.tail_tip)
	_check(snout.y < tail.y, "the specimen was not presented snout-up")
	_check(Rect2(Vector2.ZERO, view.size).has_point(snout),
		"the specimen was framed off the stage")
	# Every station of the animal is on the page, which is the whole claim the fit
	# makes and the one that silently breaks when a creature changes size.
	var contained: bool = true
	for i in range(main.creature.body.last_index + 1):
		contained = contained and Rect2(Vector2.ZERO, view.size).has_point(
			view.to_panel(main.creature.spine.points[i]))
	_check(contained, "part of the creature was framed off the stage")

	# Peeling. The mask is what the colour reading is taken through, so an ink
	# that does not move when the skin comes off is a panel drawing its own body.
	var torso: TissueGrid.Patch = main.creature.anatomy.tissue.patch(TissueGrid.BODY_KEY)
	var cell: int = (TissueGrid.HEAD_COLS + 5) * torso.rows + torso.rows / 2
	var base: int = cell * TissueGrid.LAYERS
	var capacity: float = main.creature.anatomy.tissue.fat_capacity(torso, cell)
	var skinned: Color = CreatureView.tissue_color(torso.hp, base, capacity)
	view.set_layer_shown(TissueGrid.SKIN, false)
	_check(not view.layer_shown(TissueGrid.SKIN), "the skin layer would not come off")
	var peeled: Color = CreatureView.tissue_color(torso.hp, base, capacity, view.layers)
	_check(skinned != peeled, "peeling the skin off did not reach the layer under it")
	view.set_layer_shown(TissueGrid.SKIN, true)

	# The readout names the structure actually under the pointer.
	view._pick(view.to_panel(torso.centre_of(cell)))
	_check(panel._readout.text.begins_with("THORAX"),
		"hovering the chest did not read out the thorax: " + panel._readout.text)

	_check_composition(panel, main.creature)
	_check_orbit(panel, main.creature)

	# A second specimen is a second body, not a second label — and the readouts
	# have to follow it. Bitten first, so the two bodies cannot agree by accident.
	var target: Creature = main.target_creature
	for _repeat in 8:
		target.apply_bite(BiteMark.mouthful(target.body.head.pos, Vector2.RIGHT, 12.0, 4.0))
	target.anatomy.update(target)
	panel.select_specimen(1)
	_check(panel.creature() == target,
		"picking the other specimen did not change whose anatomy is on the slab")
	panel.refresh()
	var wounded: float = panel._integrity.values[0]
	_check(panel._note.text.contains("OUT OF"),
		"the stage note did not report the holes bitten in the specimen: " + panel._note.text)
	_check(panel._status.text != "Intact",
		"a specimen with its head chewed open still read as intact")
	panel.select_specimen(0)
	panel.refresh()
	_check(not is_equal_approx(panel._integrity.values[0], wounded),
		"switching back to the unbitten specimen kept the bitten one's integrity")

	panel.refresh()
	summary = ("specimen %s · integrity %.3f · %s · %s · %s · skin %s fat %s muscle %s bone %s"
		+ " · brain %s heart %s blood %s") % [
		panel._chips[0].text, panel._integrity.values[0], panel._status.text,
		panel._note.text, panel._mass.text,
		panel._rows[0]["value"].text, panel._rows[1]["value"].text,
		panel._rows[2]["value"].text, panel._rows[3]["value"].text,
		panel._vitals[AnatomyPanel.BRAIN_VITAL]["word"].text,
		panel._vitals[AnatomyPanel.HEART_VITAL]["word"].text,
		panel._vitals[AnatomyPanel.BLOOD_VITAL]["word"].text,
	]
	_check(main.creature.anatomy.tissue.lattice != null and panel._note.text.contains(
			str(main.creature.anatomy.tissue.lattice.built_total)),
		"the stage note did not count the creature's own cell lattice: " + panel._note.text)

	var f3 := InputEventKey.new()
	f3.keycode = KEY_F3
	f3.pressed = true
	main._unhandled_input(f3)
	_check(hud.active_view() == EvolutionHUD.VIEW_FIELD, "F3 did not toggle the view back")
	_check(not panel.visible, "the anatomy drawer stayed out over the field")


## What the drawer says the animal is *made of*, and what its organs are doing.
##
## Composition is checked as a composition — the shares have to account for the
## whole body — because the failure worth catching is a panel quoting four
## unrelated percentages that happen to look plausible. And the organ rows are
## checked for what they no longer say: a healthy brain reporting "100%" was the
## reading that took up a quarter of this panel and told nobody anything.
func _check_composition(panel: AnatomyPanel, each: Creature) -> void:
	var grid: TissueGrid = each.anatomy.tissue
	var lat: AnatomyLattice = grid.lattice
	_check(lat != null and lat.count > 0, "the specimen has no cell lattice to quote")
	var total: float = 0.0
	for tissue_kind in AnatomyPanel.COMPOSITION:
		total += lat.mass_share(tissue_kind)
	_check(is_equal_approx(total, 1.0),
		"the tissue shares did not account for the whole body: %.4f" % total)
	# The flesh outnumbers the frame: however coarse the animal, its muscle is
	# laid around the skeleton in more cells than the skeleton itself.
	_check(lat.tissue_cells(AnatomyLattice.MUSCLE) > lat.tissue_cells(AnatomyLattice.BONE),
		"the specimen read as more skeleton than muscle")

	panel.refresh()
	var muscle: String = panel._rows[2]["value"].text
	_check(muscle.ends_with("%") and muscle != "100%",
		"the muscle row did not read as a share of the body: " + muscle)
	_check(panel._rows[AnatomyPanel.NERVES_ROW]["value"].text == "SOUND",
		"an unbitten creature reported cut nerves: "
			+ panel._rows[AnatomyPanel.NERVES_ROW]["value"].text)
	# Every proportion on the panel is a bar, and the bars are on the creature's
	# own numbers rather than on whatever was last set.
	_check(is_equal_approx(panel._rows[2]["meter"].values[0],
		float(lat.tissue_cells(AnatomyLattice.MUSCLE)) \
			/ maxf(float(lat.tissue_built(AnatomyLattice.MUSCLE)), 1.0)),
		"the muscle bar was not the muscle cells left standing")

	var brain: String = panel._vitals[AnatomyPanel.BRAIN_VITAL]["word"].text
	var heart: String = panel._vitals[AnatomyPanel.HEART_VITAL]["word"].text
	_check(brain == "ALERT" and heart == "STEADY",
		"a whole animal's organs did not read as working: %s / %s" % [brain, heart])
	_check(not brain.contains("%") and not heart.contains("%"),
		"an organ was still quoting a percentage: %s / %s" % [brain, heart])
	_check(is_equal_approx(panel._vitals[AnatomyPanel.HEART_VITAL]["meter"].values[0],
		each.anatomy.state.circulation), "the heart bar was not what the heart delivers")


## Turning the specimen. It is a camera and nothing else, so what is worth checking
## is that it genuinely moves the eye through the third axis — the one the lattice
## has been carrying all along — that the animal stays framed and still answers the
## pointer once it has been turned, and that turning it is a turn and not a zoom.
func _check_orbit(panel: AnatomyPanel, each: Creature) -> void:
	var view: AnatomyView = panel.view
	var grid: TissueGrid = each.anatomy.tissue
	var torso: TissueGrid.Patch = grid.patch(TissueGrid.BODY_KEY)
	var cell: int = (TissueGrid.HEAD_COLS + 5) * torso.rows + torso.rows / 2

	_check(not view.orbited(), "the specimen did not come up looking straight down")
	var flat: Vector2 = view.to_panel(each.body.head.pos)
	# A height that reads the same as the ground from overhead and cannot once the
	# eye is off it. That is the whole claim the third axis makes.
	_check(view.project(each.body.head.pos, 40.0).is_equal_approx(flat),
		"a height moved the specimen while the view was still top-down")
	_settled(view)
	var rested: float = view._scale

	view.spin = deg_to_rad(25.0)
	view.tilt = deg_to_rad(20.0)
	_check(view.orbited(), "orbiting the specimen left it flat")
	_check(is_equal_approx(view.spin, deg_to_rad(25.0))
		and is_equal_approx(view.tilt, deg_to_rad(20.0)),
		"the eye did not read back at the angles it was sent to")
	_check(absf(view.roll) < 0.001, "naming a viewpoint by its angles tipped the page over")
	_check(not view.project(each.body.head.pos, 40.0).is_equal_approx(
		view.to_panel(each.body.head.pos)),
		"the turned specimen still ignored how high the body stands")

	_settled(view)
	var stage := Rect2(Vector2.ZERO, view.size)
	var framed: bool = true
	for i in range(each.body.last_index + 1):
		framed = framed and stage.has_point(view.to_panel(each.spine.points[i]))
	_check(framed, "part of the turned specimen was framed off the stage")
	# The specimen is framed by the ball it sits in, so no angle of the eye can
	# resize it. Without this the fit reads the silhouette and every drag is a zoom.
	_check(is_equal_approx(view._scale, rested),
		"turning the specimen resized it: %f then %f" % [rested, view._scale])

	# The hit test has to follow the projection, or a turned specimen is a picture
	# with a stale grid of hotspots behind it.
	var band := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	torso.surfaces_of(cell, band)
	var top: float = (band[0].y + band[1].y + band[2].y + band[3].y) * 0.25
	view._pick(view.project(torso.centre_of(cell), top))
	_check(panel._readout.text.begins_with("THORAX"),
		"the turned specimen misread the cell under the pointer: " + panel._readout.text)

	panel.refresh()
	_check(panel._orbit.text.contains("SPIN"),
		"the stage did not report where the eye had been moved to: " + panel._orbit.text)

	_check_trackball(view)

	view.reset_orbit()
	_check(not view.orbited() and is_zero_approx(view.spin) and is_zero_approx(view.roll),
		"resetting the view did not put the eye back over the animal's back")
	_settled(view)


## The drag itself. The specimen is held inside a sphere and the pointer takes hold
## of it, so the one thing that has to be true is that the body follows the hand:
## the part of the animal that was under the cursor comes with it, the way it would
## if the sphere were a real one being turned, and it goes on turning when the drag
## runs off the edge of the ball instead of stalling against it.
func _check_trackball(view: AnatomyView) -> void:
	view.reset_orbit()
	_settled(view)
	var middle: Vector2 = view.size * 0.5
	# The near face of the sphere, as a place in the animal rather than as a place on
	# the page — so that where it lands is a question with an answer, and the answer
	# has to be wherever the pointer has taken it.
	var pole: Vector2 = _ball_point(view, Vector3(0.0, 0.0, 1.0))
	_check(pole.is_equal_approx(middle),
		"the near face of the sphere was not at the middle of the stage: %v" % pole)

	view.grab_ball(middle)
	var to: Vector2 = middle + Vector2(view.ball_radius() * 0.5, 0.0)
	view.turn_ball(to)
	_check(_ball_point(view, Vector3(0.0, 0.0, 1.0)).is_equal_approx(to),
		"the point of the sphere that was grabbed did not follow the pointer: %v for %v"
			% [_ball_point(view, Vector3(0.0, 0.0, 1.0)), to])
	_check(view.spin > 0.0, "dragging sideways did not walk the eye around the animal")

	# A pointer brought back to where it seized the ball must leave the specimen
	# exactly where it stood, or a click on the stage is a nudge.
	view.turn_ball(middle)
	_check(_ball_point(view, Vector3(0.0, 0.0, 1.0)).is_equal_approx(middle),
		"letting the pointer come back to where it grabbed did not put the specimen back")

	# Off the ball entirely. A sphere caught by its rim rolls; it does not stop.
	view.reset_orbit()
	var rim: Vector2 = middle + Vector2(view.ball_radius() * 1.6, 0.0)
	view.grab_ball(rim)
	view.turn_ball(rim + Vector2(0.0, 40.0))
	_check(absf(view.roll) > 0.01, "a drag past the edge of the ball turned nothing")


## Where a direction out of the middle of the containing sphere meets its surface,
## on the page. Asked through the same projection the specimen is drawn by, off the
## same fit, so it is the drawn ball that is being measured and not a second idea
## of one.
func _ball_point(view: AnatomyView, direction: Vector3) -> Vector2:
	var at: Vector3 = view._centre3 + direction.normalized() * view._radius
	return view.project(view._anchor + Vector2(at.x, at.y).rotated(-view._rot), at.z)


## Runs the fit out to where it has stopped moving, so a measurement of it is of
## the fit and not of the ease.
func _settled(view: AnatomyView) -> void:
	for _step in 8:
		view._settle(1.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print(("UI interaction smoke OK — the creation menu's species, sliders, revert and"
			+ " specimen are live, and so is the anatomy tab\n  creation | %s\n  anatomy  | %s")
			% [summary_creator, summary])
		quit(0)
	else:
		for failure in failures:
			print("UI FAIL — ", failure)
		quit(1)
