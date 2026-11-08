extends SceneTree
# The spot a stone is set down on mid-capture must never touch another stone, on any board.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.epoch += 1
	seed(7)
	var bad := 0
	var worst := 99.0
	var trials := 0
	var lifted := 0
	for n in 4000:
		var used := {}
		var pos := [[], []]
		for p in 2:
			for i in 7:
				var w := 0
				for tries in 20:
					var c := randi_range(0, 14)
					var cell: Vector2i = m.path_cell(p, c) if c > 0 and c < 15 else Vector2i(-1, -1)
					if c == 0 or not used.has(cell):
						w = c
						if c > 0:
							used[cell] = true
						break
				pos[p].append(w)
				m.pnodes[p][i].position = m.rest(m.slot_pos(p, w, i, 0))
		# a human stone captures an AI stone on the shared lane
		var v: int = -1
		for i in 7:
			if pos[1][i] >= 5 and pos[1][i] <= 12:
				v = i
				break
		if v == -1:
			continue
		var mover := randi_range(0, 6)
		var at: Vector3 = m.rest(m.slot_pos(1, pos[1][v], v, 0))
		var aside: Dictionary = m.free_spot_beside(at, 0, [m.pnodes[0][mover], m.pnodes[1][v]])
		var spot: Vector3 = aside.spot
		if not aside.slide:
			lifted += 1
		trials += 1
		var clear := 99.0
		for p in 2:
			for i in 7:
				var nd = m.pnodes[p][i]
				if nd == m.pnodes[0][mover] or nd == m.pnodes[1][v]:
					continue
				var o: Vector3 = nd.global_position
				# the spot itself must be clear; the way back only if it is pushed (not lifted) back
				var dd := Vector2(o.x - spot.x, o.z - spot.z).length()
				clear = minf(clear, m.seg_dist_xz(spot, at, o) if aside.slide else dd)
		clear = minf(clear, Vector2(at.x - spot.x, at.z - spot.z).length())   # the victim, still there
		worst = minf(worst, clear)
		if clear < 2.0 * m.PIECE_R:
			bad += 1
	print("%d captures tried, %d with no clear spot, %d lifted back instead of pushed, tightest clearance %.2f (stones touch below %.2f)" % [trials, bad, lifted, worst, 2.0 * m.PIECE_R])
	print("OK" if bad == 0 else "FAIL")
	quit()
