extends SceneTree
# A die propped against another, mid-gather: when the hand lifts the die it leans on, the
# propped die must fall under gravity onto the tray floor (not hang in the air), then lie
# still and frozen again so the rest of the gathering treats it as a die on the table.
# Headless is fine.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.8).timeout
	m.epoch += 1                 # stop the game's own flow touching the dice
	m.phase = m.Phase.BUSY
	await physics_frame
	var bodies: Array = m.dice_bodies
	var a: RigidBody3D = bodies[0]   # the one that gets picked up
	var b: RigidBody3D = bodies[1]   # the one propped against it
	var txf: Transform3D = m.tray_xf()
	var tray: Rect2 = m.TRAY
	var base := a.global_transform
	# the other two well out of the way, in far corners of the tray
	var inset := 1.0
	for k in [2, 3]:
		var c := Vector2(tray.position.x + inset, tray.position.y + inset) if k == 2 \
				else Vector2(tray.end.x - inset, tray.end.y - inset)
		var p: Vector3 = txf * Vector3(c.x, 0.0, c.y)
		(bodies[k] as RigidBody3D).global_transform = Transform3D(base.basis, Vector3(p.x, base.origin.y, p.z))
	# the propped die: tilted, raised off the floor, beside `a` and as close as it can be
	# without overlapping it (as if leaning on it)
	var tilt := Basis(Vector3(1, 0, 0.3).normalized(), deg_to_rad(35.0)) * base.basis
	var dir := Vector3(1, 0, 0)
	var lift := 1.6 * UrHand.CM
	var shape: Shape3D = null
	for c in b.get_children():
		if c is CollisionShape3D:
			shape = c.shape
	var space := b.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.exclude = [b.get_rid()]
	var lo := 0.0
	var hi := 2.0
	for it in 30:
		var mid := (lo + hi) * 0.5
		q.transform = Transform3D(tilt, base.origin + dir * mid + Vector3(0, lift, 0))
		if space.intersect_shape(q, 4).any(func(r: Dictionary) -> bool: return r.collider == a):
			lo = mid
		else:
			hi = mid
	b.global_transform = Transform3D(tilt, base.origin + dir * (hi + 0.01) + Vector3(0, lift, 0))
	for k in 4:
		var bb: RigidBody3D = bodies[k]
		bb.linear_velocity = Vector3.ZERO
		bb.angular_velocity = Vector3.ZERO
		bb.freeze = true
	await physics_frame

	var g: DiceGrip = m.grip
	var h: UrHand = m.hands[0]
	h.visible = true
	h.global_position = a.global_position + Vector3(0, 1.5, 0)
	g.begin(h)
	var floor_y: float = g.floor_y
	var low0 := _lowest(b, g)
	print("propped die: lowest point %.2f cm above the tray floor" % ((low0 - floor_y) / UrHand.CM))
	# the hand picks up `a` and lifts it well clear
	g.carry(0)
	for f in 20:
		h.global_position += Vector3(0, 0.1, 0)
		g.sync()
		await physics_frame
	var t := 0.0
	while t < 2.0:
		await physics_frame
		t += 1.0 / 120.0
	var gap := (_lowest(b, g) - floor_y) / UrHand.CM
	print("after lifting the die it leaned on: lowest point %.2f cm above the floor, frozen=%s" % [gap, b.freeze])
	var ok := gap < 0.3 and b.freeze
	print("dice lean: ", "ok" if ok else "FAIL")
	g.end()
	quit(0 if ok else 1)


func _lowest(b: RigidBody3D, g: DiceGrip) -> float:
	var xf := b.global_transform
	var y := INF
	for s in g.samples:
		y = minf(y, (xf * (s * UrHand.CM)).y)
	return y
