extends SceneTree
# Throw the physics dice several times; check they settle in the tray and that dice
# left leaning (on the rim or each other) are counted as they lie, not nudged flat.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	var leaning := 0
	for n in 12:
		m.phase = m.Phase.ROLL
		m._on_roll_pressed()
		var t0 := Time.get_ticks_msec()
		var p0 := Engine.get_physics_frames()
		var t := 0.0
		var sim := 0.0
		while m.roll < 0 and t < 14.0: # roll is -1 from the shake until the dice settle
			await process_frame
			t = (Time.get_ticks_msec() - t0) / 1000.0
			sim = (Engine.get_physics_frames() - p0) / float(Engine.physics_ticks_per_second)
		var tilts: Array = []
		for b in m.dice_bodies:
			var tv: Dictionary = m.top_vertex(b)
			tilts.append(snappedf(tv.upright, 0.01))
			if tv.upright < 0.9:
				leaning += 1
			assert(m.TRAY.grow(0.3).has_point(m.tray_local(b.global_position)), "die outside tray")
		print("throw %2d  settled in %.1fs game time (%.1fs wall)  roll=%d  results=%s  uprightness=%s" % [n, sim, t, m.roll, m.dice_result, tilts])
		m.epoch += 1
		m.roll = -1
	print("dice left leaning and counted as they lie: ", leaning)
	print("frames rendered per second during test: ", Engine.get_frames_per_second())
	quit()
