extends Control

## Одна вертикальная дорожка Потока Барда (В.3 + Фикс А, вердикт спеца 09/10-
## ответы). Оркестратор BardFlowUI создаёт две (harmony слева, chord справа),
## каждый кадр задаёт позицию (set_lane_pos) и сглаженные часы (set_time).
## Рисует: тёмный коридор-подложку с градиентом альфы в верхних 50 px,
## боковые стенки, Good-зону ±22 px, Perfect-рамку-мишень 46×20 с белой
## центральной линией, «прожим» рамки на каждое нажатие (0.88→1.12→1.0 за
## 0.12 с), летящие сверху ноты-капсулы 36×12 с белым центром и fade-in,
## телеграф-вспышку в Perfect-зоне, ring-burst + флэш планки на попадание,
## микро-шейк на MISS, попапы PERFECT!/GOOD/MISS/«МИМО −1.2с».
## MOUSE_FILTER_IGNORE — не окно (ССОТ ui_input_rules).

const COL_HARMONY := Color(0.2, 0.9, 1.0)   # бирюза: Нота Гармонии (ЛКМ)
const COL_CHORD := Color(1.0, 0.82, 0.28)   # золото: Ударный Аккорд (ПКМ)
const COL_MISS := Color(1.0, 0.3, 0.25)
const COL_GOOD := Color(0.55, 0.95, 0.45)
const COL_CORRIDOR := Color(0.02, 0.04, 0.08)  # Фикс А: коридор-подложка

const APPROACH_S := 1.4        # В.3: путь ноты 240 px за 1.4 с (~171 px/с)
const LANE_H := 240.0          # длина дорожки (спавн y_hit − 240)
const HALF_W := 28.0           # полуширина коридора
const GOOD_HALF := 22.0        # Good-зона ±22 px вокруг y_hit
const PERFECT_W := 46.0        # рамка-мишень (Фикс А)
const PERFECT_H := 20.0
const NOTE_W := 36.0           # нота-капсула 36×12
const NOTE_H := 12.0
const FADE_PX := 40.0          # fade-in в верхних 40 px дорожки
const POPUP_T := 0.45          # жизнь попапа вердикта (всплыв 35 px)
const POPUP_RISE := 35.0
const PRESS_T := 0.12          # прожим рамки 0.88→1.12→1.0
const BURST_T := 0.3           # ring-burst попадания
const FLASH_T := 0.18          # флэш планки
const SHAKE_T := 0.15          # микро-шейк планки ±6 px (MISS)

var kind := "harmony"
var _col := COL_HARMONY
var _lane_cx := 0.0            # центр дорожки по x (задаёт оркестратор)
var _y_hit := 0.0              # линия попадания (задаёт оркестратор)
var _t_now := 0.0              # сглаженные часы conductor
var _key_label := ""           # подпись привязанной клавиши (ЛКМ/ПКМ/Q/E)
var _judge: Node = null

var _press_t := -1.0
var _burst_t := -1.0
var _flash_t := -1.0
var _shake_t := -1.0
var _popups: Array = []        # {text, col, t}

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _judge = get_node_or_null("/root/RhythmJudge")

func set_lane(k: String, col: Color) -> void:
    kind = k
    _col = col

func set_lane_pos(cx: float, hit_y: float) -> void:
    _lane_cx = cx
    _y_hit = hit_y

func set_time(t: float) -> void:
    _t_now = t

func set_key_label(lbl: String) -> void:
    _key_label = lbl

func on_press() -> void:
    _press_t = 0.0  # прожим рамки на каждое нажатие дорожки (Фикс А)

func on_judged(verdict: String, note_kind: String) -> void:
    ## Попап вердикта на СВОЕЙ дорожке (note_judged несёт kind ноты).
    if note_kind != kind:
        return
    match verdict:
        "perfect":
            _popup("PERFECT!", COL_CHORD if kind == "chord" else COL_HARMONY)
            _burst_t = 0.0
            _flash_t = 0.0
        "good":
            _popup("GOOD", COL_GOOD)
            _burst_t = 0.0
            _flash_t = 0.0
        "miss":
            _popup("MISS", COL_MISS)
            _shake_t = 0.0

