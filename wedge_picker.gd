class_name WedgePicker
extends Control
## Al-Khasm's strength, chosen by pressing one of three cuneiform wedges into
## the corner: one, two or three wedges, the way a scribe wrote 1, 2 and 3.
## Sits faint under the corner links like they do, and brightens under the mouse.

signal picked(level: int)

const WEDGE_W := 14.0      # width of a wedge's triangular head
const WEDGE_HEAD := 9.0    # its height
const WEDGE_LEN := 21.0    # head plus tail
const GAP := 7.0           # between wedges
const WORD_GAP := 14.0     # between the word and the first wedge

var names: Array = []
var level := 1
var word: Button           # the strength's name, styled like the corner links (set before adding)
var cream := Color(0.98, 0.9, 0.72)

var _hover := -1           # wedge under the mouse, or -1
var _inside := false


func _ready() -> void:
	if word != null:
		word.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the picker handles the mouse
		word.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		word.position = Vector2.ZERO
		word.size = Vector2(_wedge_x(0) - WORD_GAP, size.y)
		add_child(word)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_exited.connect(func() -> void:
		_inside = false
		_hover = -1
		queue_redraw())
	mouse_entered.connect(func() -> void:
		_inside = true
		queue_redraw())


## x of the left edge of wedge i (right-aligned to the control).
func _wedge_x(i: int) -> float:
	return size.x - (3 - i) * WEDGE_W - (2 - i) * GAP


func _wedge_at(x: float) -> int:
	for i in 3:
		var x0 := _wedge_x(i) - GAP / 2
		if x >= x0 and x < x0 + WEDGE_W + GAP:
			return i
	# anywhere on the word counts as the level it names: leave it as is
	return -1


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var h := _wedge_at(ev.position.x)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var i := _wedge_at(ev.position.x)
		if i != -1 and i != level:
			level = i
			picked.emit(level)
			queue_redraw()
		accept_event()


func _draw() -> void:
	var shown := _hover if _hover != -1 else level
	var bright := 0.95 if _inside else 0.5
	var shadow := Color(0.1, 0.05, 0.02, 0.6)
	var top := roundf((size.y - WEDGE_LEN) / 2)
	for i in 3:
		var a := bright if i <= shown else 0.28
		var pts := _wedge(_wedge_x(i), top)
		draw_colored_polygon(_shifted(pts, Vector2(0, 2)), Color(shadow, shadow.a * a / 0.95))
		draw_colored_polygon(pts, Color(cream, a))
	# the strength's name, to the left of the wedges: the links' own font_color, brighter while hovered
	if word != null and shown < names.size():
		word.text = names[shown]
		word.add_theme_color_override("font_color", Color(cream, bright))


## A vertical wedge as a stylus leaves it: a triangular head, a tapering tail.
func _wedge(x: float, y: float) -> PackedVector2Array:
	var c := x + WEDGE_W / 2
	return PackedVector2Array([
		Vector2(x, y),
		Vector2(x + WEDGE_W, y),
		Vector2(c + 2.2, y + WEDGE_HEAD),
		Vector2(c + 0.9, y + WEDGE_LEN),
		Vector2(c - 0.9, y + WEDGE_LEN),
		Vector2(c - 2.2, y + WEDGE_HEAD),
	])


func _shifted(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + d)
	return out
