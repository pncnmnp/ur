extends SceneTree
# Ambience check (numbers only): plays a few turns while a cloud comes over and Al-Khasm
# eats a date, and reports what was heard: how hard it gusted and how loud each loop got,
# every one-shot by name, and whether the 24 s wind loop is still going after 30 s.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.3).timeout
	var a: Ambience = m.amb
	var speed := float(OS.get_environment("SPEED")) if OS.get_environment("SPEED") != "" else 1.0
	Engine.time_scale = speed
	m.cloud_wait = 4.0            # a cloud's edge after four seconds
	m.chew = Vector2(14.0, 14.0)
	m.eat_date()
	var peak := {}
	var counts := {}
	var seen := {}
	var t := 0.0
	var last := Time.get_ticks_usec()
	m.phase = m.Phase.ROLL
	while t < 34.0:
		var now := Time.get_ticks_usec()
		t += (now - last) / 1e6 * speed
		last = now
		if m.phase == m.Phase.MOVE and not m.legal.is_empty():
			m.perform_move(m.game.pos[0].find(m.legal[0]))
		elif m.phase == m.Phase.ROLL:
			m._on_roll_pressed()
		peak["gust level"] = maxf(peak.get("gust level", 0.0), a.gust_level)
		for pair in [["air", a.air], ["gust", a.gust_p], ["sand", a.sand_p]]:
			if pair[1].playing:
				peak[pair[0]] = maxf(peak.get(pair[0], -80.0), pair[1].volume_db)
		for i in a.arms.size():
			for key in ["rub", "drag"]:
				var p: AudioStreamPlayer3D = a.arms[i][key]
				if p.playing:
					var k := "%s %d" % [key, i]
					peak[k] = maxf(peak.get(k, -80.0), p.volume_db)
		for p in m.sfx_pool:
			var playing: bool = p.playing and p.get_playback_position() < 0.05
			if playing and not seen.get(p, false):
				var n: String = p.stream.resource_path.get_file().get_basename()
				n = n.substr(0, n.rfind("_"))
				counts[n] = counts.get(n, 0) + 1
				if n in ["chew", "sniff", "nose_out", "cloth_move", "hand_wood", "hand_leather"]:
					print("%5.1f s  %-12s %6.1f dB  at %s" % [t, n, p.volume_db, p.position.snapped(Vector3.ONE * 0.1)])
			seen[p] = playing
		await process_frame
	print("peaks (dB): ", peak)
	print("one-shots: ", counts)
	print("air still playing after %.0f s: %s (at %.1f s of %.1f)" % [t, a.air.playing, a.air.get_playback_position(), a.air.stream.get_length()])
	for n in ["wind_air", "wind_gust", "sand_drift", "cloth_rub", "sleeve_sand"]:
		var w: AudioStreamWAV = Ambience.loop(n)
		print("%-12s %5.2f s  stereo %s  loop %d..%d" % [n, w.get_length(), w.stereo, w.loop_begin, w.loop_end])
	quit()
