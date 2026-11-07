extends SceneTree
# Diagnostic: one hand in several poses, seen close up from above, the side and below.
# Saves views_<pose>.png (three views side by side via separate captures).
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.title_label.visible = false
	var h: UrHand = m.hands[0]
	h.visible = true
	h.set_process(false)
	var poses: Array = OS.get_environment("POSES").split(",") if OS.get_environment("POSES") != "" else ["reach", "pinch", "cup", "fist"]
	var cam := Camera3D.new()
	cam.fov = 35
	m.add_child(cam)
	cam.current = true
	var grip := Vector3(-1.0, 1.4, 0.0)
	for pose in poses:
		h.set_pose(pose, true)
		h.place(grip, Vector3(0, 0, -1), 20.0)
		h._solve_arm()
		var views := {"top": Vector3(0.3, 4.5, -0.6), "side": Vector3(3.6, 1.6, -0.4), "front": Vector3(0.0, 1.0, -4.0), "below_side": Vector3(-3.4, 0.4, -0.8)}
		for vn in views:
			cam.position = grip + views[vn]
			cam.look_at(grip, Vector3.UP)
			await process_frame
			await process_frame
			await create_timer(0.15).timeout
			root.get_texture().get_image().save_png(out + "/v_%s_%s.png" % [pose, vn])
	quit()
