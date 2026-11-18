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
## Синхронизация боевого лупа с тактовой сеткой (фишка из демо audio/bpm_sync):
## gen_music.gd пишет combat_loop на 120 BPM (16 с = 8 тактов × 2 с), и бас-пульс
## фона map1 стоит на тех же 2 с. Старт боевого лупа на границе такта фона →
## удары совпадают всегда (лупы 32 с и 16 с сходятся на сетке 2 с).
const COMBAT_BPM := 120.0
const BAR_SEC := 240.0 / COMBAT_BPM  # такт = 2.0 с
const FRAME_HZ := 60.0
const POS_SMOOTH_FRAMES := 2

var bg: AudioStreamPlayer
var combat: AudioStreamPlayer
var _map: String = ""
var _combat_left: float = 0.0
var _combat_tween: Tween
var _combat_pending: bool = false    # бой активен, луп ждёт границы такта
var _stall_time: float = 0.0         # позиция фона не растёт (headless) — fallback
var _pos_last: float = -1.0
var _combat_stream: AudioStream
var last_start_synced: bool = false  # для теста: старт синхронный (не fallback)

func _ready():
    _ensure_bus()
    # Шина Music появилась только что (автолоад AudioManager грузился раньше) —
    # применяем сохранённую громкость музыки.
    var audio = get_node_or_null("/root/AudioManager")
    if audio:
        audio.apply_music_volume()
    bg = _make_player()
    combat = _make_player()
    # Стрим боевого лупа грузим один раз на старте — в бою без хиккапа.
    if ResourceLoader.exists(COMBAT_TRACK):
        _combat_stream = load(COMBAT_TRACK)
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
        _event("music_switch:" + sname)
        _switch_bg(load(TRACKS[sname]))
    if _combat_pending:
        _try_start_combat(delta)
    if _combat_left > 0.0:
        _combat_left -= delta
        if _combat_left <= 0.0:
            _combat_pending = false
            _combat_release()

## Событие «идёт бой»: боевой луп поверх фона на COMBAT_HOLD секунд.
## Старт не мгновенный: pending до ближайшей границы такта фона (BAR_SEC),
## чтобы удары боевого лупа легли в пульс фона. Нет фона — старт сразу.
func note_combat(seconds: float = COMBAT_HOLD) -> void:
    _event("combat_music")
    _combat_left = seconds
    if combat.playing or _combat_pending:
        return
    if _combat_stream == null:
        print("MusicDirector: нет ", COMBAT_TRACK)
        return
    _combat_pending = true
    _stall_time = 0.0
    _pos_last = -1.0

func _try_start_combat(delta: float) -> void:
    if not bg.playing:
        _start_combat_now(false)
        return
    var pos := _stable_pos(bg)
    # Страховка: позиция фона не растёт (headless-драйвер без времени) —
    # синхронизацию не ждём, стартуем сразу.
    if absf(pos - _pos_last) < 0.00001:
        _stall_time += delta
        if _stall_time >= 0.5:
            _start_combat_now(false)
            return
    else:
        _stall_time = 0.0
    _pos_last = pos
    var to_bar := fmod(BAR_SEC - fmod(pos, BAR_SEC), BAR_SEC)
    # Стартуем заранее ровно на столько, чтобы звук вышел из колонок у границы:
    # до следующего микса + латентность вывода.
    if to_bar <= AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency():
        _start_combat_now(true)

func _start_combat_now(synced: bool) -> void:
    _combat_pending = false
    last_start_synced = synced
    _event("combat_music_synced" if synced else "combat_music_fallback")
    combat.stream = _combat_stream
    combat.volume_db = -40.0
    combat.play()
    if _combat_tween:
        _combat_tween.kill()
    _combat_tween = create_tween()
    _combat_tween.tween_property(combat, "volume_db", BG_DB, FADE_IN)
    _fade(bg, BG_DUCK_DB, FADE_IN)

## Стабильная позиция дорожки (приём из демо audio/bpm_sync):
## playback_position + время с последнего микса - латентность вывода.
func _stable_pos(p: AudioStreamPlayer) -> float:
    return p.get_playback_position() + AudioServer.get_time_since_last_mix() \
            - AudioServer.get_output_latency() + (1.0 / FRAME_HZ) * POS_SMOOTH_FRAMES

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

## Маркер для StallLogger (ловца фризов): автолоад может отсутствовать.
func _event(what: String) -> void:
    var sl := get_node_or_null("/root/StallLogger")
    if sl:
        sl.event(what)
