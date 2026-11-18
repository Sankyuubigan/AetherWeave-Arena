extends Node

## Режимы качества графики (QUEUE.md Q1, одобрено юзером 19.11.26):
## LOW «Слабое» — VRS (Q3) + без SSAO/объёмного тумана/SDFGI;
## MEDIUM «Среднее» — как карта сгенерирована (базлайн);
## HIGH «Высокое» — базлайн + SDFGI (Q4, только жирные видеокарты).
##
## Применение: корневой viewport (VRS) + WorldEnvironment текущей сцены.
## env при каждом применении копируется из меты-базлайна — переключение
## режимов туда-обратно не накапливает дельты. Смена карт ловится через
## node_added (телепорт между аренами). Персист — user://settings.cfg,
## секция [graphics] (общий файл с AudioManager).
## Автолоад: в -s-зондах его НЕТ — get_node_or_null("/root/GraphicsQuality").

enum Quality { LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"
const NAMES: Array[String] = ["Слабое (VRS)", "Среднее", "Высокое (SDFGI)"]

var quality: int = Quality.MEDIUM

var _vrs_tex: ImageTexture

func _ready() -> void:
    _load_settings()
    get_tree().node_added.connect(_on_node_added)
    _apply()

func set_quality(q: int) -> void:
    quality = clampi(q, 0, Quality.size() - 1)
    _save_settings()
    _apply()

## Для SettingsMenu (F2).
func quality_name() -> String:
    return NAMES[quality]

func _on_node_added(node: Node) -> void:
    # Карта сменилась (телепорт) — новый WorldEnvironment применяется deferred:
    # environment мог назначиться сразу после node_added.
    if node is WorldEnvironment:
        _apply_env.call_deferred(node)

func _apply() -> void:
    _apply_vrs()
    var we := _find_world_env()
    if we:
        _apply_env(we)

## VRS — только LOW (QUEUE Q3). Плотностная карта: R = горизонтальный shading
## rate, G = вертикальный (официальная дока «Variable rate shading»):
## 0x00 = 1×1, 0x55 = 2×2, 0xAA = 4×4; каждый тексел = блок 8×8 px,
## текстура lossless. Только Forward+/Mobile (Vulkan): на GPU без VRS
## просто не действует — ошибки не будет.
func _apply_vrs() -> void:
    var vp := get_viewport()
    if vp == null:
        return
    if quality == Quality.LOW:
        if _vrs_tex == null:
            _vrs_tex = _build_density_texture()
        vp.vrs_texture = _vrs_tex
        vp.vrs_mode = Viewport.VRS_TEXTURE
    else:
        vp.vrs_mode = Viewport.VRS_DISABLED
        vp.vrs_texture = null

func _build_density_texture() -> ImageTexture:
    # Фовате-подобная карта: центр 1×1 (резкость в прицеле), пояс 2×2,
    # края 4×4. 256×144 хватает (viewport/8 при 1280×720 ≈ 160×90).
    var w := 256
    var h := 144
    var img := Image.create(w, h, false, Image.FORMAT_RGB8)
    for y in h:
        for x in w:
            var d := Vector2(x - w * 0.5, y - h * 0.5).length() / (w * 0.5)
            var rate := 0
            if d > 0.75:
                rate = 0xAA # 4×4
            elif d > 0.45:
                rate = 0x55 # 2×2
            img.set_pixel(x, y, Color8(rate, rate, 0))
    return ImageTexture.create_from_image(img)

func _find_world_env() -> WorldEnvironment:
    var scene := get_tree().current_scene
    if scene != null:
        if scene is WorldEnvironment:
            return scene
        for c in scene.get_children():
            if c is WorldEnvironment:
                return c
    # Фолбэк (тесты/-s, WE глубже прямых детей): скан поддерева root.
    return _scan_we(get_tree().root)

func _scan_we(node: Node) -> WorldEnvironment:
    if node is WorldEnvironment:
        return node
    for c in node.get_children():
        var found := _scan_we(c)
        if found:
            return found
    return null

func _apply_env(we: WorldEnvironment) -> void:
    if not is_instance_valid(we) or we.environment == null:
        return
    var env := we.environment
    if not env.has_meta("quality_baseline"):
        env.set_meta("quality_baseline", env.duplicate())
    var baseline: Environment = env.get_meta("quality_baseline")
    # 4.8: Environment.copy_from НЕ существует (поймано 19.11.26) — свойства
    # восстанавливаем из базлайна вручную, только те, что трогают режимы.
    env.ssao_enabled = baseline.ssao_enabled
    env.volumetric_fog_enabled = baseline.volumetric_fog_enabled
    env.sdfgi_enabled = baseline.sdfgi_enabled
    env.sdfgi_cascades = baseline.sdfgi_cascades
    env.sdfgi_use_occlusion = baseline.sdfgi_use_occlusion
    match quality:
        Quality.LOW:
            env.ssao_enabled = false
            env.volumetric_fog_enabled = false
            env.sdfgi_enabled = false
        Quality.MEDIUM:
            pass # базлайн карты
        Quality.HIGH:
            env.sdfgi_enabled = true # Q4: только жирные видеокарты
            env.sdfgi_cascades = 6
            env.sdfgi_use_occlusion = true

func _load_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) != OK:
        return
    quality = clampi(int(cfg.get_value("graphics", "quality", Quality.MEDIUM)), 0, Quality.size() - 1)

func _save_settings() -> void:
    # Догруз существующего файла: AudioManager пишет [audio] в тот же файл —
    # новая ConfigFile без load() стёрла бы чужую секцию (и наоборот: сам
    # AudioManager тоже дописывает через load, фикс зеркальный).
    var cfg := ConfigFile.new()
    cfg.load(SETTINGS_PATH)
    cfg.set_value("graphics", "quality", quality)
    cfg.save(SETTINGS_PATH)
