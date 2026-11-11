extends SceneTree
# Do the hands' reaches and their small living movements keep them out of solid things?
# Plays a stretch of the game with both hands (throws, lifted moves, slides, captures; the
# human sometimes holds a stone in the air a while before setting it down) while his left
# hand eats a date. Every time a hand is placed it is checked:
#   - into the stones lying about (not the one in its fingers) and the wood they lie on,
#   - into the clay of the bowl (left hand),
#   - that its own movement (live) is never downward, sideways no more than half its room,
#     and nothing when it has none,
#   - that its own movement did not put it any deeper into anything than it would have been.
# Prints the worst of each. Runs on the code before the change too (no live / room there),
# to compare. SECS = how long to play (default 70), SEED = rng seed.
const TOL := 0.02      # world: what "deeper" has to exceed to count
const CLEAR := 0.03    # UrHand.LIFE_CLEAR (spelled out so this runs on the older code too)

var m
var worst_stone := 0.0
var worst_stone_at := ""
var worst_wood := 0.0
var worst_wood_at := ""
var worst_clay := 0.0
var worst_added := 0.0
var worst_over := 0.0
var live_air := 0.0        # the most a hand moved by itself, anywhere
var live_low := 0.0        # ... with no room (should be 0)
var live_hold := 0.0       # ... while the human held a stone in the air
var hold_room := INF
var placed_n := 0
var holding := false
var what := ""


func _init() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	if OS.get_environment("SEED") != "":
		seed(int(OS.get_environment("SEED")))
	var secs := float(OS.get_environment("SECS")) if OS.get_environment("SECS") != "" else 70.0
	for h in [m.hands[0], m.hands[1], m.lhand]:
		h.placed.connect(check.bind(h))
	m.eat_date()
	var t0 := Time.get_ticks_msec()
	var turn := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < secs:
		if m.phase == m.Phase.ROLL and m.game.current == 0:
			what = "throw"
			m._on_roll_pressed()
		elif m.phase == m.Phase.MOVE and m.game.current == 0 and not m.legal.is_empty():
			var idx: int = m.game.pos[0].find(m.legal[randi() % m.legal.size()])
			turn += 1
			if turn % 2 == 0:
				what = "move"
				m.perform_move(idx)
			else:
				await hold_and_move(idx)
		elif m.phase == m.Phase.OVER:
			break
		else:
			if m.game.current == 1:
				what = "his"
		await create_timer(0.1).timeout
	print("placements checked: %d" % placed_n)
	print("worst into a stone  %.3f cm  [%s]" % [worst_stone / UrHand.CM, worst_stone_at])
	print("worst into the wood %.3f cm  [%s]" % [worst_wood / UrHand.CM, worst_wood_at])
	print("worst into the clay %.3f cm" % [worst_clay / UrHand.CM])
	if "live" in m.hands[0]:
		print("own movement: most %.2f mm; most with no room %.3f mm; while holding a stone up %.2f mm (room there %.2f cm)" % [
			live_air / UrHand.CM * 10.0, live_low / UrHand.CM * 10.0, live_hold / UrHand.CM * 10.0, hold_room / UrHand.CM])
		print("own movement downward, or sideways beyond half its room: %.4f cm; deeper into anything because of it: %.4f cm" % [
			worst_over / UrHand.CM, worst_added / UrHand.CM])
		var ok := live_low < 1e-5 and worst_over < 1e-4 and worst_added < TOL and live_hold > 0.2 * UrHand.CM * 0.1
		print("OK" if ok else "FAIL")
	quit()


## The human presses on a stone, holds it up over the board for a while, moving it about
## and keeping it still by turns, then sets it down on its square.
func hold_and_move(idx: int) -> void:
	what = "hold"
	var node: Node3D = m.pnodes[0][idx]
	var from := node.position
	m.sel_idx = idx
	m.dragging = true
	m.release_pending = null
	m.drag_target = Vector3(from.x, m.BY + m.LIFT, from.z)
	m.human_grab(idx)
	var w := 0.0
	while not m.human_holding and w < 3.0:
		await create_timer(0.05).timeout
		w += 0.05
	if not m.human_holding:
		m.dragging = false
		return
	var dst: Vector3 = m.slot_pos(0, m.game.pos[0][idx] + m.roll, idx, m.game.finished_count(0))
	for k in 3:
		var to := from.lerp(dst, (k + 1) / 3.0) + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		m.drag_target = Vector3(to.x, m.BY + m.LIFT, to.z)
		await create_timer(0.5).timeout
		holding = true              # arrived (near enough): now it is only held
		await create_timer(0.9).timeout
		holding = false
	m.dragging = false
	what = "move"
	m.perform_move(idx)


func balls(T: Transform3D, h: UrHand) -> Array:
	var b: Array = m.bowl.hand_balls(T, h)
	b.resize(b.size() - 4)        # fingers and palm: not the wrist and sleeve
	return b


## [deepest into a stone, deepest into the wood] (world) of a hand at T.
func sink(T: Transform3D, h: UrHand) -> Vector2:
	var out := Vector2.ZERO
	var grip := T * h.grip_local()
	var stones: Array = []
	for p in 2:
		for n in m.pnodes[p]:
			var c: Vector3 = (n as Node3D).position
			if c.distance_to(grip) > 0.5 and c.distance_to(grip) < 6.0 and c.y < m.BY + m.PIECE_H:
				stones.append(c)
	for bl in balls(T, h):
		var p: Vector3 = bl[0]
		var r := float(bl[1])
		out.y = maxf(out.y, m.BY - 0.072 - (p.y - r))       # the slabs are that thick: under them is sand
		for c in stones:
			var side: float = m.PIECE_R + r - Vector2(p.x - c.x, p.z - c.z).length()
			var down: float = m.PIECE_H / 2.0 + r - absf(p.y - c.y)
			out.x = maxf(out.x, minf(side, down))
	return out


func check(h: UrHand) -> void:
	if not h.visible:
		return
	placed_n += 1
	var T := h.global_transform
	var s := sink(T, h)
	var tag := "%s, %s hand, grip %.2f,%.2f,%.2f" % [what, "left" if h == m.lhand else ("his" if h == m.hands[1] else "your"),
		h.grip_target.x, h.grip_target.y, h.grip_target.z]
	if s.x > worst_stone:
		worst_stone = s.x
		worst_stone_at = tag
	if s.y > worst_wood:
		worst_wood = s.y
		worst_wood_at = tag
	if h == m.lhand:
		worst_clay = maxf(worst_clay, -m.bowl.hand_clear(T, h))
	if not ("live" in h):
		return
	var live: Vector3 = h.live
	var T0 := T
	T0.origin -= live + h.bump
	var room: float = m.hand_room(T0, h)
	live_air = maxf(live_air, live.length())
	if room <= CLEAR:
		live_low = maxf(live_low, live.length())
	worst_over = maxf(worst_over, Vector2(live.x, live.z).length() - 0.5 * maxf(room - CLEAR, 0.0))
	worst_over = maxf(worst_over, -live.y)
	if holding and h == m.hands[0]:
		live_hold = maxf(live_hold, live.length())
		hold_room = minf(hold_room, room)
	if live.length() > 0.0:
		var T1 := T
		T1.origin -= live
		var s0 := sink(T1, h)
		worst_added = maxf(worst_added, maxf(s.x - s0.x, s.y - s0.y))
		if h == m.lhand:
			worst_added = maxf(worst_added, m.bowl.hand_clear(T1, h) - m.bowl.hand_clear(T, h) if m.bowl.hand_clear(T, h) < 0.0 else 0.0)
