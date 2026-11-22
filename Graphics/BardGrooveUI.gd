extends CanvasLayer

## HUD «Пульса Битвы» (спец 11-ответ Блок 3 п.3): МИНИМАЛИСТИЧНЫЙ — никаких
## падающих дорожек. Вокруг прицела: два тонких сходящихся полукольца-пульса
## (r 44→16 px, доля бита по часам conductor) — метроном бокового зрения;
## дуга шкалы Грува 0–100% с крупной цифрой %, мелкий остаток лимита 16 с,
## 3 ромба Tier, компакт-блок ЗАЩ/ОТР. Попапы «В БИТ! +18%»/«+10%» +
## золотая вспышка прицела от groove_hit; баннер причины выхода живёт 2.0 с
## ПОСЛЕ закрытия стойки. Слой 4 (под HUD ActionBar=5), MOUSE_FILTER_IGNORE —
## неинтерактивный оверлей (ССОТ docs/ui_input_rules.md).

const COL_T0 := Color(0.2, 0.9, 1.0)    # Tier 0–1: бирюза
const COL_T2 := Color(0.72, 0.3, 1.0)   # Tier 2: фиолет-неон
const COL_T3 := Color(1.0, 0.8, 0.25)   # ОВЕРДРАЙВ (T3): золото
const COL_MISS := Color(1.0, 0.3, 0.25)
const COL_GAIN := Color(0.55, 0.95, 0.45)

const PULSE_R0 := 44.0    # радиус полуколец в начале доли
const PULSE_R1 := 16.0    # радиус на бите (кольца схлопнулись у прицела)
const GROOVE_R := 56.0    # дуга шкалы Грува вокруг прицела
const GROOVE_DY := 46.0   # крупная цифра % под прицелом
const LIMIT_DY := 68.0    # мелкий остаток лимита под цифрой
const TIER_DY := -72.0    # ромбы Tier над прицелом
const STATUS_DY := -110.0 # компакт-блок ЗАЩ/ОТР над ромбами
const BANNER_DY := -150.0 # баннер причины выхода над прицелом
const BANNER_T := 2.0     # баннер живёт после закрытия стойки (В.4.2)
const FLASH_T := 0.14     # золотая вспышка прицела на perfect/good
const POP_T := 0.55       # жизнь попапа вердикта

## Причины выхода → [текст, цвет] (ТЗ Блок 3 п.3). max_duration строится
## из консты MAX_DURATION (лимит может правиться — как у Потока).
const EXIT_BANNERS := {
    "groove_empty": ["ГРУВ УГАС (0%)", Color(1.0, 0.3, 0.25)],
    "barrier_break": ["КУПОЛ РАЗБИТ!", Color(1.0, 0.3, 0.25)],
    "max_duration": ["ПУЛЬС ЗАВЕРШЁН", Color(1.0, 0.82, 0.28)],
    "crescendo": ["КРЕЩЕНДО!", Color(1.0, 0.85, 0.4)],
    "cancel": ["ОТМЕНА", Color(0.7, 0.7, 0.7)],
}

var _panel: Control
var _groove: Node = null
var _cond: Node = null
var _active := false
var _banner_left := 0.0
var _banner_text := ""
var _banner_col := Color.WHITE
var _flash_left := 0.0
var _pops: Array = []     # {text, col, t} — вердикты у прицела

func _ready() -> void:
    layer = 4  # под HUD (ActionBar layer 5)
    _groove = get_parent().get_node_or_null("BardGrooveComponent")
    _cond = get_node_or_null("/root/RhythmConductor")
    _panel = Control.new()
    _panel.name = "GrooveHUD"
    _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _panel.draw.connect(_on_draw)
    add_child(_panel)
    _panel.visible = false
    if _groove != null and _groove.groove_hit.is_connected(_on_groove_hit) == false:
        _groove.groove_hit.connect(_on_groove_hit)

