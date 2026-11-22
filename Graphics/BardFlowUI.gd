extends CanvasLayer

## Визуал «Потока Барда» (В.3–В.5 + Фикс А, вердикт спеца 09/10-ответы).
## Оркестратор: две вертикальные дорожки (BardLaneView) слева/справа от
## прицела — ноты летят сверху вниз 1.4 с; таймер Потока с числами под
## прицелом (min(fuel, max_duration), «ЛИМИТ», красный пульс ≤2 с, дельты);
## баннер причины выхода живёт 2.0 с ПОСЛЕ закрытия стойки; компакт-блок
## ЗАЩ/ОТР с процентами между дорожками; ромбы Tier. Слой ПОД HUD
## (4 < ActionBar 5), мышь — MOUSE_FILTER_IGNORE (НЕ окно — ССОТ
## ui_input_rules). Время нот — 1€-сглаженные часы conductor. Данные —
## сиблинг игрока BardFlowComponent + автолоады RhythmJudge/RhythmConductor.

const BardLaneView = preload("res://Graphics/BardLaneView.gd")
const OneEuroFilter = preload("res://Logic/OneEuroFilter.gd")

const COL_HARMONY := Color(0.2, 0.9, 1.0)   # бирюза: Нота Гармонии (ЛКМ)
const COL_CHORD := Color(1.0, 0.82, 0.28)   # золото: Ударный Аккорд (ПКМ)
const COL_T2 := Color(0.7, 0.35, 1.0)       # фиолет-неон: Tier 2
const COL_MISS := Color(1.0, 0.3, 0.25)
const COL_GAIN := Color(0.55, 0.95, 0.45)

const LANE_DX := 95.0          # В.3: дорожки x = center ± 95
const HIT_DY := 10.0           # y_hit = center.y + 10
const TIMER_DY := 46.0         # таймер под прицелом center + (0, +46)
const TIER_DY := -72.0         # ромбы Tier над прицелом
const STATUS_DY := -110.0      # компакт-блок ЗАЩ/ОТР над ромбами
const BANNER_DY := -150.0      # баннер причины выхода над прицелом
const BANNER_T := 2.0          # баннер живёт после закрытия стойки
const KEY_REFRESH_S := 0.5     # поллинг бейджей клавиш (авто при перебинде)

## Причины выхода → [текст, цвет] (В.4.2). max_duration — золотой,
## bard_drop — фиолетово-золотой.
const EXIT_BANNERS := {
	"fuel_out": ["ПОТОК СОРВАН (ритм потерян)", Color(1.0, 0.3, 0.25)],
	"barrier_break": ["КУПОЛ РАЗБИТ!", Color(1.0, 0.3, 0.25)],
	"max_duration": ["ПОТОК ЗАВЕРШЁН (14 с)", Color(1.0, 0.82, 0.28)],
	"bard_drop": ["ФИНАЛЬНЫЙ БАС-ДРОП!", Color(0.9, 0.62, 1.0)],
	"cancel": ["ПОТОК ОТМЕНЁН", Color(0.7, 0.7, 0.7)],
}

var _panel: Control
var _flow: Node = null
var _judge: Node = null
var _cond: Node = null
var _lane_l = null
var _lane_r = null
var _t_filter = OneEuroFilter.new()
var _smooth_t := 0.0
var _visible_flow := false
var _banner_left := 0.0        # остаток жизни баннера (после выхода)
var _banner_text := ""
var _banner_col := Color.WHITE
var _timer_pops: Array = []    # {text, col, t} — дельты у таймера
var _key_refresh := 0.0

func _ready() -> void:
	layer = 4  # под HUD (ActionBar layer 5)
	_flow = get_parent().get_node_or_null("BardFlowComponent")
	_judge = get_node_or_null("/root/RhythmJudge")
	_cond = get_node_or_null("/root/RhythmConductor")
	_panel = Control.new()
	_panel.name = "FlowLanes"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_on_draw)
	add_child(_panel)
	_lane_l = BardLaneView.new()
	_lane_l.set_lane("harmony", COL_HARMONY)
	_panel.add_child(_lane_l)
	_lane_r = BardLaneView.new()
	_lane_r.set_lane("chord", COL_CHORD)
	_panel.add_child(_lane_r)
	_panel.visible = false
	if _flow != null:
		_flow.fuel_delta.connect(_on_fuel_delta)
	if _judge != null:
		_judge.note_judged.connect(_on_note_judged)
		_judge.press_received.connect(_on_press)
		_judge.empty_press.connect(_on_empty)
	# Бейджи клавиш: при входе Потока + поллинг раз в 0.5 с (перебинд).
	call_deferred("_hook_stance")

