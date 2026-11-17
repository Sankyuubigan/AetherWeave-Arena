extends "res://Logic/Skills/Effect.gd"

@export var audio_stream: AudioStream
## Пул рандомной ротации (17.11.26, сердечко-дзынь): если непуст, каждый
## каст играет случайный вариант из пула, audio_stream игнорируется.
## Нетипизированный Array: литерал из SkillDB нельзя присвоить типизированному
## свойству («Invalid assignment» — поймал смоук), валидация в apply.
@export var audio_streams: Array = []
@export var volume_db: float = 0.0

func apply(caster: Node, _context: Dictionary) -> void:
    var pool: Array = audio_streams.filter(func(s): return s is AudioStream)
    var stream: AudioStream = audio_stream
    if not pool.is_empty():
        stream = pool[randi() % pool.size()]
    if not stream or not caster:
        return
    var tree = caster.get_tree()
    if not tree:
        return
    var audio_manager = tree.root.get_node_or_null("AudioManager")
    if audio_manager and audio_manager.has_method("play_sfx"):
        audio_manager.play_sfx(stream, volume_db)
