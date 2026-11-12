class_name Ambience
extends Node
## The sounds that nothing on the board makes: the air of the place, and the two people
## sitting at the table.
##
## - The wind. A light breeze that never quite stops, gusts that come up and die away
##   (one with every cloud's edge, and smaller ones of their own accord), and in the
##   stronger gusts the hiss of sand on the move.
## - Cloth. A sleeve rustles as its arm moves, as loudly as the arm is fast; a robe
##   shifts as its wearer leans in to reach; a hem dragged over the sand hisses.
## - Skin. A hand coming to rest on the tray's rim or its leather floor pats it softly.
## - Al-Khasm, out of sight: he chews his dates, breathes out through his nose with his
##   mouth full, and sniffs now and then.
##
## All of it is quiet: it is there to be missed if it stopped, not to be listened to.
## (The sounds themselves are made by tools/make_sounds.py.)

# Loudness (dB) of each, at its loudest. The loops are stored at full scale.
const AIR_DB := -31.0          # the breeze that is always there
const AIR_GUST_DB := 3.0       # and how much it comes up in a gust
const GUST_DB := -20.0          # a full gust (a thick cloud's edge)
const SAND_DB := -26.0         # sand on the move in it
const RUB_DB := -20.0          # a sleeve, the arm at full speed
const DRAG_DB := -15.0         # a hem over sand, likewise
const CHEW_DB := 0.0           # (on top of the sound's own level in main.gd's SFX_DB)

const GUST_SAND := 0.5         # sand only moves in gusts stronger than this (0..1)
const ARM_FAST := 11.0         # (world/s) a quick reach: the sleeve at its loudest
const ARM_STILL := 0.6         # below this the cloth makes no sound (the hand's own small movements)
const HANG_CM := 7.0           # how far the loose sleeve hangs below a level forearm
const SAND := 0                # what ground() says lies under a point
const WOOD := 1
const LEATHER := 2

var play: Callable             # (name, at, vol_db, pitch_var): a one-shot sound somewhere on the table
var ground: Callable           # (world point) -> Vector2(height of what lies under it, which of the above)
var mouth := Vector3.ZERO      # where his mouth is

var air: AudioStreamPlayer
var gust_p: AudioStreamPlayer
var sand_p: AudioStreamPlayer
var gusts: Array = []          # the gusts blowing now: {t, rise, hold, fall, amp}
var gust_wait := 0.0           # seconds to the next one that comes of its own accord
var gust_level := 0.0          # how hard it is gusting now (0..1)
var wind_t := 0.0

var arms: Array = []           # one per hand: see add_hand

var chew_left := 0.0           # he has a date in his mouth for this much longer (s)
var chew_next := 0.0           # seconds to his next chew
var chew_bout := 0             # chews left before he pauses
var chew_period := 0.7
var chew_n := 0
var nose_in := INF             # seconds until he breathes out through his nose
var sniff_wait := 0.0          # and until he next sniffs


func _init(play_fn: Callable, ground_fn: Callable, mouth_at: Vector3) -> void:
	play = play_fn
	ground = ground_fn
	mouth = mouth_at


func _ready() -> void:
	air = _bed("wind_air")
	gust_p = _bed("wind_gust")
	sand_p = _bed("sand_drift")
	air.volume_db = AIR_DB
	air.play(randf() * 20.0)
	gust_wait = randf_range(8.0, 25.0)
	sniff_wait = randf_range(40.0, 120.0)


## A sound that goes round and round (the files are made to join end to beginning).
static func loop(name: String) -> AudioStream:
	var path := "res://assets/sfx/%s.wav" % name
	if not ResourceLoader.exists(path):
		return null
	var st: AudioStream = load(path)
	var w := st as AudioStreamWAV
	if w != null and w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		w.loop_begin = 0
		w.loop_end = int(round(w.get_length() * w.mix_rate))
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return st


