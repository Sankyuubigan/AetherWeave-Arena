extends CanvasLayer

## Визуал «Потока Гармонии» (Q16 Шаг 7): две симметричные дуги слева/справа
## от прицела (к ним летят ноты), дуга топлива («дышит» от попаданий), тонкое
## кольцо барьера купола, мини-индикатор Tier, шкалы Защита/Отражение над
## дугами, вспышки вердиктов. Слой ПОД HUD (4 < ActionBar 5), мышь —
## MOUSE_FILTER_IGNORE (НЕ окно, захват не блокируем — ССОТ ui_input_rules).
## Время нот — 1€-сглаженные часы conductor. Данные — сиблинг игрока
## BardFlowComponent + автолоады RhythmJudge/RhythmConductor.

const OneEuroFilter = preload("res://Logic/OneEuroFilter.gd")

const COL_HARMONY := Color(0.2, 0.9, 1.0)   # бирюза: Ноты Гармонии (ЛКМ)
const COL_CHORD := Color(1.0, 0.82, 0.28)   # золото: Ударный Аккорд (ПКМ)
const COL_T2 := Color(0.7, 0.35, 1.0)       # фиолет-неон: Tier 2
const COL_MISS := Color(1.0, 0.3, 0.25)
const LANE_SPEED := 420.0    # px/с: скорость ноты вдоль дорожки
const NOTE_WINDOW := 2.0     # с: горизонт нот на дорожке
const ARC_DX := 96.0         # отступ дуг от центра экрана
const ARC_R := 26.0

var _panel: Control
var _flow: Node = null
var _judge: Node = null
var _cond: Node = null
var _t_filter = OneEuroFilter.new()
var _smooth_t := 0.0
var _pulse := 0.0            # «дыхание» от попаданий (сигналы flow)
var _flash_miss := 0.0
var _flash_perfect := 0.0
var _visible_flow := false

func _ready() -> void:
	layer = 4  # под HUD (ActionBar layer 5)
	_flow = get_parent().get_node_or_null("BardFlowComponent")
	_judge = get_node_or_null("/root/RhythmJudge")
	_cond = get_node_or_null("/root/RhythmConductor")
	_panel = Control.new()
	_panel.name = "FlowArcs"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_on_draw)
	add_child(_panel)
	_panel.visible = false
	if _flow != null:
		_flow.fuel_changed.connect(_on_flow_signal)
		_flow.barrier_changed.connect(_on_flow_signal)
		_flow.flow_tier_changed.connect(_on_flow_signal)
	if _judge != null:
		_judge.note_judged.connect(_on_note_judged)

func _exit_tree() -> void:
	if _flow != null:
		if _flow.fuel_changed.is_connected(_on_flow_signal):
			_flow.fuel_changed.disconnect(_on_flow_signal)
		if _flow.barrier_changed.is_connected(_on_flow_signal):
			_flow.barrier_changed.disconnect(_on_flow_signal)
		if _flow.flow_tier_changed.is_connected(_on_flow_signal):
			_flow.flow_tier_changed.disconnect(_on_flow_signal)
	if _judge != null and _judge.note_judged.is_connected(_on_note_judged):
		_judge.note_judged.disconnect(_on_note_judged)

func _on_flow_signal(_v) -> void:
	_pulse = 1.0

func _on_note_judged(_id: int, verdict: String) -> void:
	if verdict == "miss":
		_flash_miss = 1.0
	elif verdict == "perfect":
		_flash_perfect = 1.0

func _process(delta: float) -> void:
	var flowing: bool = _flow != null and _flow.is_flowing
	if flowing != _visible_flow:
		_visible_flow = flowing
		_panel.visible = flowing
		if not flowing:
			return
	if not flowing:
		return
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	_flash_miss = maxf(0.0, _flash_miss - delta * 3.0)
	_flash_perfect = maxf(0.0, _flash_perfect - delta * 3.0)
	if _cond != null:
		_smooth_t = _t_filter.filter(float(_cond.song_time), delta)
	_panel.queue_redraw()

