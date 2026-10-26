class_name CardTable
extends RefCounted

## 第一幕卡牌数据。唯一真相源：design/ACT1_CONTENT.md。
##
## 每张牌由若干"句"（lines）组成，每句是一组操作（ops）。
## 涂黑以句为单位：被涂黑的句不生效。牌面文字由 ops 自动生成，
## 保证数字和效果永远一致。
##
## 操作字段约定：
##   k   操作类型
##   a   主数值
##   t   次数
##   to  目标：one 单体 / all 全体 / random 随机
##   其余字段见 describe_op。

enum Type { ATTACK, SKILL, POWER, STATUS }

const TYPE_NAMES: Array[String] = ["攻击", "技能", "能力", "状态"]

const STITCHER_STARTER: Array[StringName] = [
	&"strike", &"strike", &"strike", &"strike",
	&"defend", &"defend", &"defend", &"defend",
	&"overload_slash", &"missing_word",
]

const STATUS_NAMES: Dictionary = {
	"strength": "力量", "weak": "虚弱", "vulnerable": "易伤",
}

const POWER_TEXT: Dictionary = {
	"red_hand": "过载 5 以上时，你的攻击伤害 +{a}。",
	"explode": "过载爆的时候，你不掉血，改成对所有敌人造成 {a} 伤害。",
	"scab": "回合结束时，如果这回合掉过血，获得 {a} 格挡。",
	"grudge": "你每掉一次血，获得 {a} 力量。",
	"open_wound": "每回合开始，掉 1 血，抽 {a} 张牌。",
	"wound_block": "每回合开始，获得 {a} 格挡。",
	"patch": "每回合你第一次凑齐攻击、技能、能力各一张时，抽 2 张，获得 1 能量。",
	"finish": "每当你打出的牌和上一张类型不同，对随机敌人造成 {a} 伤害，获得 {a} 格挡。",
	"cant_stop": "过载爆的时候，获得 {a} 力量。",
	"spare": "每回合多抽 {a} 张。",
}

## 需要玩家额外选择的操作。规则：这类操作只能放在牌的第一句第一个。
const CHOICE_OPS: Array[String] = [
	"halve", "bury", "recover_discard", "other_pick", "look_top", "exhaust_choice", "copy_hand",
]

