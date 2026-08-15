## Phase-4 gate for the v2 skin — see docs/V2_DESIGN.md §11.2.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/SkinProbe.gd
##
## Asserts what the ring skin claims to be. The claims are ported from
## SpecimenTest and the v1 silhouette work rather than their constants:
##
##   * **the skin is the census** — every station of every chain is drawn, the
##     sampler is exact where the census is authoritative, and the radius a view
##     reads is `Corpus.surface_radius` and nothing else;
##   * **a wound is a dent** — flesh taken off a wedge is flesh gone off the
##     drawn ring, to the last decimal, on the tick it is taken and with no
##     rebuild of anything: what is hit is what is displayed;
##   * **posing never carves** — a posed animal moves no cell and re-reads no
##     radius, and every ring stays on the bone it was hung from. Weaker than it
##     was while the movers are out for rewrite: the body is standing through
##     those ticks rather than travelling — see `_tick`;
##   * **the peel is one sum** — bone, +muscle, +fat, +skin are four evaluations
##     of the same radius, in radial order, the last of them the surface;
##   * **the silhouette is the animal's** — the stance the legs deliver and the
##     proportions of the body, against the Gait HUD mock's Cat block (the
##     design spec) and v1's Cat preset (the running oracle);
##   * **cost is rings, not volume** — the mesh is a fixed count of facets
##     whatever the pose and whatever has been bitten out of it, and the tick
##     cost is measured rather than asserted.
extends SceneTree

const TICK: float = 1.0 / 60.0

## The Cat row of "Evolution Game UI Design-7/Gait HUD.dc.html", as proportions
## of its own girdle gap — the spec the silhouette is checked against. Taken
## from the mock's `geo` block: gap 78, shH 50, hipH 53, depth 30, headR 8.5.
## Proportions rather than pixels, because the mock is drawn at its own scale.
const MOCK := {
	"shoulder": 50.0 / 78.0,
	"hip": 53.0 / 78.0,
	"depth": 30.0 / 78.0,
	"head": 2.0 * 8.5 / 78.0,
}
## The same measurements off v1's Cat preset, which is the oracle that actually
## runs: gap 55.4, shoulder 34.1, hip 35.8, hip half-width 13.1, head r 11.5.
const ORACLE := {
	"shoulder": 34.1 / 55.4,
	"hip": 35.8 / 55.4,
	"depth": 2.0 * 13.1 / 55.4,
	"head": 2.0 * 11.5 / 55.4,
}
## How far a proportion may sit outside the band the two references make before
## it is a different animal. They disagree with each other by a third on the
## girth, so the claim is "inside the band, or close to it" rather than a number.
const SILHOUETTE_SLACK: float = 0.15

var failures: Array[String] = []
var notes: Array[String] = []
var main: Node
var checked: bool = false


func _initialize() -> void:
	main = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	if checked:
		return false
	checked = true
	var creature: Creature2 = main.creature
	_check(creature != null, "the lab did not build a creature")
	if creature == null:
		_finish()
		return false
	main.terrain.clear()

	_check_the_skin_is_the_census(creature)
	_check_the_peel_is_one_sum(creature)
	_check_posing_never_carves(creature)
	_check_the_silhouette(creature)
	_check_a_wound_is_a_dent(creature)
	_check_cost_is_rings(creature)
	_finish()
	return false


# ------------------------------------------------------- the skin is the census ----