func _exit_tree() -> void:
	if _flow != null and _flow.fuel_delta.is_connected(_on_fuel_delta):
		_flow.fuel_delta.disconnect(_on_fuel_delta)
	if _judge != null:
		if _judge.note_judged.is_connected(_on_note_judged):
			_judge.note_judged.disconnect(_on_note_judged)
		if _judge.press_received.is_connected(_on_press):
			_judge.press_received.disconnect(_on_press)
		if _judge.empty_press.is_connected(_on_empty):
			_judge.empty_press.disconnect(_on_empty)

func _hook_stance() -> void:
	var stance = get_parent().get_node_or_null("StanceComponent")
	if stance != null and not stance.stance_entered.is_connected(_on_stance_entered):
		stance.stance_entered.connect(_on_stance_entered)

func _on_stance_entered(_overrides: Dictionary, _sid: String) -> void:
	_refresh_key_labels()

func _refresh_key_labels() -> void:
	## Подписи текущей привязанной клавиши на бейджах дорожек (В.3): бинд
	## или default_slot под-приёма; при перебинде подхватывается поллингом.
	var bar = get_parent().get_node_or_null("ActionBar")
	if bar == null or not bar.has_method("get_stance_sub_slot_label"):
		return
	var fl = get_parent().get_node_or_null("BardFlowComponent")
	if fl == null:
		return
	_lane_l.set_key_label(str(bar.get_stance_sub_slot_label(
			fl.STANCE_SKILL_ID, "bard_note")))
	_lane_r.set_key_label(str(bar.get_stance_sub_slot_label(
			fl.STANCE_SKILL_ID, "bard_chord")))

func _on_fuel_delta(delta: float) -> void:
	## Дельта топлива у таймера (В.4.1): «+1.2с»/«−1.2с» всплывает 0.45 с.
	if not _visible_flow:
		return
	if _timer_pops.size() >= 4:
		_timer_pops.pop_front()
	_timer_pops.append({
		"text": "%+.1f с" % delta,
		"col": COL_GAIN if delta >= 0.0 else COL_MISS,
		"t": 0.0,
	})

func _on_note_judged(_id: int, verdict: String, kind: String) -> void:
	if not _visible_flow:
		return
	if kind == "harmony":
		_lane_l.on_judged(verdict, kind)
	elif kind == "chord":
		_lane_r.on_judged(verdict, kind)

func _on_press(kind: String) -> void:
	## Прожим рамки-мишени на каждое нажатие (Фикс А).
	if not _visible_flow:
		return
	if kind == "" or kind == "harmony":
		_lane_l.on_press()
	if kind == "" or kind == "chord":
		_lane_r.on_press()

func _on_empty(kind: String) -> void:
	if not _visible_flow:
		return
	if kind == "harmony":
		_lane_l.on_empty(kind)
	elif kind == "chord":
		_lane_r.on_empty(kind)

func _process(delta: float) -> void:
	var flowing: bool = _flow != null and _flow.is_flowing
	if flowing != _visible_flow:
		if _visible_flow and not flowing:
			# Выход из Потока: баннер причины живёт ПОСЛЕ закрытия стойки.
			var reason := "cancel"
			if "last_exit_reason" in _flow:
				reason = str(_flow.last_exit_reason)
			var entry: Array = EXIT_BANNERS.get(reason, EXIT_BANNERS["cancel"])
			var etext := str(entry[0])
			if reason == "max_duration" and "MAX_FLOW_DURATION" in _flow:
				# Лимит менялся (14 → 60 с, вердикт юзера 22.11.26) — текст
				# считаем из консты, а не хардкодим в EXIT_BANNERS.
				etext = "ПОТОК ЗАВЕРШЁН (%d с)" % int(round(float(_flow.MAX_FLOW_DURATION)))
			_show_banner(etext, entry[1])
		_visible_flow = flowing
		if flowing:
			_refresh_key_labels()
			_timer_pops.clear()
	_banner_left = maxf(0.0, _banner_left - delta)
	_panel.visible = flowing or _banner_left > 0.0
	if not _panel.visible:
		return
	var vp := _panel.get_viewport_rect().size
	var c := Vector2(vp.x * 0.5, vp.y * 0.5)
	if flowing:
		if _cond != null:
			_smooth_t = _t_filter.filter(float(_cond.song_time), delta)
		_lane_l.set_time(_smooth_t)
		_lane_r.set_time(_smooth_t)
		var y_hit := c.y + HIT_DY
		_lane_l.set_lane_pos(c.x - LANE_DX, y_hit)
		_lane_r.set_lane_pos(c.x + LANE_DX, y_hit)
		_key_refresh -= delta
		if _key_refresh <= 0.0:
			_key_refresh = KEY_REFRESH_S
			_refresh_key_labels()
	for p in _timer_pops:
		p["t"] = float(p["t"]) + delta
	_timer_pops = _timer_pops.filter(func(pp): return float(pp["t"]) < 0.45)
	_panel.queue_redraw()

