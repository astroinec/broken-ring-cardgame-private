class_name EnemyTable
extends RefCounted

## 第一幕敌人数据。唯一真相源：design/ACT1_CONTENT.md 第五节。
##
## 出招操作字段：
##   atk        攻击：a 伤害，t 次数
##   block      获得 a 格挡
##   prime      下一次攻击 +a
##   strength   获得 a 力量
##   weak       给你 a 层虚弱
##   add_draw   往你抽牌堆塞 a 张 card
##   steal      从你弃牌堆拿走一张牌放进袋子
##   mirror     照着你这回合最后打出的牌出招
##   blackout   涂黑你抽牌堆里一张牌的一句
##   idle       什么都不做

const DEFS: Dictionary = {
	&"ink_moth": {
		"name": "墨蛾", "size": "小", "hp": [11, 14],
		"moves": {
			"flap": {"name": "扑", "ops": [{"k": "atk", "a": 5}]},
			"stick": {"name": "粘", "ops": [{"k": "weak", "a": 1}]},
		},
		"pattern": ["flap", "flap", "stick"], "start": "random",
	},
	&"scent_hound": {
		"name": "嗅名犬", "size": "中", "hp": [40, 44],
		"moves": {
			"sniff": {"name": "嗅", "ops": [{"k": "prime", "a": 4}]},
			"bite": {"name": "咬", "ops": [{"k": "atk", "a": 9}]},
			"maul": {"name": "扑咬", "ops": [{"k": "atk", "a": 6, "t": 2}]},
		},
		"pattern": ["sniff", "bite", "maul"], "start": "fixed",
		"first_attack_log": "狗绕着你走了一圈，然后扑了上来。",
	},
	&"stone_guard": {
		"name": "石卫", "size": "中", "hp": [44, 48],
		"moves": {
			"wall": {"name": "封路", "ops": [{"k": "block", "a": 8}, {"k": "prime", "a": 3}]},
			"slam": {"name": "石盾砸", "ops": [{"k": "atk", "a": 12}]},
		},
		"pattern": ["wall", "slam"], "start": "fixed",
		"shell": 5,
	},
	&"eye_jelly": {
		"name": "多眼水母", "size": "中", "hp": [30, 34],
		"moves": {
			"drift": {"name": "漂着", "ops": [{"k": "idle"}]},
			"mirror": {"name": "照着你", "ops": [{"k": "mirror"}]},
		},
		"opening": ["drift"], "pattern": ["mirror"], "start": "fixed",
	},
	&"word_goblin": {
		"name": "拾字地精", "size": "小", "hp": [22, 26],
		"moves": {
			"steal": {"name": "偷", "ops": [{"k": "steal"}]},
			"flee": {"name": "跑", "ops": [{"k": "block", "a": 6}]},
			"poke": {"name": "戳", "ops": [{"k": "atk", "a": 8}]},
		},
		"pattern": ["steal", "poke", "flee"], "start": "fixed",
		"first_steal_line": "这个字我拿走了，你又不用。",
	},
	&"binder": {
		"name": "装订机", "size": "大", "hp": [72, 76], "elite": true,
		"moves": {
			"pierce": {"name": "穿孔", "ops": [{"k": "atk", "a": 6, "t": 2}]},
			"bind": {"name": "装订", "ops": [{"k": "add_draw", "card": &"waste_page", "a": 2}, {"k": "block", "a": 6}]},
			"press": {"name": "压页", "ops": [{"k": "atk", "a": 14}]},
		},
		"pattern": ["pierce", "bind", "press"], "start": "fixed",
		"block_on_waste_draw": 3,
	},
	&"proofreader": {
		"name": "校对员", "size": "大", "hp": [78, 82], "elite": true,
		"moves": {
			"circle": {"name": "圈出", "ops": [{"k": "atk", "a": 8}, {"k": "blackout"}]},
			"correct": {"name": "改错", "ops": [{"k": "atk", "a": 12}]},
			"tidy": {"name": "誊清", "ops": [{"k": "block", "a": 10}, {"k": "strength", "a": 2}]},
		},
		"pattern": ["circle", "correct", "tidy"], "start": "fixed",
	},
}

## 遭遇组：early 用于第 1～3 层，late 用于第 4 层以后，elite 用于精英。
const ENCOUNTERS: Dictionary = {
	"early": [
		[&"scent_hound"],
		[&"ink_moth", &"ink_moth", &"ink_moth"],
		[&"stone_guard"],
		[&"word_goblin", &"ink_moth"],
	],
	"late": [
		[&"scent_hound", &"ink_moth"],
		[&"stone_guard", &"ink_moth"],
		[&"eye_jelly", &"word_goblin"],
		[&"word_goblin", &"word_goblin", &"ink_moth"],
		[&"eye_jelly", &"ink_moth", &"ink_moth"],
		[&"scent_hound", &"word_goblin"],
	],
	"elite": [
		[&"binder"],
		[&"proofreader"],
	],
}


static func has_enemy(enemy_id: StringName) -> bool:
	return DEFS.has(enemy_id)


static func get_def(enemy_id: StringName) -> Dictionary:
	return (DEFS.get(enemy_id, {}) as Dictionary).duplicate(true)
