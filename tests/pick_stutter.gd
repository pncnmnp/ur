extends SceneTree
# Do the fingers stutter while a hand gathers the dice, and where?
# The dice are not thrown: each trial lays the four of them where it wants them (hard
# against a rim board, in a corner, a little way off a board, or out in the middle),
# turned at random, and has a hand gather them. Every drawn frame the fingertips' places
# in the world and every finger joint's bend are recorded; "stutter" is motion that turns
# about and, within a few frames, turns about again (a single turn-about is only the hand
# changing what it is doing). The part of each step that undoes the last is what counts,
# summed while each die is being gone for, lifted and tucked away.
#
# Prints one line per die taken (where it lay, stutter of tips in mm and joints in
# degrees, the worst single flick and when), then the totals by where the die lay.
#   N = trials (default 12; 4 dice each), SEED, P = 0 you / 1 him / 2 both (default),
#   LAY = wall|corner|near|mid|mix (default mix), TRACE = 1 to print every flick over 0.4 mm.
# Run it headless at a fixed rate, so it does not wait for the clock:
#   Godot --headless --fixed-fps 60 --path . -s tests/pick_stutter.gd
const TIP_EPS := 0.004       # cm: steps smaller than this are not motion
const JOINT_EPS := 0.03      # degrees

var m
var g: DiceGrip
var rest_basis: Basis
var rest_y := 0.0
var rng := RandomNumberGenerator.new()
var trace := false

# the recording of the hand being watched
var h: UrHand
var rec_on := false
var tips_prev := []          # last frame's tip places (world), and the step before
var tips_step := []
var joint_prev := []
var joint_step := []
var cur := {}                # stutter gathered for the die now being taken
var t_trial := 0.0
var names := []
var tray_worst := 0.0        # the deepest any of the hand (or a die it holds) was in the tray's wood or leather (world)
var tray_when := ""
const AGAIN := 6             # frames: two turn-abouts no further apart than this are a stutter
var frame_n := 0
var tip_turn := []           # the frame each tip last turned about
var joint_turn := []


func _init() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.epoch += 1
	m.phase = m.Phase.BUSY
	m.shoo_ok = false
	await physics_frame
	g = m.grip
	rng.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 1
	seed(rng.seed)
	trace = OS.get_environment("TRACE") != ""
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 12
	var who := int(OS.get_environment("P")) if OS.get_environment("P") != "" else 2
	var lay: String = OS.get_environment("LAY") if OS.get_environment("LAY") != "" else "mix"
	rest_basis = (m.dice_bodies[0] as Node3D).global_transform.basis.orthonormalized()
	rest_y = (m.dice_bodies[0] as Node3D).global_position.y
	for d in UrHand.DIGITS:
		for s in 3:
			names.append("%s_%d" % [d, s])
	process_frame.connect(_frame)
	var sums := {}      # kind -> [dice, tip stutter, joint stutter, worst flick, dice with a flick > 0.5 mm]
	for t in n:
		var p := t % 2 if who == 2 else who
		var kinds := lay_dice(lay, t)
		await physics_frame
		await physics_frame
		var res: Array = await gather(p)
		for r in res:
			var kind: String = kinds[r.die]
			var s: Array = sums.get(kind, [0, 0.0, 0.0, 0.0, 0])
			s[0] += 1
			s[1] += float(r.tip)
			s[2] += float(r.joint)
			s[3] = maxf(s[3], r.worst)
			if float(r.worst) > 0.05:
				s[4] += 1
			sums[kind] = s
			print("trial %2d %s die %d %-6s  tips %6.2f mm  joints %6.1f deg  worst flick %.2f mm (%s, %.2fs, %s)%s" % [t, "you" if p == 0 else "him", r.die, kind,
				float(r.tip) * 10.0, r.joint, float(r.worst) * 10.0, r.worst_tip, r.worst_t, r.worst_phase, "" if r.taken else "   NOT TAKEN"])
	print("")
	print("deepest the hand was in the tray: %.2f mm (%s)" % [tray_worst / UrHand.CM * 10.0, tray_when])
	for kind in sums:
		var s: Array = sums[kind]
		print("%-6s  %3d dice   tips %6.2f mm each   joints %6.1f deg each   worst flick %.2f mm   dice with a flick over 0.5 mm: %d" % [kind, s[0],
			float(s[1]) * 10.0 / s[0], float(s[2]) / s[0], float(s[3]) * 10.0, s[4]])
	quit()