func _bed(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = loop(name)
	p.volume_db = -80.0
	add_child(p)
	return p


## A hand whose sleeve is to be heard. `db`: louder or softer than the rest; `pats`: it
## can come to rest on the dice tray; `robe`: its owner's robe is heard shifting as it
## comes out (not the hand that only ever goes to the bowl at his side).
func add_hand(h: UrHand, db := 0.0, pats := false, robe := true) -> void:
	var a := {"hand": h, "db": db, "pats": pats, "robe": robe, "seen": false, "last": Vector3.ZERO,
		"speed": 0.0, "bump": 0.0, "cool": 0.0}
	for key in ["rub", "drag"]:
		var p := AudioStreamPlayer3D.new()
		p.stream = loop("cloth_rub" if key == "rub" else "sleeve_sand")
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.attenuation_filter_db = 0.0
		p.panning_strength = 0.6
		p.volume_db = -80.0
		add_child(p)
		a[key] = p
	arms.append(a)


## A gust: it comes up over `rise` seconds to `amp` (0..1), blows for `hold`, and dies
## away over `fall`.
func gust(amp: float, rise: float, hold: float, fall: float) -> void:
	gusts.append({"t": 0.0, "rise": rise, "hold": hold, "fall": fall, "amp": clampf(amp, 0.0, 1.0)})


## He has just put a date in his mouth, and will have it there for `dur` seconds.
func chew(dur: float) -> void:
	if dur < 3.0:
		return
	chew_left = dur
	chew_next = randf_range(0.5, 0.9)
	chew_bout = randi_range(5, 9)
	chew_period = randf_range(0.62, 0.76)
	chew_n = 0


func _process(delta: float) -> void:
	_wind(delta)
	for a in arms:
		_arm(a, delta)
	_mouth(delta)


# ---------------------------------------------------------------- wind

func _wind(delta: float) -> void:
	wind_t += delta
	gust_wait -= delta
	if gust_wait <= 0.0:
		gust_wait = randf_range(14.0, 50.0)
		gust(randf_range(0.2, 0.55), randf_range(1.5, 3.0), randf_range(0.5, 3.0), randf_range(3.0, 7.0))
	# gusts on top of one another do not add up: each fills some of what is left
	var calm := 1.0
	for i in range(gusts.size() - 1, -1, -1):
		var g: Dictionary = gusts[i]
		g.t += delta
		var t: float = g.t
		var k := 0.0
		if t < g.rise:
			k = smoothstep(0.0, 1.0, t / g.rise)
		elif t < g.rise + g.hold:
			k = 1.0
		elif t < g.rise + g.hold + g.fall:
			k = 1.0 - smoothstep(0.0, 1.0, (t - g.rise - g.hold) / g.fall)
		else:
			gusts.remove_at(i)
			continue
		calm *= 1.0 - k * float(g.amp)
	gust_level = 1.0 - calm
	# the breeze itself wanders a little, over minutes
	var wander := 1.6 * sin(wind_t * 0.043) + 1.1 * sin(wind_t * 0.117 + 1.3)
	air.volume_db = AIR_DB + wander + AIR_GUST_DB * gust_level
	_level(gust_p, GUST_DB, pow(gust_level, 1.6))
	gust_p.pitch_scale = 0.93 + 0.12 * gust_level      # a harder blow is a brighter one
	_level(sand_p, SAND_DB, pow(smoothstep(GUST_SAND, 1.0, gust_level), 2.0))


## Play a loop at `lin` (0..1) of its full loudness `db`; silent, it is stopped.
func _level(p: Node, db: float, lin: float, rate := 0.0, delta := 0.0) -> void:
	if p.stream == null:
		return
	if lin < 0.003:
		if p.playing and p.volume_db < -55.0:
			p.stop()
		p.volume_db = maxf(p.volume_db - 240.0 * maxf(delta, 0.016), -80.0)
		return
	var to := db + linear_to_db(lin)
	if not p.playing:
		p.volume_db = -60.0
		p.play(randf() * maxf(p.stream.get_length() - 0.1, 0.0))
	p.volume_db = to if rate <= 0.0 else lerpf(maxf(p.volume_db, -60.0), to, 1.0 - exp(-rate * delta))


# ---------------------------------------------------------------- cloth and skin

func _arm(a: Dictionary, delta: float) -> void:
	var h: UrHand = a.hand
	var rub: AudioStreamPlayer3D = a.rub
	var drag: AudioStreamPlayer3D = a.drag
	if not h.visible or delta <= 0.0:
		a.seen = false
		a.speed = 0.0
		_level(rub, 0.0, 0.0, 0.0, delta)
		_level(drag, 0.0, 0.0, 0.0, delta)
		return
	var w := h.global_position
	if not a.seen:
		a.seen = true
		a.last = w
		a.bump = h.bump.length()
		# he leans in and his arm comes out: the robe shifts on him
		if a.robe:
			play.call("cloth_move", h.shoulder.lerp(w, 0.5), float(a.db) + randf_range(-4.0, 0.0), 0.1)
	var step: Vector3 = w - a.last
	a.last = w
	var v := step / delta
	if step.length() > 3.0:        # put somewhere else, not moved there
		v = Vector3.ZERO
	a.speed = lerpf(a.speed, v.length(), 1.0 - exp(-14.0 * delta))
	var fast := clampf((float(a.speed) - ARM_STILL) / (ARM_FAST - ARM_STILL), 0.0, 1.0)
	# the loose cloth under the forearm: where it lies on something and is pulled along,
	# it rubs on it (on wood and leather that is one more soft rustle; on sand, a hiss)
	var along := h.elbow - w
	var touch := 0.0
	var kind := SAND
	if along.length() > 0.01:
		var dir := along.normalized()
		var hang := HANG_CM * UrHand.CM * (1.0 - absf(dir.y))
		for cm in [7.0, 13.0, 19.0]:
			var p: Vector3 = w + dir * (cm * UrHand.CM)
			var g: Vector2 = ground.call(p)
			# (its folds hang unevenly: it starts to brush a couple of centimetres before it lies)
			var t := clampf(1.0 - (p.y - hang - g.x) / (2.5 * UrHand.CM), 0.0, 1.0)
			if t > touch:
				touch = t
				kind = int(g.y)
	var pull := touch * clampf(Vector2(v.x, v.z).length() / 9.0, 0.0, 1.0)
	var rustle := pow(fast, 1.2)
	if kind != SAND:
		rustle = maxf(rustle, pull)
	var at := w.lerp(h.elbow, 0.6)
	rub.position = at
	drag.position = at
	_level(rub, RUB_DB + float(a.db), rustle, 16.0, delta)
	rub.pitch_scale = 0.9 + 0.22 * fast
	_level(drag, DRAG_DB + float(a.db), pull if kind == SAND else 0.0, 16.0, delta)
	drag.pitch_scale = 0.92 + 0.16 * clampf(pull, 0.0, 1.0)
	# skin: the hand comes down on the tray (it is solid to it) with a soft pat, harder
	# the faster it came
	if a.pats:
		a.cool = float(a.cool) - delta
		var b := h.bump.length()
		# (coming down onto it: brushing past the rim sideways makes no sound to speak of)
		if b > 0.012 and float(a.bump) <= 0.012 and float(a.cool) <= 0.0 and v.length() > 0.4 and h.bump.y > 0.6 * b:
			var tip := h.grip_world()
			var under: Vector2 = ground.call(tip)
			play.call("hand_leather" if int(under.y) == LEATHER else "hand_wood", tip,
				linear_to_db(clampf(v.length() / 8.0, 0.18, 1.0)), 0.08)
			a.cool = 0.4
		a.bump = b


# ---------------------------------------------------------------- his mouth

func _mouth(delta: float) -> void:
	if chew_left > 0.0:
		chew_left -= delta
		chew_next -= delta
		if chew_left <= 0.0:
			# done: often a breath, or a sniff, once the stone is out of his mouth
			if randf() < 0.5:
				sniff_wait = minf(sniff_wait, randf_range(2.5, 7.0))
		elif chew_left > 1.6 and chew_next <= 0.0:     # (the last moments he is working the stone to his lips)
			# a date softens as it is chewed: each chew a little quieter than the last
			play.call("chew", mouth, CHEW_DB - minf(0.45 * chew_n, 7.0) - randf() * 3.0, 0.07)
			chew_n += 1
			chew_bout -= 1
			if chew_bout > 0:
				chew_next = chew_period * randf_range(0.88, 1.14)
			else:
				# a pause: he shifts it in his mouth, and breathes
				chew_next = randf_range(0.9, 2.4)
				chew_bout = randi_range(3, 8)
				chew_period *= randf_range(1.0, 1.08)
				if randf() < 0.35:
					nose_in = randf_range(0.15, 0.5)
	nose_in -= delta
	if nose_in <= 0.0:
		nose_in = INF
		play.call("nose_out", mouth, randf_range(-3.0, 0.0), 0.06)
	sniff_wait -= delta
	if sniff_wait <= 0.0:
		sniff_wait = randf_range(45.0, 150.0)
		if chew_left <= 0.0:
			play.call("sniff" if randf() < 0.65 else "nose_out", mouth, randf_range(-4.0, 0.0), 0.06)
