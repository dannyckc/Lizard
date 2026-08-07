## FABRIK — Forward And Backward Reaching Inverse Kinematics.
##
## Used here for the two-bone arms and legs. It is a good fit because it is just
## the same circle projection the spine uses, applied alternately from each end
## of the chain, so the whole creature is solved by one geometric idea. It also
## degrades gracefully: no trig, no matrices, no singularities when the limb is
## straight, and it naturally preserves the bend direction it starts from.
class_name Fabrik
extends RefCounted


## Solves `joints` (root .. tip) so that the tip reaches `target` while every
## bone keeps its length. `joints.size()` must be `lengths.size() + 1`.
## Returns the solved chain; the input array is not modified.
##
## The caller controls which way the elbow/knee bends by seeding joints[1]
## before calling — FABRIK stays on whichever side of the root->target axis it
## begins on, so the seed is the pole vector.
static func solve(
		joints: PackedVector2Array,
		lengths: PackedFloat32Array,
		root: Vector2,
		target: Vector2,
		iterations: int = 6,
		tolerance: float = 0.05) -> PackedVector2Array:

	var out: PackedVector2Array = joints.duplicate()
	var n: int = out.size()
	if n < 2 or lengths.size() != n - 1:
		return out

	var total: float = 0.0
	for l in lengths:
		total += l

	# Unreachable target: no amount of relaxing will get there, so lay the chain
	# out straight toward it. Handling this up front keeps the loop below from
	# oscillating and gives a clean "fully extended" pose.
	if root.distance_to(target) >= total:
		var dir: Vector2 = (target - root)
		dir = dir.normalized() if dir.length_squared() > 0.000001 else Vector2.RIGHT
		out[0] = root
		for i in range(1, n):
			out[i] = out[i - 1] + dir * lengths[i - 1]
		return out

	# At least one full pass always runs, and the convergence test sits at the
	# *end* of the body. Checking it up front would let a chain whose tip
	# happens to already sit on the target skip the passes entirely — and since
	# the caller moves the root (the body walks) and seeds the middle joint (the
	# pole) between calls, such a chain still has stale, wrong bone lengths.
	for _it in range(maxi(iterations, 1)):
		# Backward pass: pin the tip to the target, then walk toward the root
		# pulling each joint onto its bone circle. Bone lengths end up correct
		# but the root has drifted off its socket.
		out[n - 1] = target
		for i in range(n - 2, -1, -1):
			out[i] = Constraints.project_to_circle(out[i], out[i + 1], lengths[i])

		# Forward pass: pin the root back to the shoulder/hip, then walk toward
		# the tip re-projecting. Root is correct again and every bone length is
		# now exact; only the tip has drifted off target — hence iterating. It
		# converges fast, two or three passes for a two-bone limb.
		out[0] = root
		for i in range(1, n):
			out[i] = Constraints.project_to_circle(out[i], out[i - 1], lengths[i - 1])

		if out[n - 1].distance_to(target) < tolerance:
			break

	return out
