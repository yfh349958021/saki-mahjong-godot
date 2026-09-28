class_name MTile
extends RefCounted
## 牌的纯逻辑工具(无任何 UI / Node 依赖,可在 --headless 下独立运行)。
##
## 编码体系:
##   kind(种类)0..8 = 一万..九万, 9..17 = 一筒..九筒, 18..26 = 一索..九索,
##   27..33 = 東南西北白發中。共 34 种。
##   tile id(实体牌)= kind * 4 + n,n ∈ 0..3,共 136 张。
##   红宝牌:5万/5筒/5索 各一张,取 n == 0 的那张。

const KIND_COUNT: int = 34
const TOTAL_TILES: int = 136

const SUIT_MAN: int = 0
const SUIT_PIN: int = 1
const SUIT_SOU: int = 2
const SUIT_HONOR: int = 3

const RED_KINDS: Array[int] = [4, 13, 22]  # 5万 / 5筒 / 5索

const HONOR_LABELS: Array[String] = ["東", "南", "西", "北", "白", "發", "中"]
const SUIT_LABELS: Array[String] = ["萬", "筒", "索"]

const EAST: int = 27
const SOUTH: int = 28
const WEST: int = 29
const NORTH: int = 30
const HAKU: int = 31
const HATSU: int = 32
const CHUN: int = 33

const TERMINAL_KINDS: Array[int] = [
	0, 8, 9, 17, 18, 26,  # 幺九数牌
	27, 28, 29, 30, 31, 32, 33,  # 字牌
]


static func suit(kind: int) -> int:
	return kind / 9


static func rank(kind: int) -> int:
	# 字牌返回 0,数牌返回 1..9
	return kind % 9 + 1 if kind < 27 else 0


static func is_honor(kind: int) -> bool:
	return kind >= 27


static func is_terminal(kind: int) -> bool:
	return kind == 0 or kind == 8 or kind == 9 or kind == 17 \
		or kind == 18 or kind == 26 or kind >= 27


static func kind_of(tile_id: int) -> int:
	return tile_id / 4


static func is_red(tile_id: int) -> bool:
	return tile_id % 4 == 0 and tile_id / 4 in RED_KINDS


## 同花色内将 kind 平移 delta(+1 / -1),越界或字牌返回 -1。
## 这是“宫永咲 ±1”类技能的底层操作。
static func shift_kind(kind: int, delta: int) -> int:
	if is_honor(kind):
		return -1
	var r := rank(kind) + delta
	if r < 1 or r > 9:
		return -1
	return suit(kind) * 9 + (r - 1)


static func label(kind: int) -> String:
	if is_honor(kind):
		return HONOR_LABELS[kind - 27]
	return "%d%s" % [rank(kind), SUIT_LABELS[suit(kind)]]


static func label_id(tile_id: int) -> String:
	var s := label(kind_of(tile_id))
	return s if not is_red(tile_id) else "红" + s


## 便捷构造:把 "123m456p12s東" 形式的简写展开为 tile id 数组(测试用)。
## 数牌:数字 + m/p/s;字牌:東南西北白發中(或 1z..7z)。
static func parse(short: String) -> Array[int]:
	var out: Array[int] = []
	var digits: Array[int] = []
	for ch in short:
		var c := ch.to_lower()
		if c >= "1" and c <= "9":
			digits.append(int(c))
		elif c == "0":
			digits.append(0)  # 红宝牌 0m/0p/0s
		elif c == "m" or c == "p" or c == "s":
			var suit_id: int = {"m": 0, "p": 1, "s": 2}[c]
			for d in digits:
				var rank_v := 5 if d == 0 else d  # 0 = 红宝牌 5
				out.append((suit_id * 9 + rank_v - 1) * 4 + (0 if d == 0 else 1))
			digits.clear()
		elif HONOR_LABELS.has(ch):
			out.append((27 + HONOR_LABELS.find(ch)) * 4 + 1)
		elif c >= "a" and c <= "g":
			out.append((27 + (c.unicode_at(0) - 97)) * 4 + 1)
	return out


## 把 id 数组转成 34 维计数表。
static func to_counts(ids: Array) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(KIND_COUNT)
	counts.fill(0)
	for id in ids:
		counts[kind_of(id)] += 1
	return counts
