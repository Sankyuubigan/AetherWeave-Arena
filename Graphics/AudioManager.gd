extends Node

## Громкости (линейные 0..1): Master — общая, SFX — эффекты, Music — музыка,
## Bard — «Поток Барда» (Q16 Шаг 5). Шины SFX/Bard создаются здесь, Music —
## в MusicDirector, все отправляются в Master. Значения в user://settings.cfg.

const SETTINGS_PATH := "user://settings.cfg"

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0
var bard_volume: float = 1.0
## Компенсация задержки звука (Q16 Шаг 5): −150..+150 мс. Пишется калибровкой
## SettingsMenu («Калибровать»: 8 нажатий → медиана), читается RhythmJudge
## через _eff_offset_ms() при каждой оценке (живое применение без перезапуска).
var audio_offset_ms: float = 0.0

## Нет фокуса у окна игры (клик в другое окно, свёрнуто) → весь звук глушится
## (директива юзера 18.11.26: музыка/звуки не должны играть вне фокуса).
## Отдельный флаг поверх громкостей: settings.cfg НЕ трогаем, при возврате
## фокуса звук восстанавливается ровно как был.
var _unfocused: bool = false

func _notification(what: int) -> void:
    match what:
        Node.NOTIFICATION_APPLICATION_FOCUS_OUT:
            _unfocused = true
            _apply_all_buses()
        Node.NOTIFICATION_APPLICATION_FOCUS_IN:
            _unfocused = false
            _apply_all_buses()

func _apply_all_buses() -> void:
    # Шина Music может ещё не существовать (создаёт MusicDirector) — _apply_bus
    # молча пропустит, а MusicDirector.apply_music_volume() доведёт позже.
    _apply_bus("Master", master_volume)
    _apply_bus("SFX", sfx_volume)
    _apply_bus("Music", music_volume)
    _apply_bus("Bard", bard_volume)

func _ready():
    _ensure_sfx_bus()
    _ensure_bard_bus()
    _ensure_master_limiter()
    _load_settings()
    _apply_bus("Master", master_volume)
    _apply_bus("SFX", sfx_volume)
    _apply_bus("Music", music_volume)
    _apply_bus("Bard", bard_volume)

## Шина Bard (Q16 Шаг 5): полифонические ноты Потока + ритм-луп барда.
## Лимитер на Master уже страхует сумму шин от клипа.
func _ensure_bard_bus() -> void:
    if AudioServer.get_bus_index("Bard") >= 0:
        return
    AudioServer.add_bus()
    var i := AudioServer.bus_count - 1
    AudioServer.set_bus_name(i, "Bard")
    AudioServer.set_bus_send(i, "Master")

## Предохранитель от клипа на выходе (фишка из демо audio/audio_effects):
## ассеты нормированы K-LUFS по отдельности, но Music + боевой луп + SFX на
## пике вместе могут превысить 0 dBFS. Лимитер прижимает только пики,
## при обычных уровнях звук не меняет.
func _ensure_master_limiter() -> void:
    for i in AudioServer.get_bus_effect_count(0):
        if AudioServer.get_bus_effect(0, i) is AudioEffectLimiter:
            return
    var lim := AudioEffectLimiter.new()
    lim.threshold_db = -3.0
    lim.ceiling_db = -0.8
    AudioServer.add_bus_effect(0, lim)

func play_sfx(stream: AudioStream, volume_db: float = 0.0):
    if not stream:
        return
    var player = AudioStreamPlayer.new()
    player.stream = stream
    player.volume_db = volume_db + 6.0
    player.bus = "SFX"
    add_child(player)
    player.finished.connect(_on_player_finished.bind(player))
    player.play()

## Вызывается из SettingsMenu (F2). v: 0..1 линейно.
func set_master_volume(v: float) -> void:
    master_volume = clampf(v, 0.0, 1.0)
    _apply_bus("Master", master_volume)
    _save_settings()

func set_sfx_volume(v: float) -> void:
    sfx_volume = clampf(v, 0.0, 1.0)
    _apply_bus("SFX", sfx_volume)
    _save_settings()

func set_music_volume(v: float) -> void:
    music_volume = clampf(v, 0.0, 1.0)
    _apply_bus("Music", music_volume)
    _save_settings()

func set_bard_volume(v: float) -> void:
    bard_volume = clampf(v, 0.0, 1.0)
    _apply_bus("Bard", bard_volume)
    _save_settings()

## Калибровка (SettingsMenu) пишет, RhythmJudge читает при каждой оценке.
func set_audio_offset_ms(v: float) -> void:
    audio_offset_ms = clampf(v, -150.0, 150.0)
    _save_settings()

## Вызывается из MusicDirector ПОСЛЕ создания шины Music: автолоад AudioManager
## грузится раньше, шины ещё не было — теперь применяем сохранённое значение.
func apply_music_volume() -> void:
    _apply_bus("Music", music_volume)

func _apply_bus(bus_name: String, v: float) -> void:
    var idx := AudioServer.get_bus_index(bus_name)
    if idx < 0:
        return
    # Мьют = нет фокуса ИЛИ громкость 0 (mute-флаг фокуса независим от настроек).
    AudioServer.set_bus_mute(idx, _unfocused or v <= 0.001)
    if v > 0.001:
        AudioServer.set_bus_volume_db(idx, linear_to_db(v))

func _ensure_sfx_bus() -> void:
    if AudioServer.get_bus_index("SFX") >= 0:
        return
    AudioServer.add_bus()
    var i := AudioServer.bus_count - 1
    AudioServer.set_bus_name(i, "SFX")
    AudioServer.set_bus_send(i, "Master")

func _load_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) != OK:
        return
    master_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
    sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)
    music_volume = clampf(float(cfg.get_value("audio", "music_volume", 1.0)), 0.0, 1.0)
    bard_volume = clampf(float(cfg.get_value("audio", "bard_volume", 1.0)), 0.0, 1.0)
    audio_offset_ms = clampf(float(cfg.get_value("audio", "audio_offset_ms", 0.0)),
            -150.0, 150.0)

func _save_settings() -> void:
    # Догруз существующего файла: GraphicsQuality пишет секцию [graphics] в тот
    # же user://settings.cfg — новая ConfigFile без load() стёрла бы её.
    var cfg := ConfigFile.new()
    cfg.load(SETTINGS_PATH)
    cfg.set_value("audio", "master_volume", master_volume)
    cfg.set_value("audio", "sfx_volume", sfx_volume)
    cfg.set_value("audio", "music_volume", music_volume)
    cfg.set_value("audio", "bard_volume", bard_volume)
    cfg.set_value("audio", "audio_offset_ms", audio_offset_ms)
    cfg.save(SETTINGS_PATH)

func _on_player_finished(player: AudioStreamPlayer):
    if is_instance_valid(player):
        player.queue_free()
