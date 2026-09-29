extends SceneTree
var main
var frames := 0


func _initialize() -> void:
	main = load("res://main.gd").new()
	root.add_child(main)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 8:
		var img := root.get_texture().get_image()
		img.save_png("/tmp/saki_menu.png")
		print("[dbg] menu saved")
		main.net.my_name = "房主"
		main.net.host_game()
		main.net.my_char = "saki"
		main.net.host_set_char("saki")
		main.net.host_add_ai(1)
		main._build_room()
	if frames == 20:
		var img2 := root.get_texture().get_image()
		img2.save_png("/tmp/saki_room.png")
		print("[dbg] room saved")
		quit(0)
	return false
