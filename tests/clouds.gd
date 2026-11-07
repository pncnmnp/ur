extends SceneTree
# Passing cloud: screenshot in clear sun, mid-fade, and fully under the cloud.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(1.5).timeout
	assert(m.cloud_cover == 0.0, "should start in sunshine")
	m.cloud_wait = 0.0  # bring a cloud over now
	var shots := {0.0: "clear", 2.0: "edge", 5.0: "cloud"}
	var t0 := Time.get_ticks_msec()
	for at in shots:
		while (Time.get_ticks_msec() - t0) / 1000.0 < at:
			await process_frame
		print("%s: cover %.2f, sun %.2f" % [shots[at], m.cloud_cover, m.sun.light_energy])
		root.get_texture().get_image().save_png(out + "/cloud_%s.png" % shots[at])
	quit()