const DEFS: Dictionary = {
	# ---------- 缝线人 · 初始 ----------
	&"strike": {
		"name": "打击", "cost": 1, "type": Type.ATTACK, "rarity": "基础", "owner": &"stitcher", "tags": [],
		"lines": [[{"k": "dmg", "a": 6}]],
		"up": {"lines": [[{"k": "dmg", "a": 9}]]},
		"note": "往前砍。",
	},
	&"defend": {
		"name": "防御", "cost": 1, "type": Type.SKILL, "rarity": "基础", "owner": &"stitcher", "tags": [],
		"lines": [[{"k": "block", "a": 5}]],
		"up": {"lines": [[{"k": "block", "a": 8}]]},
		"note": "挡住。", "margin": "别指望它挡那只狗的第三下。",
	},
	&"overload_slash": {
		"name": "过载斩", "cost": 1, "type": Type.ATTACK, "rarity": "基础", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "dmg", "a": 10}], [{"k": "overload", "a": 3}]],
		"up": {"lines": [[{"k": "dmg", "a": 14}], [{"k": "overload", "a": 3}]]},
		"note": "用力过头会伤到自己。", "margin": "别连打三张。上次就是这么死的。",
	},
	&"missing_word": {
		"name": "缺字", "cost": 0, "type": Type.SKILL, "rarity": "基础", "owner": &"stitcher", "tags": [&"patch"],
		"exhaust": true,
		"lines": [[{"k": "halve"}]],
		"up": {"exhaust": false},
		"note": "少说一句。", "margin": "她用这招比你好。",
	},
	# ---------- 缝线人 · 猛攻 ----------
	&"ink_flick": {
		"name": "甩墨", "cost": 0, "type": Type.ATTACK, "rarity": "普通", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "dmg", "a": 4}], [{"k": "overload", "a": 1}]],
		"up": {"lines": [[{"k": "dmg", "a": 6}], [{"k": "overload", "a": 1}]]},
		"note": "顺手一下。",
	},
	&"cleave_open": {
		"name": "劈开", "cost": 1, "type": Type.ATTACK, "rarity": "普通", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "dmg", "a": 8, "hot": 5}]],
		"up": {"lines": [[{"k": "dmg", "a": 11, "hot": 5}]]},
		"note": "手越抖越准。",
	},
	&"chain_cut": {
		"name": "连砍", "cost": 1, "type": Type.ATTACK, "rarity": "普通", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "dmg", "a": 4, "t": 2}], [{"k": "overload", "a": 2}]],
		"up": {"lines": [[{"k": "dmg", "a": 4, "t": 3}], [{"k": "overload", "a": 2}]]},
		"note": "别停。",
	},
	&"push_line": {
		"name": "压线", "cost": 0, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "overload", "a": 3}], [{"k": "energy", "a": 1}]],
		"up": {"lines": [[{"k": "overload", "a": 3}], [{"k": "energy", "a": 2}]]},
		"note": "再快一点。",
	},
	&"sweep": {
		"name": "横扫", "cost": 2, "type": Type.ATTACK, "rarity": "普通", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "dmg", "a": 8, "to": "all"}], [{"k": "overload", "a": 2}]],
		"up": {"lines": [[{"k": "dmg", "a": 11, "to": "all"}], [{"k": "overload", "a": 2}]]},
		"note": "一圈都砍到。",
	},
	&"cool_down": {
		"name": "冷却", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "cool", "a": 4, "b": 2}]],
		"up": {"lines": [[{"k": "cool", "a": 6, "b": 2}]]},
		"note": "喘口气。",
	},
	&"red_hand": {
		"name": "红手", "cost": 1, "type": Type.POWER, "rarity": "少见", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "power", "id": "red_hand", "a": 3}]],
		"up": {"cost": 0},
		"note": "手热了。",
	},
	&"all_out": {
		"name": "全力", "cost": 2, "type": Type.ATTACK, "rarity": "少见", "owner": &"stitcher", "tags": [&"rush"],
		"exhaust": true,
		"lines": [[{"k": "dmg_clear", "a": 8, "per": 3}]],
		"up": {"exhaust": false},
		"note": "一口气用完。",
	},
	&"one_breath": {
		"name": "一口气", "cost": 3, "type": Type.ATTACK, "rarity": "稀有", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "dmg", "a": 30}], [{"k": "overload", "a": 6}]],
		"up": {"cost": 2},
		"note": "只砍一下。",
	},
	&"burst_out": {
		"name": "爆开", "cost": 2, "type": Type.POWER, "rarity": "稀有", "owner": &"stitcher", "tags": [&"rush"],
		"lines": [[{"k": "power", "id": "explode", "a": 10}]],
		"up": {"cost": 1},
		"note": "往外炸，别往里炸。",
	},
	# ---------- 缝线人 · 硬扛 ----------
	&"thick_skin": {
		"name": "皮厚", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"tough"],
		"lines": [[{"k": "block", "a": 8}]],
		"up": {"lines": [[{"k": "block", "a": 11}]]},
		"note": "挨得住。",
	},
	&"bloodlet": {
		"name": "放血", "cost": 0, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"tough"],
		"lines": [[{"k": "lose_hp", "a": 3}], [{"k": "energy", "a": 2}]],
		"up": {"lines": [[{"k": "lose_hp", "a": 3}], [{"k": "energy", "a": 3}]]},
		"note": "换一换。",
	},
	&"trade_wound": {
		"name": "以伤换伤", "cost": 1, "type": Type.ATTACK, "rarity": "普通", "owner": &"stitcher", "tags": [&"tough"],
		"lines": [[{"k": "dmg", "a": 14}], [{"k": "lose_hp", "a": 2}]],
		"up": {"lines": [[{"k": "dmg", "a": 18}], [{"k": "lose_hp", "a": 2}]]},
		"note": "你先疼，它更疼。",
	},
	&"bite_back": {
		"name": "反咬", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"tough"],
		"lines": [[{"k": "block", "a": 5}], [{"k": "thorns_turn", "a": 4}]],
		"up": {"lines": [[{"k": "block", "a": 5}], [{"k": "thorns_turn", "a": 6}]]},
		"note": "谁碰谁疼。",
	},
	&"hold_on": {
		"name": "硬挺", "cost": 1, "type": Type.ATTACK, "rarity": "少见", "owner": &"stitcher", "tags": [&"tough"],
		"lines": [[{"k": "dmg", "a": 6, "low": 18}]],
		"up": {"lines": [[{"k": "dmg", "a": 6, "low": 18}], [{"k": "block_if_low", "a": 8}]]},
		"note": "还没完。",
	},
	&"grit": {
		"name": "咬牙", "cost": 1, "type": Type.SKILL, "rarity": "少见", "owner": &"stitcher", "tags": [&"tough"],
		"lines": [[{"k": "block", "a": 4}], [{"k": "grit_turn", "a": 4}]],
		"up": {"lines": [[{"k": "block", "a": 4}], [{"k": "grit_turn", "a": 6}]]},
		"note": "疼就对了。",
	},
	&"scab": {
		"name": "结痂", "cost": 1, "type": Type.POWER, "rarity": "少见", "owner": &"stitcher", "tags": [&"tough"],
		"lines": [[{"k": "power", "id": "scab", "a": 7}]],
		"up": {"lines": [[{"k": "power", "id": "scab", "a": 10}]]},
		"note": "长好了再撕开。",
	},
	&"grudge": {
		"name": "越疼越狠", "cost": 1, "type": Type.POWER, "rarity": "少见", "owner": &"stitcher", "tags": [&"tough"],
		"lines": [[{"k": "power", "id": "grudge", "a": 1}]],
		"up": {"cost": 0},
		"note": "记仇。",
	},
	&"stitch_up": {
		"name": "缝上", "cost": 1, "type": Type.SKILL, "rarity": "少见", "owner": &"stitcher", "tags": [&"tough"],
		"exhaust": true,
		"lines": [[{"k": "heal", "a": 6}]],
		"up": {"lines": [[{"k": "heal", "a": 6}], [{"k": "cleanse"}]]},
		"note": "针脚很粗。",
	},
	&"open_wound": {
		"name": "伤口不合", "cost": 1, "type": Type.POWER, "rarity": "稀有", "owner": &"stitcher", "tags": [&"tough"],
		"lines": [[{"k": "power", "id": "open_wound", "a": 1}]],
		"up": {"lines": [[{"k": "power", "id": "open_wound", "a": 1}], [{"k": "power", "id": "wound_block", "a": 3}]]},
		"note": "一直没好。",
	},
	# ---------- 缝线人 · 拼凑 ----------
	&"bone_shard": {
		"name": "碎骨", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"patch"],
		"lines": [[{"k": "bury", "a": 2}], [{"k": "draw", "a": 1}]],
		"up": {"lines": [[{"k": "bury", "a": 2}], [{"k": "draw", "a": 2}]]},
		"note": "先放着。",
	},
	&"half_beat": {
		"name": "慢一拍", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"patch"],
		"lines": [[{"k": "replay_last_attack", "half": true}]],
		"up": {"lines": [[{"k": "replay_last_attack", "half": false}]]},
		"note": "晚一点也算。",
	},
	&"dabble": {
		"name": "杂学", "cost": 0, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"patch"],
		"lines": [[{"k": "draw", "a": 1}], [{"k": "draw_if_varied", "a": 1}]],
		"up": {"lines": [[{"k": "draw", "a": 1}], [{"k": "draw_if_varied", "a": 2}]]},
		"note": "什么都学一点。",
	},
	&"many_hands": {
		"name": "多手", "cost": 1, "type": Type.ATTACK, "rarity": "普通", "owner": &"stitcher", "tags": [&"patch"],
		"lines": [[{"k": "dmg_per_type", "a": 4, "per": 4}]],
		"up": {"lines": [[{"k": "dmg_per_type", "a": 4, "per": 6}]]},
		"note": "哪只手都行。",
	},
	&"mend": {
		"name": "缝补", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"patch"],
		"exhaust": true,
		"lines": [[{"k": "recover_discard", "free": false}]],
		"up": {"exhaust": false},
		"note": "捡回来还能用。",
	},
	&"swap_hand": {
		"name": "换只手", "cost": 1, "type": Type.SKILL, "rarity": "少见", "owner": &"stitcher", "tags": [&"patch"],
		"lines": [[{"k": "reshuffle_hand"}]],
		"up": {"cost": 0},
		"note": "这只不顺。",
	},
	&"patchwork": {
		"name": "补丁", "cost": 1, "type": Type.POWER, "rarity": "少见", "owner": &"stitcher", "tags": [&"patch"],
		"lines": [[{"k": "power", "id": "patch", "a": 1}]],
		"up": {"cost": 0},
		"note": "打满一圈。",
	},
	&"scrounge": {
		"name": "东拼西凑", "cost": 1, "type": Type.SKILL, "rarity": "稀有", "owner": &"stitcher", "tags": [&"patch"],
		"exhaust": true,
		"lines": [[{"k": "other_pick", "a": 1}]],
		"up": {"lines": [[{"k": "other_pick", "a": 2}]]},
		"note": "不知道在哪学的。",
	},
	&"stitch_done": {
		"name": "拼完", "cost": 2, "type": Type.POWER, "rarity": "稀有", "owner": &"stitcher", "tags": [&"patch"],
		"lines": [[{"k": "power", "id": "finish", "a": 3}]],
		"up": {"lines": [[{"k": "power", "id": "finish", "a": 5}]]},
		"note": "缝到最后一针。",
	},
	# ---------- 缝线人 · 桥牌 ----------
	&"cant_stop": {
		"name": "停不下", "cost": 1, "type": Type.POWER, "rarity": "少见", "owner": &"stitcher", "tags": [&"rush", &"tough"],
		"lines": [[{"k": "power", "id": "cant_stop", "a": 2}]],
		"up": {"lines": [[{"k": "power", "id": "cant_stop", "a": 3}]]},
		"note": "疼完更狠。",
	},
	&"hot_hands": {
		"name": "烫手", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"stitcher", "tags": [&"rush", &"tough"],
		"lines": [[{"k": "block_per_overload", "a": 3, "m": 2}]],
		"up": {"lines": [[{"k": "block_per_overload", "a": 3, "m": 3}]]},
		"note": "别碰。",
	},
	&"flail": {
		"name": "乱打", "cost": 1, "type": Type.ATTACK, "rarity": "普通", "owner": &"stitcher", "tags": [&"rush", &"patch"],
		"lines": [[{"k": "dmg", "a": 3, "t": 4, "to": "random"}], [{"k": "overload", "a": 2}]],
		"up": {"lines": [[{"k": "dmg", "a": 3, "t": 5, "to": "random"}], [{"k": "overload", "a": 2}]]},
		"note": "打到哪算哪。",
	},
	&"resew": {
		"name": "旧伤新缝", "cost": 1, "type": Type.SKILL, "rarity": "少见", "owner": &"stitcher", "tags": [&"tough", &"patch"],
		"lines": [[{"k": "recover_discard", "free": true}], [{"k": "lose_hp", "a": 3}]],
		"up": {"lines": [[{"k": "recover_discard", "free": true}], [{"k": "lose_hp", "a": 2}]]},
		"note": "拆了重缝。",
	},
	# ---------- 通用 ----------
	&"throw_stone": {
		"name": "扔石头", "cost": 0, "type": Type.ATTACK, "rarity": "普通", "owner": &"common", "tags": [&"common"],
		"exhaust": true,
		"lines": [[{"k": "dmg", "a": 5}]],
		"up": {"lines": [[{"k": "dmg", "a": 8}]]},
		"note": "手边有什么扔什么。",
	},
	&"catch_breath": {
		"name": "喘口气", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"common", "tags": [&"common"],
		"lines": [[{"k": "draw", "a": 2}]],
		"up": {"lines": [[{"k": "draw", "a": 3}]]},
		"note": "先别动。",
	},
	&"roll": {
		"name": "翻滚", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"common", "tags": [&"common"],
		"lines": [[{"k": "block", "a": 4}], [{"k": "draw", "a": 1}]],
		"up": {"lines": [[{"k": "block", "a": 6}], [{"k": "draw", "a": 1}]]},
		"note": "躲开再说。",
	},
	&"trip": {
		"name": "绊一下", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"common", "tags": [&"common"],
		"lines": [[{"k": "apply", "s": "weak", "a": 2}]],
		"up": {"lines": [[{"k": "apply", "s": "weak", "a": 3}]]},
		"note": "让它站不稳。",
	},
	&"find_gap": {
		"name": "找破绽", "cost": 1, "type": Type.SKILL, "rarity": "普通", "owner": &"common", "tags": [&"common"],
		"lines": [[{"k": "apply", "s": "vulnerable", "a": 2}]],
		"up": {"lines": [[{"k": "apply", "s": "vulnerable", "a": 3}]]},
		"note": "那里没盖住。",
	},
	&"peek": {
		"name": "看一眼", "cost": 0, "type": Type.SKILL, "rarity": "少见", "owner": &"common", "tags": [&"common"],
		"lines": [[{"k": "look_top", "a": 3}]],
		"up": {"lines": [[{"k": "look_top", "a": 5}]]},
		"note": "先看看下一步。",
	},
	&"tear_off": {
		"name": "撕掉", "cost": 0, "type": Type.SKILL, "rarity": "少见", "owner": &"common", "tags": [&"common"],
		"exhaust": true,
		"lines": [[{"k": "exhaust_choice", "a": 2}]],
		"up": {"lines": [[{"k": "exhaust_choice", "a": 3}]]},
		"note": "这页不要了。",
	},
	&"spare": {
		"name": "备用", "cost": 1, "type": Type.POWER, "rarity": "稀有", "owner": &"common", "tags": [&"common"],
		"lines": [[{"k": "power", "id": "spare", "a": 1}]],
		"up": {"cost": 0},
		"note": "多带一份总没错。",
	},
	# ---------- 别的角色的牌（东拼西凑、别人的扣子会给出） ----------
	&"copy_one": {
		"name": "抄一份", "cost": 1, "type": Type.SKILL, "rarity": "少见", "owner": &"mute_scribe", "tags": [],
		"lines": [[{"k": "copy_hand"}]],
		"up": {"cost": 0},
		"note": "字迹一模一样。",
	},
	&"lay_to_rest": {
		"name": "下葬", "cost": 0, "type": Type.SKILL, "rarity": "少见", "owner": &"coffin_bearer", "tags": [],
		"lines": [[{"k": "bury", "a": 2}], [{"k": "draw", "a": 2}]],
		"up": {"lines": [[{"k": "bury", "a": 1}], [{"k": "draw", "a": 2}]]},
		"note": "土还是松的。",
	},
	&"note_it": {
		"name": "记下来", "cost": 1, "type": Type.SKILL, "rarity": "少见", "owner": &"clock_child", "tags": [],
		"lines": [[{"k": "record_next"}]],
		"up": {"cost": 0},
		"note": "我会记得的。",
	},
	# ---------- 状态牌 ----------
	&"waste_page": {
		"name": "废页", "cost": -1, "type": Type.STATUS, "rarity": "状态", "owner": &"status", "tags": [],
		"lines": [[{"k": "unplayable"}]],
		"note": "订歪了。",
	},
	&"smudge": {
		"name": "涂痕", "cost": -1, "type": Type.STATUS, "rarity": "状态", "owner": &"status", "tags": [],
		"lines": [[{"k": "unplayable"}], [{"k": "smudge_on_draw"}]],
		"note": "红的。",
	},
}

