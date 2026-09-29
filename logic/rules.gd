class_name MRules
extends RefCounted
## 对局规则配置:房主可在房间内调整;以字典承载,缺省合并。

const DEFAULTS := {
	"start_score": 25000,   # 初始点数:25000 / 35000
	"red_dora": 3,          # 红宝牌数量:0 / 3
	"kuitan": true,         # 食断:副露是否允许断幺九
	"ippatsu": true,        # 一发
	"ura": true,            # 里宝
	"ai_difficulty": 1,     # AI 难度:0 简单 / 1 普通 / 2 困难
}


static func merged(rules: Dictionary = {}) -> Dictionary:
	var out := DEFAULTS.duplicate()
	for k in rules:
		if out.has(k):
			out[k] = rules[k]
	return out