func _check_the_skin_is_the_census(c: Creature2) -> void:
	var skin: Contour = c.contour
	_check(skin.rings > 0 and skin.facet_count() > 0, "the animal has no skin")
	_check(skin.bands.size() == c.corpus.chains.size(),
		"%d bands over %d census chains" % [skin.bands.size(), c.corpus.chains.size()])

	# Every station of the census is under some ring. A station nothing draws is
	# flesh that can be bitten and never seen to have been.
	var missed: int = 0
	for band in skin.bands:
		var seen := PackedByteArray()
		seen.resize(band.stations)
		seen.fill(0)
		for r in range(band.first, band.first + band.count):
			seen[skin.ring_station[r]] = 1
		for st in band.stations:
			if seen[st] == 0:
				missed += 1
	_check(missed == 0, "%d census stations are drawn by no ring at all" % missed)

	# The sampler is exact where the census is authoritative: at a station's own
	# centre the interpolated radius is that station's radius, not near it.
	var worst: float = 0.0
	for band in skin.bands:
		for st in band.stations:
			var t: float = (float(st) + 0.5) / float(band.stations)
			for sec in band.sectors:
				worst = maxf(worst, absf(skin.radius_at(band.name, t, sec)
					- c.corpus.surface_radius(band.name, st, sec)))
	_check(worst < 0.000001,
		"the ring sampler disagrees with the census by %.6f px at a station centre"
		% worst)

	# ...and the drawn surface is that radius about the ring's own centre.
	var off: float = 0.0
	for r in skin.rings:
		var band: Contour.Band = skin.bands[skin.ring_band[r]]
		for sec in band.sectors:
			var v: int = skin.ring_base[r] + sec
			off = maxf(off, absf(skin.surface[v].distance_to(skin.ring_centre[r])
				- skin.radius[v]))
	_check(off < 0.0005, "a drawn surface point sits %.5f px off its own radius" % off)
	notes.append("%d rings / %d facets cover %d census columns"
		% [skin.rings, skin.facet_count(), c.corpus.columns])


func _check_the_peel_is_one_sum(c: Creature2) -> void:
	var skin: Contour = c.contour
	var wrong: int = 0
	var surface_off: float = 0.0
	for band in skin.bands:
		for st in band.stations:
			for sec in band.sectors:
				var last: float = 0.0
				for layers in range(1, 5):
					var r: float = c.corpus.layer_radius(band.name, st, sec, layers)
					if r < last - 0.000001:
						wrong += 1
					last = r
				surface_off = maxf(surface_off, absf(last
					- c.corpus.surface_radius(band.name, st, sec)))
	_check(wrong == 0, "%d peels take the body outward as a layer is lifted off" % wrong)
	_check(surface_off < 0.000001,
		"the fourth peel and the surface disagree by %.6f px" % surface_off)

	# ...and the drawn peel is the same thing in the world: four points on one
	# ray out of the ring's centre, in radial order, the last of them the
	# surface the animal is drawn at. No second geometry under the skin.
	var out_of_order: int = 0
	var apart: float = 0.0
	for r in skin.rings:
		var band: Contour.Band = skin.bands[skin.ring_band[r]]
		for sec in band.sectors:
			var last_out: float = -1.0
			for layers in range(1, 5):
				var at: Vector3 = skin.peel(r, sec, layers)
				var depth: float = at.distance_to(skin.ring_centre[r])
				if depth < last_out - 0.000001:
					out_of_order += 1
				last_out = depth
			apart = maxf(apart, skin.peel(r, sec, 4).distance_to(
				skin.surface[skin.ring_base[r] + sec]))
	_check(out_of_order == 0,
		"%d drawn peels come out further than the layer over them" % out_of_order)
	_check(apart < 0.0005,
		"the peeled surface and the drawn surface are %.5f px apart" % apart)


# ------------------------------------------------------ posing never carves ----

func _check_posing_never_carves(c: Creature2) -> void:
	var skin: Contour = c.contour
	_tick(c, 0.0, false, 60)
	var revision: int = c.corpus.revision
	var read: int = skin._radius_rev
	var facets: int = skin.facet_count()
	_tick(c, 1.0, true, 300)
	_check(c.corpus.revision == revision,
		"300 ticks moved the census %d times" % (c.corpus.revision - revision))
	_check(skin._radius_rev == read, "300 ticks made the skin re-read the census")
	_check(skin.facet_count() == facets, "300 ticks changed the mesh")

	# Every ring is still on the bone it was hung from, and none of it is NaN.
	var adrift: float = 0.0
	var wild: int = 0
	for r in skin.rings:
		var a: Vector3 = c.armature.pos[skin.ring_a[r]]
		var b: Vector3 = c.armature.pos[skin.ring_b[r]]
		var at: Vector3 = skin.ring_centre[r]
		if not is_finite(at.x) or not is_finite(at.y) or not is_finite(at.z):
			wild += 1
			continue
		adrift = maxf(adrift, _distance_to_segment(at, a, b))
	_check(wild == 0, "%d rings came out of the pose as nothing at all" % wild)
	# The axial rings are splined through their stations, so a ring is allowed to
	# stand off the straight line between two nodes — by the sagitta of the bend
	# it is smoothing, and not by more.
	_check(adrift < 2.0, "a ring hangs %.2f px off its own stick" % adrift)
	notes.append("300 standing ticks: census untouched, no ring more than %.2f px off its stick"
		% adrift)


