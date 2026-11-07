extends SceneTree
# Picks up a stone and drags it to the far edge of the screen: the hand must stop where
# the arm (and a leaning body) can reach, not stretch on. Saves drag_far.png.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	while m.phase != m.Phase.MOVE:
		if m.phase == m.Phase.ROLL and m.game.current == 0:
			m._on_roll_pressed()
		elif m.phase == m.Phase.ROLL:
			pass
		await create_timer(0.2).timeout
		if m.phase == m.Phase.MOVE and m.game.current != 0:
			continue
	var idx: int = m.game.pos[0].find(m.legal[0])
	var pt: Vector2 = m.cam.unproject_position(m.pnodes[0][idx].position)
	m.mouse_pos = pt
	m._on_press(pt)
	while not m.human_holding:
		await process_frame
	var to := Vector2(float(OS.get_environment("X")) if OS.get_environment("X") != "" else 800.0, float(OS.get_environment("Y")) if OS.get_environment("Y") != "" else 20.0)
	for k in 30:
		var p := pt.lerp(to, (k + 1) / 30.0)
		m.mouse_pos = p
		m._carry(p)
		await process_frame
	await create_timer(1.0).timeout
	var h: UrHand = m.hands[0]
	print("grip ", h.grip_world(), " target ", m.drag_target, " stone ", m.pnodes[0][idx].position)
	root.get_texture().get_image().save_png(out + "/drag_far.png")
	quit()
