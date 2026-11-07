extends SceneTree
# Diagnostic: plays a few turns and records how far each hand's shoulder had to travel
# from where the player sits (cm), how straight the arm got, and whether the
# shoulder ever came into the camera's view.
var stats := [{}, {}]

func _track(m, i: int) -> void:
	var h: UrHand = m.hands[i]
	if not h.visible:
		return
	var ua: int = h.bones["upperarm"]
	var fa: int = h.bones["forearm"]
	var gp: Transform3D = h.global_transform * h.skel.get_bone_global_pose(ua)
	var S: Vector3 = gp * Vector3(0, 0, UrHand.UPPERARM_CM)
	var E: Vector3 = h.global_transform * h.skel.get_bone_global_pose(ua).origin
	var W: Vector3 = h.global_position
	var lean_cm := (S - h.shoulder).length() / UrHand.CM
	var ext := W.distance_to(S) / ((UrHand.FOREARM_CM + UrHand.UPPERARM_CM) * UrHand.CM)
	var s: Dictionary = stats[i]
	if lean_cm > s.get("lean", 0.0):
		s["lean"] = lean_cm
		s["at"] = h.grip_target
	s["ext"] = maxf(s.get("ext", 0.0), ext)
	if h.grip_world().distance_to(h.grip_target + h.shake) > 0.02:
		s["clamped"] = s.get("clamped", 0) + 1   # sent somewhere out of reach
	var on: bool = not m.cam.is_position_behind(S) and Rect2(Vector2.ZERO, root.get_visible_rect().size).has_point(m.cam.unproject_position(S))
	if on:
		s["shoulder_seen"] = s.get("shoulder_seen", 0) + 1

func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	Engine.time_scale = float(OS.get_environment("SPEED")) if OS.get_environment("SPEED") != "" else 4.0
	for i in 2:
		var ii := i
		m.hands[i].placed.connect(func() -> void: _track(m, ii))
	var t0 := Time.get_ticks_msec()
	var dur := int(OS.get_environment("MS")) if OS.get_environment("MS") != "" else 40000
	while Time.get_ticks_msec() - t0 < dur and m.phase != m.Phase.OVER:
		if m.phase == m.Phase.ROLL and m.game.current == 0:
			m._on_roll_pressed()
		elif m.phase == m.Phase.MOVE and m.game.current == 0:
			var l: Array = m.legal
			m.perform_move(m.game.pos[0].find(l[randi() % l.size()]))
		await create_timer(0.1).timeout
	for i in 2:
		print(["HUMAN", "AI"][i], " ", stats[i])
	quit()
