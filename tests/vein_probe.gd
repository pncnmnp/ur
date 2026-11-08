extends SceneTree
# Log each hand's vein state (tension, low, pump, the fill sent to the shader) every 0.1 s
# through a human turn and an AI turn.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	var t0 := Time.get_ticks_msec()
	var acted_roll := false
	var acted_move := false
	while Time.get_ticks_msec() - t0 < 25000:
		if m.phase == m.Phase.ROLL and not acted_roll:
			acted_roll = true
			m._on_roll_pressed()
		elif m.phase == m.Phase.MOVE and not acted_move:
			acted_move = true
			m.perform_move(m.game.pos[0].find(m.legal[0]))
		elif m.phase == m.Phase.ROLL and acted_move and Time.get_ticks_msec() - t0 > 12000:
			break
		var s := "%5.1f " % ((Time.get_ticks_msec() - t0) / 1000.0)
		for h in m.hands:
			s += "| %s t%.2f e%.2f low%.2f pump%.2f fill%.2f " % ["V" if h.visible else "-", h.tension, h.effort, h.low, h.pump, float(h.skin_mat.get_shader_parameter("pump"))]
		print(s)
		await create_timer(0.1).timeout
	quit()
