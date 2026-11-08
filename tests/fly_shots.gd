extends SceneTree
# Views of the flies, one capture per run (macOS stops redrawing a covered window).
# SHOT_DIR = output folder, VIEW = one of the names below, TAG = file name suffix.
# KIND = what the first fly sits on (date, rim, pit); STAGE = seconds after he starts to
# shoo it (VIEW flick: KIND date; VIEW wave: KIND pit); FLY = 1: let it fly about instead.
const VIEWS := {
	"date": [Vector3(4.6, 1.5, -3.2), "fly"],
	"pit": [Vector3(6.6, 1.0, -3.0), "fly"],
	"macro": [Vector3(0.0, 0.35, 0.55), "fly"],     # relative to the fly
	"game": [],
	"flick": [Vector3(3.2, 4.2, 0.6), Vector3(4.6, 1.0, -4.5)],
	"wave": [Vector3(4.6, 4.0, 0.4), Vector3(6.0, 0.8, -4.2)],
}
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var view: String = OS.get_environment("VIEW") if OS.get_environment("VIEW") != "" else "date"
	var kind: String = OS.get_environment("KIND") if OS.get_environment("KIND") != "" else "date"
	var stage := float(OS.get_environment("STAGE")) if OS.get_environment("STAGE") != "" else 0.5
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	m.title_label.visible = false
	m.epoch += 1
	m.snack_ok = false
	m.shoo_ok = false
	m.cloud_wait = 1e9
	for i in 4:
		m.eat_instantly()
	await create_timer(0.3).timeout
	var fl: Flies = m.flies
	fl.enabled = false
	fl.sit_on(0, kind)
	await create_timer(0.2).timeout
	var f: Dictionary = fl.flies[0]
	if OS.get_environment("FLY") != "":
		fl.enabled = true
		f.state = Flies.FLY
		f.loiter = 99.0
		f.goal = fl._wander(f.pos)
		await create_timer(0.4).timeout
	var v: Array = VIEWS[view]
	if v.size() > 0:
		var cam := Camera3D.new()
		cam.fov = 40 if view != "macro" else 30
		m.add_child(cam)
		if view == "macro":
			cam.position = f.pos + v[0]
			cam.look_at(f.pos, Vector3.UP)
		else:
			cam.position = v[0]
			cam.look_at(f.pos if v[1] is String else v[1], Vector3.UP)
		cam.current = true
	if view == "flick" or view == "wave":
		await create_timer(1.0).timeout
		m.shoo_ok = true
		m.shoo_next = 0.0
		m.shoo_free = -100.0
		f.patience = 0.0
		await create_timer(stage).timeout
	else:
		await create_timer(1.2).timeout
	var img := root.get_texture().get_image()
	img.save_png(out.path_join("fly_%s%s.png" % [view, OS.get_environment("TAG")]))
	quit()
