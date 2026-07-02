extends "res://Logic/Skills/Effect.gd"

@export var audio_stream: AudioStream
@export var volume_db: float = 0.0

func apply(caster: Node, _context: Dictionary) -> void:
    if not audio_stream or not caster:
        return
    var tree = caster.get_tree()
    if not tree:
        return
    var audio_manager = tree.root.get_node_or_null("AudioManager")
    if audio_manager and audio_manager.has_method("play_sfx"):
        audio_manager.play_sfx(audio_stream, volume_db)
