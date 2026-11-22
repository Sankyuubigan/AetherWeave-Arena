extends SceneTree

func _dump(tag: String) -> void:
	var c := ConfigFile.new()
	c.load("user://settings.cfg")
	print(tag, " bard=", c.get_value("audio", "bard_volume", "<нет>"),
			" offs=", c.get_value("audio", "audio_offset_ms", "<нет>"))

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var am = root.get_node_or_null("AudioManager")
	print("am=", am)
	_dump("start:")
	am.set_bard_volume(0.5)
	_dump("after 0.5:")
	am.set_bard_volume(1.0)
	_dump("after 1.0:")
	am.set_audio_offset_ms(-45.0)
	_dump("after -45:")
	am.set_audio_offset_ms(0.0)
	_dump("after 0.0:")
	quit(0)
