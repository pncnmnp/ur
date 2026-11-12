extends SceneTree
# Probe: how deep do the human's (and his) fingers go into the board wood while moving/releasing a stone?
var m
var worst := {}
var phase_name := ""
func _init() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	seed(int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 3)
	var env := OS.get_environment("OFF")
	for h in [m.hands[0], m.hands[1]]:
		if "draw" in env and "draw_back" in h: h.draw_back = 0.0
		if "live" in env and "room" in h: h.room = Callable()
		h.placed.connect(check.bind(h))
	var t0 := Time.get_ticks_msec()
	var turn := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < 60.0:
		if m.phase == m.Phase.ROLL and m.game.current == 0:
			phase_name = "throw"; m._on_roll_pressed()
		elif m.phase == m.Phase.MOVE and m.game.current == 0 and not m.legal.is_empty():
			var idx: int = m.game.pos[0].find(m.legal[randi() % m.legal.size()])
			turn += 1
			if turn % 2 == 0:
				phase_name = "move"; m.perform_move(idx)
			else:
				await drag(idx)
		elif m.phase == m.Phase.OVER:
			break
		else:
			phase_name = "his"
		await create_timer(0.1).timeout
	var ks := worst.keys(); ks.sort()
	for k in ks:
		print("%-22s %.3f cm  %s" % [k, worst[k][0] / UrHand.CM, worst[k][1]])
	quit()

func drag(idx: int) -> void:
	phase_name = "grab"
	var node: Node3D = m.pnodes[0][idx]
	var from := node.position
	m.sel_idx = idx; m.dragging = true; m.release_pending = null
	m.drag_target = Vector3(from.x, m.BY + m.LIFT, from.z)
	m.human_grab(idx)
	var w := 0.0
	while not m.human_holding and w < 3.0:
		await create_timer(0.05).timeout; w += 0.05
	if not m.human_holding:
		m.dragging = false; return
	phase_name = "drag"
	var dst: Vector3 = m.slot_pos(0, m.game.pos[0][idx] + m.roll, idx, m.game.finished_count(0))
	for k in 3:
		var to := from.lerp(dst, (k + 1) / 3.0)
		m.drag_target = Vector3(to.x, m.BY + m.LIFT, to.z)
		await create_timer(0.6).timeout
	m.dragging = false
	phase_name = "release"
	m.perform_move(idx)

func check(h: UrHand) -> void:
	if not h.visible: return
	var b: Array = m.bowl.hand_balls(h.global_transform, h, true)
	var s := 0.0
	var which := -1
	for i in b.size():
		var p: Vector3 = b[i][0]
		var d: float = m.BY - (p.y - float(b[i][1]))
		if d > s: s = d; which = i
	var key := "%s %s" % ["you" if h == m.hands[0] else "him", phase_name]
	if s > float(worst.get(key, [0.0])[0]):
		worst[key] = [s, "ball %d grip %.2f,%.2f,%.2f live %s" % [which, h.grip_target.x, h.grip_target.y, h.grip_target.z, str(h.live) if "live" in h else "-"]]
