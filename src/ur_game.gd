class_name UrGame
extends RefCounted
## Pure rules engine for the Royal Game of Ur (Finkel rules).
##
## Each player has 7 pieces. A piece's position along its own path is:
##   0      = waiting off the board
##   1..4   = player's private lane
##   5..12  = shared middle lane (captures happen here)
##   13..14 = player's private lane
##   15     = borne off (finished)
## Rosettes at path positions 4, 8 and 14 grant an extra turn.
## The rosette at 8 is a safe square: it cannot be captured there.

const PIECES := 7
const FINISH := 15
const ROSETTES := [4, 8, 14]
const SAFE_ROSETTE := 8
const SHARED_FIRST := 5
const SHARED_LAST := 12

var pos: Array = [[], []]
var current := 0


func _init() -> void:
	for p in 2:
		var a: Array = []
		a.resize(PIECES)
		a.fill(0)
		pos[p] = a


func clone() -> UrGame:
	var g := UrGame.new()
	g.pos = [pos[0].duplicate(), pos[1].duplicate()]
	g.current = current
	return g


func finished_count(p: int) -> int:
	return pos[p].count(FINISH)


func has_won(p: int) -> bool:
	return finished_count(p) == PIECES


func can_move(p: int, src: int, roll: int) -> bool:
	var dst := src + roll
	if roll == 0 or dst > FINISH:
		return false
	if dst == FINISH:
		return true # exact roll bears off
	if pos[p].has(dst):
		return false
	if dst == SAFE_ROSETTE and pos[1 - p].has(dst):
		return false
	return true


## Distinct source positions (path indices) the player may move from.
func legal_moves(p: int, roll: int) -> Array:
	var moves: Array = []
	var seen := {}
	for src in pos[p]:
		if src == FINISH or seen.has(src):
			continue
		seen[src] = true
		if can_move(p, src, roll):
			moves.append(src)
	return moves


## idx optionally names which piece (index into pos[p]) moves; default is the
## first piece standing on src.
func apply_move(p: int, src: int, roll: int, idx: int = -1) -> Dictionary:
	var dst := src + roll
	if idx == -1:
		idx = pos[p].find(src)
	pos[p][idx] = dst
	var captured := false
	if dst >= SHARED_FIRST and dst <= SHARED_LAST:
		var o: int = pos[1 - p].find(dst)
		if o != -1:
			pos[1 - p][o] = 0
			captured = true
	return {"to": dst, "captured": captured, "extra_turn": dst in ROSETTES}
