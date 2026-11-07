extends SceneTree
# Close-ups for material work: both players' sleeves and jewellery in two poses (so the
# creases can be compared as the arm moves) and the clay tablet. Saves wear_*.png into SHOT_DIR.
# ONLY=tablet or ONLY=hands limits what is shot.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var only: String = OS.get_environment("ONLY")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.title_label.visible = false
	m.set_status("Your turn: throw the dice")
	var cam := Camera3D.new()
	cam.fov = 32
	m.add_child(cam)
	cam.current = true
	if only != "tablet":
		for hi in 2:
			var h: UrHand = m.hands[hi]
			h.visible = true
			h.set_process(false)
			if OS.get_environment("CLOTH_DEBUG") != "":
				h.sleeve_mat.set_shader_parameter("debug", int(OS.get_environment("CLOTH_DEBUG")))
			for pose in ["reach", "fist"]:
				# reach: arm stretched out to the far side of the board; fist: pulled in close, elbow bent
				var grip := Vector3(-1.0, 0.0, -2.0 if pose == "reach" else 3.0) * (1.0 if hi == 0 else -1.0) + Vector3(0, 1.4, 0)
				h.set_pose(pose, true)
				h.place(grip, m.hand_fwd(h, grip), 20.0 if pose == "reach" else 45.0)
				h._solve_arm()
				h._update_sleeve()
				var wrist: Vector3 = h.global_position
				var back: Vector3 = (h.shoulder - wrist).normalized()
				var side: Vector3 = back.cross(Vector3.UP).normalized()
				var ring_bone := "ring_0" if hi == 0 else "index_0"
				var ring_at: Vector3 = h.skel.global_transform * h.skel.get_bone_global_pose(h.bones[ring_bone]).origin
				var elbow: Vector3 = h.skel.global_transform * h.skel.get_bone_global_pose(h.bones["upperarm"]).origin
				var views := {
					"mid": [wrist + back * 4.0 + Vector3(0, 7.5, 0) + side * 4.0, wrist + back * 4.0],
					"wrist": [wrist + back * 1.2 + Vector3(0, 2.6, 0) + side * 2.0, wrist + back * 1.6],
					"elbow": [elbow + Vector3(0, 3.2, 0) + side * 2.6 - back * 1.0, elbow],
					"ring": [ring_at + h.global_transform.basis.y.normalized() * 1.3 + side * 0.5 + back * 0.7, ring_at],
				}
				for vn in views:
					cam.position = views[vn][0]
					cam.look_at(views[vn][1], Vector3.UP)
					await process_frame
					await process_frame
					await create_timer(0.15).timeout
					root.get_texture().get_image().save_png(out + "/wear_h%d_%s_%s.png" % [hi, pose, vn])
			h.visible = false
	if only != "hands":
		var tp: Vector3 = m.TABLET_POS
		for vn in ["near", "corner"]:
			cam.position = tp + (Vector3(0.0, 2.2, 2.6) if vn == "near" else Vector3(1.5, 1.1, 1.6))
			cam.look_at(tp + (Vector3.ZERO if vn == "near" else Vector3(0.9, 0, 0.3)), Vector3.UP)
			await create_timer(0.6).timeout
			root.get_texture().get_image().save_png(out + "/wear_tablet_%s.png" % vn)
	quit()
