extends SceneTree
# Diagnostic: where is the thumb? Rest pose vs posed, thumb region painted red, side view.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.title_label.visible = false
	var h: UrHand = m.hands[0]
	h.visible = true
	h.set_process(false)
	for c in h.skel.get_children():
		if c is MeshInstance3D and c.material_override is ShaderMaterial and c.mesh.get_surface_count() > 0:
			c.material_override.set_shader_parameter("debug_view", 2)
	var cam := Camera3D.new()
	cam.fov = 40
	m.add_child(cam)
	cam.current = true
	var at := Vector3(-1.0, 1.4, 0.0)
	for mode in ["rest", "reach"]:
		h.skel.reset_bone_poses()
		if mode != "rest":
			h.set_pose(mode, true)
		h.global_transform = Transform3D(Basis().scaled(Vector3.ONE * h.CM), at)
		for vn in ["top", "under"]:
			cam.position = at + (Vector3(0.6, 5.0, 2.0) if vn == "top" else Vector3(0.5, -0.9, 2.2))
			cam.look_at(at + Vector3(0, 0, 2.0), Vector3.UP)
			await create_timer(0.2).timeout
			root.get_texture().get_image().save_png(out + "/t_%s_%s.png" % [mode, vn])
		for i in [h.bones["thumb_0"], h.bones["thumb_1"], h.bones["thumb_2"], h.bones["index_0"]]:
			var g: Transform3D = h.skel.get_bone_global_pose(i)
			print(mode, " ", h.skel.get_bone_name(i), " head ", g.origin.snapped(Vector3.ONE * 0.01), " z ", g.basis.z.normalized().snapped(Vector3.ONE * 0.01))
	quit()