## Lay the four dice for a trial; returns what kind of place each lies in.
func lay_dice(lay: String, t: int) -> Array:
	var R: Rect2 = m.TRAY
	var txf: Transform3D = m.tray_xf()
	var kinds := []
	var modes := ["wall", "corner", "near", "mid"]
	# one die to each quarter of the tray, so they never crowd each other
	var quarters := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for i in 4:
		var kind: String = lay if lay != "mix" else modes[(t + i) % 4]
		var q: Vector2 = quarters[(i + t) % 4]
		var c := R.get_center()
		var half := R.size / 2.0
		var yaw := rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw) * rest_basis
		var gap := 0.0
		var l := Vector2.ZERO          # tray layout (x, z)
		var to_x := false              # pressed toward its x wall / its z wall
		var to_z := false
		match kind:
			"wall":
				to_x = rng.randf() < 0.5
				to_z = not to_x
				l = c + Vector2(q.x * half.x * rng.randf_range(0.25, 0.75), q.y * half.y * rng.randf_range(0.25, 0.75))
			"corner":
				to_x = true
				to_z = true
			"near":
				to_x = rng.randf() < 0.5
				to_z = not to_x
				gap = rng.randf_range(0.05, 0.3)
				l = c + Vector2(q.x * half.x * rng.randf_range(0.25, 0.75), q.y * half.y * rng.randf_range(0.25, 0.75))
			_:
				l = c + Vector2(q.x * half.x * rng.randf_range(0.3, 0.45), q.y * half.y * rng.randf_range(0.3, 0.45))
		# how far the die reaches each way from its centre, turned as it is (tray layout)
		var ext := Vector2.ZERO
		var tb := txf.basis.orthonormalized().inverse() * basis
		for s in g.samples:
			var e: Vector3 = tb * (s * UrHand.CM)
			ext.x = maxf(ext.x, e.x * q.x)
			ext.y = maxf(ext.y, e.z * q.y)
		if to_x:
			l.x = c.x + q.x * (half.x - ext.x - gap - 0.004)
		if to_z:
			l.y = c.y + q.y * (half.y - ext.y - gap - 0.004)
		var w: Vector3 = txf * Vector3(l.x, 0.0, l.y)
		var b: RigidBody3D = m.dice_bodies[i]
		b.freeze = true
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
		b.global_transform = Transform3D(basis, Vector3(w.x, rest_y, w.z))
		b.visible = true
		kinds.append(kind)
	return kinds


## Have player p's hand gather the dice (and cast them); returns, per die in the order
## taken: {die, tip, joint, worst, worst_tip, worst_t, worst_phase, taken}.
func gather(p: int) -> Array:
	m.epoch += 1
	m.phase = m.Phase.BUSY
	m.game.current = p
	h = m.hands[p]
	h.visible = false
	h.room = Callable()          # (its own breathing and tremor are not what is being looked for)
	var out: Array = []
	m.hand_throw(p)
	t_trial = 0.0
	tips_prev = []
	joint_prev = []
	var held_before := 0
	cur = _fresh(-1)
	rec_on = true
	var waited := 0
	while waited < 60 * 40:
		await process_frame
		waited += 1
		if not g.active():
			if waited > 30:
				break
			continue
		# a die has gone into the hand: what was gathered belongs to it
		var held := 0
		var newest := -1
		for i in 4:
			if g.mode[i] != DiceGrip.TABLE:
				held += 1
		if held > held_before:
			for i in 4:
				if g.mode[i] != DiceGrip.TABLE and not out.any(func(r: Dictionary) -> bool: return r.die == i):
					newest = i
			held_before = held
			cur.die = newest
			cur.taken = true
		# ... and once it is tucked away (the next is being gone for), close its account
		if cur.taken and t_trial - float(cur.close) > 0.55:
			out.append(cur)
			cur = _fresh(-1)
		if h.grip_override == UrHand.PALM_C:
			break                # the fist is closing: the gathering is over
	rec_on = false
	if cur.taken:
		out.append(cur)
	# let the cast go its way, then stop everything and take the dice back
	var w := 0
	while (g.active() or h.visible) and w < 60 * 12:
		await process_frame
		w += 1
	m.epoch += 1
	for t in m.tweens:
		if t.is_valid():
			t.kill()
	h.visible = false
	return out


func _fresh(die: int) -> Dictionary:
	return {"die": die, "tip": 0.0, "joint": 0.0, "worst": 0.0, "worst_tip": "", "worst_t": 0.0, "worst_phase": "", "taken": false, "close": 0.0}


func _phase() -> String:
	var held := 0
	for i in 4:
		if g.mode[i] != DiceGrip.TABLE:
			held += 1
	var driving := ""
	for d in ["index", "middle", "thumb"]:
		if g.ctl.has(d):
			driving = "closing"
	return "%d held %s bump %.2f mm" % [held, driving, h.bump.length() / UrHand.CM * 10.0]


func _frame() -> void:
	if not rec_on or h == null or not h.visible:
		return
	t_trial += 1.0 / 60.0
	frame_n += 1
	if tip_turn.is_empty():
		tip_turn.resize(5)
		tip_turn.fill(-1000)
		joint_turn.resize(15)
		joint_turn.fill(-1000)
	if OS.get_environment("BUMPS") != "":
		print("    %.2fs bump %6.2f %6.2f %6.2f mm  grip %.3f %.3f %.3f  pitch %.1f yaw %.1f  [%s]" % [t_trial, h.bump.x / UrHand.CM * 10.0, h.bump.y / UrHand.CM * 10.0, h.bump.z / UrHand.CM * 10.0,
			h.grip_target.x, h.grip_target.y, h.grip_target.z, h.aim_pitch, h.aim_yaw, _phase()])
	var T := h.global_transform
	for c in g.solid_contacts(T, h, h.capsules(), true):
		if float(c[1]) > tray_worst:
			tray_worst = float(c[1])
			tray_when = "%.2fs, %s" % [t_trial, _phase()]
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
				# going back the way it came: the part of this step that undoes the last
				if a.length() > TIP_EPS and b.length() > TIP_EPS and a.dot(b) < 0.0:
					var back := minf(-a.dot(b) / a.length(), a.length())
					back = minf(back, b.length())
					# one turn-about is a hand changing its mind (closing, then opening for the
					# next die); stutter is turning about again within a few frames
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

