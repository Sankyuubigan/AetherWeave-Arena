class_name DecalFrames
extends RefCounted
## Генераторы кадров анимированных декалей (процедурные, без внешних ассетов).
##
## Каждый генератор возвращает Array[Image] 64x64 RGBA8 — кадры флипбука для
## AnimatedDecalComponent (Graphics/AnimatedDecalComponent.gd). Фаза анимации
## и финальный фейд ВШИТЫ в кадры: компонент просто блитит их по порядку.
##
## Стиль рисования одинаковый: радиальный профиль от центра (x,y -> dx,dy),
## цвет ящика задаёт скилл. Все функции static — GDScript-статика не зовёт
## нестатическое (урок TerrainBuilder).

const SIZE := 64
const CENTER := 31.5

# --- Публичные генераторы (по скиллам) -------------------------------------

## Луч (beam): прожог от вспышки к остывающему следу.
## 0..~0.4 кадра: бело-горячее ядро с оранжевой кромкой; дальше ядро темнеет
## до цвета угля, пятно чуть расползается, последние кадры — тёмный след.
static func beam_scorch(hot: Color, frames_count: int = 10) -> Array[Image]:
    var cold := Color(0.03, 0.03, 0.03)
    var frames: Array[Image] = []
    for i in frames_count:
        var t := float(i) / maxf(frames_count - 1, 1)
        var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
        # Радиус пятна слегка растёт (прожог расползается).
        var radius := 0.55 + 0.35 * ease_out(t)
        # Температура ядра падает от 1 к 0 (горячее -> уголь).
        var heat := 1.0 - ease_out(t)
        for y in SIZE:
            for x in SIZE:
                var d := dist01(x, y)
                var a := ring_profile(d, radius)
                if a <= 0.0:
                    continue
                var c := hot.lerp(cold, clampf(1.0 - heat, 0.0, 1.0))
                # Ядро горячее кромки: внутри радиуса цвет светлее.
                var core := clampf((radius - d) / maxf(radius, 0.001), 0.0, 1.0)
                c = c.lerp(Color.WHITE, core * core * heat * 0.7)
                img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
        frames.append(img)
    return frames

## Огненный шар / метеор (fireball): огненное кольцо расширяется и гаснет
## в чёрный след, который потом тает.
static func explosion_scorch(fire: Color, frames_count: int = 12) -> Array[Image]:
    var char_col := Color(0.05, 0.04, 0.03)
    var frames: Array[Image] = []
    for i in frames_count:
        var t := float(i) / maxf(frames_count - 1, 1)
        var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
        # Кольцо огня расширяется от 0.15 до 0.9.
        var ring_r := 0.15 + 0.75 * ease_out(t)
        # Огонь живёт первую треть, потом остаётся уголь.
        var fire_life := clampf(1.0 - t / 0.35, 0.0, 1.0)
        for y in SIZE:
            for x in SIZE:
                var d := dist01(x, y)
                var a := ring_profile(d, ring_r)
                if a <= 0.0:
                    continue
                var c := char_col
                if fire_life > 0.0:
                    # Огненная кромка: яркая на кольце радиуса ring_r.
                    var edge := absf(d - ring_r) * 4.0
                    var fire_a := clampf(1.0 - edge, 0.0, 1.0) * fire_life
                    c = c.lerp(fire, fire_a)
                    c = c.lerp(Color.WHITE, fire_a * fire_a * 0.35)
                # Весь след тает к последним кадрам.
                var fade := clampf(1.0 - maxf(0.0, t - 0.7) / 0.3, 0.0, 1.0)
                img.set_pixel(x, y, Color(c.r, c.g, c.b, a * fade))
        frames.append(img)
    return frames

## Шаровая молния (ball_lightning): мигающие электрические дуги.
## Каждая кадр — новый узор трещин (детерминированный seed), яркость гаснет.
static func electric_scorch(arc: Color, frames_count: int = 10) -> Array[Image]:
    var frames: Array[Image] = []
    var rng := RandomNumberGenerator.new()
    for i in frames_count:
        var t := float(i) / maxf(frames_count - 1, 1)
        var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
        rng.seed = 1000 + i * 77
        # Трещины: ломаные от центра наружу, 5-8 штук.
        var bolts := 5 + (i % 4)
        img.fill(Color(0, 0, 0, 0))
        for b in bolts:
            var ang := rng.randf() * TAU
            var len := rng.randf_range(0.35, 0.85)
            var prev := Vector2(CENTER, CENTER)
            var steps := 4
            for s in steps:
                var prog := float(s + 1) / steps
                var a2 := ang + rng.randf_range(-0.5, 0.5)
                var next := Vector2(CENTER, CENTER) + Vector2(cos(a2), sin(a2)) * len * prog * CENTER
                draw_line_px(img, prev, next, arc, 1.0 - t * 0.7)
                prev = next
        # Мягкое свечение в центре, гаснет быстрее дуг.
        for y in SIZE:
            for x in SIZE:
                var d := dist01(x, y)
                var glow := clampf(1.0 - d / 0.45, 0.0, 1.0)
                glow = glow * glow * (1.0 - t) * 0.6
                if glow > 0.01:
                    var old := img.get_pixel(x, y)
                    img.set_pixel(x, y, Color(arc.r, arc.g, arc.b, clampf(old.a + glow, 0.0, 1.0)))
        frames.append(img)
    return frames

