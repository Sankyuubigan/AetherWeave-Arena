extends Node

## Общая громкость (линейная 0..1). Управляет Master-шиной —
## играет всё: SFX, музыка, звуки скиллов.
var master_volume: float = 1.0

const SETTINGS_PATH := "user://settings.cfg"

func _ready():
    _load_settings()
    _apply_master_volume()

func play_sfx(stream: AudioStream, volume_db: float = 0.0):
    if not stream:
        return
    var player = AudioStreamPlayer.new()
    player.stream = stream
    player.volume_db = volume_db + 6.0
    player.bus = "Master"
    add_child(player)
    player.finished.connect(_on_player_finished.bind(player))
    player.play()

## Вызывается из SettingsMenu (F2). v: 0..1 линейно.
func set_master_volume(v: float) -> void:
    master_volume = clampf(v, 0.0, 1.0)
    _apply_master_volume()
    _save_settings()

func _apply_master_volume() -> void:
    var idx := AudioServer.get_bus_index("Master")
    if idx < 0:
        return
    AudioServer.set_bus_mute(idx, master_volume <= 0.001)
    if master_volume > 0.001:
        AudioServer.set_bus_volume_db(idx, linear_to_db(master_volume))

func _load_settings() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SETTINGS_PATH) != OK:
        return
    master_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)

func _save_settings() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("audio", "master_volume", master_volume)
    cfg.save(SETTINGS_PATH)

func _on_player_finished(player: AudioStreamPlayer):
    if is_instance_valid(player):
        player.queue_free()
