extends SceneTree
# Vidur's bowl of dates: close views of the bowl and the dates in it, and of him eating.
# SHOT_DIR = output folder, VIEW = one of the names below (one capture per run: macOS stops
# redrawing a covered window after a few frames), TAG = suffix for the file name.
# EAT = how many dates he eats first (instantly, with their stones spat out beside the bowl).
# STAGE = for VIEW "eat": seconds into an eat to capture (he reaches, picks, lifts).
# SPIT = 1: instead, capture STAGE seconds into him putting a date stone down by the bowl.
const VIEWS := {
	"bowl": [Vector3(4.2, 3.3, -1.6), Vector3(4.3, 0.4, -4.55)],
	"close": [Vector3(4.3, 2.4, -2.5), Vector3(4.3, 0.5, -4.55)],
	"low": [Vector3(3.2, 0.9, -3.0), Vector3(4.3, 0.4, -4.55)],
	"side": [Vector3(8.6, 2.6, -2.2), Vector3(4.3, 0.4, -4.55)],
	"game": [],
	"eat": [],
	"eatclose": [Vector3(3.2, 3.6, 0.2), Vector3(4.6, 1.4, -4.4)],
	"pits": [Vector3(5.6, 1.7, -1.8), Vector3(6.3, 0.1, -4.1)],
}
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var view: String = OS.get_environment("VIEW") if OS.get_environment("VIEW") != "" else "bowl"
	var tag: String = OS.get_environment("TAG")
	var eat := int(OS.get_environment("EAT")) if OS.get_environment("EAT") != "" else 0
	var stage := float(OS.get_environment("STAGE")) if OS.get_environment("STAGE") != "" else 1.0
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	m.title_label.visible = false
	m.epoch += 1                  # no game going on: nothing else moves
	m.snack_ok = false
	m.cloud_wait = 1e9            # stay in clear sun
	for i in eat:
		m.eat_instantly()
	if VIEWS[view].size() > 0:
		var cam := Camera3D.new()
		cam.fov = 40
		m.add_child(cam)
		cam.position = VIEWS[view][0]
		cam.look_at(VIEWS[view][1], Vector3.UP)
		cam.current = true
	if OS.get_environment("SPIT") != "":
		await create_timer(1.0).timeout
		m.left_busy = true
		m.spit_stone(0.0)
		await create_timer(stage).timeout
	elif view == "eat" or view == "eatclose":
		await create_timer(1.0).timeout
		m.eat_date()
		await create_timer(stage).timeout
	else:
		await create_timer(1.2).timeout   # SDFGI and SSAO settle
	root.get_texture().get_image().save_png("%s/%s%s.png" % [out, view, tag])
	quit()
