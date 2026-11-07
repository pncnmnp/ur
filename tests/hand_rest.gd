extends SceneTree
# Debug: one hand in its rest pose (no finger pose, no arm IK), seen from the game camera.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	var h := UrHand.new(UrHand.Style.BLACK, Vector3(-0.5, 6.0, -13.0), Vector3(-1, 0, 0))
	m.add_child(h)
	await process_frame
	h.visible = true
	h.set_process(false)
	h.skel.reset_bone_poses()
	var mode := OS.get_environment("MODE")
	if mode != "":
		h.set_pose(mode, true)
	if OS.get_environment("DEBUG") != "":
		for c in h.skel.get_children():
			if c is MeshInstance3D and c.material_override is ShaderMaterial:
				c.material_override.set_shader_parameter("debug_view", int(OS.get_environment("DEBUG")))
	h.global_transform = Transform3D(Basis().scaled(Vector3.ONE * h.CM), Vector3(-3.0, 1.2, -1.5))
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png(out + "/hand_rest.png")
	quit()
