class_name BattleEnemy
extends RefCounted

## 战斗中的一个敌人。

var index: int = 0
var id: StringName = &""
var name: String = ""
var size: String = "中"
var elite: bool = false
var max_hp: int = 0
var hp: int = 0
var block: int = 0
var alive: bool = true

var strength: int = 0
var weak: int = 0
var vulnerable: int = 0
## 下一次出招里的攻击 +X，出完这一招清零。
var prime: int = 0

var move_id: String = ""
var step: int = 0
var opening: Array[String] = []

## 石卫的石壳：每回合补的格挡。碎了以后不再补。
var shell: int = 0
var shell_broken: bool = false
## 本回合被每种类型的牌打中的次数。
var hits_by_type: Dictionary = {}

## 拾字地精的袋子。
var sack: Array[BattleCard] = []
## 被红笔涂黑了下一次出招。
var pen_blocked: bool = false

var said_first_line: bool = false


func move_def() -> Dictionary:
	var def: Dictionary = EnemyTable.DEFS[id]
	return (def["moves"] as Dictionary).get(move_id, {}) as Dictionary


func move_name() -> String:
	return str(move_def().get("name", ""))


func move_ops() -> Array:
	return move_def().get("ops", []) as Array
