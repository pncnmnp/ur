extends SceneTree
# Do his fingers stutter while his left hand takes a date out of the bowl, and where?
# He is not left to choose: every date lying free on top is taken in turn, bowl after
# bowl (each bowl heaped afresh from another seed), so the ones hard against the clay
# and low down in the bowl come up as often as the easy ones on top of the heap. Every
# drawn frame the fingertips' places in the world and every finger joint's bend are
# recorded; "stutter" is motion that turns about and, within a few frames, turns about
# again. The part of each step that undoes the last is what counts, summed from his hand
# coming over the bowl until the date is gone to his mouth.
#
# Prints one line per date (how far out from the bowl's middle it lay, how deep, stutter of
# tips in mm and joints in degrees, the worst single flick and when), then totals.
#   BOWLS = bowls (default 3), SEED, MOST = dates taken from each bowl (default all),
#   TRACE = 1 to print every flick over 1 mm.
# Run it headless at a fixed rate, so it does not wait for the clock:
#   Godot --headless --fixed-fps 60 --path . -s tests/date_stutter.gd
const TIP_EPS := 0.004       # cm: steps smaller than this are not motion
const JOINT_EPS := 0.03      # degrees
const AGAIN := 6             # frames: two turn-abouts no further apart than this are a stutter

var m
var h: UrHand
var bowl: DateBowl
var trace := false
var rec_on := false
var tips_prev := []
var tips_step := []
var joint_prev := []
var joint_step := []
var tip_turn := []
var joint_turn := []
var frame_n := 0
var t_trial := 0.0
var cur := {}
var names := []
var clay_worst := 0.0        # the deepest any of the hand was in the clay (cm)


func _init() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.epoch += 1
	m.phase = m.Phase.BUSY
	m.shoo_ok = false
	m.chew = Vector2(0.1, 0.1)
	bowl = m.bowl
	h = m.lhand
	h.room = Callable()          # (its own breathing and tremor are not what is being looked for)
	trace = OS.get_environment("TRACE") != ""
	var bowls := int(OS.get_environment("BOWLS")) if OS.get_environment("BOWLS") != "" else 3
	var sd := int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1
	var most := int(OS.get_environment("MOST")) if OS.get_environment("MOST") != "" else 99
	for d in UrHand.DIGITS:
		for s in 3:
			names.append("%s_%d" % [d, s])
	tip_turn.resize(5)
	joint_turn.resize(15)
	process_frame.connect(_frame)
	var sums := {}
	for b in bowls:
		if b > 0:
			await refill(sd * 1000 + b)
		var taken := 0
		while bowl.remaining() > 0 and taken < most:
			var c: Array = bowl.candidates(bowl.global_position - h.shoulder, 99)
			var d: Node3D = c[randi() % c.size()]
			var depth: float = (m.heap_top() - d.global_position.y) / DateBowl.CM
			var off: Vector3 = (bowl.global_transform.affine_inverse() * d.global_position) / DateBowl.CM
			var out := Vector2(off.x, off.z).length()
			var kind := "by the wall" if out > 3.0 else "middle"
			var r: Dictionary = await eat(d)
			taken += 1
			if not r.ok:
				print("bowl %d  date not taken (no way found)" % b)
				continue
			var s: Array = sums.get(kind, [0, 0.0, 0.0, 0.0, 0])
			s[0] += 1
			s[1] += float(r.tip)
			s[2] += float(r.joint)
			s[3] = maxf(s[3], r.worst)
			if float(r.worst) > 0.05:
				s[4] += 1
			sums[kind] = s
			print("bowl %d  %-11s (%.1f cm out, %.1f cm down, %2d left)  tips %6.2f mm  joints %6.1f deg  worst flick %.2f mm (%s, %.2fs, %s)" % [b, kind, out, depth,
				bowl.remaining(), float(r.tip) * 10.0, r.joint, float(r.worst) * 10.0, r.worst_tip, r.worst_t, r.worst_phase])
	print("")
	print("deepest the hand was in the clay: %.2f mm" % (clay_worst * 10.0))
	for kind in sums:
		var s: Array = sums[kind]
		print("%-11s  %3d dates   tips %6.2f mm each   joints %6.1f deg each   worst flick %.2f mm   dates with a flick over 0.5 mm: %d" % [kind, s[0],
			float(s[1]) * 10.0 / s[0], float(s[2]) / s[0], float(s[3]) * 10.0, s[4]])
	quit()


