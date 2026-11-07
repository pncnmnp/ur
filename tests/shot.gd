extends SceneTree
# Visual check: roll dice, take screenshots mid-roll / settled / after a move.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.phase = m.Phase.ROLL
	m._on_roll_pressed()
	await create_timer(0.95).timeout
	root.get_texture().get_image().save_png(out + "/roll_mid.png")
	while m.rolling:
		await process_frame
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png(out + "/roll_done.png")
	# play a few moves for the looks
	for i in 6:
		if m.phase == m.Phase.MOVE:
			var src: int = m.legal[0]
			m.perform_move(m.game.pos[0].find(src))
		await create_timer(2.2).timeout
		if m.phase == m.Phase.ROLL:
			m._on_roll_pressed()
		await create_timer(2.5).timeout
	root.get_texture().get_image().save_png(out + "/later.png")
	quit()
