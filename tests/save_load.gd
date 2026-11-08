extends SceneTree
# Save a mid-game position, scramble the board, load it back: the rules state and every
# stone must come back as saved, with Al-Khasm's turn resumed. Screenshots the loaded table.
# The player's own save slot is kept aside and put back afterwards.
func _init() -> void:
	var out: String = OS.get_environment("SHOT_DIR")
	var path: String = load("res://main.gd").SAVE_PATH
	var kept: Variant = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else null
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.snack_ok = false

	var g := UrGame.new()
	g.pos = [[0, 3, 6, 8, 13, 15, 15], [0, 0, 5, 9, 14, 15, 2]]
	g.current = 1
	m.set_up(g)
	m.save_game()
	assert(FileAccess.file_exists(path), "save file not written")
	assert(not m.load_button.disabled, "load should be enabled after a save")

	m.new_game()   # scramble: everything back on the strips
	await create_timer(0.3).timeout
	m.load_game()
	await process_frame
	assert(m.game.pos == g.pos, "loaded position differs: %s" % [m.game.pos])
	assert(m.game.current == 1, "should be Al-Khasm's turn")
	for p in 2:
		var k := 0
		for i in 7:
			var w: int = g.pos[p][i]
			var want: Vector3 = m.rest(m.slot_pos(p, w, i, k))
			if w == 15:
				k += 1
			assert(m.pnodes[p][i].position.distance_to(want) < 0.001, "stone %d/%d misplaced" % [p, i])

	# a corrupt slot is refused, not half-loaded
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"pos": [[1,2],[3]], "current": 0}')
	f.close()
	assert(m.read_save() == null, "corrupt save accepted")

	if kept == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(kept)
		f.close()
	print("save/load round trip ok")
	await create_timer(0.6).timeout
	if out != "":
		root.get_texture().get_image().save_png(out + "/save_load.png")
	quit()
