extends CanvasLayer

## Спектр-визуализатор музыки (фишка из демо audio/spectrum): 40 лог-полос
## 40 Гц…16 кГц через AudioEffectSpectrumAnalyzer на шине Music.
## Автозагрузка (/root/MusicSpectrum), F4 — показать/скрыть, по умолчанию скрыт.
## Эффект на шину добавляется лениво (шина создаёт MusicDirector).

const BARS := 40
const FREQ_MIN := 40.0
const FREQ_MAX := 16000.0
const BAR_W := 9.0
const BAR_GAP := 2.0
const BAR_H := 90.0
const GAIN := 600.0

var _panel: Control
var _smoothed := PackedFloat32Array()

func _ready() -> void:
    layer = 99
    process_mode = Node.PROCESS_MODE_ALWAYS
    _smoothed.resize(BARS)
    _panel = Control.new()
    _panel.name = "SpectrumBars"
    _panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    _panel.draw.connect(_on_draw)
    add_child(_panel)
    _panel.hide()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo \
            and event.physical_keycode == KEY_F4:
        _panel.visible = not _panel.visible

func _process(_delta: float) -> void:
    if not _panel.visible:
        return
    var analyzer := _analyzer_instance()
    if analyzer == null:
        return
    for b in BARS:
        var f0 := FREQ_MIN * pow(FREQ_MAX / FREQ_MIN, float(b) / BARS)
        var f1 := FREQ_MIN * pow(FREQ_MAX / FREQ_MIN, float(b + 1) / BARS)
        var m: float = analyzer.get_magnitude_for_frequency_range(f0, f1,
                AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
        _smoothed[b] = lerpf(_smoothed[b], m, 0.4)
    _panel.queue_redraw()

## Публичный доступ для других VFX (AcousticBarrierVFX, Q16 Шаг 7):
## ленивый инстанс спектр-анализатора на шине Music.
func get_analyzer() -> AudioEffectSpectrumAnalyzerInstance:
    return _analyzer_instance()

## Спектр-анализатор на шине Music: находим среди эффектов, иначе добавляем.
func _analyzer_instance() -> AudioEffectSpectrumAnalyzerInstance:
    var idx := AudioServer.get_bus_index("Music")
    if idx < 0:
        return null
    for i in AudioServer.get_bus_effect_count(idx):
        if AudioServer.get_bus_effect(idx, i) is AudioEffectSpectrumAnalyzer:
            return AudioServer.get_bus_effect_instance(idx, i)
    AudioServer.add_bus_effect(idx, AudioEffectSpectrumAnalyzer.new())
    return AudioServer.get_bus_effect_instance(idx, AudioServer.get_bus_effect_count(idx) - 1)

func _on_draw() -> void:
    for b in BARS:
        var h := clampf(_smoothed[b] * GAIN, 2.0, BAR_H)
        var r := Rect2(Vector2(10.0 + b * (BAR_W + BAR_GAP), -h - 8.0), Vector2(BAR_W, h))
        _panel.draw_rect(r, Color(0.2, 0.9, 1.0, 0.55))
