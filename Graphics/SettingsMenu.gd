extends CanvasLayer

## Окно настроек (автолоад): три ползунка громкости (общая/эффекты/музыка)
## + кнопка тест-звука. Открытие/закрытие — F2. Громкости через AudioManager
## (шины Master/SFX/Music), значения сохраняются в user://settings.cfg.
## UI строится кодом по образцу SkillMenu (без .tscn).

var is_open: bool = false
var _root: Control
var _panel: PanelContainer
var _master_slider: HSlider
var _master_label: Label
var _sfx_slider: HSlider
var _sfx_label: Label
var _music_slider: HSlider
var _music_label: Label
var _quality_option: OptionButton
var _aim_slider: HSlider
var _aim_label: Label

## AIM ASSIST (Q29): угловая толерантность наведения, градусы. Персист
## user://settings.cfg секция [input] (файл общий с [audio]/[graphics]).
var aim_assist_deg: float = 4.0

const TEST_SOUND := "res://Audio/SFX/neural_ui_click.res"
## Качество графики (QUEUE Q1): скрипт автолоада прелоадом — голое имя
## автолоада в -s-режиме не резолвится (правило проекта).
const GraphicsQualityScript = preload("res://Graphics/GraphicsQuality.gd")

func _ready():
    layer = 50
    _load_aim()
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

    var master := _add_volume_row(vbox, "Общая громкость:")
    _master_slider = master[0]
    _master_label = master[1]
    _master_slider.value_changed.connect(_on_master_changed)

    var sfx := _add_volume_row(vbox, "Эффекты:")
    _sfx_slider = sfx[0]
    _sfx_label = sfx[1]
    _sfx_slider.value_changed.connect(_on_sfx_changed)

    var music := _add_volume_row(vbox, "Музыка:")
    _music_slider = music[0]
    _music_label = music[1]
    _music_slider.value_changed.connect(_on_music_changed)

    # Качество графики (QUEUE Q1): LOW = VRS+без SSAO/тумана, MEDIUM = базлайн,
    # HIGH = + SDFGI (жирные видеокарты). Применяет GraphicsQuality autoload.
    var qrow := HBoxContainer.new()
    qrow.add_theme_constant_override("separation", 10)
    vbox.add_child(qrow)
    var qcaption := Label.new()
    qcaption.text = "Качество графики:"
    qrow.add_child(qcaption)
    _quality_option = OptionButton.new()
    for q_name in GraphicsQualityScript.NAMES:
        _quality_option.add_item(q_name)
    qrow.add_child(_quality_option)
    _quality_option.item_selected.connect(_on_quality_changed)

    # AIM ASSIST (Q29): «чувствительность наведения» — насколько близко к цели
    # вести прицел, чтобы появилась анимированная отметка (0.5–12°, дефолт 4°).
    var arow := HBoxContainer.new()
    arow.add_theme_constant_override("separation", 10)
    vbox.add_child(arow)
    var acaption := Label.new()
    acaption.text = "Чувствительность наведения:"
    arow.add_child(acaption)
    _aim_label = Label.new()
    _aim_label.text = "%.1f°" % aim_assist_deg
    arow.add_child(_aim_label)
    _aim_slider = HSlider.new()
    _aim_slider.min_value = 0.5
    _aim_slider.max_value = 12.0
    _aim_slider.step = 0.5
    _aim_slider.value = aim_assist_deg
    _aim_slider.custom_minimum_size = Vector2(0, 24)
    vbox.add_child(_aim_slider)
    _aim_slider.value_changed.connect(_on_aim_changed)

    var test_btn := Button.new()
    test_btn.text = "Проверить звук (эффекты)"
    test_btn.pressed.connect(_on_test_sound)
    vbox.add_child(test_btn)

    vbox.add_child(HSeparator.new())

    var hint := Label.new()
    hint.text = "F2 — открыть/закрыть настройки"
    hint.add_theme_font_size_override("font_size", 13)
    hint.modulate = Color(1, 1, 1, 0.6)
    vbox.add_child(hint)

## Строка «подпись: N%» + слайдер под ней. Возвращает [слайдер, подпись-значения].
func _add_volume_row(vbox: VBoxContainer, caption_text: String) -> Array:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    vbox.add_child(row)

    var caption := Label.new()
    caption.text = caption_text
    row.add_child(caption)

    var value_label := Label.new()
    value_label.text = "100%"
    row.add_child(value_label)

    var slider := HSlider.new()
    slider.min_value = 0
    slider.max_value = 100
    slider.step = 1
    slider.value = 100
    slider.custom_minimum_size = Vector2(0, 24)
    vbox.add_child(slider)
    return [slider, value_label]

