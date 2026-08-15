## Saves three-view pictures of the skeleton itself — front, side and plan —
## while the animal stands, strides and gathers. The eyeball half of the rig
## gate: full articulation has to be visible across all three axes, not just
## asserted. Must run windowed: headless renders nothing.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1440x810 --script tests/RigShot.gd
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://rig"
const WARM: int = 160

var lab: Node
var frames: int = 0
var saved: Array = []
var view: RigView


class RigView extends Node2D:
	var creature: Creature2
	var caption: String = ""

	const PANEL_W: float = 470.0
	const PANEL_H: float = 700.0
	## Fit the whole animal fore-aft; the front view can afford more.
	const SCALE: float = 2.35
	const SCALE_FRONT: float = 4.6

	func _draw() -> void:
		if creature == null:
			return
		draw_rect(Rect2(0, 0, 1440, 810), Color(0.09, 0.10, 0.12))
		var a: Armature = creature.armature
		var pel: Vector2 = a.plan(a.pelvis_index())
		var wit: Vector2 = a.plan(a.withers_index())
		var centre: Vector2 = (pel + wit) * 0.5
		var fwd2: Vector2 = (wit - pel).normalized()
		var perp2 := Vector2(-fwd2.y, fwd2.x)

		_panel(a, 10.0, "SIDE  (along +fwd, up)", centre, fwd2, perp2, 0)
		_panel(a, 20.0 + PANEL_W, "FRONT  (facing the animal, up)", centre, fwd2, perp2, 1)
		_panel(a, 30.0 + PANEL_W * 2.0, "PLAN  (top down)", centre, fwd2, perp2, 2)
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(20, 795), caption, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 20, Color(0.95, 0.95, 0.85))

	## One orthographic panel. mode 0 side, 1 front, 2 plan.
	func _panel(a: Armature, x0: float, title: String, centre: Vector2,
			fwd2: Vector2, perp2: Vector2, mode: int) -> void:
		var font: Font = ThemeDB.fallback_font
		draw_rect(Rect2(x0, 40, PANEL_W, PANEL_H), Color(0.13, 0.145, 0.17))
		draw_string(font, Vector2(x0 + 10, 66), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.85, 0.9))
		var origin := Vector2(x0 + PANEL_W * 0.5, 40.0 + PANEL_H * 0.78)
		if mode != 2:
			# The ground line.
			draw_line(Vector2(x0 + 8, origin.y), Vector2(x0 + PANEL_W - 8, origin.y),
				Color(0.35, 0.4, 0.3), 1.5)

		# Sticks, coloured by chain; the girdle-offset stick dimmed.
		for name: StringName in a.chains:
			var chain: Armature.Chain = a.chains[name]
			var tint: Color = _tint(name)
			for j in chain.sticks.size():
				var ia: int = a.stick_a[chain.sticks[j]]
				var ib: int = a.stick_b[chain.sticks[j]]
				var width: float = 2.4 if chain.limb else 2.0
				var c: Color = tint
				if chain.limb and j == 0:
					c = Color(tint, 0.35)
				draw_line(_project(a.pos[ia], origin, centre, fwd2, perp2, mode),
					_project(a.pos[ib], origin, centre, fwd2, perp2, mode), c, width)
		# The virtual scapula: girdle datum to glided socket, where they differ.
		for limb in a.limbs:
			var glide: Vector3 = a.socket_of(limb) - a.girdle_of(limb)
			if Vector2(glide.x, glide.y).length() < 0.05:
				continue
			draw_line(_project(a.girdle_of(limb), origin, centre, fwd2, perp2, mode),
				_project(a.socket_of(limb), origin, centre, fwd2, perp2, mode),
				Color(1.0, 0.8, 0.2, 0.8), 1.2)
		# Joints as explicit points.
		for i in a.pos.size():
			draw_circle(_project(a.pos[i], origin, centre, fwd2, perp2, mode),
				2.4, Color(0.95, 0.95, 0.95))

		# Interior angles for the left limbs, side panel only.
		if mode == 0:
			var y: float = 40.0 + PANEL_H - 64.0
			for limb in a.limbs:
				if limb.side > 0.0:
					continue
				var mid: float = _interior(limb, 1)
				var low: float = _interior(limb, 2)
				draw_string(font, Vector2(x0 + 10, y),
					"%s  %s %.0f°  %s %.0f°" % [limb.name,
						"elbow" if _fore(a, limb) else "stifle", mid,
						"carpus" if _fore(a, limb) else "tarsus", low],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.8, 0.7))
				y += 20.0

	func _project(p: Vector3, origin: Vector2, centre: Vector2, fwd2: Vector2,
			perp2: Vector2, mode: int) -> Vector2:
		var flat := Vector2(p.x, p.y) - centre
		match mode:
			0:
				return origin + Vector2(flat.dot(fwd2), -p.z) * SCALE
			1:
				return origin + Vector2(-flat.dot(perp2), -p.z) * SCALE_FRONT
			_:
				return origin + Vector2(flat.dot(fwd2), flat.dot(perp2)) * SCALE \
					+ Vector2(0.0, -PANEL_H * 0.28)

	func _tint(name: StringName) -> Color:
		match name:
			BodySchema.TRUNK: return Color(0.95, 0.9, 0.75)
			BodySchema.NECK: return Color(0.85, 0.75, 0.55)
			BodySchema.TAIL: return Color(0.6, 0.62, 0.68)
			&"FL": return Color(0.45, 0.75, 0.95)
			&"FR": return Color(0.25, 0.5, 0.75)
			&"HL": return Color(0.55, 0.9, 0.55)
			&"HR": return Color(0.35, 0.65, 0.35)
		return Color.WHITE

	func _fore(a: Armature, limb: Armature.Chain) -> bool:
		return limb.parent_node != a.chain(BodySchema.TRUNK).nodes[0]

	func _interior(limb: Armature.Chain, j: int) -> float:
		var incoming: Vector2 = limb.sag[j] - limb.sag[j - 1]
		var outgoing: Vector2 = limb.sag[j + 1] - limb.sag[j]
		return rad_to_deg(PI - absf(wrapf(outgoing.angle() - incoming.angle(),
			-PI, PI)))


func _initialize() -> void:
	lab = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(lab)
	view = RigView.new()
	# Screen-fixed: the lab's camera must not carry the panels away.
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	layer.add_child(view)


func _process(_delta: float) -> bool:
	frames += 1
	var creature: Creature2 = lab.creature
	if frames == 2:
		lab.terrain.clear()
		lab.set_process(false)
	if frames < 2:
		return false
	view.creature = creature

	creature.command.throttle = 1.0 if frames > WARM and frames <= WARM * 2 else 0.0
	creature.command.jump = frames > WARM * 2 + 30 and frames < WARM * 2 + 100
	view.queue_redraw()

	if frames == WARM - 10:
		view.caption = "STAND — deterministic symmetric stance, digitigrade pasterns"
	elif frames == WARM - 8:
		_shoot("stand")
	elif frames == WARM * 2 - 40:
		view.caption = "STRIDE — walking; scapular glide drawn amber where it leads/trails"
	elif frames == WARM * 2 - 38:
		_shoot("stride")
	elif frames == WARM * 2 + 95:
		view.caption = "GATHER — jump charge held; lumbar arch over pinned girdles"
	elif frames == WARM * 2 + 97:
		_shoot("gather")
	elif frames > WARM * 2 + 110:
		print("rig shots: " + " · ".join(saved))
		print("  in " + ProjectSettings.globalize_path(OUT))
		quit(0)
	return false


func _shoot(word: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [OUT, word]
	image.save_png(path)
	saved.append(word)
