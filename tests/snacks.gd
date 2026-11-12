extends SceneTree
# Vidur's dates over a whole game, sped up (headless is fine): you play the first legal
# move each turn after a pause, he plays and helps himself to dates on both turns. Checks
# that the dates only ever run down, never below zero, that each one eaten leaves a stone
# by the bowl, that he never plays (throws or moves) while a date is on its way to his
# mouth, and that the game never stalls. THINK = seconds you pause before each action
# (default 1), LIMIT_S = stop after this many real seconds instead of playing to the end.
func _init() -> void:
	Engine.time_scale = 4.0
	var think := float(OS.get_environment("THINK")) if OS.get_environment("THINK") != "" else 1.0   # your pause (s)
	var limit := int(OS.get_environment("LIMIT_S")) * 1000 if OS.get_environment("LIMIT_S") != "" else 0  # stop early (real s)
	var t_start := Time.get_ticks_msec()
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	m.snack_rate = 4.0
	var start: int = m.bowl.remaining()
	var last: int = start
	var on_turn := [0, 0]           # dates eaten on your turn / his
	var played_while_eating := 0
	var last_change := Time.get_ticks_msec()
	var last_state := ""
	var waited := 0.0
	var fails := 0
	while m.phase != m.Phase.OVER and Time.get_ticks_msec() - last_change < 30000 / 1:
		await create_timer(0.1).timeout
		waited += 0.1
		if limit > 0 and Time.get_ticks_msec() - t_start > limit:
			break
		var r: int = m.bowl.remaining()
		if r > last:
			print("FAIL: dates went up ", last, " -> ", r)
			fails += 1
		if r < last:
			on_turn[m.game.current] += last - r
		last = r
		# his right hand must stay put while the left is taking a date to his mouth
		if m.eating and m.game.current == m.AI and m.hands[m.AI].visible:
			played_while_eating += 1
		if m.phase == m.Phase.ROLL and waited > think:
			waited = 0.0
			m._on_roll_pressed()
		elif m.phase == m.Phase.MOVE and waited > think:
			waited = 0.0
			m.perform_move(m.game.pos[0].find(m.legal[0]))
		var st := "%d %d %d %s" % [m.phase, m.game.current, r, str(m.game.pos)]
		if st != last_state:
			last_state = st
			last_change = Time.get_ticks_msec()
	if m.phase != m.Phase.OVER and (limit == 0 or Time.get_ticks_msec() - t_start < limit):
		print("FAIL: game stalled in phase ", m.phase, " turn ", m.game.current, " eating ", m.eating, " busy ", m.left_busy)
		fails += 1
	# let the last stone be put down
	await create_timer(12.0).timeout
	var pits := 0
	for c in m.get_children():
		if c is MeshInstance3D and c.material_override is ShaderMaterial and c.material_override.get_shader_parameter("kind") == 1:
			pits += 1
	var eaten: int = start - m.bowl.remaining()
	print("dates: ", start, " -> ", m.bowl.remaining(), "  eaten on your turn ", on_turn[0], ", on his ", on_turn[1], "  stones by the bowl ", pits)
	if pits != eaten:
		print("FAIL: ", eaten, " eaten but ", pits, " stones")
		fails += 1
	if played_while_eating > 0:
		print("FAIL: his right hand was out while he ate (", played_while_eating, " samples)")
		fails += 1
	if m.bowl.remaining() < 0 or eaten == 0:
		print("FAIL: eaten ", eaten)
		fails += 1
	print("PASS" if fails == 0 else "FAILED %d" % fails)
	quit()
