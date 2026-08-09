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


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true

	var hud: EvolutionHUD = main.hud
	_check(hud != null, "HUD was not created")
	_check(hud.panel != null, "tuning panel was not created")
	if hud == null or hud.panel == null:
		_finish()
		return false

	hud.set_panel_open(false)
	_check(not hud.panel.visible, "tuning button did not close the drawer")
	hud.set_panel_open(true)
	_check(hud.panel.visible, "tuning button did not reopen the drawer")

	hud.select_species("Cat")
	_check(main.creature.params.segment_count == 12, "Cat tab did not apply its preset")
	_check(main.creature.posture.kind == Posture.SEMI_UPRIGHT,
		"the Cat tab did not rebuild the creature into its own posture")
	_check(main.creature.spine.size() == 12, "species change did not rebuild the creature")

	main.creature.params.segment_count = 18
	hud.panel.refresh()
	hud.panel._on_reset_pressed()
	_check(main.creature.params.segment_count == 12, "panel reset did not restore the active species")

	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	main._unhandled_input(f1)
	_check(not hud.panel.visible, "F1 did not toggle the designed tuning drawer")

	hud.set_panel_open(true)
	_check_anatomy(hud)

	_finish()
	return false


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
	_check(not hud.panel.visible, "the tuning drawer stayed out under the specimen")
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
	_check(panel._note.text.contains(str(main.creature.anatomy.tissue.cell_count())),
		"the stage note did not count the creature's own lattice: " + panel._note.text)

	var f3 := InputEventKey.new()
	f3.keycode = KEY_F3
	f3.pressed = true
	main._unhandled_input(f3)
	_check(hud.active_view() == EvolutionHUD.VIEW_FIELD, "F3 did not toggle the view back")
	_check(hud.panel.visible, "returning to the field did not restore the tuning drawer")


## What the drawer says the animal is *made of*, and what its organs are doing.
##
## Composition is checked as a composition — the shares have to account for the
## whole body — because the failure worth catching is a panel quoting four
## unrelated percentages that happen to look plausible. And the organ rows are
## checked for what they no longer say: a healthy brain reporting "100%" was the
## reading that took up a quarter of this panel and told nobody anything.
func _check_composition(panel: AnatomyPanel, each: Creature) -> void:
	var grid: TissueGrid = each.anatomy.tissue
	var total: float = 0.0
	for layer in AnatomyPanel.COMPOSITION:
		total += grid.layer_share(layer)
	_check(is_equal_approx(total, 1.0),
		"the tissue shares did not account for the whole body: %.4f" % total)
	_check(grid.layer_share(TissueGrid.MUSCLE) > grid.layer_share(TissueGrid.SKIN),
		"the specimen read as more skin than muscle")

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
		grid.layer_left(TissueGrid.MUSCLE)), "the muscle bar was not the muscle left")

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
		print("UI interaction smoke OK — drawer, species tabs, reset and the anatomy tab are live | %s"
			% summary)
		quit(0)
	else:
		for failure in failures:
			print("UI FAIL — ", failure)
		quit(1)
