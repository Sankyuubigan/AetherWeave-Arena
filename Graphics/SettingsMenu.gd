extends CanvasLayer

## Окно настроек (автолоад): слайдер общей громкости + кнопка тест-звука.
## Открытие/закрытие — F2. Громкость через AudioManager (Master-шина),
## значение сохраняется в user://settings.cfg.
## UI строится кодом по образцу SkillMenu (без .tscn).

var is_open: bool = false
var _root: Control
var _panel: PanelContainer
var _slider: HSlider
var _value_label: Label

const TEST_SOUND := "res://Audio/SFX/neural_ui_click.res"

func _ready():
    layer = 50
    _build_ui()
    # ВАЖНО: прячем КОРЕНЬ, а не только панель — full-rect Control со
    # STOP-фильтром, оставшись видимым, перехватывал бы ВСЕ клики игры
    # (драг карточек SkillMenu, покупку), пока меню закрыто.
    _root.hide()

func _build_ui() -> void:
    _root = Control.new()
    _root.name = "SettingsRoot"
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_root)

    _panel = PanelContainer.new()
    _panel.name = "SettingsPanel"
    _panel.set_anchors_preset(Control.PRESET_CENTER)
    _panel.custom_minimum_size = Vector2(380, 0)
    _root.add_child(_panel)

    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 16)
    _panel.add_child(margin)

    var vbox := VBoxContainer.new()
    vbox.add_theme_constant_override("separation", 10)
    margin.add_child(vbox)

    var title := Label.new()
    title.text = "Настройки"
    title.add_theme_font_size_override("font_size", 22)
    vbox.add_child(title)

    vbox.add_child(HSeparator.new())

    var vol_row := HBoxContainer.new()
    vol_row.add_theme_constant_override("separation", 10)
    vbox.add_child(vol_row)

    var vol_caption := Label.new()
    vol_caption.text = "Общая громкость:"
    vol_row.add_child(vol_caption)

    _value_label = Label.new()
    _value_label.text = "100%"
    vol_row.add_child(_value_label)

    _slider = HSlider.new()
    _slider.min_value = 0
    _slider.max_value = 100
    _slider.step = 1
    _slider.value = 100
    _slider.custom_minimum_size = Vector2(0, 24)
    _slider.value_changed.connect(_on_volume_changed)
    vbox.add_child(_slider)

    var test_btn := Button.new()
    test_btn.text = "Проверить звук"
    test_btn.pressed.connect(_on_test_sound)
    vbox.add_child(test_btn)

    vbox.add_child(HSeparator.new())

    var hint := Label.new()
    hint.text = "F2 — открыть/закрыть настройки"
    hint.add_theme_font_size_override("font_size", 13)
    hint.modulate = Color(1, 1, 1, 0.6)
    vbox.add_child(hint)

## _unhandled_input: не сработает, пока GUI занят событиями (печать текста).
func _unhandled_input(event):
    if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
        is_open = !is_open
        if is_open:
            _sync_from_audio()
            _root.show()
            Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        else:
            _root.hide()
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _sync_from_audio() -> void:
    var audio = get_node_or_null("/root/AudioManager")
    var v: float = audio.master_volume if audio else 1.0
    _slider.set_value_no_signal(roundf(v * 100.0))
    _update_value_label()

func _on_volume_changed(v: float) -> void:
    _update_value_label()
    var audio = get_node_or_null("/root/AudioManager")
    if audio:
        audio.set_master_volume(v / 100.0)

func _update_value_label() -> void:
    _value_label.text = str(int(roundf(_slider.value))) + "%"

func _on_test_sound() -> void:
    var audio = get_node_or_null("/root/AudioManager")
    if not audio or not ResourceLoader.exists(TEST_SOUND):
        return
    audio.play_sfx(load(TEST_SOUND), 0.0)
