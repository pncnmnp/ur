extends SceneTree
# Capturing in a crowd: the human drags a stone onto an AI stone, and has another stone right
# next to that square on its own row. The hand sets the held stone down beside the target
# for a moment - that spot must be clear, so no two stones are ever on top of each other.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.epoch += 1
	var g = m.game
	g.pos[0][0] = 4   # human stone on its rosette, about to move 2
	g.pos[0][1] = 3   # human stone in its own row, right beside shared square 6
	g.pos[1][0] = 6   # AI stone on shared square 6 (the victim)
	g.pos[1][1] = 7   # AI stone next along the lane
	g.pos[1][2] = 3   # AI stone in its own row, on the far side of square 6
	if OS.get_environment("PACKED") == "1":   # so tight it must be lifted back, not pushed
		g.pos[0][2] = 2
		g.pos[1][3] = 5
		g.pos[1][4] = 4
		g.pos[1][5] = 2
	g.current = 0
	for p in 2:
		for i in 7:
			m.pnodes[p][i].position = m.rest(m.slot_pos(p, g.pos[p][i], i, 0))
	m.pnodes[0][0].position = m.slot_pos(0, 6, 0, 0) + Vector3(0.1, m.LIFT, 0.05)
	m.hands[0].visible = true
	m.hands[0].set_pose("pinch", true)
	m.hands[0].place(m.pnodes[0][0].position, Vector3(0, 0, -1), 26.0)
	m.human_holding = true
	m.sel_idx = 0
	m.roll = 2
	m.perform_move(0)
	var min_gap := 99.0
	var worst := ""
	var t := 0.0
	while t < 9.0:
		await process_frame
		t += 1.0 / 60.0
		if OS.get_environment("SHOT") != "" and absf(t - float(OS.get_environment("SHOT"))) < 0.009:
			root.get_texture().get_image().save_png(OS.get_environment("OUT"))
		var all: Array = []
		for p in 2:
			for i in 7:
				all.append([m.pnodes[p][i], "%s%d" % ["H" if p == 0 else "A", i]])
		for a in all.size():
			for b in range(a + 1, all.size()):
				var dd: Vector3 = all[a][0].position - all[b][0].position
				var horiz := Vector2(dd.x, dd.z).length()
				if absf(dd.y) < m.PIECE_H * 1.5 and horiz < 2.0 * m.PIECE_R and horiz < min_gap:
					min_gap = horiz
					worst = "%s/%s at %.2fs" % [all[a][1], all[b][1], t]
	print("overlap: %s" % ("none" if min_gap > 90.0 else "%.2f apart (%s)" % [min_gap, worst]))
	assert(min_gap > 90.0)
	assert(g.pos[0][0] == 6 and g.pos[1][0] == 0)
	print("OK")
	quit()