func _show_banner(text: String, col: Color) -> void:
	_banner_text = text
	_banner_col = col
	_banner_left = BANNER_T

func _on_draw() -> void:
	if _flow == null:
		return
	var vp := _panel.get_viewport_rect().size
	var c := Vector2(vp.x * 0.5, vp.y * 0.5)
	var f := ThemeDB.fallback_font
	var tier: int = int(_flow.tier)
	var base := COL_HARMONY
	if tier >= 3:
		base = COL_CHORD
	elif tier == 2:
		base = COL_T2

	# ── Компакт-блок ЗАЩ/ОТР с процентами (В.5.3): center.y − 110 ──
	if f != null and _visible_flow and "DR" in _flow and tier < _flow.DR.size():
		var dr := int(round(float(_flow.DR[tier]) * 100.0))
		var rr := int(round(float(_flow.RR[tier]) * 100.0))
		# Плейтест-4 (22.11.26): 11px юзер не замечал — 16px, шаг строк 22,
		# ширина 90 (16px «ЗАЩ 50%» в 64 не влезает).
		_panel.draw_string(f, c + Vector2(-64.0, STATUS_DY), "ЗАЩ %d%%" % dr,
				HORIZONTAL_ALIGNMENT_LEFT, 90.0, 16, COL_HARMONY)
		_panel.draw_string(f, c + Vector2(-64.0, STATUS_DY + 22.0), "ОТР %d%%" % rr,
				HORIZONTAL_ALIGNMENT_LEFT, 90.0, 16, COL_CHORD)

	# ── Мини-индикатор Tier: 3 ромба над прицелом ──
	if _visible_flow:
		for i in 3:
			var filled: bool = i < tier
			var pc := base if filled else Color(1, 1, 1, 0.18)
			_diamond(c + Vector2((i - 1) * 18.0, TIER_DY), 5.0, pc)

	# ── Таймер Потока с числами (В.4.1): center + (0, +46) ──
	if f != null and _visible_flow:
		var fuel_left := float(_flow.fuel)
		var dur_left := 99.0
		if _flow.has_method("max_duration_left"):
			dur_left = float(_flow.max_duration_left())
		var left := minf(fuel_left, dur_left)
		var limited := fuel_left > dur_left + 0.01
		var tc := Color(1, 1, 1, 0.92)
		var tsize := 15
		if left <= 2.0:
			# Краснеет и пульсирует.
			var ph := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
			tc = Color(1.0, 0.3, 0.25, 0.7 + 0.3 * ph)
			tsize = 15 + int(round(2.0 * ph))
		var ttext := "%.1f с" % left
		if limited:
			ttext += "  ЛИМИТ"
			tc = Color(1.0, 0.85, 0.3, 0.95)
		# Плейтест-4 (22.11.26): было c + (-70, c.y + TIMER_DY) — center.y
		# прибавлялся ДВАЖДЫ, таймер рисовался ЗА нижним краем экрана
		# (юзер: «таймер не отображается не тикает»).
		_panel.draw_string(f, c + Vector2(-70.0, TIMER_DY), ttext,
				HORIZONTAL_ALIGNMENT_CENTER, 140.0, tsize, tc)
		# Дельты топлива: всплывают над таймером 0.45 с.
		for p in _timer_pops:
			var pt: float = float(p["t"]) / 0.45
			var pc2: Color = p["col"]
			pc2.a = 1.0 if pt < 0.7 else 1.0 - (pt - 0.7) / 0.3
			_panel.draw_string(f, c + Vector2(24.0, TIMER_DY - 14.0 - 20.0 * pt),
					str(p["text"]), HORIZONTAL_ALIGNMENT_LEFT, 70.0, 12, pc2)

	# ── Баннер причины выхода (В.4.2): живёт ПОСЛЕ закрытия стойки ──
	if _banner_left > 0.0 and f != null:
		var a := clampf(_banner_left / 0.4, 0.0, 1.0)
		var bcol := _banner_col
		bcol.a = a
		var w := f.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
		var bg := Rect2(c.x - w * 0.5 - 14.0, c.y + BANNER_DY - 24.0, w + 28.0, 34.0)
		var bgc := Color(0, 0, 0, 0.55 * a)
		_panel.draw_rect(bg, bgc)
		_panel.draw_string(f, Vector2(c.x - w * 0.5, c.y + BANNER_DY), _banner_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 21, bcol)

func _diamond(p: Vector2, r: float, col: Color) -> void:
	_panel.draw_colored_polygon(
			PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0),
			p + Vector2(0, r), p + Vector2(-r, 0)]), col)
