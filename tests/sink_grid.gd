extends SceneTree
# Probe: for every square/slot, place the human hand on a resting stone and report sink + grip error.
var m
func _init() -> void:
	m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	var h: UrHand = m.hands[0]
	if "room" in h: h.room = Callable()
	h.visible = true
	h.grip_override = UrHand.GRASP_C
	h.set_pose_dict(h.grasp_pose(UrHand.STONE_GRIP_R), true)
	for w in range(0, 16):
		for idx in [0, 3, 6]:
			if w > 0 and idx > 0: continue
			var at: Vector3 = m.rest(m.slot_pos(0, w, idx, 0))
			for y in [0.0, 0.15, 0.36]:
				var g := at + Vector3(0, y, 0)
				h.place(g, m.hand_fwd(h, g), 30.0)
				var b: Array = m.bowl.hand_balls(h.global_transform, h, true)
				var s := -INF
				for i in b.size():
					if i == 11: continue
					var p: Vector3 = b[i][0]
					s = maxf(s, m.BY - (p.y - float(b[i][1])))
				print("w %2d i %d y+%.2f  sink %.3f  griperr %.4f" % [w, idx, y, s / UrHand.CM, h.grip_world().distance_to(g)])
	quit()
