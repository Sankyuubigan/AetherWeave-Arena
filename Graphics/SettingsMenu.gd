extends CanvasLayer

## Окно настроек (автолоад): громкости (общая/эффекты/музыка/бард) + тест-звук,
## качество графики, чувствительность наведения, компенсация задержки звука
## с калибровкой (Q16 Шаг 5: 8 нажатий под метроном RhythmConductor → медиана).
## Открытие/закрытие — F2. Значения через AudioManager в user://settings.cfg.
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
## Q16 Шаг 5: громкость Барда + компенсация задержки звука + калибровка.
var _bard_slider: HSlider
var _bard_label: Label
var _offset_slider: HSlider
var _offset_label: Label
var _calib_button: Button
var _calib_hint: Label
var _calib_on := false
var _calib_deltas: Array = []
var _calib_cond: Node = null
var _calib_cond_started := false

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
    # Q33 (юзер 19.11.26): панель прижата к ВЕРХУ экрана — у PRESET_CENTER
    # при росте контента низ вылезал за кадр. Выезд сверху при открытии (_slide_in).
    _panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
    _panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _panel.grow_vertical = Control.GROW_DIRECTION_END
    _panel.offset_top = 48
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

    # Q16 Шаг 5: громкость Барда (шина Bard — Поток + ритм-луп).
    var bard := _add_volume_row(vbox, "Бард:")
    _bard_slider = bard[0]
    _bard_label = bard[1]
    _bard_slider.value_changed.connect(_on_bard_changed)

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

    # Q16 Шаг 5: компенсация задержки звука (−150..+150 мс) + калибровка —
    # 8 нажатий в ритм метронома 120 BPM → медиана отклонения → audio_offset_ms.
    var orow := HBoxContainer.new()
    orow.add_theme_constant_override("separation", 10)
    vbox.add_child(orow)
    var ocap := Label.new()
    ocap.text = "Компенсация звука:"
    orow.add_child(ocap)
    _offset_label = Label.new()
    _offset_label.text = "+0 мс"
    orow.add_child(_offset_label)
    _offset_slider = HSlider.new()
    _offset_slider.min_value = -150.0
    _offset_slider.max_value = 150.0
    _offset_slider.step = 5.0
    _offset_slider.value = 0.0
    _offset_slider.custom_minimum_size = Vector2(0, 24)
    vbox.add_child(_offset_slider)
    _offset_slider.value_changed.connect(_on_offset_changed)

    _calib_button = Button.new()
    _calib_button.text = "Калибровать (8 нажатий в ритм)"
    _calib_button.pressed.connect(_on_calibrate_pressed)
    vbox.add_child(_calib_button)

    _calib_hint = Label.new()
    _calib_hint.add_theme_font_size_override("font_size", 13)
    _calib_hint.modulate = Color(1, 1, 1, 0.75)
    _calib_hint.visible = false
    vbox.add_child(_calib_hint)

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

## Q33: выезд панели сверху при открытии (после кадра лейаута панель знает
## свой размер; рисуем старт за верхней кромкой и доводим tween'ом).
func _slide_in() -> void:
    await get_tree().process_frame
    if not is_open or _root == null:
        return
    var target_y := _panel.position.y
    _panel.position.y = -_panel.size.y - 24.0
    var tw := create_tween()
    tw.tween_property(_panel, "position:y", target_y, 0.22) \
        .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## _unhandled_input: не сработает, пока GUI занят событиями (печать текста).
func _unhandled_input(event):
    # Q16 Шаг 5: во время калибровки ЛЮБАЯ клавиша (кроме F2) = нажатие в ритм.
    if event is InputEventKey and event.pressed and not event.echo \
            and _calib_on and event.keycode != KEY_F2:
        _calib_press()
        return
    if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
        is_open = !is_open
        if is_open:
            _sync_from_audio()
            _root.show()
            _slide_in()
            # МЫШЬ ССОТ (docs/ui_input_rules.md): открытие UI делает мышь
            # видимой; закрытие её НЕ трогает — клик по миру вернёт захват.
            Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
        else:
            _calib_cancel()
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
    var bard: float = audio.bard_volume if audio else 1.0
    var offs: float = audio.audio_offset_ms if audio else 0.0
    _master_slider.set_value_no_signal(roundf(master * 100.0))
    _sfx_slider.set_value_no_signal(roundf(sfx * 100.0))
    _music_slider.set_value_no_signal(roundf(music * 100.0))
    _bard_slider.set_value_no_signal(roundf(bard * 100.0))
    _offset_slider.set_value_no_signal(offs)
    _offset_label.text = "%+d мс" % int(roundf(offs))
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

