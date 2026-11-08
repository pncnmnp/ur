extends SceneTree
# Close views of where things meet the sand: the board's near edge, a reserve strip with its
# stones, a corner of the dice tray, the clay tablet, and the whole table from the game camera.
# SHOT_DIR = output folder, VIEW = one of the names below (one capture per run: macOS stops
# redrawing a covered window after a few frames), TAG = suffix for the file name.
const VIEWS := {
	"edge": [Vector3(0.6, 1.3, 4.6), Vector3(0.2, 0.0, 1.9)],
	"strip": [Vector3(1.6, 1.6, 5.4), Vector3(0.8, 0.1, 2.5)],
	"tray": [Vector3(-3.6, 1.7, 3.6), Vector3(-5.2, 0.1, 2.4)],
	"tablet": [Vector3(-5.6, 1.5, 6.4), Vector3(-6.7, 0.1, 4.0)],
	"game": [],
}
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var view: String = OS.get_environment("VIEW") if OS.get_environment("VIEW") != "" else "edge"
	var tag: String = OS.get_environment("TAG")
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	m.title_label.visible = false
	m.epoch += 1
	m.cloud_wait = 1e9            # stay in clear sun
	if view != "game":
		var cam := Camera3D.new()
		cam.fov = 40
		m.add_child(cam)
		cam.position = VIEWS[view][0]
		cam.look_at(VIEWS[view][1], Vector3.UP)
		cam.current = true
	await create_timer(1.2).timeout   # SDFGI and SSAO settle
	root.get_texture().get_image().save_png("%s/%s%s.png" % [out, view, tag])
	quit()
