extends SceneTree
# Flies never go into the bowl's clay or into a date, and never pass through either
# between one frame and the next; a fly sitting on a date or a stone has its feet on the
# surface (not sunk in, not hovering). Sped up, headless; he shoos them and eats dates
# (which shifts the heap under them) as usual. SECONDS = game seconds (default 400).
const SINK := 0.06           # cm a point may be inside a surface before it counts
const HOVER := 0.12          # cm a sitting fly's feet may be above the surface
const SAND_Y := -0.04        # the sand round the bowl, where the date stones lie (world)

func _init() -> void:
	Engine.time_scale = float(OS.get_environment("SPEED")) if OS.get_environment("SPEED") != "" else 2.0
	var secs := float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 400.0
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.6).timeout
	m.epoch += 1
	m.snack_ok = false
	for i in 3:
		m.eat_instantly()
	var bowl: DateBowl = m.bowl
	var fl: Flies = m.flies
	fl.often()                    # (in play they come only now and then)
	var prev: Array = []
	var left: Array = []          # [node, where] each fly last sat
	for f in fl.flies:
		prev.append(null)
		left.append(null)
	var bad := {}               # kind -> [count, worst cm, example]
	var t0: float = m.fly_clock
	var next_eat := 20.0
	var sat_frames := 0
	var frames := 0
	while m.fly_clock - t0 < secs:
		await process_frame
		if m.fly_clock - t0 > next_eat and not m.left_busy and bowl.remaining() > 2:
			next_eat += randf_range(20.0, 40.0)
			m.eat_date()
		for i in fl.flies.size():
			var f: Dictionary = fl.flies[i]
			if f.state == Flies.AWAY:
				prev[i] = null
				continue
			frames += 1
			var p: Vector3 = f.pos
			var body: Vector3 = (f.node as Node3D).global_transform * Vector3(0, 0.2 * DateBowl.CM, 0)
			var pts: Array = [[p, "feet"], [body, "body"]]
			# along the way from last frame: did it go through anything?
			if prev[i] != null:
				for k in range(1, 6):
					pts.append([(prev[i] as Vector3).lerp(p, k / 6.0), "path"])
			prev[i] = p
			var st: String = ["away", "fly", "land", "sit", "flee"][f.state]
			for q in pts:
				var w: Vector3 = q[0]
				# (a fly on a date stands on its skin: the date's own solid balls bulge past it)
				var own: Node3D = f.spot.node if (f.state == Flies.SIT or f.descend) and not f.spot.is_empty() else null
				# (and just lifting off it, still within a millimetre or two of where it stood)
				if own == null and left[i] != null and is_instance_valid(left[i][0]) and w.distance_to(left[i][1]) < 0.25 * DateBowl.CM:
					own = left[i][0]
				var clay: float = bowl.clay_sdf(w) / DateBowl.CM
				# (on the lip, or just leaving it, its feet are on the clay you see, which has chips
				# out of it the simplified solid has not: the surface check below judges those)
				var on_rim: bool = own == bowl or (f.state == Flies.LAND and f.descend and f.spot.kind == "rim") \
					or (left[i] != null and left[i][0] == bowl and w.distance_to(left[i][1]) < 0.3 * DateBowl.CM)
				if clay < -SINK and not on_rim:
					_note(bad, "in the clay (%s, %s)" % [q[1], st], -clay, w)
				var dd := _date_depth(bowl, w, own)
				if dd > SINK:
					_note(bad, "in a date (%s, %s)" % [q[1], st], dd, w)
				if w.y < SAND_Y - SINK * DateBowl.CM:
					_note(bad, "under the sand (%s, %s)" % [q[1], st], (SAND_Y - w.y) / DateBowl.CM, w)
			if f.state == Flies.SIT:
				left[i] = [f.spot.node, p]
				sat_frames += 1
				var hit: Variant = fl.surface_at(fl._mesh_of(f.spot.node), p)
				var gap: float = 99.0 if hit == null else (p.y - (hit as Vector3).y) / DateBowl.CM
				if gap > HOVER:
					_note(bad, "hovering over a %s" % f.spot.kind, gap, p)
				elif gap < -SINK:
					_note(bad, "sunk into a %s" % f.spot.kind, -gap, p)
	print("watched ", frames, " fly-frames (", sat_frames, " sitting)")
	var fails := 0
	for k in bad:
		print("FAIL: %s: %d frames, worst %.2f cm" % [k, bad[k][0], bad[k][1]])
		fails += 1
	print("PASS" if fails == 0 else "FAILED %d" % fails)
	quit()


func _note(bad: Dictionary, k: String, cm: float, at: Vector3) -> void:
	if not bad.has(k):
		bad[k] = [0, 0.0, at]
	bad[k][0] += 1
	bad[k][1] = maxf(bad[k][1], cm)


## How deep (cm) the point is inside the nearest date in the bowl (its solid balls).
func _date_depth(bowl: DateBowl, w: Vector3, skip: Node3D) -> float:
	var c := bowl.global_transform.affine_inverse() * w / DateBowl.CM
	var deep := -1e9
	for d in bowl.dates:
		if d.node == skip:
			continue
		var lv := bowl.live(d)
		for b in bowl._balls(lv[0], lv[1], d.sph):
			deep = maxf(deep, float(b[1]) - c.distance_to(b[0]))
	return deep
