extends SceneTree
# Filmstrip of play with hands: the human throws, moves (click-to-place style, so the
# hand does the whole move), then the AI throws and moves. Saves a frame every 0.3 s.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	var t0 := Time.get_ticks_msec()
	var k := 0
	var acted_roll := false
	var acted_move := false
	while Time.get_ticks_msec() - t0 < 22000:
		if m.phase == m.Phase.ROLL and not acted_roll:
			acted_roll = true
			m._on_roll_pressed()
		elif m.phase == m.Phase.MOVE and not acted_move:
			acted_move = true
			m.perform_move(m.game.pos[0].find(m.legal[0]))
		elif m.phase == m.Phase.ROLL and acted_move:
			break
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png(out + "/seq_%02d.png" % k)
		k += 1
	print("frames: ", k)
	quit()