# ------------------------------------------------------------- the silhouette ----

func _check_the_silhouette(c: Creature2) -> void:
	_tick(c, 0.0, false, 120)
	var skin: Contour = c.contour
	var trunk: Contour.Band = skin.band(BodySchema.TRUNK)
	var neck: Contour.Band = skin.band(BodySchema.NECK)

	# The ruler is the girdle gap — the one length on a quadruped both references
	# quote everything else against.
	var fore: Vector3 = c.armature.pos[c.armature.chain(BodySchema.TRUNK).nodes[
		c.armature.chain(BodySchema.TRUNK).nodes.size() - 2]]
	var hind: Vector3 = c.armature.pos[c.armature.pelvis_index()]
	var gap: float = Vector2(fore.x - hind.x, fore.y - hind.y).length()

	var mid: int = trunk.first + int(float(trunk.count) * 0.5)
	var depth: float = 2.0 * skin.mean_radius(mid)
	var width: float = skin.radius[skin.ring_base[mid] + trunk.right] \
		+ skin.radius[skin.ring_base[mid] + trunk.left]
	var head: float = 2.0 * skin.mean_radius(neck.first + neck.count - 1)
	var measured := {
		"shoulder": c.armature.fore_carry / gap,
		"hip": c.armature.hind_carry / gap,
		"depth": depth / gap,
		"head": head / gap,
	}
	for key: String in measured:
		var lo: float = minf(MOCK[key], ORACLE[key]) - SILHOUETTE_SLACK
		var hi: float = maxf(MOCK[key], ORACLE[key]) + SILHOUETTE_SLACK
		_check(measured[key] >= lo and measured[key] <= hi,
			"%s is %.3f of the girdle gap, outside the %.3f..%.3f the mock and v1 make"
			% [key, measured[key], lo, hi])
	notes.append("silhouette per girdle gap %.1f px: shoulder %.2f hip %.2f girth %.2f head %.2f (mock %.2f/%.2f/%.2f/%.2f · v1 %.2f/%.2f/%.2f/%.2f)"
		% [gap, measured["shoulder"], measured["hip"], measured["depth"], measured["head"],
			MOCK["shoulder"], MOCK["hip"], MOCK["depth"], MOCK["head"],
			ORACLE["shoulder"], ORACLE["hip"], ORACLE["depth"], ORACLE["head"]])
	notes.append("body %.1f px nose to tail, %.1f px across the trunk, %.1f deep"
		% [_body_span(c), width, depth])


# --------------------------------------------------------- a wound is a dent ----

func _check_a_wound_is_a_dent(c: Creature2) -> void:
	var skin: Contour = c.contour
	var corpus: Corpus = c.corpus
	var trunk: Contour.Band = skin.band(BodySchema.TRUNK)
	# A swath of one flank, wide enough that the ring in the middle of it reads
	# nothing but chewed stations — the interpolation is honest, so a one-station
	# bite would smear across half a station either side of itself.
	var sector: int = trunk.right
	var mid: int = trunk.first + int(float(trunk.count) * 0.5)
	var station: int = skin.ring_station[mid]
	var before: float = skin.radius[skin.ring_base[mid] + sector]
	var facets: int = skin.facet_count()
	var rings: int = skin.rings

	# Deep enough to be through the skin and the fat and into the meat, which is
	# what the ink claim below is about.
	var taken: float = 0.0
	for st in range(station - 2, station + 3):
		taken = corpus.gouge(BodySchema.TRUNK, st, sector, 3.5)
	skin.refresh()
	var after: float = skin.radius[skin.ring_base[mid] + sector]
	_check(taken > 0.0, "the bite took no flesh at all")
	_check(absf((before - after) - taken) < 0.000001,
		"the ring lost %.6f px where the bite took %.6f" % [before - after, taken])
	_check(skin.facet_count() == facets and skin.rings == rings,
		"a bite rebuilt the mesh")

	# ...and the picture agrees: the wedge is drawn as whatever is on top of it
	# now, which after skin and fat have gone is meat.
	var likeness: Likeness = main.get_node("Creature2/Likeness")
	var column: int = corpus.column(BodySchema.TRUNK, station, sector)
	var ink: Color = likeness._ink(column)
	var layer: int = _top_layer(corpus, column)
	_check(layer == BodySchema.Layer.MUSCLE,
		"the bitten wedge is showing layer %d, not muscle" % layer)
	_check(ink.is_equal_approx(Likeness.MUSCLE)
		or ink.is_equal_approx(Likeness.MUSCLE.lerp(Likeness.MUSCLE_DEEP,
			1.0 / float(Likeness.WEAR - 1))),
		"a wedge bitten to the meat is drawn %s" % ink.to_html(false))

	# The census is the only thing that moved: one revision per bite, and the
	# mesh it feeds is the same mesh.
	c._physics_process(TICK)
	_check(skin._radius_rev == corpus.revision,
		"the skin is drawing a census revision it has not read")
	notes.append("a %.2f px bite dents the drawn ring by %.2f px and shows meat"
		% [taken, before - after])


