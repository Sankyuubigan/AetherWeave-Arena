class_name AnimatedDecalComponent
extends Decal
## Анимированная декаль (Godot 4.8): DrawableTexture2D + бли́т кадров флипбука.
##
## Как работает (проверено по PR GH-115653 и дампу extension_api 4.8-beta3):
## 4.8 умеет обновлять ОДНУ текстуру в DecalAtlas без полного ребилда —
## поэтому blit_rect() нового кадра в DrawableTexture2D виден сразу на декали.
## Сами кадры — Array[Image] от Graphics/DecalFrames.gd (процедурные).
##
## Жизненный цикл: кадры играют fps раз в секунду (loop опционален),
## по истечении lifetime декаль растворяется через modulate:a (у Decal нет
## albedo_color — свойство называется modulate) и free-ится.
##
## Использование (эффекты скиллов): new() → configure() → parent.add_child()
## → place(). Прямое self-обращение к class_name внутри файла НЕ используем
## (глобальный кэш классов в -s-режиме не пересканируется — само-ссылка падает).

const FRAME_SIZE := 64

var _frames: Array[Texture2D] = []
var _drawable: DrawableTexture2D
var _fps: float = 10.0
var _loop: bool = false
var _lifetime: float = 5.0
var _time: float = 0.0
var _last_frame: int = -1
var _fading: bool = false

## Конфигурация до add_child: кадры (Array[Image] от DecalFrames), fps, время
## жизни, размер декали (м), зацикливание, цвет-модуляция.
func configure(frames: Array[Image], fps: float, lifetime: float, size: float,
        loop: bool = false, modulate_color: Color = Color(1, 1, 1, 1)) -> void:
    # self.size — свойство Decal (Vector3); параметр size — float (диаметр в метрах).
    self.size = Vector3(size, 0.5, size)
    modulate = modulate_color
    _lifetime = lifetime
    _fps = maxf(fps, 1.0)
    _loop = loop
    _init_frames(frames)

## Поставить на поверхность: pos — точка, normal — ось Y декали ложится на неё.
## Вызывать ПОСЛЕ add_child (нужен вход в дерево для global_transform).
func place(pos: Vector3, normal: Vector3) -> void:
    var y_axis := normal.normalized()
    var x_axis := Vector3.UP.cross(y_axis)
    if x_axis.length_squared() < 0.001:
        x_axis = Vector3.RIGHT.cross(y_axis)
    x_axis = x_axis.normalized()
    var z_axis := x_axis.cross(y_axis).normalized()
    global_transform.basis = Basis(x_axis, y_axis, z_axis)
    global_position = pos + y_axis * 0.02

## Эмиссия декали (лава-лужа, QUEUE Q5): та же DrawableTexture2D в
## texture_emission — светятся только непрозрачные тексели (прожилки, корка
## почти нет). Вызывать ПОСЛЕ configure (нужна _drawable).
func set_emission(energy: float) -> void:
    texture_emission = _drawable
    emission_energy = energy

## Нормаль поверхности в точке удара: одиночный луч навстречу движению.
## dir — направление полёта/взрыва; fallback вернётся, если луч ничего не нашёл.
static func surface_normal(world: World3D, pos: Vector3, dir: Vector3, fallback: Vector3) -> Vector3:
    if world == null:
        return fallback
    var d := dir.normalized()
    var query := PhysicsRayQueryParameters3D.new()
    query.from = pos - d * 1.0
    query.to = pos + d * 0.5
    var hit := world.direct_space_state.intersect_ray(query)
    if hit and hit.has("normal"):
        return hit.normal
    return fallback

## Пол под точкой (для благословений/варпа у ног персонажа).
## Возвращает {} (пусто), если пола в 3 м нет — декаль тогда не спавним.
## Иначе {"position": Vector3, "normal": Vector3}.
static func ground_hit_below(world: World3D, pos: Vector3) -> Dictionary:
    if world == null:
        return {}
    var query := PhysicsRayQueryParameters3D.new()
    query.from = pos + Vector3.UP * 2.0
    query.to = pos - Vector3.UP * 3.0
    var hit := world.direct_space_state.intersect_ray(query)
    if hit and hit.has("normal"):
        return {"position": hit.position, "normal": hit.normal}
    return {}

func _init_frames(images: Array[Image]) -> void:
    _drawable = DrawableTexture2D.new()
    _drawable.setup(FRAME_SIZE, FRAME_SIZE, DrawableTexture2D.DRAWABLE_FORMAT_RGBA8, Color(0, 0, 0, 0), false)
    texture_albedo = _drawable
    # Кадры конвертируем в ImageTexture один раз (блит берёт Texture2D).
    for img in images:
        _frames.append(ImageTexture.create_from_image(img))
    if not _frames.is_empty():
        _blit_frame(0)

func _process(delta: float) -> void:
    if _frames.is_empty():
        set_process(false)
        return
    _time += delta

    # Фазa анимации кадров.
    var frame_count := _frames.size()
    var anim_len := float(frame_count) / _fps
    if _time < anim_len:
        var idx := int(_time * _fps)
        if idx < frame_count and idx != _last_frame:
            _blit_frame(idx)
    elif not _loop and not _fading:
        # Кадры кончились: остаётся последний кадр, ждём конца lifetime.
        pass

    # Конец жизни: растворение и удаление. Фейд короткий у коротких эффектов
    # (кольцо волны 1.6с — фейд 0.4с), длинный у пятен (прожог 15с — 1.5с).
    if _time >= _lifetime and not _fading:
        _fading = true
        var fade_time := clampf(_lifetime * 0.25, 0.3, 1.5)
        var tween := create_tween()
        tween.tween_property(self, "modulate:a", 0.0, fade_time)
        tween.tween_callback(queue_free)

func _blit_frame(idx: int) -> void:
    _last_frame = idx
    # MIX заменяет содержимое текстуры кадром (кадры несут свою альфу).
    _drawable.blit_rect(
        Rect2i(0, 0, FRAME_SIZE, FRAME_SIZE),
        _frames[idx],
        Color(1, 1, 1, 1),
        0,
        null
    )