func on_empty(note_kind: String) -> void:
    ## Пустой пресс (В.1.2/В.5): красный «МИМО −1.2с» на дорожке.
    if note_kind == kind:
        _popup("МИМО −1.2с", COL_MISS)

func _popup(text: String, col: Color) -> void:
    if _popups.size() >= 4:
        _popups.pop_front()
    _popups.append({"text": text, "col": col, "t": 0.0})

func _process(delta: float) -> void:
    _press_t = maxf(-1.0, _press_t - delta if _press_t >= 0.0 else -1.0)
    _burst_t = maxf(-1.0, _burst_t - delta if _burst_t >= 0.0 else -1.0)
    _flash_t = maxf(-1.0, _flash_t - delta if _flash_t >= 0.0 else -1.0)
    _shake_t = maxf(-1.0, _shake_t - delta if _shake_t >= 0.0 else -1.0)
    var alive: Array = []
    for p in _popups:
        p["t"] = float(p["t"]) + delta
        if float(p["t"]) < POPUP_T:
            alive.append(p)
    _popups = alive
    queue_redraw()

func _draw() -> void:
    var top := _y_hit - LANE_H
    var left := _lane_cx - HALF_W
    var right := _lane_cx + HALF_W
    var f := ThemeDB.fallback_font

    # ── Коридор-подложка (Фикс А): градиент 0→0.30 в верхних 50 px ──
    var grad_end := minf(top + 50.0, _y_hit)
    _draw_v_grad(Vector2(left, top), Vector2(right, grad_end), 0.0, 0.30)
    if grad_end < _y_hit:
        var c := COL_CORRIDOR
        c.a = 0.30
        draw_rect(Rect2(left, grad_end, HALF_W * 2.0, _y_hit - grad_end), c)
    # Боковые стенки 1.5 px, альфа 0.40.
    var wall := Color(1, 1, 1, 0.40)
    draw_line(Vector2(left, top), Vector2(left, _y_hit), wall, 1.5)
    draw_line(Vector2(right, top), Vector2(right, _y_hit), wall, 1.5)

    # ── Good-зона ±22 px: полоса α0.14 + тусклые границы ──
    var g := Color(1, 1, 1, 0.14)
    draw_rect(Rect2(left, _y_hit - GOOD_HALF, HALF_W * 2.0, GOOD_HALF * 2.0), g)
    var gl := Color(1, 1, 1, 0.18)
    draw_line(Vector2(left, _y_hit - GOOD_HALF), Vector2(right, _y_hit - GOOD_HALF), gl, 1.0)
    draw_line(Vector2(left, _y_hit + GOOD_HALF), Vector2(right, _y_hit + GOOD_HALF), gl, 1.0)

    _draw_notes()

    # ── Perfect-рамка-мишень: шейк-офсет + прожим-масштаб + флэш ──
    var off_x := 0.0
    if _shake_t >= 0.0:
        off_x = sin(_shake_t * 60.0) * 6.0 * (1.0 - _shake_t / SHAKE_T)
    var scale := 1.0
    if _press_t >= 0.0:
        var half := PRESS_T * 0.5
        scale = lerpf(0.88, 1.12, clampf(_press_t / half, 0.0, 1.0)) \
                if _press_t < half else lerpf(1.12, 1.0, clampf((_press_t - half) / half, 0.0, 1.0))
    var fw := PERFECT_W * 0.5 * scale
    var fh := PERFECT_H * 0.5 * scale
    var fc := _col
    if _flash_t >= 0.0:
        var fill := _col
        fill.a = 0.35 * (1.0 - _flash_t / FLASH_T)
        draw_rect(Rect2(_lane_cx - fw + off_x, _y_hit - fh, fw * 2.0, fh * 2.0), fill)
    fc.a = 0.95
    draw_rect(Rect2(_lane_cx - fw + off_x, _y_hit - fh, fw * 2.0, fh * 2.0), fc, false, 2.5)
    # Белая центральная линия.
    draw_line(Vector2(_lane_cx - PERFECT_W * 0.5 + off_x, _y_hit),
            Vector2(_lane_cx + PERFECT_W * 0.5 + off_x, _y_hit),
            Color(1, 1, 1, 0.85), 2.0)

    # ── Бейдж клавиши: тёмный, y_hit+24 (Фикс А) ──
    if _key_label != "" and f != null:
        var bd := Rect2(_lane_cx - 26.0, _y_hit + 24.0, 52.0, 18.0)
        draw_rect(bd, Color(0, 0, 0, 0.55))
        draw_string(f, Vector2(bd.position.x, bd.position.y + 13.0), _key_label,
                HORIZONTAL_ALIGNMENT_CENTER, bd.size.x, 11, Color(1, 1, 1, 0.85))

    # ── Ring-burst попадания ──
    if _burst_t >= 0.0:
        var k := _burst_t / BURST_T
        var bc := _col
        bc.a = 0.6 * (1.0 - k)
        draw_arc(Vector2(_lane_cx, _y_hit), 26.0 + 40.0 * k, 0.0, TAU, 40, bc, 2.5)

    # ── Попапы над y_hit−22: всплыв 35 px, pop-скейл 1.25→1.0 ──
    for p in _popups:
        var pt := float(p["t"]) / POPUP_T
        var pc: Color = p["col"]
        pc.a = 1.0 if pt < 0.7 else 1.0 - (pt - 0.7) / 0.3
        var size := lerpf(20.0, 16.0, pt)  # 16 × 1.25 → 16
        if f != null:
            draw_string(f, Vector2(_lane_cx - 60.0,
                    _y_hit - GOOD_HALF - 4.0 - POPUP_RISE * pt), str(p["text"]),
                    HORIZONTAL_ALIGNMENT_CENTER, 120.0, int(size), pc)

