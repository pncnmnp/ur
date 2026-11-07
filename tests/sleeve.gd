extends SceneTree
# Close look at the human's arm and sleeve, hand gathering at the tray.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	var h: UrHand = m.hands[0]
	h.visible = true
	h.set_pose(OS.get_environment("POSE") if OS.get_environment("POSE") != "" else "fist", true)
	h.place(Vector3(-6.4, 1.6, 0.6), m.hand_fwd(h, Vector3(-6.4, 1.6, 0.6)), 15.0)
	await create_timer(1.0).timeout
	var img := root.get_texture().get_image()
	img.save_png(out + "/sleeve_test.png")
	quit()
