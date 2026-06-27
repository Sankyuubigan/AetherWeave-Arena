extends Node

var file: FileAccess

func _ready():
    var dir = DirAccess.open("res://")
    if dir:
        dir.make_dir_recursive("test")
    file = FileAccess.open("res://test/last_logs.txt", FileAccess.WRITE)
    if file:
        file.store_string("")
        file.close()

func log_message(msg: String):
    file = FileAccess.open("res://test/last_logs.txt", FileAccess.READ_WRITE)
    if file:
        file.seek_end()
        file.store_line(msg)
        file.close()
