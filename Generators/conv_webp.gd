extends SceneTree
## Конвертация картинок в png для просмотра: conv_webp.gd <путь1> [путь2 ...]
func _init():
	for a in OS.get_cmdline_user_args():
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(a))
		if img:
			img.save_png(a.get_basename() + ".png")
			print("CV: ", a)
	quit(0)
