extends SceneTree
# Look at the hands: both players' hands held over the board in a few poses.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var pose_ai: String = OS.get_environment("POSE_AI") if OS.get_environment("POSE_AI") != "" else "pinch"
	var pose_h: String = OS.get_environment("POSE_H") if OS.get_environment("POSE_H") != "" else "reach"
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	var ai := UrHand.new(UrHand.Style.BLACK, Vector3(-0.5, 6.0, -13.0), Vector3(-1, 0, 0))
	var hu := UrHand.new(UrHand.Style.WHITE, Vector3(1.0, 6.0, 13.0), Vector3(1, 0, 0))
	m.add_child(ai)
	m.add_child(hu)
	await process_frame
	ai.visible = true
	hu.visible = true
	ai.set_pose(pose_ai, true)
	hu.set_pose(pose_h, true)
	ai.place(m.rest(m.cell_pos(Vector2i(2, 0))), Vector3(0, 0, 1), 28.0)
	hu.place(m.rest(m.cell_pos(Vector2i(5, 2))) + Vector3(0, 0.6, 0), Vector3(0, 0, -1), 15.0)
	await create_timer(1.5).timeout
	root.get_texture().get_image().save_png(out + "/hands.png")
	quit()
