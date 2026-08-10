## Prints each preset's built silhouette geometry — the numbers the Gait HUD
## redesign is tuned against. Throwaway diagnostic scaffolding.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##       --path . --script tests/SilhouetteProbe.gd
extends SceneTree

const TICK: float = 1.0 / 60.0

var main: Node
var player: Creature
var ticked: Array[Node] = []


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	main.process_mode = Node.PROCESS_MODE_DISABLED
	player = main.get_node("Creature")
	main.terrain.clear()
	main.get_node("TargetCreature").reset(Vector2(0.0, 9000.0), 0.0)
	_collect(main)
	for preset_name in CreatureParams.PRESETS:
		_probe(str(preset_name))
	quit(0)
	return true


func _collect(node: Node) -> void:
	if node.has_method("_physics_process") and node != main:
		ticked.append(node)
	for child in node.get_children():
		child.process_mode = Node.PROCESS_MODE_DISABLED
		_collect(child)


func _tick(frames: int, throttle: float, sprint: bool) -> void:
	for i in frames:
		player.command.throttle = throttle
		player.command.sprint = sprint
		for node in ticked:
			node._physics_process(TICK)


func _probe(preset_name: String) -> void:
	player.params.apply_preset(preset_name)
	player.rebuild()
	player.reset(Vector2.ZERO, 0.0)
	var p: CreatureParams = player.params
	_tick(30, 0.0, false)

	var length: float = player.body_length()
	var n: int = player.spine.size()
	var gap: float = (p.rear_limb_t - p.front_limb_t) * length
	var tail_t: float = BodyPlan.tail_t(p.rear_limb_t)
	var clip: float = BodyPlan.clip_t(p)
	var hip_i: int = clampi(int(round(p.rear_limb_t * float(n - 1))), 0, n - 1)
	var base_i: int = clampi(int(round(tail_t * float(n - 1))), 0, n - 1)
	var body: BodyShape = player.body
	print("--- %s ---" % preset_name)
	print("  length %.1f · gap %.1f · segments %d x %.1f" % [
		length, gap, p.segment_count, p.segment_length])
	print("  head r %.1f · width @hip %.1f @tailbase %.1f @tip %.1f" % [
		body.head_radius, body.widths[hip_i], body.widths[base_i],
		body.widths[body.last_index]])
	print("  tail: starts %.2f ends %.2f -> %.1f px long (%.2f of gap)" % [
		tail_t, clip, (clip - tail_t) * length, (clip - tail_t) * length / gap])
	print("  stand: clearance %.1f depth %.1f stand %.1f head_h %.1f · mass %.2f" % [
		player.stature.clearance, player.stature.depth,
		player.stature.stand_height(), player.stature.head_height,
		player.physique.mass])

	_tick(240, 1.0, false)
	print("  walk: %s · Fr %.2f · duty %.2f · sh %.1f hip %.1f" % [
		player.gait.footfall.describe(), player.gait.footfall.froude,
		player.gait.duty_measured(), player.gait.shoulder_height,
		player.gait.hip_height])
	_tick(300, 1.0, true)
	print("  run : %s · Fr %.2f · duty %.2f · aerial %.2f" % [
		player.gait.footfall.describe(), player.gait.footfall.froude,
		player.gait.duty_measured(), player.gait.footfall.aerial])