func _draw_notes() -> void:
    ## Ноты дорожки сверху вниз: y = y_hit − (note_time − t_now) × SPEED.
    if _judge == null:
        return
    var speed := LANE_H / APPROACH_S
    var top := _y_hit - LANE_H
    for n in _judge.get_notes():
        if str(n["kind"]) != kind:
            continue
        if bool(n["judged"]):
            continue
        var dt := float(n["time"]) - _t_now
        if dt < -0.06 or dt > APPROACH_S:
            continue
        var y := _y_hit - dt * speed
        var a := clampf((y - top) / FADE_PX, 0.0, 1.0)
        # Телеграф (Фикс А): нота в Perfect-зоне вспыхивает белым.
        var telegraph: bool = absf(dt) <= 0.07
        var col := Color(1, 1, 1, a) if telegraph else Color(_col.r, _col.g, _col.b, a)
        var cx := _lane_cx
        var glow := col
        glow.a = a * 0.25
        draw_circle(Vector2(cx, y), 11.0 if telegraph else 9.0, glow)
        draw_circle(Vector2(cx - NOTE_W * 0.5 + 6.0, y), 6.0, col)
        draw_circle(Vector2(cx + NOTE_W * 0.5 - 6.0, y), 6.0, col)
        draw_rect(Rect2(cx - NOTE_W * 0.5 + 6.0, y - NOTE_H * 0.5,
                NOTE_W - 12.0, NOTE_H), col)
        var core := Color(1, 1, 1, a * 0.9)
        draw_rect(Rect2(cx - 8.0, y - 2.0, 16.0, 4.0), core)

func _draw_v_grad(tl: Vector2, br: Vector2, a_top: float, a_bot: float) -> void:
    ## Вертикальный градиент альфы через вершинные цвета draw_polygon.
    var c := Color(COL_CORRIDOR.r, COL_CORRIDOR.g, COL_CORRIDOR.b, a_top)
    var c2 := Color(COL_CORRIDOR.r, COL_CORRIDOR.g, COL_CORRIDOR.b, a_bot)
    draw_polygon(PackedVector2Array([tl, Vector2(br.x, tl.y), br, Vector2(tl.x, br.y)]),
            PackedColorArray([c, c, c2, c2]))
