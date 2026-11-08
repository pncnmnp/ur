extends SceneTree
# The human hand mid-game, gripping (WHEN=dice: holding the dice; WHEN=stone: holding a stone),
# frozen and shot from the game camera with the veins forced empty and full.
# Saves vein_<when>_<fill>.png plus the hand's screen position.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var when: String = OS.get_environment("WHEN") if OS.get_environment("WHEN") != "" else "dice"
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	var h: UrHand = m.hands[0]
	var t0 := Time.get_ticks_msec()
	var acted_roll := false
	var acted_move := false
	while Time.get_ticks_msec() - t0 < 20000:
		if m.phase == m.Phase.ROLL and not acted_roll:
			acted_roll = true
			m._on_roll_pressed()
		elif m.phase == m.Phase.MOVE and not acted_move:
			acted_move = true
			m.perform_move(m.game.pos[0].find(m.legal[0]))
		await process_frame
		if h.visible and h.tension > 0.95 and ((when == "dice" and not acted_move and Time.get_ticks_msec() - t0 > 3000) or (when == "stone" and acted_move)):
			break
	h.set_process(false)
	m.process_mode = Node.PROCESS_MODE_DISABLED
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	print("hand screen: ", cam.unproject_position(h.global_position), " size ", root.size)
	for f in [float(OS.get_environment("LO") if OS.get_environment("LO") != "" else "0.1"), float(OS.get_environment("HI") if OS.get_environment("HI") != "" else "1.0")]:
		h.skin_mat.set_shader_parameter("pump", f)
		for i in 4:
			await process_frame
		await create_timer(0.2).timeout
		root.get_texture().get_image().save_png(out + "/vein_%s_%s.png" % [when, "lo" if f < 0.5 else "hi"])
	quit()