func _on_bard_changed(_v: float) -> void:
    var audio = get_node_or_null("/root/AudioManager")
    if audio:
        audio.set_bard_volume(_bard_slider.value / 100.0)
    _update_labels()

func _on_offset_changed(v: float) -> void:
    _offset_label.text = "%+d мс" % int(roundf(v))
    var audio = get_node_or_null("/root/AudioManager")
    if audio:
        audio.set_audio_offset_ms(v)

## ── Калибровка задержки звука (Q16 Шаг 5) ────────────────────────────────
## Метроном — RhythmConductor на 120 BPM (тик = клик TEST_SOUND). Игрок жмёт
## ЛЮБУЮ клавишу 8 раз в ритм; отклонение нажатия от ближайшей доли (0.5 с)
## → медиана → offset = −медиана (жмёт поздно → отрицательный оффсет).
## Если conductor уже играет (Поток) — метроном не трогаем, только слушаем.
const CALIB_PRESSES := 8
const CALIB_BPM := 120.0
const CALIB_BEAT := 0.5

func _on_calibrate_pressed() -> void:
    if _calib_on:
        _calib_finish(true)  # повторный клик по кнопке = отмена
        return
    var cond = get_node_or_null("/root/RhythmConductor")
    if cond == null:
        _calib_hint.text = "Нет RhythmConductor"
        _calib_hint.visible = true
        return
    _calib_cond = cond
    _calib_cond_started = not cond.is_running
    if _calib_cond_started:
        cond.start(CALIB_BPM)
    if not cond.beat_tick.is_connected(_on_calib_beat):
        cond.beat_tick.connect(_on_calib_beat)
    _calib_deltas.clear()
    _calib_on = true
    _calib_button.text = "Стоп калибровки"
    _calib_hint.visible = true
    _calib_hint.text = "Жми ЛЮБУЮ клавишу в ритм: 0/8"
    # Фокус у кнопки съел бы ПРОБЕЛ (повторный press) — снимаем.
    _calib_button.release_focus()

func _on_calib_beat(_bar: int, _beat: int) -> void:
    var audio = get_node_or_null("/root/AudioManager")
    if audio and ResourceLoader.exists(TEST_SOUND):
        audio.play_sfx(load(TEST_SOUND), -4.0)

func _calib_press() -> void:
    if not _calib_on or _calib_cond == null:
        return
    var t: float = _calib_cond.song_time
    _calib_deltas.append(t - roundf(t / CALIB_BEAT) * CALIB_BEAT)
    _calib_hint.text = "Жми ЛЮБУЮ клавишу в ритм: %d/8" % _calib_deltas.size()
    if _calib_deltas.size() >= CALIB_PRESSES:
        _calib_finish(false)

func _calib_cancel() -> void:
    if _calib_on:
        _calib_finish(true)

func _calib_finish(cancelled: bool) -> void:
    if _calib_cond != null and _calib_cond.beat_tick.is_connected(_on_calib_beat):
        _calib_cond.beat_tick.disconnect(_on_calib_beat)
    if _calib_cond != null and _calib_cond_started:
        _calib_cond.stop()
    _calib_cond = null
    _calib_on = false
    _calib_button.text = "Калибровать (8 нажатий в ритм)"
    _calib_hint.visible = false
    if cancelled:
        return
    var offs := _offset_from_deltas(_calib_deltas)
    var audio = get_node_or_null("/root/AudioManager")
    if audio:
        audio.set_audio_offset_ms(offs)
    _offset_slider.set_value_no_signal(offs)
    _offset_label.text = "%+d мс" % int(roundf(offs))

## Медиана отклонений → оффсет в мс (округление до 5, кламп ±150).
## Знак: стабильно поздние нажатия (медиана > 0) → отрицательный оффсет.
func _offset_from_deltas(deltas: Array) -> float:
    if deltas.is_empty():
        return 0.0
    var s := deltas.duplicate()
    s.sort()
    var n: int = s.size()
    var med: float = s[n / 2] if n % 2 == 1 else (s[n / 2 - 1] + s[n / 2]) * 0.5
    return clampf(roundf(-med * 1000.0 / 5.0) * 5.0, -150.0, 150.0)

func _update_labels() -> void:
    _master_label.text = str(int(roundf(_master_slider.value))) + "%"
    _sfx_label.text = str(int(roundf(_sfx_slider.value))) + "%"
    _music_label.text = str(int(roundf(_music_slider.value))) + "%"
    _bard_label.text = str(int(roundf(_bard_slider.value))) + "%"

func _on_test_sound() -> void:
    var audio = get_node_or_null("/root/AudioManager")
    if not audio or not ResourceLoader.exists(TEST_SOUND):
        return
    audio.play_sfx(load(TEST_SOUND), 0.0)
