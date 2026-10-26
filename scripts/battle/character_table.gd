class_name CharacterTable
extends RefCounted

## 可玩角色数据。加角色只改这里和 CardTable，不改战斗代码。

const DEFS: Dictionary = {
	&"stitcher": {
		"name": "缝线人",
		"home": "档案馆",
		"max_hp": 75,
		"starter_deck": [
			&"strike", &"strike", &"strike", &"strike",
			&"defend", &"defend", &"defend", &"defend",
			&"overload_slash", &"missing_word",
		],
		"starter_relic": &"broken_ring",
		"archetypes": {
			&"rush": "猛攻",
			&"tough": "硬扛",
			&"patch": "拼凑",
		},
		"unlocked_by_default": true,
	},
	&"mute_scribe": {
		"name": "哑书记", "home": "无字城", "playable": false,
		"archetypes": {&"cut": "删减", &"copy": "抄写", &"erase": "除名"},
	},
	&"coffin_bearer": {
		"name": "背棺人", "home": "骨园", "playable": false,
		"archetypes": {&"grave": "埋和挖", &"corpse": "尸仆", &"dirty": "脏牌"},
	},
	&"clock_child": {
		"name": "钟表童", "home": "停钟", "playable": false,
		"archetypes": {&"replay": "重放", &"order": "顺序", &"freeze": "定格"},
	},
}


static func get_def(character_id: StringName) -> Dictionary:
	return (DEFS.get(character_id, {}) as Dictionary).duplicate(true)


static func starter_deck(character_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for card_id: Variant in get_def(character_id).get("starter_deck", []):
		result.append(card_id as StringName)
	return result
