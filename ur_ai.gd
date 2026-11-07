class_name UrAI
extends RefCounted
## Expectimax AI: searches a few plies, weighting dice outcomes by probability.

const PROBS := [1.0 / 16, 4.0 / 16, 6.0 / 16, 4.0 / 16, 1.0 / 16]
const WIN := 10000.0


static func choose_move(g: UrGame, roll: int, depth: int = 3) -> int:
	var me := g.current
	var best := -1
	var best_val := -INF
	for src in g.legal_moves(me, roll):
		var n := g.clone()
		var r := n.apply_move(me, src, roll)
		var v := _after_move(n, me, me, r.extra_turn, depth)
		if v > best_val:
			best_val = v
			best = src
	return best


static func _after_move(n: UrGame, me: int, mover: int, extra: bool, depth: int) -> float:
	if n.has_won(mover):
		return WIN if mover == me else -WIN
	n.current = mover if extra else 1 - mover
	return _chance(n, me, depth)


static func _chance(g: UrGame, me: int, depth: int) -> float:
	if depth <= 0:
		return _evaluate(g, me)
	var mover := g.current
	var total := 0.0
	for roll in 5:
		var moves := g.legal_moves(mover, roll)
		var v: float
		if moves.is_empty():
			var n := g.clone()
			n.current = 1 - mover
			v = _chance(n, me, depth - 1)
		else:
			var maximize := mover == me
			v = -INF if maximize else INF
			for src in moves:
				var n := g.clone()
				var r := n.apply_move(mover, src, roll)
				var mv := _after_move(n, me, mover, r.extra_turn, depth - 1)
				v = maxf(v, mv) if maximize else minf(v, mv)
		total += PROBS[roll] * v
	return total


static func _score(g: UrGame, p: int) -> float:
	var s := 0.0
	for x in g.pos[p]:
		s += x
		if x == UrGame.FINISH:
			s += 4.0
		elif x == UrGame.SAFE_ROSETTE:
			s += 3.0
	return s


static func _evaluate(g: UrGame, me: int) -> float:
	return _score(g, me) - _score(g, 1 - me)