func _exit_tree() -> void:
    if _groove != null and _groove.groove_hit.is_connected(_on_groove_hit):
        _groove.groove_hit.disconnect(_on_groove_hit)

func _on_groove_hit(verdict: String, _source: String, delta: float) -> void:
    ## Попапы вердиктов + золотая вспышка прицела (ТЗ Блок 3 п.3).
    if not _active:
        return
    if _pops.size() >= 4:
        _pops.pop_front()
    if verdict == "perfect":
        _pops.append({"text": "В БИТ! +%d%%" % int(round(delta)), "col": COL_T3, "t": 0.0})
        _flash_left = FLASH_T
    elif verdict == "good":
        _pops.append({"text": "+%d%%" % int(round(delta)), "col": COL_GAIN, "t": 0.0})
        _flash_left = FLASH_T
    else:  # offbeat_spam: мягкий штраф −6 + красный попап
        _pops.append({"text": "%d%%" % int(round(delta)), "col": COL_MISS, "t": 0.0})

func _process(delta: float) -> void:
    var active: bool = _groove != null and bool(_groove.is_active)
    if active != _active:
        if _active and not active:
            # Выход из стойки: баннер причины живёт ПОСЛЕ закрытия (В.4.2).
            var reason := "cancel"
            if "last_exit_reason" in _groove:
                reason = str(_groove.last_exit_reason)
            var entry: Array = EXIT_BANNERS.get(reason, EXIT_BANNERS["cancel"])
            var etext := str(entry[0])
            if reason == "max_duration" and "MAX_DURATION" in _groove:
                etext = "ПУЛЬС ЗАВЕРШЁН (%d с)" % int(round(float(_groove.MAX_DURATION)))
            _show_banner(etext, entry[1])
            _pops.clear()
        _active = active
    _banner_left = maxf(0.0, _banner_left - delta)
    _flash_left = maxf(0.0, _flash_left - delta)
    _panel.visible = _active or _banner_left > 0.0
    if not _panel.visible:
        return
    for p in _pops:
        p["t"] = float(p["t"]) + delta
    _pops = _pops.filter(func(pp): return float(pp["t"]) < POP_T)
    _panel.queue_redraw()

func _show_banner(text: String, col: Color) -> void:
    _banner_text = text
    _banner_col = col
    _banner_left = BANNER_T

