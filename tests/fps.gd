extends SceneTree
# Rough frame-rate check with the full lighting, measured while a hand gathers,
# rattles and throws the dice (the heaviest moment).
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(3.0).timeout
	m._on_roll_pressed()
	var f0 := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await create_timer(3.0).timeout
	print("fps: %.0f" % ((Engine.get_frames_drawn() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)))
	quit()