func _on_draw() -> void:
	if _flow == null:
		return
	var vp := _panel.get_viewport_rect().size
	var c := Vector2(vp.x * 0.5, vp.y * 0.5)
	var tier: int = int(_flow.tier)
	# Цвет базы по tier: T0–1 бирюза → T2 фиолет → T3 золото.
	var base := COL_HARMONY
	if tier >= 3:
		base = COL_CHORD
	elif tier == 2:
		base = COL_T2
	var breath := 1.0 + 0.04 * sin(Time.get_ticks_msec() * 0.006) + _pulse * 0.18

	# ── Дуга топлива вокруг прицела (светится, «дышит» от попаданий) ──
	var cap := 14.0
	if "FUEL_CAP" in _flow:
		cap = float(_flow.FUEL_CAP)
	var fuel := clampf(float(_flow.fuel) / cap, 0.0, 1.0)
	var r_fuel := 44.0 * breath
	var fuel_col := base
	fuel_col.a = clampf(0.55 + _pulse * 0.45, 0.0, 1.0)
	_arc(c, r_fuel, 135.0, 135.0 + 270.0 * fuel, fuel_col, 3.5)

	# ── Тонкое кольцо барьера купола (внутри дуги топлива) ──
	var bmax := 120.0
	if "BARRIER_MAX" in _flow:
		bmax = float(_flow.BARRIER_MAX)
	var bar := clampf(float(_flow.barrier) / bmax, 0.0, 1.0)
	var bcol := COL_CHORD
	if bar < 0.25:
		bcol = COL_MISS
	elif bar < 0.5:
		bcol = Color(1.0, 0.55, 0.2)
	bcol.a = 0.8
	_arc(c, 34.0, 135.0, 135.0 + 270.0 * bar, bcol, 2.0)

	# ── Две симметричные дуги-«скобки» слева/справа от прицела ──
	var arc_l := Vector2(c.x - ARC_DX, c.y)
	var arc_r := Vector2(c.x + ARC_DX, c.y)
	_arc(arc_l, ARC_R, -55.0, 55.0, base, 3.0)
	_arc(arc_r, ARC_R, 125.0, 235.0, COL_CHORD, 3.0)

	# ── Летящие ноты: бирюза слева (ЛКМ), золото справа (ПКМ) ──
	if _judge != null:
		for n in _judge.get_notes():
			var nt: float = float(n["time"])
			var dt := nt - _smooth_t
			if n["judged"] or dt < -0.05 or dt > NOTE_WINDOW:
				continue
			var col: Color = COL_HARMONY if n["kind"] == "harmony" else COL_CHORD
			var nr := 5.5 if n["kind"] == "harmony" else 8.0
			if n["kind"] == "harmony":
				var p := Vector2(arc_l.x - dt * LANE_SPEED, arc_l.y)
				if p.x > 4.0:
					_note(p, nr, col)
			else:
				var p2 := Vector2(arc_r.x + dt * LANE_SPEED, arc_r.y)
				if p2.x < vp.x - 4.0:
					_note(p2, nr, col)

	# ── Мини-индикатор Tier: 3 ромба над прицелом ──
	for i in 3:
		var filled := i < tier
		var pc := base if filled else Color(1, 1, 1, 0.18)
		_diamond(Vector2(c.x + (i - 1) * 18.0, c.y - 72.0), 5.0, pc)

	# ── Шкалы Защита/Отражение над дугами ──
	var dr := 0.0
	var rr := 0.0
	if "DR" in _flow and tier < _flow.DR.size():
		dr = float(_flow.DR[tier])
	if "RR" in _flow and tier < _flow.RR.size():
		rr = float(_flow.RR[tier])
	_scale(arc_l + Vector2(0, -46), dr / 0.5, "ЗАЩ", base)
	_scale(arc_r + Vector2(0, -46), rr / 0.6, "ОТР", COL_CHORD)

	# ── Вспышки вердиктов вокруг прицела ──
	if _flash_perfect > 0.0:
		var fc := COL_CHORD
		fc.a = _flash_perfect * 0.7
		_arc(c, 52.0, 0.0, 360.0, fc, 2.0)
	if _flash_miss > 0.0:
		var mc := COL_MISS
		mc.a = _flash_miss * 0.8
		_arc(c, 52.0, 0.0, 360.0, mc, 2.5)

func _arc(center: Vector2, radius: float, from_deg: float, to_deg: float,
		col: Color, width: float) -> void:
	_panel.draw_arc(center, radius, deg_to_rad(from_deg), deg_to_rad(to_deg),
			48, col, width, true)

func _note(p: Vector2, r: float, col: Color) -> void:
	var glow := col
	glow.a = 0.25
	_panel.draw_circle(p, r + 4.0, glow)   # ореол
	_panel.draw_circle(p, r, col)

func _diamond(p: Vector2, r: float, col: Color) -> void:
	_panel.draw_colored_polygon(
			PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0),
			p + Vector2(0, r), p + Vector2(-r, 0)]), col)

func _scale(p: Vector2, frac: float, label: String, col: Color) -> void:
	# Шкала 70×5: тёмная подложка + цветная заливка + подпись.
	var bg := Color(0, 0, 0, 0.45)
	_panel.draw_rect(Rect2(p - Vector2(35, 2.5), Vector2(70, 5)), bg)
	var w := clampf(frac, 0.0, 1.0) * 70.0
	_panel.draw_rect(Rect2(p - Vector2(35, 2.5), Vector2(w, 5)), col)
	var f := ThemeDB.fallback_font
	if f != null:
		_panel.draw_string(f, p + Vector2(-35, -8), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.75))
