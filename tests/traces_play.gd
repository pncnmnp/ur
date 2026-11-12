extends SceneTree
# A stretch of real play (the human's moves made for him), then a look at what it left
# on the table: prints how many marks of each sort were made (traces.gd) and where the sun
# has got to, and saves one picture.
# SHOT_DIR = output folder, TAG = file suffix, MS = how long to play (real ms), SPEED = time
# scale, DAY = seconds of the afternoon already gone at the start, HUNGRY = his appetite
# (snack_rate), VIEW = "game" or one of the close views below.
const VIEWS := {
	"pits": [Vector3(6.6, 2.2, -1.2), Vector3(6.3, 0.0, -4.1)],
	"near": [Vector3(1.0, 3.4, 7.4), Vector3(0.6, 0.0, 2.6)],
	"board": [Vector3(0.0, 3.6, 3.9), Vector3(0.0, 0.0, 0.3)],
}
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var view: String = OS.get_environment("VIEW") if OS.get_environment("VIEW") != "" else "game"
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	m.title_label.visible = false
	m.cloud_wait = 1e9
	m.day_time = float(OS.get_environment("DAY"))
	if OS.get_environment("HUNGRY") != "":
		m.snack_rate = float(OS.get_environment("HUNGRY"))
	Engine.time_scale = float(OS.get_environment("SPEED")) if OS.get_environment("SPEED") != "" else 4.0
	var t0 := Time.get_ticks_msec()
	var dur := int(OS.get_environment("MS")) if OS.get_environment("MS") != "" else 30000
	while Time.get_ticks_msec() - t0 < dur and m.phase != m.Phase.OVER:
		if m.phase == m.Phase.ROLL and m.game.current == 0:
			m._on_roll_pressed()
		elif m.phase == m.Phase.MOVE and m.game.current == 0:
			var l: Array = m.legal
			m.perform_move(m.game.pos[0].find(l[randi() % l.size()]))
		await create_timer(0.1).timeout
	Engine.time_scale = 1.0
	m.epoch += 1                  # stop the game where it is, and take the hands away
	for t in m.tweens:
		if t.is_valid():
			t.kill()
	for h in m.hands + [m.lhand]:
		h.move_id += 1
		h.visible = false
	print("marks made: ", m.traces.made, "  still waiting: ", m.traces.queue.size())
	print("the afternoon: %.0f s gone, %.2f of the way; sun at %s, colour %s, strength %.2f" % [m.day_time, m.day_part(),
		m.sun.rotation_degrees, m.sun.light_color, m.sun.light_energy])
	if out != "":
		if view != "game":
			var cam := Camera3D.new()
			cam.fov = 40
			m.add_child(cam)
			cam.position = VIEWS[view][0]
			cam.look_at(VIEWS[view][1], Vector3.UP)
			cam.current = true
		await create_timer(1.0).timeout
		root.get_texture().get_image().save_png("%s/play_%s%s.png" % [out, view, OS.get_environment("TAG")])
	quit()
