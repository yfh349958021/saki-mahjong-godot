extends SceneTree

func _initialize() -> void:
	# 散乱手牌(最坏情况)与听牌手的向听计算基准
	var scattered := MTile.parse("19m19p19s1234567z")
	var near_win := MTile.parse("123m456m789m123s4s")
	var t0 := Time.get_ticks_msec()
	var acc := 0
	for i in 100:
		MShanten.reset_memo()
		acc += MShanten.for_tiles(scattered)
	var t1 := Time.get_ticks_msec()
	for i in 100:
		MShanten.reset_memo()
		acc += MShanten.for_tiles(near_win)
	var t2 := Time.get_ticks_msec()
	print("散乱 100 次(无 memo 复用) = %d ms; 听牌 100 次 = %d ms (acc=%d)" % [t1 - t0, t2 - t1, acc])
	# memo 热身后 1400 次调用(模拟一手牌的 14 候选 × 100 巡)
	MShanten.reset_memo()
	var t3 := Time.get_ticks_msec()
	for i in 100:
		for k in scattered.size():
			var out: Array[int] = []
			for j in scattered.size():
				if j != k:
					out.append(scattered[j])
			acc += MShanten.for_tiles(out)
	var t4 := Time.get_ticks_msec()
	print("热 memo 后 1400 次打牌候选扫描 = %d ms (acc=%d)" % [t4 - t3, acc])
	quit(0)
