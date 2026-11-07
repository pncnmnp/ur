extends SceneTree
# A die still sliding slowly after the call time is stopped where it is and read as it lies.
func _init() -> void:
	var m = load("res://main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m.phase = m.Phase.ROLL
	m._on_roll_pressed()
	while m.roll < 0:
		await physics_frame
	m.epoch += 1   # stop the game flow (e.g. the AI's turn) from touching the dice
	# simulate a slow creeper late in a throw
	m.rolling = true
	m.throw_time = m.DICE_CALL_TIME - 0.05
	var b: RigidBody3D = m.dice_bodies[0]
	b.freeze = false
	b.linear_velocity = Vector3(0.6, 0, 0)
	var before := b.global_position
	var frames := 0
	while m.rolling and frames < 240:
		await physics_frame
		frames += 1
	print("called after %.2fs, die slid %.3f before stopping, frozen=%s, still rolling=%s" % [frames / 120.0, b.global_position.distance_to(before), b.freeze, m.rolling])
	assert(not m.rolling and frames < 120)
	print("OK")
	quit()
