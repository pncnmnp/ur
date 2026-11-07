extends SceneTree
# Close look at a hand gripping a real stone: fingers and thumb should press on it
# from opposite sides, the thumb visible. Also open (pre-grasp) for comparison.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.title_label.visible = false
	m.epoch += 1
	var cam := Camera3D.new()
	cam.fov = 32
	m.add_child(cam)
	cam.current = true
	var h: UrHand = m.hands[int(OS.get_environment("P")) if OS.get_environment("P") != "" else 0]
	var stone: Node3D = m.pnodes[0][3]
	stone.position = m.rest(m.cell_pos(Vector2i(2, 1)))
	h.visible = true
	h.set_process(false)
	h.grip_override = h.GRASP_C
	for mode in ["open", "closed"]:
		var d: Dictionary = h.grasp_pose(1.5 if mode == "closed" else 3.2)
		h.set_pose_dict(d, true)
		h.place(stone.position, m.hand_fwd(h, stone.position), 32.0)
		var views := {"top": Vector3(0.4, 4.0, 1.0), "side": Vector3(3.0, 0.9, 0.0), "front": Vector3(0.2, 0.8, -3.2), "thumbside": Vector3(-3.0, 0.8, 0.5)}
		for vn in views:
			cam.position = stone.position + views[vn]
			cam.look_at(stone.position, Vector3.UP)
			await create_timer(0.15).timeout
			root.get_texture().get_image().save_png(out + "/g_%s_%s.png" % [mode, vn])
	for r in [1.5, 3.2]:
		h.set_pose_dict(h.grasp_pose(r), true)
		var C: Vector3 = h.GRASP_C
		var fz := sqrt(maxf(r * r - 0.8, 0.25))
		var goals := {"index_2": C + Vector3(0.85, 0, fz), "middle_2": C + Vector3(-0.95, 0, fz), "thumb_2": C + Vector3(0.35, 0, -r)}
		for bn in goals:
			var i: int = h.bones[bn]
			var g: Transform3D = h.skel.get_bone_global_pose(i)
			var pad := g * Vector3(0, -0.6, h.bone_len[i] * 0.7)
			print("r=%.1f %s pad miss %.2f cm" % [r, bn, pad.distance_to(goals[bn])])
	quit()