## Сердечко (heart_heal): мягкий пульсирующий круг благословения.
## Два пульса свечения, потом тает.
static func heal_pulse(glow: Color, frames_count: int = 12) -> Array[Image]:
    var frames: Array[Image] = []
    for i in frames_count:
        var t := float(i) / maxf(frames_count - 1, 1)
        var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
        # Два пульса за время жизни: sin с двумя горбами.
        var pulse := pow(absf(sin(t * TAU * 0.75)), 1.5)
        var global_fade := clampf(1.0 - maxf(0.0, t - 0.8) / 0.2, 0.0, 1.0)
        for y in SIZE:
            for x in SIZE:
                var d := dist01(x, y)
                var core := clampf(1.0 - d / 0.75, 0.0, 1.0)
                var a := core * core * pulse * global_fade * 0.85
                if a > 0.01:
                    var c := glow.lerp(Color.WHITE, core * 0.4)
                    img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
        frames.append(img)
    return frames

## Громовой раскат / AoE (thunderclap): кольцо ударной волны.
## Быстро расширяющееся яркое кольцо с мягким заполнением внутри.
static func shockwave_ring(wave: Color, frames_count: int = 8) -> Array[Image]:
    var frames: Array[Image] = []
    for i in frames_count:
        var t := float(i) / maxf(frames_count - 1, 1)
        var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
        var ring_r := 0.1 + 0.85 * ease_out(t)
        var fade := 1.0 - t
        for y in SIZE:
            for x in SIZE:
                var d := dist01(x, y)
                # Кольцо: пик на ring_r, ширина ~0.12.
                var band := clampf(1.0 - absf(d - ring_r) / 0.12, 0.0, 1.0)
                var inner := clampf(1.0 - d / maxf(ring_r, 0.001), 0.0, 1.0) * 0.35
                var a := (band * band + inner) * fade
                if a > 0.01:
                    var c := wave.lerp(Color.WHITE, band * 0.5)
                    img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
        frames.append(img)
    return frames

## Телепорт (teleport): круг варпа — кольцо сжимается к центру (уход)
## или расширяется (приход). Направление задаёт contract=true/false.
static func warp_ring(warp: Color, contract: bool, frames_count: int = 8) -> Array[Image]:
    var frames: Array[Image] = []
    for i in frames_count:
        var raw := float(i) / maxf(frames_count - 1, 1)
        var t := (1.0 - raw) if contract else raw
        var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
        var ring_r := 0.15 + 0.75 * t
        var fade := (raw if contract else (1.0 - raw)) * 0.9 + 0.1
        for y in SIZE:
            for x in SIZE:
                var d := dist01(x, y)
                var band := clampf(1.0 - absf(d - ring_r) / 0.10, 0.0, 1.0)
                var swirl := 0.75 + 0.25 * sin(atan2(float(y - CENTER), float(x - CENTER)) * 6.0 + t * TAU)
                var a := band * band * fade * swirl
                if a > 0.01:
                    var c := warp.lerp(Color.WHITE, band * 0.6)
                    img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
        frames.append(img)
    return frames

# --- Хелперы рисования ------------------------------------------------------

## Нормализованное расстояние от центра кадра (0..1, 1 = угол).
static func dist01(x: int, y: int) -> float:
    var dx := (x - CENTER) / CENTER
    var dy := (y - CENTER) / CENTER
    return sqrt(dx * dx + dy * dy)

## Профиль пятна: 1 в центре, спад к краю радиуса, за радиусом 0.
static func ring_profile(d: float, radius: float) -> float:
    if d > radius:
        return 0.0
    var k := 1.0 - d / maxf(radius, 0.001)
    return k * k * 0.95

static func ease_out(t: float) -> float:
    return 1.0 - (1.0 - t) * (1.0 - t)

## Линия толщиной ~2px в Image (для дуг молнии).
static func draw_line_px(img: Image, from: Vector2, to: Vector2, color: Color, alpha: float) -> void:
    var steps := int(from.distance_to(to)) + 1
    for s in steps + 1:
        var p := from.lerp(to, float(s) / maxf(steps, 1))
        for oy in 2:
            for ox in 2:
                var x := int(p.x) + ox
                var y := int(p.y) + oy
                if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
                    continue
                var old := img.get_pixel(x, y)
                if color.a * alpha > old.a:
                    img.set_pixel(x, y, Color(color.r, color.g, color.b, clampf(color.a * alpha, 0.0, 1.0)))