## Heap the bowl afresh, and let the dates come to rest.
func refill(sd: int) -> void:
	while m.left_busy or m.eating:
		await process_frame
	for e in bowl.dates:
		(e.node as Node).queue_free()
	bowl.dates.clear()
	for p in m.pits:
		if is_instance_valid(p):
			(p as Node).queue_free()
	m.pits.clear()
	bowl.pits_out = 0
	bowl.rng.seed = sd
	bowl.build_dates()
	for k in 90:
		await physics_frame


## He takes date d; returns {ok, tip, joint, worst, worst_tip, worst_t, worst_phase}.
func eat(d: Node3D) -> Dictionary:
	while m.left_busy or m.eating:
		await process_frame
	cur = {"ok": false, "tip": 0.0, "joint": 0.0, "worst": 0.0, "worst_tip": "", "worst_t": 0.0, "worst_phase": ""}
	var before: int = bowl.remaining()
	m.want_date = d
	t_trial = 0.0
	tips_prev = []
	tips_step = []
	tip_turn.fill(-1000)
	joint_turn.fill(-1000)
	rec_on = true
	m.eat_date()
	await process_frame
	var w := 0
	while m.eating and w < 60 * 30:
		await process_frame
		w += 1
	rec_on = false
	m.want_date = null
	cur.ok = bowl.remaining() < before
	return cur


func _phase() -> String:
	var over: float = (h.global_transform * h.grip_local()).y - m.heap_top()
	return "%s, grip %.1f cm %s the heap's top, bump %.2f mm" % ["has it" if bowl.spare_date == null or not is_instance_valid(bowl.spare_date) or bowl.spare_date.get_parent() != bowl else "reaching",
		absf(over) / DateBowl.CM, "over" if over > 0.0 else "under", h.bump.length() / UrHand.CM * 10.0]


func _frame() -> void:
	if not rec_on or not h.visible:
		return
	t_trial += 1.0 / 60.0
	frame_n += 1
	if OS.get_environment("BUMPS") != "":
		print("    %.2fs bump %6.2f %6.2f %6.2f mm  [%s]" % [t_trial, h.bump.x / UrHand.CM * 10.0, h.bump.y / UrHand.CM * 10.0, h.bump.z / UrHand.CM * 10.0, _phase()])
	var T := h.global_transform
	clay_worst = maxf(clay_worst, -bowl.hand_clear(T, h) / DateBowl.CM)
	var tips := []
	for d in UrHand.DIGITS:
		tips.append(T * (h.capsule(h.bones[d + "_2"])[1] as Vector3))
	var joints := []
	for nm in names:
		var bi: int = h.bones[nm]
		joints.append((h.pose_cur[bi] as Vector2).x + ((h.pose_give[bi] as Vector2).x if h.pose_give.has(bi) else 0.0))
	if not tips_prev.is_empty() and t_trial > 0.25:      # (not its first moments, coming in from out of view)
		var steps := []
		for k in 5:
			steps.append(((tips[k] as Vector3) - (tips_prev[k] as Vector3)) / UrHand.CM)
		var jsteps := []
		for k in joints.size():
			jsteps.append(float(joints[k]) - float(joint_prev[k]))
		if not tips_step.is_empty():
			for k in 5:
				var a: Vector3 = tips_step[k]
				var b: Vector3 = steps[k]
				if a.length() > TIP_EPS and b.length() > TIP_EPS and a.dot(b) < 0.0:
					var back := minf(minf(-a.dot(b) / a.length(), a.length()), b.length())
					var since: int = frame_n - int(tip_turn[k])
					tip_turn[k] = frame_n
					if since > AGAIN:
						continue
					cur.tip += back
					if back > float(cur.worst):
						cur.worst = back
						cur.worst_tip = UrHand.DIGITS[k]
						cur.worst_t = t_trial
						cur.worst_phase = _phase()
					if trace and back > 0.1:
						print("    %.2fs %s tip back %.2f mm  [%s]" % [t_trial, UrHand.DIGITS[k], back * 10.0, _phase()])
			for k in joints.size():
				var a: float = joint_step[k]
				var b: float = jsteps[k]
				if absf(a) > JOINT_EPS and absf(b) > JOINT_EPS and a * b < 0.0:
					var since: int = frame_n - int(joint_turn[k])
					joint_turn[k] = frame_n
					if since > AGAIN:
						continue
					cur.joint += minf(absf(a), absf(b))
					if trace and minf(absf(a), absf(b)) > 1.0:
						print("    %.2fs %s joint back %.1f deg  [%s]" % [t_trial, names[k], minf(absf(a), absf(b)), _phase()])
		tips_step = steps
		joint_step = jsteps
	tips_prev = tips
	joint_prev = joints
