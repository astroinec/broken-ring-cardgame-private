class_name BattleCard
extends RefCounted

## 战斗中的一张牌（实例）。牌的定义来自 CardTable，这里保存这场战斗里的变化：
## 永久涂黑（缺字）、临时涂黑（校对员、涂痕）、本回合费用、是否抄本等。

var uid: int = 0
var id: StringName = &""
var upgraded: bool = false
var name: String = ""
var type: int = CardTable.Type.ATTACK
var cost: int = 0
var rarity: String = ""
var owner: StringName = &""
var exhaust: bool = false
var note: String = ""
var margin: String = ""
var lines: Array = []

## 永久去掉的句（本场战斗内）。
var black_perm: Array[int] = []
## 临时涂黑的句：下一次打出时不生效，打完恢复。
var black_temp: Array[int] = []
## 本回合费用改为 0。
var free_this_turn: bool = false
## 抄本：永久 0 费，打出后消耗。
var is_copy: bool = false


static func create(card_id: StringName, p_uid: int, p_upgraded: bool = false) -> BattleCard:
	var def: Dictionary = CardTable.get_def(card_id)
	assert(not def.is_empty(), "未知卡牌：%s" % card_id)
	var card: BattleCard = BattleCard.new()
	card.uid = p_uid
	card.id = card_id
	card.upgraded = p_upgraded
	card.name = str(def["name"])
	card.type = int(def["type"])
	card.cost = int(def["cost"])
	card.rarity = str(def["rarity"])
	card.owner = def["owner"]
	card.exhaust = bool(def.get("exhaust", false))
	card.note = str(def.get("note", ""))
	card.margin = str(def.get("margin", ""))
	card.lines = (def["lines"] as Array).duplicate(true)
	if p_upgraded and def.has("up"):
		var up: Dictionary = def["up"]
		card.name += "+"
		if up.has("cost"):
			card.cost = int(up["cost"])
		if up.has("exhaust"):
			card.exhaust = bool(up["exhaust"])
		if up.has("lines"):
			card.lines = (up["lines"] as Array).duplicate(true)
	return card


func clone(new_uid: int) -> BattleCard:
	var copy: BattleCard = BattleCard.create(id, new_uid, upgraded)
	copy.black_perm = black_perm.duplicate()
	copy.lines = lines.duplicate(true)
	return copy


func is_unplayable() -> bool:
	return type == CardTable.Type.STATUS


func is_line_active(index: int) -> bool:
	return not black_perm.has(index) and not black_temp.has(index)


func active_line_indices() -> Array[int]:
	var result: Array[int] = []
	for index: int in range(lines.size()):
		if is_line_active(index):
			result.append(index)
	return result


## 永久没被去掉的句（临时涂黑的也算在内）。缺字用它判断"有两句效果"。
func standing_line_indices() -> Array[int]:
	var result: Array[int] = []
	for index: int in range(lines.size()):
		if not black_perm.has(index):
			result.append(index)
	return result


func active_ops() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in active_line_indices():
		for op: Variant in lines[index]:
			result.append(op as Dictionary)
	return result


func current_cost() -> int:
	if is_copy or free_this_turn:
		return 0
	return cost


func has_choice_first() -> bool:
	var ops: Array[Dictionary] = active_ops()
	if ops.is_empty():
		return false
	return CardTable.CHOICE_OPS.has(str(ops[0]["k"]))


func needs_enemy_target() -> bool:
	for op: Dictionary in active_ops():
		var kind: String = str(op["k"])
		if kind in ["dmg", "dmg_clear", "dmg_per_type"] and str(op.get("to", "one")) == "one":
			return true
		if kind == "apply":
			return true
	return false


## 牌面上印的第一处伤害（多眼水母照抄用）。返回 [单次伤害, 次数]。
func printed_damage() -> Array[int]:
	for op: Dictionary in active_ops():
		if str(op["k"]) in ["dmg", "dmg_clear", "dmg_per_type"]:
			return [int(op.get("a", 0)), int(op.get("t", 1))]
	return [0, 0]


func printed_block() -> int:
	for op: Dictionary in active_ops():
		if str(op["k"]) in ["block", "block_per_overload", "block_if_low"]:
			return int(op.get("a", 0))
	return 0


## 缺字：去掉第二句，第一句的数字翻倍。
func apply_halve() -> bool:
	var standing: Array[int] = standing_line_indices()
	if standing.size() < 2:
		return false
	black_perm.append(standing[1])
	for op: Variant in lines[standing[0]]:
		var data: Dictionary = op as Dictionary
		for key: String in ["a", "low"]:
			if data.has(key):
				data[key] = int(data[key]) * 2
	return true


## 牌面文字，按句返回：[{text, blacked}]。
func text_lines() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(lines.size()):
		if black_perm.has(index):
			continue
		result.append({
			"text": CardTable.describe_line(lines[index]),
			"blacked": black_temp.has(index),
		})
	if exhaust or is_copy:
		result.append({"text": "消耗。", "blacked": false})
	return result


func full_text() -> String:
	var parts: Array[String] = []
	for line: Dictionary in text_lines():
		parts.append("████" if bool(line["blacked"]) else str(line["text"]))
	return "".join(parts)


func type_name() -> String:
	return CardTable.TYPE_NAMES[type]
