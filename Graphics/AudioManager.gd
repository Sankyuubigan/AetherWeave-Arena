extends Node

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

func _on_player_finished(player: AudioStreamPlayer):
    if is_instance_valid(player):
        player.queue_free()
