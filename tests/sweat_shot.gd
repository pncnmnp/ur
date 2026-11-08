extends SceneTree
# The human hand in a loose fist, close up under the game's sun, with the sweat forced to
# SWEAT (default 0). One shot per launch (the window stops redrawing after a few):
# saves sweat_<SWEAT>_<VIEW>.png. VIEW: game (the game camera) or close (default, over
# the knuckles from the light side). DEBUG=5 shows the film (red) and beads (green).
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var sw := float(OS.get_environment("SWEAT")) if OS.get_environment("SWEAT") != "" else 0.0
	var view: String = OS.get_environment("VIEW") if OS.get_environment("VIEW") != "" else "close"
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.title_label.visible = false
	var h: UrHand = m.hands[0]
	h.visible = true
	h.set_process(false)
	var grip := Vector3(-1.0, 1.0, 1.0)
	h.set_pose(OS.get_environment("POSE") if OS.get_environment("POSE") != "" else "fist", true)
	h.place(grip, Vector3(0, 0, -1), 20.0)
	h._solve_arm()
	h.sweat = sw
	h._update_skin()
	if OS.get_environment("DEBUG") != "":
		h.skin_mat.set_shader_parameter("debug_view", int(OS.get_environment("DEBUG")))
	if view == "close":
		var cam := Camera3D.new()
		cam.fov = 30
		m.add_child(cam)
		cam.current = true
		var off := Vector3(1.6, 2.6, 2.2)
		if OS.get_environment("OFF") != "":
			var v := OS.get_environment("OFF").split(",")
			off = Vector3(float(v[0]), float(v[1]), float(v[2]))
		cam.position = h.global_position + off
		cam.look_at(h.global_position, Vector3.UP)
	m.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 6:
		await process_frame
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png(out + "/sweat_%s_%s%s.png" % [str(sw), view, "_dbg" if OS.get_environment("DEBUG") != "" else ""])
	quit()
