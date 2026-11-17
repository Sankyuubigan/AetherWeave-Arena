extends Node

## Громкости (линейные 0..1): Master — общая, SFX — эффекты, Music — музыка.
## Шины SFX и Music создаются кодом (SFX здесь, Music — в MusicDirector),
## обе отправляются в Master. Значения хранятся в user://settings.cfg.

const SETTINGS_PATH := "user://settings.cfg"

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0

func _ready():
    _ensure_sfx_bus()
    _load_settings()
    _apply_bus("Master", master_volume)
    _apply_bus("SFX", sfx_volume)
    _apply_bus("Music", music_volume)

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

## Вызывается из MusicDirector ПОСЛЕ создания шины Music: автолоад AudioManager
## грузится раньше, шины ещё не было — теперь применяем сохранённое значение.
func apply_music_volume() -> void:
    _apply_bus("Music", music_volume)

func _apply_bus(bus_name: String, v: float) -> void:
    var idx := AudioServer.get_bus_index(bus_name)
    if idx < 0:
        return
    AudioServer.set_bus_mute(idx, v <= 0.001)
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

func _save_settings() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("audio", "master_volume", master_volume)
    cfg.set_value("audio", "sfx_volume", sfx_volume)
    cfg.set_value("audio", "music_volume", music_volume)
    cfg.save(SETTINGS_PATH)

func _on_player_finished(player: AudioStreamPlayer):
    if is_instance_valid(player):
        player.queue_free()
