extends SceneTree
# Contact sheets of a hand gathering and throwing the dice, from a close camera on the
# tray. SHOT_DIR = output folder, PLAYER=1 for the AI's hand, VIEW = near|side|top,
# STEP = seconds between frames. Writes sheet_<view>_<n>.png (4x4 frames each).
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var p := int(OS.get_environment("PLAYER")) if OS.get_environment("PLAYER") != "" else 0
	var view: String = OS.get_environment("VIEW") if OS.get_environment("VIEW") != "" else "near"
	var step := float(OS.get_environment("STEP")) if OS.get_environment("STEP") != "" else 0.12
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.title_label.visible = false
	m.epoch += 1
	var cam := Camera3D.new()
	cam.fov = 30
	m.add_child(cam)
	var c: Vector3 = m.tray_xf() * Vector3(m.TRAY.get_center().x, 0.0, m.TRAY.get_center().y)
	var offs := {"near": Vector3(1.2, 4.2, 6.0), "side": Vector3(5.5, 1.6, 0.4), "top": Vector3(0.01, 8.5, 0.6),
		"low": Vector3(-4.5, 1.0, 2.5), "wide": Vector3(2.0, 6.5, 8.0), "close": Vector3(0.6, 2.4, 3.4)}
	cam.position = c + offs.get(view, Vector3(0, 5, 5))
	cam.look_at(c + Vector3(0, 0.6, 0), Vector3.UP)
	cam.current = view != "game"
	m.game.current = p
	m.phase = m.Phase.BUSY
	m.do_roll()
	if OS.get_environment("FROM") != "":
		await create_timer(float(OS.get_environment("FROM"))).timeout
	var W := 480
	var H := 270
	var sheet := Image.create(W * 4, H * 4, false, Image.FORMAT_RGB8)
	var n := 0
	var page := 0
	var t0 := Time.get_ticks_msec()
	var frames := 0
	for k in 64:
		await create_timer(step).timeout
		var img := root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(W, H, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((n % 4) * W, (n / 4) * H))
		n += 1
		if n == 16:
			sheet.save_png(out + "/sheet_%s_%d.png" % [view, page])
			page += 1
			n = 0
			sheet.fill(Color.BLACK)
		if not m.rolling and k > 4 and m.dice_hand == null and not m.hands[p].visible:
			break
	if n > 0:
		sheet.save_png(out + "/sheet_%s_%d.png" % [view, page])
	print("roll: ", m.roll, "  fps ", Engine.get_frames_per_second())
	quit()