const OTHER_CHARACTER_CARDS: Array[StringName] = [&"copy_one", &"lay_to_rest", &"note_it"]


static func has_card(card_id: StringName) -> bool:
	return DEFS.has(card_id)


static func get_def(card_id: StringName) -> Dictionary:
	return (DEFS.get(card_id, {}) as Dictionary).duplicate(true)


## 按角色和流派取奖励池。只含普通 / 少见 / 稀有，不含基础和状态牌。
static func reward_pool(owner: StringName, include_common: bool = true) -> Array[StringName]:
	var result: Array[StringName] = []
	for card_id: StringName in DEFS:
		var def: Dictionary = DEFS[card_id]
		var rarity: String = str(def["rarity"])
		if rarity not in ["普通", "少见", "稀有"]:
			continue
		var card_owner: StringName = def["owner"]
		if card_owner == owner or (include_common and card_owner == &"common"):
			result.append(card_id)
	return result


static func tags_of(card_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for tag: Variant in (DEFS.get(card_id, {}) as Dictionary).get("tags", []):
		result.append(tag as StringName)
	return result


## 一个操作的牌面文字。尽量用玩家一眼看懂的大白话。
static func describe_op(op: Dictionary) -> String:
	var a: int = int(op.get("a", 0))
	match str(op["k"]):
		"dmg":
			var times: int = int(op.get("t", 1))
			var target: String = str(op.get("to", "one"))
			var text: String = ""
			match target:
				"all":
					text = "对所有敌人造成 %d 伤害" % a
				"random":
					text = "对随机敌人造成 %d 伤害" % a
				_:
					text = "造成 %d 伤害" % a
			if times > 1:
				text += " %d 次" % times
			text += "。"
			if op.has("hot"):
				text += "过载 %d 以上时，伤害翻倍。" % int(op["hot"])
			if op.has("low"):
				text += "你的血低于一半时，改成 %d 伤害。" % int(op["low"])
			return text
		"dmg_clear":
			return "造成 %d 伤害。然后清空过载，每清掉 1 点多造成 %d 伤害。" % [a, int(op["per"])]
		"dmg_per_type":
			return "造成 %d 伤害。这回合你每打出过一种类型的牌，多造成 %d 伤害。" % [a, int(op["per"])]
		"block":
			return "获得 %d 格挡。" % a
		"block_per_overload":
			return "获得 %d 格挡，再加上当前过载的 %d 倍。" % [a, int(op["m"])]
		"block_if_low":
			return "你的血低于一半时，获得 %d 格挡。" % a
		"draw":
			return "抽 %d 张。" % a
		"draw_if_varied":
			return "如果这回合已经打出过攻击和技能，再抽 %d 张。" % a
		"energy":
			return "获得 %d 能量。" % a
		"overload":
			return "过载 %d。" % a
		"cool":
			return "去掉最多 %d 点过载。每去掉 1 点，获得 %d 格挡。" % [a, int(op["b"])]
		"lose_hp":
			return "掉 %d 血。" % a
		"heal":
			return "回复 %d 血。" % a
		"cleanse":
			return "去掉你身上所有虚弱和易伤。"
		"apply":
			return "给一个敌人 %d 层%s。" % [a, str(STATUS_NAMES.get(str(op["s"]), op["s"]))]
		"power":
			return str(POWER_TEXT.get(str(op["id"]), "")).replace("{a}", str(a))
		"thorns_turn":
			return "这回合每被攻击一次，对攻击你的敌人造成 %d 伤害。" % a
		"grit_turn":
			return "这回合你每掉一次血，再获得 %d 格挡。" % a
		"halve":
			return "选一张有两句效果的手牌：去掉第二句，第一句的数字翻倍。"
		"bury":
			if a <= 1:
				return "把一张手牌埋起来。下回合它回到你手里，那回合费用为 0。"
			return "把一张手牌埋起来。%d 回合后它回到你手里，那回合费用为 0。" % a
		"replay_last_attack":
			if bool(op.get("half", false)):
				return "下回合开始时，把这回合你打出的最后一张攻击再打一次，伤害减半。"
			return "下回合开始时，把这回合你打出的最后一张攻击再打一次。"
		"recover_discard":
			if bool(op.get("free", false)):
				return "从弃牌堆选一张牌放回手里，它这回合费用为 0。"
			return "从弃牌堆选一张牌放回手里。"
		"reshuffle_hand":
			return "把手牌全放到抽牌堆底，再抽同样多张。"
		"other_pick":
			if a > 1:
				return "从三张别的角色的牌里挑一张放进手里，这回合费用为 0。挑 %d 次。" % a
			return "从三张别的角色的牌里挑一张放进手里，这回合费用为 0。"
		"look_top":
			return "看抽牌堆顶 %d 张，挑 1 张放进弃牌堆。" % a
		"exhaust_choice":
			return "消耗一张手牌，抽 %d 张。" % a
		"copy_hand":
			return "复制一张手牌。抄本 0 费，打出后消耗。"
		"record_next":
			return "这回合你打出的下一张牌，下回合开始时自动再打一次。"
		"unplayable":
			return "不能打出。"
		"smudge_on_draw":
			return "抽到它时，涂黑你手里另一张牌的一句效果，然后它消耗。"
	return ""


static func describe_line(ops: Array) -> String:
	var parts: Array[String] = []
	for op: Variant in ops:
		parts.append(describe_op(op as Dictionary))
	return "".join(parts)
