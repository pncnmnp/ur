extends SceneTree
# Probe: frame-by-frame trace of the human's lowest fingertip vs the board while setting a held stone down.
var m
var on := false
var t0 := 0
func _init() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	seed(5)
	var h: UrHand = m.hands[0]
	if OS.get_environment("OFF") == "draw" and "draw_back" in h: h.draw_back = 0.0
	if OS.get_environment("OFF") == "live" and "room" in h: h.room = Callable()
	h.placed.connect(check.bind(h))
	m.epoch += 1
	m.game.current = 0
	m.roll = int(OS.get_environment("ROLL")) if OS.get_environment("ROLL") != "" else 2
	m.phase = m.Phase.MOVE
	m.legal = m.game.legal_moves(0, m.roll)
	var idx := int(OS.get_environment("IDX")) if OS.get_environment("IDX") != "" else 0
	var node: Node3D = m.pnodes[0][idx]
	m.sel_idx = idx; m.dragging = true
	var from := node.position
	m.drag_target = Vector3(from.x, m.BY + m.LIFT, from.z)
	m.human_grab(idx)
	if OS.get_environment("AT") == "grab":
		m.title_label.visible = false
		for k in 7:
			await create_timer(0.07).timeout
			print("shot ", k, " grip ", m.hands[0].grip_target)
			root.get_texture().get_image().save_png(OS.get_environment("OUT") + "_%d.png" % k)
		quit(); return
	while not m.human_holding:
		await process_frame
	var dst: Vector3 = m.slot_pos(0, m.game.pos[0][idx] + m.roll, idx, m.game.finished_count(0))
	m.drag_target = Vector3(dst.x, m.BY + m.LIFT, dst.z)
	await create_timer(1.2).timeout
	if OS.get_environment("AT") == "drag":
		root.get_texture().get_image().save_png(OS.get_environment("OUT")); quit(); return
	m.dragging = false
	print("release")
	on = true; t0 = Time.get_ticks_msec()
	m.perform_move(idx)
	var at := float(OS.get_environment("AT")) if OS.get_environment("AT") != "" else 0.25
	m.title_label.visible = false
	if at < 0.0:
		quit(); return
	await create_timer(at).timeout
	for k in 6:
		print("shot ", k, " grip ", m.hands[0].grip_target, " vis ", m.hands[0].visible)
		root.get_texture().get_image().save_png(OS.get_environment("OUT") + "_%d.png" % k)
		await create_timer(0.06).timeout
	quit()

func check(h: UrHand) -> void:
	if not on: return
	var b: Array = m.bowl.hand_balls(h.global_transform, h, true)
	var s := -INF; var which := -1
	for i in b.size():
		var p: Vector3 = b[i][0]
		var d: float = m.BY - (p.y - float(b[i][1]))
		if d > s: s = d; which = i
	print("%4d ms grip y %.3f pitch %.1f sink %.3f cm (ball %d) live %.4f stone y %.3f" % [Time.get_ticks_msec() - t0, h.grip_target.y, h.aim_pitch, s / UrHand.CM, which, h.live.y if "live" in h else 0.0, m.pnodes[0][int(OS.get_environment("IDX")) if OS.get_environment("IDX") != "" else 0].position.y])