## _unhandled_input: не сработает, пока GUI занят событиями (печать текста).
func _unhandled_input(event):
    if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
        is_open = !is_open
        if is_open:
            _sync_from_audio()
            _root.show()
            # МЫШЬ ССОТ (docs/ui_input_rules.md): открытие UI делает мышь
            # видимой; закрытие её НЕ трогает — клик по миру вернёт захват.
            Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        else:
            _root.hide()
            # МЫШЬ ССОТ v2: закрытие F2 возвращает мышь в игру (вердикт юзера
            # 19.11.26). Гард _process ниже разруливает случай, когда открыто
            # и другое окно (кто-то из двоих капчурит — гард возвращает VISIBLE
            # пока ЭТО окно открыто).
            Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(_delta):
    # Q24-гард «пока F2 открыто — фокус всегда с мышкой» (верб. юзера 19.11.26)
    # сохранён как страховка: по МЫШЬ ССОТ (docs/ui_input_rules.md) единственный
    # захватчик мыши в игре — клик по миру в PlayerController, и он заблокирован
    # гейтом _gui_blocks_capture(), пока is_open. Гард ловит только утечки
    # будущего кода, нарушающего ССОТ.
    if is_open and Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
        Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## AIM ASSIST (Q29): загрузка/сохранение толерантности. load-first: cfg общий
## с [audio]/[graphics] — ConfigFile без load() стёр бы чужие секции (грабля
## GraphicsQuality, см. её _save_settings).
func _load_aim() -> void:
    var cf := ConfigFile.new()
    if cf.load("user://settings.cfg") == OK:
        aim_assist_deg = clampf(
            cf.get_value("input", "aim_assist_deg", 4.0), 0.5, 12.0)

func _save_aim() -> void:
    var cf := ConfigFile.new()
    cf.load("user://settings.cfg")
    cf.set_value("input", "aim_assist_deg", aim_assist_deg)
    cf.save("user://settings.cfg")

func _on_aim_changed(v: float) -> void:
    aim_assist_deg = v
    if _aim_label:
        _aim_label.text = "%.1f°" % v
    _save_aim()

func _sync_from_audio() -> void:
    var audio = get_node_or_null("/root/AudioManager")
    var master: float = audio.master_volume if audio else 1.0
    var sfx: float = audio.sfx_volume if audio else 1.0
    var music: float = audio.music_volume if audio else 1.0
    _master_slider.set_value_no_signal(roundf(master * 100.0))
    _sfx_slider.set_value_no_signal(roundf(sfx * 100.0))
    _music_slider.set_value_no_signal(roundf(music * 100.0))
    _sync_quality()
    if _aim_slider:
        _aim_slider.set_value_no_signal(aim_assist_deg)
        _aim_label.text = "%.1f°" % aim_assist_deg
    _update_labels()

func _gq() -> Node:
    return get_node_or_null("/root/GraphicsQuality")

func _sync_quality() -> void:
    var gq := _gq()
    if gq:
        _quality_option.select(int(gq.quality))

func _on_quality_changed(idx: int) -> void:
    var gq := _gq()
    if gq:
        gq.set_quality(idx)

func _on_master_changed(_v: float) -> void:
    var audio = get_node_or_null("/root/AudioManager")
    if audio:
        audio.set_master_volume(_master_slider.value / 100.0)
    _update_labels()

func _on_sfx_changed(_v: float) -> void:
    var audio = get_node_or_null("/root/AudioManager")
    if audio:
        audio.set_sfx_volume(_sfx_slider.value / 100.0)
    _update_labels()

func _on_music_changed(_v: float) -> void:
    var audio = get_node_or_null("/root/AudioManager")
    if audio:
        audio.set_music_volume(_music_slider.value / 100.0)
    _update_labels()

func _update_labels() -> void:
    _master_label.text = str(int(roundf(_master_slider.value))) + "%"
    _sfx_label.text = str(int(roundf(_sfx_slider.value))) + "%"
    _music_label.text = str(int(roundf(_music_slider.value))) + "%"

func _on_test_sound() -> void:
    var audio = get_node_or_null("/root/AudioManager")
    if not audio or not ResourceLoader.exists(TEST_SOUND):
        return
    audio.play_sfx(load(TEST_SOUND), 0.0)
