extends SceneTree
# Headless self-play: AI vs random, checks invariants and win rate.

func _init() -> void:
	var ai_wins := 0
	var games := 20
	for i in games:
		var g := UrGame.new()
		var turns := 0
		while not (g.has_won(0) or g.has_won(1)) and turns < 5000:
			turns += 1
			var roll := 0
			for d in 4:
				roll += randi() % 2
			var moves := g.legal_moves(g.current, roll)
			if moves.is_empty():
				g.current = 1 - g.current
				continue
			var src: int = UrAI.choose_move(g, roll, 2) if g.current == 1 else moves[randi() % moves.size()]
			var p := g.current
			var r := g.apply_move(p, src, roll)
			for q in 2:
				var seen := {}
				for x in g.pos[q]:
					if x > 0 and x < 15:
						assert(not seen.has(x), "stacked pieces")
						seen[x] = true
			if not r.extra_turn:
				g.current = 1 - p
		assert(turns < 5000, "game did not end")
		if g.has_won(1):
			ai_wins += 1
	print("AI won %d/%d vs random" % [ai_wins, games])
	quit()