func _on_draw() -> void:
    var vp := _panel.get_viewport_rect().size
    var c := Vector2(vp.x * 0.5, vp.y * 0.5)
    var f := ThemeDB.fallback_font
    var tier := 0
    var groove := 0.0
    var dur_left := 0.0
    if _groove != null:
        tier = int(_groove.tier)
        groove = float(_groove.groove)
        if _groove.has_method("max_duration_left"):
            dur_left = float(_groove.max_duration_left())
    var base := COL_T0
    if tier >= 3:
        base = COL_T3
    elif tier == 2:
        base = COL_T2

    if _active:
        # ── Два сходящихся полукольца-пульса: доля бита 0→1, r 44→16 ──
        if _cond != null:
            var fl := _fraction_len()
            if fl > 0.0:
                var ph := clampf(fposmod(float(_cond.filtered_time), fl) / fl, 0.0, 1.0)
                var pr := lerpf(PULSE_R0, PULSE_R1, ph)
                var pc := Color(base.r, base.g, base.b, 0.18 + 0.62 * ph)
                _panel.draw_arc(c, pr, PI + 0.06, TAU - 0.06, 36, pc, 2.0, true)
                _panel.draw_arc(c, pr, 0.06, PI - 0.06, 36, pc, 2.0, true)
        # ── Дуга шкалы Грува (фон-остаток тусклый, заполнение по tier) ──
        var span := TAU * clampf(groove, 0.0, 100.0) / 100.0
        _panel.draw_arc(c, GROOVE_R, -PI / 2.0 + span, -PI / 2.0 + TAU, 64,
                Color(1, 1, 1, 0.08), 3.5, true)
        if span > 0.01:
            var gc := Color(base.r, base.g, base.b, 0.9)
            _panel.draw_arc(c, GROOVE_R, -PI / 2.0, -PI / 2.0 + span, 64, gc, 3.5, true)
        # ── Крупная цифра % + мелкий остаток лимита 16 с ──
        var tcol := Color(1, 1, 1, 0.92)
        if tier >= 3:
            tcol = COL_T3
        _panel.draw_string(f, c + Vector2(-70.0, GROOVE_DY), "%d%%" % int(round(groove)),
                HORIZONTAL_ALIGNMENT_CENTER, 140.0, 20, tcol)
        _panel.draw_string(f, c + Vector2(-70.0, LIMIT_DY), "%.1f с" % dur_left,
                HORIZONTAL_ALIGNMENT_CENTER, 140.0, 13, Color(1, 1, 1, 0.6))
        # ── Компакт-блок ЗАЩ/ОТР (16px, плейтест-4: 11px юзер не замечал) ──
        if f != null and "DR" in _groove and tier < int(_groove.DR.size()):
            var dr := int(round(float(_groove.DR[tier]) * 100.0))
            var rr := int(round(float(_groove.RR[tier]) * 100.0))
            _panel.draw_string(f, c + Vector2(-64.0, STATUS_DY), "ЗАЩ %d%%" % dr,
                    HORIZONTAL_ALIGNMENT_LEFT, 90.0, 16, COL_T0)
            _panel.draw_string(f, c + Vector2(-64.0, STATUS_DY + 22.0), "ОТР %d%%" % rr,
                    HORIZONTAL_ALIGNMENT_LEFT, 90.0, 16, COL_T3)
        # ── 3 ромба Tier над прицелом ──
        for i in 3:
            var filled: bool = i < tier
            var pc2 := base if filled else Color(1, 1, 1, 0.18)
            _diamond(c + Vector2((i - 1) * 18.0, TIER_DY), 5.0, pc2)
        # ── Золотая вспышка прицела на perfect/good ──
        if _flash_left > 0.0:
            var fa := _flash_left / FLASH_T
            _panel.draw_circle(c, PULSE_R1 + 2.0 * fa, Color(1.0, 0.85, 0.3, 0.5 * fa))
        # ── Попапы вердиктов (справа от прицела, всплывают вверх) ──
        for p in _pops:
            var pt: float = float(p["t"]) / POP_T
            var ppc: Color = p["col"]
            ppc.a = 1.0 if pt < 0.7 else 1.0 - (pt - 0.7) / 0.3
            _panel.draw_string(f, c + Vector2(60.0, 40.0 - 26.0 * pt), str(p["text"]),
                    HORIZONTAL_ALIGNMENT_LEFT, 110.0, 14, ppc)

    # ── Баннер причины выхода: живёт ПОСЛЕ закрытия стойки ──
    if _banner_left > 0.0 and f != null:
        var a := clampf(_banner_left / 0.4, 0.0, 1.0)
        var bcol := _banner_col
        bcol.a = a
        var w := f.get_string_size(_banner_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x
        var bg := Rect2(c.x - w * 0.5 - 14.0, c.y + BANNER_DY - 24.0, w + 28.0, 34.0)
        _panel.draw_rect(bg, Color(0, 0, 0, 0.55 * a))
        _panel.draw_string(f, Vector2(c.x - w * 0.5, c.y + BANNER_DY), _banner_text,
                HORIZONTAL_ALIGNMENT_LEFT, -1, 21, bcol)

## Доля такта для сетки бита — та же формула, что у BardGrooveComponent
## (четверть 0.5 с при 120 BPM / восьмая 0.4167 при 72).
func _fraction_len() -> float:
    if _cond == null:
        return 0.5
    var bl := float(_cond.beat_len)
    return bl if bl <= 0.6 else bl * 0.5

func _diamond(p: Vector2, r: float, col: Color) -> void:
    _panel.draw_colored_polygon(
            PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0),
            p + Vector2(0, r), p + Vector2(-r, 0)]), col)
