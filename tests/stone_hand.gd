extends SceneTree
# Filmstrip of the AI's hand taking a stone and moving it (frames every 0.15 s).
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.title_label.visible = false
	m.epoch += 1
	m.game.current = 1
	m.roll = 3
	m.perform_move(2)
	for k in 24:
		await create_timer(0.15).timeout
		root.get_texture().get_image().save_png(out + "/s_%02d.png" % k)
	quit()
