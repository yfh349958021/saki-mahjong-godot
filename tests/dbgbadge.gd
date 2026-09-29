extends SceneTree
func _initialize() -> void:
	var main = load("res://main.gd").new()
	root.add_child(main)
	var badges = main.get("_badges")
	print("badges size: ", badges.size())
	var b = badges[0]
	for c in b.get_children():
		print("child: ", c.name)
		for cc in c.get_children():
			print("   . ", cc.name, " (", cc.get_class(), ")")
			for ccc in cc.get_children():
				print("       . ", ccc.name)
	quit(0)
