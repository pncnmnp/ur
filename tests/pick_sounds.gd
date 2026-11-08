extends SceneTree
# Which sounds play while a hand gathers and throws the dice, and when: every new sound
# from the effects pool is listed with its time, name and volume. PLAYER=1 for the AI.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.epoch += 1
	m.game.current = int(OS.get_environment("PLAYER")) if OS.get_environment("PLAYER") != "" else 0
	m.phase = m.Phase.BUSY
	m.roll = -1
	m.do_roll()
	var last := {}
	var t0 := Time.get_ticks_msec()
	var held_prev := 0
	while m.roll < 0 and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		var held := 0
		for i in 4:
			if m.grip.mode[i] != 0:
				held += 1
		if held != held_prev:
			print("%6.2f   -- dice in hand: %d" % [t, held])
			held_prev = held
		for p in m.sfx_pool + [m.slide_player]:
			var pos: float = p.get_playback_position() if p.playing else -1.0
			var key: int = p.get_instance_id()
			var prev: Array = last.get(key, [null, -1.0])
			if p.playing and (p.stream != prev[0] or pos < float(prev[1]) - 0.001):
				print("%6.2f  %-14s %6.1f dB  pitch %.2f" % [t, p.stream.resource_path.get_file().get_basename(), p.volume_db, p.pitch_scale])
			last[key] = [p.stream, pos]
	quit()
