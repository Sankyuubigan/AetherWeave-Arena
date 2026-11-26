extends SceneTree

var frames = 0

func _process(delta):
    if frames == 0:
        var root = get_root()
        var packed = load("res://Scenes/player.tscn")
        var test = Node.new()
        test.set_script(load("res://Generators/test_runner.gd"))
        root.add_child(test)
    frames += 1
    # SceneTree._process(delta) -> bool: true = выйти из цикла. Без этого
    # return скрипт не компилировался («Not all code paths return a value»,
    # найдено гейтом check_parse.gd 27.11.26).
    return false