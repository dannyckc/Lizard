## Windowed render of the target cursor, in the two states it has to be legible
## in — see the note about screenshotting the UI: a headless run draws nothing,
## so this opens a real window, poses one bite scenario twice and saves each.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . --script tests/ReticleShot.gd
##
## What it is for is the two things about the marker no headless check can see:
## that it sits *on* the surface it has selected rather than behind it, and that
## it is drawn in whichever ink reads against that surface. A Cat nose to nose
## with a Lizard puts the mark on black hide, which is exactly the case a mark in
## the ordinary ink disappears into.
##
##   reticle-near.png  a head it can reach — a ring, and the structure traced
##   reticle-far.png   the same body out of reach overhead — a cross
extends SceneTree

const TICK: float = 1.0 / 60.0
## How far above the target the second shot points, in px. Past anything a Cat's
## neck and its fold add up to, so the refusal is vertical — which is the one the
## third axis exists to deliver.
const OVERHEAD: float = 320.0
## Frames to let the renderer actually draw a staged pose before it is saved.
const SETTLE_FRAMES: int = 12

var main: Node
var frames: int = 0
var shots: Array[String] = ["near", "far"]
var taken: int = 0


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		# Main's own input pump resolves the cursor every physics tick and would
		# overwrite the aim staged below with wherever the real mouse happens to
		# be. The habitat is a fixture here, not a game.
		main.set_physics_process(false)
		main.set_process(false)
		_stage(shots[taken])
		return false
	if frames < SETTLE_FRAMES:
		return false
	root.get_viewport().get_texture().get_image().save_png(
		"res://reticle-%s.png" % shots[taken])
	taken += 1
	if taken >= shots.size():
		print("reticle shots: %s" % ", ".join(shots))
		quit(0)
		return false
	frames = 0
	return false


func _stage(which: String) -> void:
	var player: Creature = main.creature
	var target: Creature = main.target_creature
	target.alive = true
	main.terrain.clear()
	player.params.apply_preset("Cat")
	target.params.apply_preset("Lizard")
	target.reset(Vector2.ZERO, PI * 0.5)
	player.reset(Vector2(-300.0, 0.0), 0.0)
	_settle(player, target, 40)
	# Beside the drawn head, because that is a primitive a cursor can genuinely
	# land on: the pick is made in the picture, so a plan position would select
	# the patch of ground behind the animal instead.
	player.reset(target.body.head.pos + Vector2(-Reach.span(player) * 0.5, 0.0), 0.0)
	_settle(player, target, 40)
	var at: Vector2 = target.body.head.pos
	if which == "far":
		at += Vector2(0.0, -OVERHEAD)
	player.aim_at(Reticle.resolve(Reticle.pick(self, at, Reticle.SLACK, player), player))
	_settle(player, target, 30)
	main.camera.global_position = player.head_pos + Vector2(40.0, 0.0)
	main.camera.zoom = Vector2(3.4, 3.4)
	main.target_mark.show_aim(player, main.camera.zoom.x)
	main.queue_redraw()


func _settle(a: Creature, b: Creature, ticks: int) -> void:
	for _tick in ticks:
		a._physics_process(TICK)
		b._physics_process(TICK)
