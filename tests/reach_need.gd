extends SceneTree
# Diagnostic: how far each player has to lean (cm) to bring his grip to every place the
# game sends his hand: every square he can stand on, his strip, home plate and the tray.
func _lean(m, h: UrHand, g: Vector3) -> float:
	var b := h.hand_basis(m.hand_fwd(h, g), 20.0, 0.0)
	var W := g - b * (h.grip_local() * UrHand.CM)
	var S0 := h.shoulder
	S0.x = lerpf(h.shoulder.x, W.x, h.lean)
	var r := (UrHand.FOREARM_CM + UrHand.UPPERARM_CM) * UrHand.CM * UrHand.REACH_FRAC
	var d := W.distance_to(S0)
	var S := S0 if d <= r else W + (S0 - W).normalized() * r
	return (S - h.shoulder).length() / UrHand.CM

func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.3).timeout
	for p in 2:
		var h: UrHand = m.hands[p]
		h.set_pose("reach", true)
		var pts := {}
		for x in 8:
			for y in 3:
				pts["cell %d,%d" % [x, y]] = m.rest(m.cell_pos(Vector2i(x, y)))
		for i in 7:
			pts["strip %d" % i] = m.rest(m.slot_pos(p, 0, i, 0))
			pts["home %d" % i] = m.rest(m.slot_pos(p, UrGame.FINISH, i, i))
		var t: Transform3D = m.tray_xf()
		for u in [-1.3, 0.0, 1.3]:
			for v in [-2.0, 0.0, 2.0]:
				pts["tray %.1f,%.1f" % [u, v]] = t * Vector3(m.TRAY.get_center().x + u, 0.4, m.TRAY.get_center().y + v)
		var worst := []
		for k in pts:
			worst.append([_lean(m, h, pts[k]), k])
		worst.sort()
		worst.reverse()
		print(["HUMAN", "AI"][p], " ", worst.slice(0, 6))
	quit()
