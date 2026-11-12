extends SceneTree
# The marks the table keeps (traces.gd): some are made by hand here, then looked at.
# SHOT_DIR = output folder, VIEW = "game" / "sand" / "board" (one capture per run), TAG = file suffix,
# AGE = seconds of wind to let pass over them first (sped up).
const VIEWS := {
	"sand": [Vector3(2.4, 2.6, 7.6), Vector3(2.2, 0.0, 4.3)],
	"board": [Vector3(0.0, 3.2, 3.6), Vector3(0.0, 0.0, 0.4)],
	"game": [],
}
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var view: String = OS.get_environment("VIEW") if OS.get_environment("VIEW") != "" else "game"
	var age := float(OS.get_environment("AGE"))
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	m.title_label.visible = false
	m.epoch += 1
	m.cloud_wait = 1e9
	var t: Traces = m.traces
	# a hand's heel, a sleeve's trail, three date stones
	t.press(Vector3(1.0, 0, 4.4), Vector3(1.25, 0, 4.5), 0.42, 0.06, 0.02)
	t.press(Vector3(2.2, 0, 3.9), Vector3(3.6, 0, 4.6), 0.3, 0.02, 0.006)
	t.press(Vector3(3.6, 0, 4.6), Vector3(4.4, 0, 5.6), 0.3, 0.02, 0.006)
	for p in [Vector3(1.9, 0, 5.0), Vector3(2.5, 0, 5.2), Vector3(2.2, 0, 5.6)]:
		t.press(p - Vector3(0.18, 0, 0.05), p + Vector3(0.18, 0, 0.05), 0.11, 0.035, 0.012)
	# a stone pushed three squares, one set down, a sleeve over the near edge
	t.wipe(Vector3(-2.5, 0, 1.0), Vector3(0.5, 0, 1.0), 0.3, 0.9, 0.5)
	t.wipe(Vector3(2.5, 0, 0.0), Vector3(2.5, 0, 0.0), 0.22, 0.4)
	t.wipe(Vector3(1.0, 0, 1.6), Vector3(3.0, 0, 1.2), 0.4, 0.3)
	for i in 8:
		await process_frame
	var img := t.sim.get_texture().get_image()
	var uv := func(x: float, z: float) -> Vector2i:
		return Vector2i(int((x - Traces.AREA.position.x) * Traces.PPU), int((z - Traces.AREA.position.y) * Traces.PPU))
	print("format ", img.get_format(), " size ", img.get_size())
	print("heel floor ", img.get_pixelv(uv.call(1.1, 4.45)), "  untouched ", img.get_pixelv(uv.call(-3.0, 5.0)))
	print("wipe mid ", img.get_pixelv(uv.call(-1.0, 1.0)), "  wipe edge ", img.get_pixelv(uv.call(-1.0, 1.31)))
	print("kept ", t.keep.get_texture().get_image().get_pixelv(uv.call(1.1, 4.45)))
	if age > 0.0:
		Engine.time_scale = 20.0
		await create_timer(age).timeout
		Engine.time_scale = 1.0
		for i in 6:
			await process_frame
		img = t.sim.get_texture().get_image()
		print("after %d s: heel floor " % int(age), img.get_pixelv(uv.call(1.1, 4.45)), "  wipe mid ", img.get_pixelv(uv.call(-1.0, 1.0)))
	if out != "":
		if view != "game":
			var cam := Camera3D.new()
			cam.fov = 40
			m.add_child(cam)
			cam.position = VIEWS[view][0]
			cam.look_at(VIEWS[view][1], Vector3.UP)
			cam.current = true
		await create_timer(1.2).timeout
		root.get_texture().get_image().save_png("%s/traces_%s%s.png" % [out, view, OS.get_environment("TAG")])
	quit()
