extends SceneTree
# Audio check: logs every sound effect that starts playing during a roll and a few moves.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	var seen := {}
	var counts := {}
	var t0 := Time.get_ticks_msec()
	await create_timer(0.3).timeout
	m.phase = m.Phase.ROLL
	m._on_roll_pressed()
	while Time.get_ticks_msec() - t0 < 16000:
		if m.phase == m.Phase.MOVE:
			m.perform_move(m.game.pos[0].find(m.legal[0]))
		elif m.phase == m.Phase.ROLL:
			m._on_roll_pressed()
		for p in m.sfx_pool:
			var playing: bool = p.playing and p.get_playback_position() < 0.03
			if playing and not seen.get(p, false):
				var n: String = p.stream.resource_path.get_file().get_basename()
				n = n.substr(0, n.rfind("_"))
				counts[n] = counts.get(n, 0) + 1
				print("%6d ms  %-12s %5.1f dB" % [Time.get_ticks_msec() - t0, n, p.volume_db])
			seen[p] = playing
		await process_frame
	print(counts)
	quit()
