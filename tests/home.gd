extends SceneTree
# Bear off all 7 stones of both players through the real move animation and screenshot
# the home plates: stones must sit side by side on the plate, not stacked.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.epoch += 1
	for p in 2:
		for i in 7:
			m.game.current = p
			m.game.pos[p][i] = 14
			m.pnodes[p][i].position = m.rest(m.slot_pos(p, 14, i, 0))
			m.roll = 1
			m.perform_move(i)
			while m.game.pos[p][i] != 15:   # wait for the hand to finish the move
				await create_timer(0.1).timeout
			await create_timer(0.9).timeout
			m.epoch += 1  # stop the game flow continuing to the next turn
	await create_timer(0.5).timeout
	var worst := 99.0
	for p in 2:
		for i in 7:
			var a: Vector3 = m.pnodes[p][i].position
			assert(absf(a.y - m.rest(Vector3(0, m.BY, 0)).y) < 0.01, "stone not lying on the plate")
			for j in range(i + 1, 7):
				worst = minf(worst, Vector2(a.x, a.z).distance_to(Vector2(m.pnodes[p][j].position.x, m.pnodes[p][j].position.z)))
	print("all stones flat on the plates; closest centres %.2f apart" % worst)
	root.get_texture().get_image().save_png(out + "/home.png")
	quit()
