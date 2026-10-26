class_name ItemTable
extends RefCounted

## 第一幕遗物和药。唯一真相源：design/ACT1_CONTENT.md 第四、六节。
## 战斗里生效的遗物由 Battle 读取 id 处理；out_of_battle 的遗物由远征层处理。

const RELICS: Dictionary = {
	&"broken_ring": {"name": "一截断环", "text": "每场第一次过载爆，只掉一半血。", "tag": "编号磨掉了。", "pool": "starter"},
	&"hot_needle": {"name": "烧红的针", "text": "每场第一次过载爆后，你下一张攻击伤害翻倍。", "tag": "还烫手。", "pool": "rush"},
	&"old_bandage": {"name": "旧绷带", "text": "每回合第一次掉血时，抽 1 张牌。", "tag": "洗过很多次。", "pool": "tough"},
	&"strange_button": {"name": "别人的扣子", "text": "每场第一回合，把一张别的角色的牌放进你手里，费用为 0。", "tag": "一颗扣子。不是这件衣服上的。", "pool": "patch"},
	&"half_cake": {"name": "半块饼", "text": "拿到时最大生命 +8。", "tag": "口粮。过期了。", "pool": "common", "out_of_battle": true},
	&"iron_thimble": {"name": "铁顶针", "text": "每场开始获得 8 格挡。", "tag": "缝东西用的。", "pool": "common"},
	&"whetstone": {"name": "磨刀石", "text": "每场第一张攻击伤害 +8。", "tag": "磨得只剩一半。", "pool": "common"},
	&"paperweight": {"name": "镇纸", "text": "回合结束时如果你没有格挡，获得 6 格挡。", "tag": "压住，别让纸飞了。", "pool": "common"},
	&"empty_ink": {"name": "空墨瓶", "text": "你每打出 10 张牌，获得 1 能量。", "tag": "里面是干的。", "pool": "common"},
	&"dock_pass": {"name": "码头通行证", "text": "商店删牌便宜 25 铜板。", "tag": "照片那一栏是空的。", "pool": "event", "out_of_battle": true},
	&"red_seal": {"name": "红章", "text": "每场开始，给所有敌人 1 层易伤。", "tag": "档案馆的章。印泥是新的。", "pool": "boss"},
	&"red_pen": {"name": "红笔", "text": "每场一次：涂黑一个敌人的下一次出招。", "tag": "笔尖是红的。", "pool": "boss"},
}

const POTIONS: Dictionary = {
	&"strong_wine": {"name": "一口烈酒", "text": "获得 2 力量（这场战斗）。", "target": false},
	&"styptic": {"name": "止血粉", "text": "获得 12 格挡。", "target": false},
	&"ink_bottle": {"name": "墨水瓶", "text": "对所有敌人造成 10 伤害。", "target": false},
	&"cold_water": {"name": "凉水", "text": "清空过载。", "target": false},
	&"pep_pill": {"name": "提神丸", "text": "获得 2 能量。", "target": false},
}


static func relic_name(relic_id: StringName) -> String:
	return str((RELICS.get(relic_id, {}) as Dictionary).get("name", str(relic_id)))


static func potion_name(potion_id: StringName) -> String:
	return str((POTIONS.get(potion_id, {}) as Dictionary).get("name", str(potion_id)))
