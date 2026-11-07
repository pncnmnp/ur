extends SceneTree
# Physics-step time (ms) while a hand gathers, rattles and throws the dice.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.epoch += 1
	m.game.current = 0
	m.phase = m.Phase.BUSY
	m.do_roll()
	var worst := 0.0
	var tot := 0.0
	var n := 0
	var worst_frame := 0.0
	for k in 700:
		await physics_frame
		if not m.grip.active():
			if k > 50: break
			continue
		var t := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var f := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		worst = maxf(worst, t)
		worst_frame = maxf(worst_frame, f)
		tot += t
		n += 1
	print("physics step ms: mean %.2f  worst %.2f   process worst %.2f  (%d ticks)" % [tot / maxf(n, 1), worst, worst_frame, n])
	quit()
