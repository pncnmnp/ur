extends SceneTree
# Filmstrip of a hand gathering and throwing the dice (frames every 0.2 s), seen from
# the game camera, cropped later to the tray. PLAYER=1 for the AI's hand.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.title_label.visible = false
	m.epoch += 1
	var p := int(OS.get_environment("PLAYER")) if OS.get_environment("PLAYER") != "" else 0
	m.game.current = p
	m.phase = m.Phase.BUSY
	m.do_roll()
	for k in 30:
		await create_timer(0.2).timeout
		root.get_texture().get_image().save_png(out + "/d_%02d.png" % k)
	print("roll: ", m.roll)
	quit()