func _check_cost_is_rings(c: Creature2) -> void:
	var skin: Contour = c.contour
	# Manual ticks, the PerfProbe lesson: timing a physics callback measures the
	# 60 Hz interval rather than the work.
	var runs: int = 400
	var started: int = Time.get_ticks_usec()
	for _i in runs:
		skin.pose()
	var posed: float = float(Time.get_ticks_usec() - started) / float(runs)

	# Chew a good deal off the animal; the mesh is the same mesh and costs the
	# same, because cells were never what it was made of.
	var facets: int = skin.facet_count()
	for st in range(0, 8):
		for sec in range(0, 5):
			c.corpus.gouge(BodySchema.TRUNK, st, sec, 12.0)
	skin.refresh()
	started = Time.get_ticks_usec()
	for _i in runs:
		skin.pose()
	var chewed: float = float(Time.get_ticks_usec() - started) / float(runs)
	_check(skin.facet_count() == facets,
		"a chewed animal draws %d facets against %d" % [skin.facet_count(), facets])
	_check(chewed < posed * 1.5 + 20.0,
		"posing a chewed animal costs %.0f us against %.0f whole" % [chewed, posed])
	notes.append("pose %.0f us a tick whole, %.0f chewed, for %d facets that never move"
		% [posed, chewed, facets])


# ------------------------------------------------------------------ helpers ----

## Runs the body for `ticks` with that much being asked of it.
##
## The ask is recorded and, with the movers taken out to be rewritten, read by
## nothing — so these are *standing* ticks, and the claims below are weaker than
## they were by exactly that much: they still prove a posed tick carves nothing and
## leaves every ring on its bone, but they no longer prove it over a body that is
## travelling. Re-strengthened when the locomotion lands.
func _tick(c: Creature2, throttle: float, sprint: bool, ticks: int) -> void:
	c.command.throttle = throttle
	c.command.sprint = sprint
	c.command.jump = false
	for _i in ticks:
		c._physics_process(TICK)


func _body_span(c: Creature2) -> float:
	var skin: Contour = c.contour
	var tail: int = skin.bands.find(skin.band(BodySchema.TAIL))
	var neck: int = skin.bands.find(skin.band(BodySchema.NECK))
	return Vector2(skin.tips[tail].x, skin.tips[tail].y).distance_to(
		Vector2(skin.tips[neck].x, skin.tips[neck].y))


func _top_layer(corpus: Corpus, column: int) -> int:
	for layer in [BodySchema.Layer.SKIN, BodySchema.Layer.FAT,
			BodySchema.Layer.MUSCLE, BodySchema.Layer.BONE]:
		if corpus.thickness[column * 4 + layer] > 0.0 and corpus.hp[column * 4 + layer] > 0.0:
			return layer
	return -1


func _distance_to_segment(at: Vector3, a: Vector3, b: Vector3) -> float:
	var run: Vector3 = b - a
	var length: float = run.length_squared()
	if length < 0.000001:
		return at.distance_to(a)
	var t: float = clampf((at - a).dot(run) / length, 0.0, 1.0)
	return at.distance_to(a + run * t)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	for note in notes:
		print("  " + note)
	if failures.is_empty():
		print("skin OK — the census, posed and drawn: %s" % " · ".join(notes))
	else:
		print("SKIN FAIL — %d problem(s):" % failures.size())
		for failure in failures:
			print("  - " + failure)
	quit(0 if failures.is_empty() else 1)
