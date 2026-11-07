extends SceneTree
# Capture animation order: the captured stone must leave its square before the capturer lands.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.epoch += 1
	var g = m.game
	g.pos[0][0] = 4   # human stone on its rosette
	g.pos[1][0] = 6   # AI stone on shared square 6
	g.current = 0
	m.pnodes[0][0].position = m.rest(m.slot_pos(0, 4, 0, 0))
	if OS.get_environment("HELD") == "1": # as if dragged over the target square, still in the hand
		m.pnodes[0][0].position = m.slot_pos(0, 6, 0, 0) + Vector3(0.1, m.LIFT, 0.05)
		m.hands[0].visible = true
		m.hands[0].set_pose("pinch", true)
		m.hands[0].place(m.pnodes[0][0].position, Vector3(0, 0, -1), 26.0)
		m.human_holding = true
		m.sel_idx = 0
	m.pnodes[1][0].position = m.rest(m.slot_pos(1, 6, 0, 0))
	m.roll = 2
	m.perform_move(0)
	var sq: Vector3 = m.rest(m.slot_pos(0, 6, 0, 0))
	var victim_left := -1.0
	var mover_arrived := -1.0
	var min_gap := 99.0
	var t := 0.0
	while t < 9.0:
		await process_frame
		t += 1.0 / 60.0
		var dd: Vector3 = m.pnodes[0][0].position - m.pnodes[1][0].position
		# flat stones overlap only if close sideways AND vertically
		var horiz := Vector2(dd.x, dd.z).length()
		if absf(dd.y) < m.PIECE_H and horiz < 2.0 * m.PIECE_R:
			min_gap = minf(min_gap, horiz)
		if victim_left < 0 and m.pnodes[1][0].position.distance_to(sq) > 0.6:
			victim_left = t
		if mover_arrived < 0 and m.pnodes[0][0].position.distance_to(sq) < 0.02:
			mover_arrived = t
	var victim_home: bool = m.pnodes[1][0].position.distance_to(m.rest(m.slot_pos(1, 0, 0, 0))) < 0.02
	print("victim left square at %.2fs, mover landed at %.2fs, victim back in reserve: %s, game says AI stone at %d" % [victim_left, mover_arrived, victim_home, g.pos[1][0]])
	assert(victim_left >= 0 and mover_arrived > victim_left and victim_home)
	print("overlap found: %s" % ("none" if min_gap > 90.0 else "yes, %.2f apart" % min_gap))
	assert(min_gap > 90.0)
	print("OK")
	quit()
