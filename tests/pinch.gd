extends SceneTree
# Close look at both hands taking a stone between thumb and fingers.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.epoch += 1
	for p in 2:
		var h: UrHand = m.hands[p]
		var node: Node3D = m.pnodes[p][3]
		m.hand_take(h, node)
	await create_timer(1.6).timeout
	for p in 2:
		var h: UrHand = m.hands[p]
		m.hand_move(h, h.grip_target + Vector3(0, 0.6, 0), 0.3, 0.0, 30.0, m.pnodes[p][3])
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "/pinch.png")
	quit()
