extends SceneTree
# Screenshot of the empty dice tray (dice hidden) to check the leather lining.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(1.0).timeout
	for b in m.dice_bodies:
		b.visible = false
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png(out + "/tray.png")
	quit()
