extends Node

## Музыка карт (17.11.26): фоновая дорожка по карте + боевой луп при бою.
## Автозагрузка (/root/MusicDirector). Шина «Music» создаётся кодом.
## Фон играет ВСЕГДА (луп из .res, loop_mode в ресурсе), боевой луп НАКЛАДЫВАЕТСЯ
## поверх, фон при этом приглушается — нет проблем синхронизации рестартов.
## Триггер боя: note_combat() из HealthComponent.take_damage (урон в любую
## сторону). Когда появятся боты — тот же API дергается из их ИИ.
## План: tasks/261116_2218-b2a0cddb/17.11.26 Музыка карт.md

const TRACKS := {
    "MainArena": "res://Audio/Music/map1_ambient.res",
    "ProceduralArena": "res://Audio/Music/map2_ambient.res",
}
const COMBAT_TRACK := "res://Audio/Music/combat_loop.res"
const FADE_IN := 1.5
const FADE_OUT := 2.0
const BG_DB := 0.0
const BG_DUCK_DB := -12.0
const COMBAT_HOLD := 12.0

var bg: AudioStreamPlayer
var combat: AudioStreamPlayer
var _map: String = ""
var _combat_left: float = 0.0
var _combat_tween: Tween

func _ready():
    _ensure_bus()
    # Шина Music появилась только что (автолоад AudioManager грузился раньше) —
    # применяем сохранённую громкость музыки.
    var audio = get_node_or_null("/root/AudioManager")
    if audio:
        audio.apply_music_volume()
    bg = _make_player()
    combat = _make_player()
    process_mode = Node.PROCESS_MODE_ALWAYS

func _ensure_bus() -> void:
    if AudioServer.get_bus_index("Music") < 0:
        AudioServer.add_bus()
        var i := AudioServer.bus_count - 1
        AudioServer.set_bus_name(i, "Music")
        AudioServer.set_bus_send(i, "Master")

func _make_player() -> AudioStreamPlayer:
    var p := AudioStreamPlayer.new()
    p.bus = "Music"
    add_child(p)
    return p

## Смена карты — по имени текущей сцены (каждый кадр дешёвая проверка)
func _process(delta):
    var scene := get_tree().current_scene
    var sname := String(scene.name) if scene else ""
    if sname != _map and TRACKS.has(sname):
        _map = sname
        _switch_bg(load(TRACKS[sname]))
    if _combat_left > 0.0:
        _combat_left -= delta
        if _combat_left <= 0.0:
            _combat_release()

## Событие «идёт бой»: боевой луп поверх фона на COMBAT_HOLD секунд
func note_combat(seconds: float = COMBAT_HOLD) -> void:
    _combat_left = seconds
    if combat.playing:
        return
    var s = load(COMBAT_TRACK)
    if s == null:
        print("MusicDirector: нет ", COMBAT_TRACK)
        return
    combat.stream = s
    combat.volume_db = -40.0
    combat.play()
    if _combat_tween:
        _combat_tween.kill()
    _combat_tween = create_tween()
    _combat_tween.tween_property(combat, "volume_db", BG_DB, FADE_IN)
    _fade(bg, BG_DUCK_DB, FADE_IN)

func _combat_release() -> void:
    if _combat_tween:
        _combat_tween.kill()
    _combat_tween = create_tween()
    _combat_tween.tween_property(combat, "volume_db", -40.0, FADE_OUT)
    _combat_tween.tween_callback(combat.stop)
    _fade(bg, BG_DB, FADE_OUT)

func _switch_bg(stream: AudioStream) -> void:
    if stream == null:
        return
    if bg.playing:
        var old := bg
        var tw := create_tween()
        tw.tween_property(old, "volume_db", -40.0, FADE_OUT)
        tw.tween_callback(old.stop)
        bg = _make_player()                       # новый плеер — старый доигрывает
        bg.stream = stream
        bg.volume_db = -40.0
        bg.play()
        _fade(bg, BG_DB, FADE_IN)
    else:
        bg.stream = stream
        bg.volume_db = -40.0
        bg.play()
        _fade(bg, BG_DB, FADE_IN)

func _fade(p: AudioStreamPlayer, to_db: float, dur: float) -> Tween:
    var tw := create_tween()
    tw.tween_property(p, "volume_db", to_db, dur)
    return tw
