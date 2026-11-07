extends SceneTree
# Every throw: are all four dice still in the hand (near the palm) when it tosses them?
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 6
	var lost_total := 0
	for t in n:
		m.epoch += 1
		m.game.current = t % 2
		m.phase = m.Phase.BUSY
		m.roll = -1
		m.do_roll()
		var far := 0.0
		var low := INF
		var waited := 0.0
		var shook := false
		while m.roll < 0 and waited < 20.0:
			await physics_frame
			waited += 1.0 / 120.0
			var g: DiceGrip = m.grip
			if g.active() and g.hand.shake != Vector3.ZERO:
				shook = true
			if g.active() and shook:
				var pc: Vector3 = g.hand.global_transform * UrHand.PALM_C
				for i in 4:
					var w: Vector3 = g.hand.global_transform * (g.pos[i] as Vector3)
					far = maxf(far, w.distance_to(pc) / UrHand.CM)
					low = minf(low, (w.y - pc.y) / UrHand.CM)
		var lost := 1 if far > 5.5 else 0
		lost_total += lost
		print("throw %d: while rattling, farthest die %.1f cm from mid-palm, lowest %.1f cm relative to it %s" % [t, far, low, "LOST" if lost else ""])
		await create_timer(0.9).timeout
	print("throws where a die left the hand: ", lost_total)
	quit()
