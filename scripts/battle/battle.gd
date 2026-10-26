class_name Battle
extends RefCounted

## 新战斗核心：1～3 个敌人，规则只读数据表，不为某张牌或某个怪写分支以外的特例。
## 伤害结算顺序固定：基础值 → 加法（力量、红手、磨刀石）→ 乘法（虚弱、烧红的针）
## → 受击方乘法（易伤）→ 格挡 → 扣血。乘法一律向下取整。

const BASE_ENERGY: int = 3
const BASE_DRAW: int = 5
const MAX_HAND: int = 10
const OVERLOAD_CAP: int = 10
const BURST_DAMAGE: int = 8
const WEAK_MULT: float = 0.75
const VULN_MULT: float = 1.5

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var seed_value: int = 0
var next_uid: int = 1
var turn: int = 0
var over: bool = false
var won: bool = false

var character_id: StringName = &""
var hp: int = 0
var max_hp: int = 0
var block: int = 0
var energy: int = 0
var overload: int = 0
var strength: int = 0
var weak: int = 0
var vulnerable: int = 0
var powers: Dictionary = {}
var relics: Array[StringName] = []
var potions: Array[StringName] = []

var enemies: Array[BattleEnemy] = []
var draw_pile: Array[BattleCard] = []
var hand: Array[BattleCard] = []
var discard_pile: Array[BattleCard] = []
var exhaust_pile: Array[BattleCard] = []
var power_zone: Array[BattleCard] = []
## 埋起来的牌：[{card, turns}]
var buried: Array[Dictionary] = []
## 下回合开始自动再打一次的牌：[{card, mult}]
var replay_queue: Array[Dictionary] = []

# ---------- 本回合状态 ----------
var types_played_turn: Array[int] = []
var last_card_turn: BattleCard = null
var last_attack_turn: BattleCard = null
var hp_lost_turn: bool = false
var thorns_turn: int = 0
var grit_turn: int = 0
var bandage_used_turn: bool = false
var patch_done_turn: bool = false
var half_beat_turn: Array[bool] = []
var record_next_pending: int = 0

# ---------- 整场状态 ----------
var last_type_played: int = -1
var cards_played_total: int = 0
var bursts: int = 0
var ring_used: bool = false
var needle_armed: bool = false
var needle_used: bool = false
var whetstone_used: bool = false
var red_pen_used: bool = false

## 等待玩家选择：{card, target, kind, op, options, paid, remaining}
var pending: Dictionary = {}
var log_lines: Array[String] = []
## 给界面播动画用的事件流。
var events: Array[Dictionary] = []

# ---------- 当前结算中的牌 ----------
var _ctx_card: BattleCard = null
var _ctx_hit: Dictionary = {}
var _ctx_whetstone: bool = false
var _ctx_needle: bool = false
var _ctx_set_record: bool = false
var _ctx_mult: float = 1.0


# =====================================================================
# 开战
# =====================================================================

## deck: [{"id": StringName, "upgraded": bool}]
func start(
	p_seed: int,
	p_character: StringName,
	deck: Array[Dictionary],
	enemy_ids: Array[StringName],
	p_hp: int = -1,
	p_max_hp: int = -1,
	p_relics: Array[StringName] = [],
	p_potions: Array[StringName] = []
) -> void:
	seed_value = p_seed
	rng.seed = p_seed
	character_id = p_character
	var character: Dictionary = CharacterTable.get_def(p_character)
	max_hp = p_max_hp if p_max_hp > 0 else int(character.get("max_hp", 75))
	hp = clampi(p_hp if p_hp > 0 else max_hp, 1, max_hp)
	relics = p_relics.duplicate()
	potions = p_potions.duplicate()
	for entry: Dictionary in deck:
		draw_pile.append(_new_card(entry["id"] as StringName, bool(entry.get("upgraded", false))))
	_shuffle(draw_pile)
	for enemy_id: StringName in enemy_ids:
		_spawn_enemy(enemy_id)
	_log("战斗开始。")
	_start_player_turn()
	_apply_battle_start_relics()


static func deck_from_ids(ids: Array[StringName]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card_id: StringName in ids:
		result.append({"id": card_id, "upgraded": false})
	return result


func _spawn_enemy(enemy_id: StringName) -> void:
	var def: Dictionary = EnemyTable.get_def(enemy_id)
	assert(not def.is_empty(), "未知敌人：%s" % enemy_id)
	var enemy: BattleEnemy = BattleEnemy.new()
	enemy.index = enemies.size()
	enemy.id = enemy_id
	enemy.name = str(def["name"])
	enemy.size = str(def.get("size", "中"))
	enemy.elite = bool(def.get("elite", false))
	var hp_range: Array = def["hp"]
	enemy.max_hp = rng.randi_range(int(hp_range[0]), int(hp_range[1]))
	enemy.hp = enemy.max_hp
	enemy.shell = int(def.get("shell", 0))
	for move: Variant in def.get("opening", []):
		enemy.opening.append(str(move))
	var pattern: Array = def["pattern"]
	if str(def.get("start", "fixed")) == "random":
		enemy.step = rng.randi_range(0, pattern.size() - 1)
	enemies.append(enemy)
	_advance_enemy_move(enemy)


func _apply_battle_start_relics() -> void:
	if relics.has(&"iron_thimble"):
		_gain_block(8)
		_log("铁顶针：获得 8 格挡。")
	if relics.has(&"red_seal"):
		for enemy: BattleEnemy in alive_enemies():
			enemy.vulnerable += 1
		_log("红章：所有敌人易伤 1。")
	if relics.has(&"strange_button") and hand.size() < MAX_HAND:
		var pick: StringName = CardTable.OTHER_CHARACTER_CARDS[rng.randi_range(0, CardTable.OTHER_CHARACTER_CARDS.size() - 1)]
		var card: BattleCard = _new_card(pick)
		card.free_this_turn = true
		hand.append(card)
		_log("别人的扣子：手里多了一张《%s》。" % card.name)


# =====================================================================
# 查询（给界面和测试）
# =====================================================================

func alive_enemies() -> Array[BattleEnemy]:
	var result: Array[BattleEnemy] = []
	for enemy: BattleEnemy in enemies:
		if enemy.alive:
			result.append(enemy)
	return result


func is_valid_target(target: int) -> bool:
	return target >= 0 and target < enemies.size() and enemies[target].alive


func can_play(hand_index: int) -> bool:
	if over or not pending.is_empty():
		return false
	if hand_index < 0 or hand_index >= hand.size():
		return false
	var card: BattleCard = hand[hand_index]
	if card.is_unplayable():
		return false
	if card.current_cost() > energy:
		return false
	if card.has_choice_first() and _choice_options(card, card.active_ops()[0]).is_empty():
		return false
	return true


func why_cannot_play(hand_index: int) -> String:
	if hand_index < 0 or hand_index >= hand.size():
		return ""
	var card: BattleCard = hand[hand_index]
	if card.is_unplayable():
		return "这张牌不能打出。"
	if card.current_cost() > energy:
		return "能量不够。"
	if card.has_choice_first() and _choice_options(card, card.active_ops()[0]).is_empty():
		return "现在没有可以选的牌。"
	return ""


## 敌人下一招的显示数据。
func enemy_intent(enemy_index: int) -> Dictionary:
	var enemy: BattleEnemy = enemies[enemy_index]
	var result: Dictionary = {"name": enemy.move_name(), "kind": "unknown", "damage": 0, "times": 0, "block": 0, "parts": []}
	if not enemy.alive:
		return result
	if enemy.pen_blocked:
		result["name"] = "被涂黑了"
		result["kind"] = "none"
		return result
	var parts: Array[String] = []
	var kinds: Array[String] = []
	for raw: Variant in enemy.move_ops():
		var op: Dictionary = raw as Dictionary
		match str(op["k"]):
			"atk":
				result["damage"] = preview_enemy_damage(enemy, int(op["a"]))
				result["times"] = int(op.get("t", 1))
				kinds.append("attack")
				parts.append("%d×%d" % [result["damage"], result["times"]] if int(result["times"]) > 1 else str(result["damage"]))
			"block":
				result["block"] = int(op["a"])
				kinds.append("defend")
				parts.append("格挡 %d" % int(op["a"]))
			"prime", "strength":
				kinds.append("buff")
				parts.append("蓄力")
			"weak":
				kinds.append("debuff")
				parts.append("虚弱 %d" % int(op["a"]))
			"add_draw":
				kinds.append("debuff")
				parts.append("塞 %d 张《%s》" % [int(op["a"]), CardTable.DEFS[op["card"]]["name"]])
			"steal":
				kinds.append("debuff")
				parts.append("偷一张牌")
			"blackout":
				kinds.append("debuff")
				parts.append("涂黑一句")
			"mirror":
				var mirrored: Dictionary = _mirror_preview(enemy)
				kinds.append(str(mirrored["kind"]))
				parts.append(str(mirrored["text"]))
				result["damage"] = int(mirrored["damage"])
				result["times"] = int(mirrored["times"])
				result["block"] = int(mirrored["block"])
			"idle":
				kinds.append("none")
				parts.append("没动静")
	result["parts"] = parts
	if kinds.has("attack"):
		result["kind"] = "attack" if kinds.size() == 1 else "attack_plus"
	elif kinds.size() > 0:
		result["kind"] = kinds[0]
	return result


func enemy_intent_text(enemy_index: int) -> String:
	var intent: Dictionary = enemy_intent(enemy_index)
	var parts: Array = intent["parts"]
	if parts.is_empty():
		return str(intent["name"])
	return "%s · %s" % [intent["name"], "，".join(parts)]


func preview_enemy_damage(enemy: BattleEnemy, base: int) -> int:
	var value: float = float(base + enemy.strength + enemy.prime)
	if enemy.weak > 0:
		value = floor(value * WEAK_MULT)
	if vulnerable > 0:
		value = floor(value * VULN_MULT)
	return maxi(0, int(value))


## 不打出牌，预估这张牌对某个敌人造成的单次伤害（界面显示用）。
func preview_card_damage(base: int, target: int) -> int:
	var value: float = float(base + strength)
	if int(powers.get("red_hand", 0)) > 0 and overload >= 5:
		value += float(powers["red_hand"])
	if weak > 0:
		value = floor(value * WEAK_MULT)
	if is_valid_target(target) and enemies[target].vulnerable > 0:
		value = floor(value * VULN_MULT)
	return maxi(0, int(value))


func pending_view() -> Dictionary:
	if pending.is_empty():
		return {}
	var labels: Array[String] = []
	for option: Variant in pending["options"]:
		if option is int:
			var card: BattleCard = _find_card_anywhere(int(option))
			labels.append(card.name if card != null else "?")
		else:
			labels.append(str(CardTable.DEFS[option]["name"]))
	return {
		"prompt": _choice_prompt(str(pending["kind"])),
		"labels": labels,
		"can_cancel": not bool(pending["paid"]),
	}


# =====================================================================
# 玩家操作
# =====================================================================

func play_card(hand_index: int, target: int = -1) -> bool:
	if not can_play(hand_index):
		return false
	var card: BattleCard = hand[hand_index]
	if card.needs_enemy_target() and not is_valid_target(target):
		var alive: Array[BattleEnemy] = alive_enemies()
		if alive.size() != 1:
			return false
		target = alive[0].index
	if card.has_choice_first():
		var op: Dictionary = card.active_ops()[0]
		pending = {
			"card": card, "target": target, "kind": str(op["k"]), "op": op,
			"options": _choice_options(card, op), "paid": false,
			"remaining": maxi(1, int(op.get("a", 1))) if str(op["k"]) == "other_pick" else 1,
		}
		return true
	_commit_play(card, target, null)
	return true


func choose(option_index: int) -> bool:
	if pending.is_empty():
		return false
	var options: Array = pending["options"]
	if option_index < 0 or option_index >= options.size():
		return false
	var current: Dictionary = pending
	var choice: Variant = options[option_index]
	pending = {}
	if not bool(current["paid"]):
		_commit_play(current["card"] as BattleCard, int(current["target"]), choice, current)
	else:
		_apply_choice(current["card"] as BattleCard, current["op"] as Dictionary, choice)
		_continue_or_finish_pick(current["card"] as BattleCard, current)
	return true


func cancel_choice() -> bool:
	if pending.is_empty() or bool(pending["paid"]):
		return false
	pending = {}
	return true


func end_turn() -> void:
	if over or not pending.is_empty():
		return
	if int(powers.get("scab", 0)) > 0 and hp_lost_turn:
		_gain_block(int(powers["scab"]))
		_log("结痂：获得 %d 格挡。" % int(powers["scab"]))
	if relics.has(&"paperweight") and block == 0:
		_gain_block(6)
		_log("镇纸：获得 6 格挡。")
	for half: bool in half_beat_turn:
		if last_attack_turn != null:
			replay_queue.append({"card": last_attack_turn.clone(_take_uid()), "mult": 0.5 if half else 1.0})
	for card: BattleCard in hand:
		card.free_this_turn = false
		discard_pile.append(card)
	hand.clear()
	weak = maxi(0, weak - 1)
	vulnerable = maxi(0, vulnerable - 1)
	for enemy: BattleEnemy in enemies:
		if over:
			return
		if enemy.alive:
			_enemy_act(enemy)
	if over:
		return
	_start_player_turn()


func use_potion(potion_index: int) -> bool:
	if over or not pending.is_empty() or potion_index < 0 or potion_index >= potions.size():
		return false
	var potion_id: StringName = potions[potion_index]
	potions.remove_at(potion_index)
	match potion_id:
		&"strong_wine":
			strength += 2
		&"styptic":
			_gain_block(12)
		&"ink_bottle":
			for enemy: BattleEnemy in alive_enemies():
				_damage_enemy(enemy, 10, false)
		&"cold_water":
			overload = 0
		&"pep_pill":
			energy += 2
		_:
			return false
	_log("喝了%s。" % ItemTable.potion_name(potion_id))
	_check_end()
	return true


func use_red_pen(enemy_index: int) -> bool:
	if over or red_pen_used or not relics.has(&"red_pen") or not is_valid_target(enemy_index):
		return false
	red_pen_used = true
	enemies[enemy_index].pen_blocked = true
	_log("你用红笔涂掉了%s的下一招。" % enemies[enemy_index].name)
	return true


# =====================================================================
# 出牌结算
# =====================================================================

func _commit_play(card: BattleCard, target: int, choice: Variant, pick_state: Dictionary = {}) -> void:
	energy -= card.current_cost()
	hand.erase(card)
	_begin_ctx(card)
	_log("打出《%s》。" % card.name)
	var ops: Array[Dictionary] = card.active_ops()
	for op_index: int in range(ops.size()):
		if over:
			break
		var op: Dictionary = ops[op_index]
		if op_index == 0 and CardTable.CHOICE_OPS.has(str(op["k"])):
			_apply_choice(card, op, choice)
			if str(op["k"]) == "other_pick":
				var state: Dictionary = pick_state.duplicate()
				state["paid"] = true
				_continue_or_finish_pick(card, state)
				return
			continue
		_apply_op(op, target)
	_finish_card(card)


func _continue_or_finish_pick(card: BattleCard, state: Dictionary) -> void:
	var remaining: int = int(state.get("remaining", 1)) - 1
	if remaining > 0 and hand.size() < MAX_HAND:
		var op: Dictionary = state["op"]
		pending = {
			"card": card, "target": int(state["target"]), "kind": "other_pick", "op": op,
			"options": _choice_options(card, op), "paid": true, "remaining": remaining,
		}
		return
	_finish_card(card)


func _begin_ctx(card: BattleCard) -> void:
	_ctx_card = card
	_ctx_hit.clear()
	_ctx_set_record = false
	_ctx_mult = 1.0
	_ctx_whetstone = false
	_ctx_needle = false
	if card.type == CardTable.Type.ATTACK:
		if relics.has(&"whetstone") and not whetstone_used:
			whetstone_used = true
			_ctx_whetstone = true
		if needle_armed:
			needle_armed = false
			_ctx_needle = true


func _finish_card(card: BattleCard) -> void:
	if int(powers.get("finish", 0)) > 0 and last_type_played >= 0 and card.type != last_type_played:
		var amount: int = int(powers["finish"])
		var alive: Array[BattleEnemy] = alive_enemies()
		if not alive.is_empty():
			_damage_enemy(alive[rng.randi_range(0, alive.size() - 1)], amount, false)
		_gain_block(amount)
	last_type_played = card.type
	if not types_played_turn.has(card.type):
		types_played_turn.append(card.type)
	if int(powers.get("patch", 0)) > 0 and not patch_done_turn:
		if types_played_turn.has(CardTable.Type.ATTACK) and types_played_turn.has(CardTable.Type.SKILL) and types_played_turn.has(CardTable.Type.POWER):
			patch_done_turn = true
			_draw(2 * int(powers["patch"]))
			energy += int(powers["patch"])
			_log("补丁：抽 %d 张，获得 %d 能量。" % [2 * int(powers["patch"]), int(powers["patch"])])
	if card.type == CardTable.Type.ATTACK:
		last_attack_turn = card
	last_card_turn = card
	if record_next_pending > 0 and not _ctx_set_record:
		record_next_pending -= 1
		replay_queue.append({"card": card.clone(_take_uid()), "mult": 1.0})
		_log("记下了《%s》。" % card.name)
	for enemy_index: Variant in _ctx_hit:
		var enemy: BattleEnemy = enemies[int(enemy_index)]
		enemy.hits_by_type[card.type] = int(enemy.hits_by_type.get(card.type, 0)) + 1
		if enemy.alive and enemy.shell > 0 and not enemy.shell_broken and int(enemy.hits_by_type[card.type]) >= 2:
			enemy.shell_broken = true
			_log("%s的石壳碎了。" % enemy.name)
			events.append({"type": "shell_break", "enemy": enemy.index})
	cards_played_total += 1
	if relics.has(&"empty_ink") and cards_played_total % 10 == 0:
		energy += 1
		_log("空墨瓶：获得 1 能量。")
	card.black_temp.clear()
	card.free_this_turn = false
	if card.type == CardTable.Type.POWER:
		power_zone.append(card)
	elif card.exhaust or card.is_copy:
		exhaust_pile.append(card)
	else:
		discard_pile.append(card)
	_ctx_card = null
	_check_end()


func _apply_op(op: Dictionary, target: int) -> void:
	var a: int = int(op.get("a", 0))
	match str(op["k"]):
		"dmg":
			var amount: int = a
			if op.has("hot") and overload >= int(op["hot"]):
				amount *= 2
			if op.has("low") and hp * 2 < max_hp:
				amount = int(op["low"])
			amount = int(floor(float(amount) * _ctx_mult))
			var times: int = int(op.get("t", 1))
			for hit: int in range(times):
				if over:
					break
				match str(op.get("to", "one")):
					"all":
						for enemy: BattleEnemy in alive_enemies():
							_damage_enemy(enemy, amount, true)
					"random":
						var alive: Array[BattleEnemy] = alive_enemies()
						if not alive.is_empty():
							_damage_enemy(alive[rng.randi_range(0, alive.size() - 1)], amount, true)
					_:
						_damage_target(target, amount)
		"dmg_clear":
			var total: int = a + int(op["per"]) * overload
			overload = 0
			_damage_target(target, int(floor(float(total) * _ctx_mult)))
		"dmg_per_type":
			var total_types: int = a + int(op["per"]) * types_played_turn.size()
			_damage_target(target, int(floor(float(total_types) * _ctx_mult)))
		"block":
			_gain_block(a)
		"block_per_overload":
			_gain_block(a + int(op["m"]) * overload)
		"block_if_low":
			if hp * 2 < max_hp:
				_gain_block(a)
		"draw":
			_draw(a)
		"draw_if_varied":
			var seen: Array[int] = types_played_turn.duplicate()
			if _ctx_card != null and not seen.has(_ctx_card.type):
				seen.append(_ctx_card.type)
			if seen.has(CardTable.Type.ATTACK) and seen.has(CardTable.Type.SKILL):
				_draw(a)
		"energy":
			energy += a
		"overload":
			_gain_overload(a)
		"cool":
			var removed: int = mini(a, overload)
			overload -= removed
			_gain_block(removed * int(op["b"]))
		"lose_hp":
			_lose_hp(a)
		"heal":
			hp = mini(max_hp, hp + a)
		"cleanse":
			weak = 0
			vulnerable = 0
		"apply":
			if is_valid_target(target):
				var enemy: BattleEnemy = enemies[target]
				if str(op["s"]) == "weak":
					enemy.weak += a
				elif str(op["s"]) == "vulnerable":
					enemy.vulnerable += a
		"power":
			var power_id: String = str(op["id"])
			powers[power_id] = int(powers.get(power_id, 0)) + a
		"thorns_turn":
			thorns_turn += a
		"grit_turn":
			grit_turn += a
		"replay_last_attack":
			half_beat_turn.append(bool(op.get("half", false)))
		"reshuffle_hand":
			var count: int = hand.size()
			for card: BattleCard in hand:
				card.free_this_turn = false
				draw_pile.insert(0, card)
			hand.clear()
			_draw(count)
		"record_next":
			record_next_pending += 1
			_ctx_set_record = true


func _damage_target(target: int, amount: int) -> void:
	if is_valid_target(target):
		_damage_enemy(enemies[target], amount, true)
	else:
		var alive: Array[BattleEnemy] = alive_enemies()
		if not alive.is_empty():
			_damage_enemy(alive[0], amount, true)


# =====================================================================
# 需要选择的操作
# =====================================================================

func _choice_options(card: BattleCard, op: Dictionary) -> Array:
	var options: Array = []
	match str(op["k"]):
		"halve":
			for other: BattleCard in hand:
				if other != card and not other.is_unplayable() and other.standing_line_indices().size() >= 2:
					options.append(other.uid)
		"bury", "exhaust_choice":
			for other: BattleCard in hand:
				if other != card:
					options.append(other.uid)
		"copy_hand":
			for other: BattleCard in hand:
				if other != card and not other.is_unplayable():
					options.append(other.uid)
		"recover_discard":
			if hand.size() < MAX_HAND or hand.has(card):
				for other: BattleCard in discard_pile:
					options.append(other.uid)
		"look_top":
			var count: int = mini(int(op.get("a", 3)), draw_pile.size())
			for offset: int in range(count):
				options.append(draw_pile[draw_pile.size() - 1 - offset].uid)
		"other_pick":
			for card_id: StringName in CardTable.OTHER_CHARACTER_CARDS:
				options.append(card_id)
	return options


func _choice_prompt(kind: String) -> String:
	match kind:
		"halve":
			return "选一张牌：去掉第二句，第一句翻倍。"
		"bury":
			return "选一张牌埋起来。"
		"exhaust_choice":
			return "选一张牌消耗。"
		"copy_hand":
			return "选一张牌复制。"
		"recover_discard":
			return "从弃牌堆选一张牌拿回手里。"
		"look_top":
			return "选一张放进弃牌堆。"
		"other_pick":
			return "挑一张。"
	return "选一张。"


func _apply_choice(card: BattleCard, op: Dictionary, choice: Variant) -> void:
	var a: int = int(op.get("a", 0))
	match str(op["k"]):
		"halve":
			var picked: BattleCard = _find_in(hand, int(choice))
			if picked != null and picked.apply_halve():
				_log("《%s》少了一句。" % picked.name)
		"bury":
			var buried_card: BattleCard = _find_in(hand, int(choice))
			if buried_card != null:
				hand.erase(buried_card)
				buried.append({"card": buried_card, "turns": maxi(1, a)})
				_log("把《%s》埋了起来。" % buried_card.name)
		"exhaust_choice":
			var torn: BattleCard = _find_in(hand, int(choice))
			if torn != null:
				hand.erase(torn)
				exhaust_pile.append(torn)
				_draw(a)
		"copy_hand":
			var source: BattleCard = _find_in(hand, int(choice))
			if source != null and hand.size() < MAX_HAND:
				var copy: BattleCard = source.clone(_take_uid())
				copy.is_copy = true
				hand.append(copy)
		"recover_discard":
			var recovered: BattleCard = _find_in(discard_pile, int(choice))
			if recovered != null and hand.size() < MAX_HAND:
				discard_pile.erase(recovered)
				if bool(op.get("free", false)):
					recovered.free_this_turn = true
				hand.append(recovered)
		"look_top":
			var looked: BattleCard = _find_in(draw_pile, int(choice))
			if looked != null:
				draw_pile.erase(looked)
				discard_pile.append(looked)
		"other_pick":
			if hand.size() < MAX_HAND:
				var picked_id: StringName = choice as StringName
				var given: BattleCard = _new_card(picked_id)
				given.free_this_turn = true
				hand.append(given)
				_log("手里多了一张《%s》。" % given.name)


# =====================================================================
# 伤害、格挡、过载、抽牌
# =====================================================================

func _damage_enemy(enemy: BattleEnemy, base: int, is_attack: bool) -> int:
	if not enemy.alive:
		return 0
	var value: float = float(base)
	if is_attack:
		value += float(strength)
		if int(powers.get("red_hand", 0)) > 0 and overload >= 5:
			value += float(powers["red_hand"])
		if _ctx_whetstone:
			_ctx_whetstone = false
			value += 8.0
		if weak > 0:
			value = floor(value * WEAK_MULT)
		if _ctx_needle:
			value *= 2.0
	if enemy.vulnerable > 0:
		value = floor(value * VULN_MULT)
	var amount: int = maxi(0, int(value))
	var blocked: int = mini(enemy.block, amount)
	enemy.block -= blocked
	var dealt: int = amount - blocked
	enemy.hp -= dealt
	if _ctx_card != null:
		_ctx_hit[enemy.index] = true
	events.append({"type": "hit_enemy", "enemy": enemy.index, "amount": dealt, "blocked": blocked})
	if enemy.hp <= 0:
		_kill_enemy(enemy)
	return dealt


func _kill_enemy(enemy: BattleEnemy) -> void:
	enemy.alive = false
	enemy.hp = 0
	enemy.block = 0
	_log("%s化成墨，渗进纸里。" % enemy.name)
	events.append({"type": "die", "enemy": enemy.index})
	if not enemy.sack.is_empty():
		for card: BattleCard in enemy.sack:
			discard_pile.append(card)
		_log("袋子破了，%d 张牌回到你的弃牌堆。" % enemy.sack.size())
		enemy.sack.clear()
	_check_end()


func _enemy_hits_player(enemy: BattleEnemy, base: int) -> void:
	var amount: int = preview_enemy_damage(enemy, base)
	var blocked: int = mini(block, amount)
	block -= blocked
	var dealt: int = amount - blocked
	hp -= dealt
	events.append({"type": "hit_player", "enemy": enemy.index, "amount": dealt, "blocked": blocked})
	if dealt > 0:
		_on_hp_lost()
	if thorns_turn > 0 and enemy.alive and not over:
		_damage_enemy(enemy, thorns_turn, false)


func _lose_hp(amount: int) -> void:
	if amount <= 0:
		return
	hp -= amount
	events.append({"type": "lose_hp", "amount": amount})
	_on_hp_lost()


func _on_hp_lost() -> void:
	hp_lost_turn = true
	if hp <= 0:
		hp = 0
		over = true
		won = false
		_log("你倒下了。")
		events.append({"type": "player_die"})
		return
	if grit_turn > 0:
		_gain_block(grit_turn)
	if int(powers.get("grudge", 0)) > 0:
		strength += int(powers["grudge"])
	if relics.has(&"old_bandage") and not bandage_used_turn:
		bandage_used_turn = true
		_draw(1)


func _gain_block(amount: int) -> void:
	if amount > 0:
		block += amount
		events.append({"type": "block", "amount": amount})


func _gain_overload(amount: int) -> void:
	if amount <= 0:
		return
	overload += amount
	if overload >= OVERLOAD_CAP:
		overload = 0
		_burst()


func _burst() -> void:
	bursts += 1
	events.append({"type": "burst"})
	if int(powers.get("explode", 0)) > 0:
		_log("过载爆了，往外炸。")
		for enemy: BattleEnemy in alive_enemies():
			_damage_enemy(enemy, int(powers["explode"]), false)
	else:
		var damage: int = BURST_DAMAGE
		if relics.has(&"broken_ring") and not ring_used:
			ring_used = true
			damage = int(BURST_DAMAGE / 2.0)
		_log("过载爆了，掉 %d 血。" % damage)
		_lose_hp(damage)
	if over:
		return
	if int(powers.get("cant_stop", 0)) > 0:
		strength += int(powers["cant_stop"])
	if relics.has(&"hot_needle") and not needle_used:
		needle_used = true
		needle_armed = true


func _draw(amount: int) -> void:
	for ignored: int in range(amount):
		if hand.size() >= MAX_HAND:
			return
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				return
			draw_pile = discard_pile
			discard_pile = []
			_shuffle(draw_pile)
			_log("弃牌堆洗回抽牌堆。")
		var card: BattleCard = draw_pile.pop_back()
		hand.append(card)
		_on_draw(card)


func _on_draw(card: BattleCard) -> void:
	if card.id == &"waste_page":
		for enemy: BattleEnemy in alive_enemies():
			var bonus: int = int(EnemyTable.DEFS[enemy.id].get("block_on_waste_draw", 0))
			if bonus > 0:
				enemy.block += bonus
				_log("%s获得 %d 格挡。" % [enemy.name, bonus])
	elif card.id == &"smudge":
		var victims: Array[BattleCard] = []
		for other: BattleCard in hand:
			if other != card and not other.is_unplayable() and not other.active_line_indices().is_empty():
				victims.append(other)
		hand.erase(card)
		exhaust_pile.append(card)
		if not victims.is_empty():
			_blackout_random_line(victims[rng.randi_range(0, victims.size() - 1)])


func _blackout_random_line(card: BattleCard) -> void:
	var lines: Array[int] = card.active_line_indices()
	if lines.is_empty():
		return
	card.black_temp.append(lines[rng.randi_range(0, lines.size() - 1)])
	_log("《%s》被涂黑了一句。" % card.name)


# =====================================================================
# 回合流程
# =====================================================================

func _start_player_turn() -> void:
	turn += 1
	block = 0
	energy = BASE_ENERGY
	types_played_turn.clear()
	last_card_turn = null
	last_attack_turn = null
	hp_lost_turn = false
	thorns_turn = 0
	grit_turn = 0
	bandage_used_turn = false
	patch_done_turn = false
	half_beat_turn.clear()
	record_next_pending = 0
	for enemy: BattleEnemy in enemies:
		enemy.hits_by_type.clear()
	var still_buried: Array[Dictionary] = []
	for entry: Dictionary in buried:
		var turns_left: int = int(entry["turns"]) - 1
		if turns_left <= 0:
			var card: BattleCard = entry["card"]
			card.free_this_turn = true
			if hand.size() < MAX_HAND:
				hand.append(card)
			else:
				discard_pile.append(card)
			_log("《%s》回到了手里。" % card.name)
		else:
			still_buried.append({"card": entry["card"], "turns": turns_left})
	buried = still_buried
	_draw(BASE_DRAW + int(powers.get("spare", 0)))
	if int(powers.get("open_wound", 0)) > 0 and not over:
		_lose_hp(1)
		_draw(int(powers["open_wound"]))
	if int(powers.get("wound_block", 0)) > 0:
		_gain_block(int(powers["wound_block"]))
	var queue: Array[Dictionary] = replay_queue.duplicate()
	replay_queue.clear()
	for entry: Dictionary in queue:
		if over:
			break
		_auto_play(entry["card"] as BattleCard, float(entry["mult"]))


func _auto_play(card: BattleCard, mult: float) -> void:
	_ctx_card = card
	_ctx_hit.clear()
	_ctx_whetstone = false
	_ctx_needle = false
	_ctx_set_record = true
	_ctx_mult = mult
	_log("《%s》又打了一次。" % card.name)
	for op: Dictionary in card.active_ops():
		if over:
			break
		if CardTable.CHOICE_OPS.has(str(op["k"])) or str(op["k"]) in ["record_next", "replay_last_attack"]:
			continue
		var alive: Array[BattleEnemy] = alive_enemies()
		var target: int = alive[rng.randi_range(0, alive.size() - 1)].index if not alive.is_empty() else -1
		_apply_op(op, target)
	_ctx_card = null
	_ctx_mult = 1.0
	_check_end()


func _enemy_act(enemy: BattleEnemy) -> void:
	enemy.block = 0
	if enemy.shell > 0 and not enemy.shell_broken:
		enemy.block += enemy.shell
	if enemy.pen_blocked:
		enemy.pen_blocked = false
		_log("%s愣了一下，什么也没做。" % enemy.name)
	else:
		_execute_move(enemy)
	if over:
		return
	enemy.weak = maxi(0, enemy.weak - 1)
	enemy.vulnerable = maxi(0, enemy.vulnerable - 1)
	_advance_enemy_move(enemy)


func _execute_move(enemy: BattleEnemy) -> void:
	var def: Dictionary = EnemyTable.DEFS[enemy.id]
	var attacked: bool = false
	for raw: Variant in enemy.move_ops():
		if over or not enemy.alive:
			return
		var op: Dictionary = raw as Dictionary
		match str(op["k"]):
			"atk":
				if not enemy.said_first_line and def.has("first_attack_log"):
					enemy.said_first_line = true
					_log(str(def["first_attack_log"]))
				for hit: int in range(int(op.get("t", 1))):
					if over:
						return
					_enemy_hits_player(enemy, int(op["a"]))
				attacked = true
			"block":
				enemy.block += int(op["a"])
			"prime":
				enemy.prime += int(op["a"])
			"strength":
				enemy.strength += int(op["a"])
			"weak":
				weak += int(op["a"])
			"add_draw":
				for ignored: int in range(int(op["a"])):
					var position: int = rng.randi_range(0, draw_pile.size())
					draw_pile.insert(position, _new_card(op["card"] as StringName))
				_log("%s往你的抽牌堆里塞了 %d 张《%s》。" % [enemy.name, int(op["a"]), CardTable.DEFS[op["card"]]["name"]])
			"steal":
				_steal(enemy, def)
			"mirror":
				attacked = _mirror(enemy) or attacked
			"blackout":
				_blackout_from_piles()
			"idle":
				pass
	if attacked:
		enemy.prime = 0


func _steal(enemy: BattleEnemy, def: Dictionary) -> void:
	var pool: Array[BattleCard] = []
	for card: BattleCard in discard_pile:
		if not card.is_unplayable():
			pool.append(card)
	var from_discard: bool = not pool.is_empty()
	if pool.is_empty():
		for card: BattleCard in draw_pile:
			if not card.is_unplayable():
				pool.append(card)
	if pool.is_empty():
		return
	var stolen: BattleCard = pool[rng.randi_range(0, pool.size() - 1)]
	if from_discard:
		discard_pile.erase(stolen)
	else:
		draw_pile.erase(stolen)
	enemy.sack.append(stolen)
	if not enemy.said_first_line and def.has("first_steal_line"):
		enemy.said_first_line = true
		_log("%s：“%s”" % [enemy.name, def["first_steal_line"]])
	_log("%s拿走了《%s》。" % [enemy.name, stolen.name])


func _mirror_preview(enemy: BattleEnemy) -> Dictionary:
	var result: Dictionary = {"kind": "none", "text": "盯着你", "damage": 0, "times": 0, "block": 0}
	var card: BattleCard = last_card_turn
	if card == null:
		return result
	match card.type:
		CardTable.Type.ATTACK:
			var printed: Array[int] = card.printed_damage()
			var base: int = printed[0] if printed[0] > 0 else 5
			var times: int = maxi(1, printed[1])
			result["kind"] = "attack"
			result["damage"] = preview_enemy_damage(enemy, base)
			result["times"] = times
			result["text"] = "%d×%d" % [result["damage"], times] if times > 1 else str(result["damage"])
		CardTable.Type.SKILL:
			var printed_block: int = card.printed_block()
			result["kind"] = "defend"
			result["block"] = printed_block if printed_block > 0 else 5
			result["text"] = "格挡 %d" % result["block"]
		CardTable.Type.POWER:
			result["kind"] = "buff"
			result["text"] = "力量 +2"
	return result


func _mirror(enemy: BattleEnemy) -> bool:
	var card: BattleCard = last_card_turn
	if card == null:
		_log("%s盯着你，没动。" % enemy.name)
		return false
	match card.type:
		CardTable.Type.ATTACK:
			var printed: Array[int] = card.printed_damage()
			var base: int = printed[0] if printed[0] > 0 else 5
			for hit: int in range(maxi(1, printed[1])):
				if over:
					break
				_enemy_hits_player(enemy, base)
			_log("%s学着你的《%s》打了回来。" % [enemy.name, card.name])
			return true
		CardTable.Type.SKILL:
			var printed_block: int = card.printed_block()
			enemy.block += printed_block if printed_block > 0 else 5
			_log("%s学着你的《%s》缩了起来。" % [enemy.name, card.name])
		CardTable.Type.POWER:
			enemy.strength += 2
			_log("%s学着你的《%s》，变壮了。" % [enemy.name, card.name])
	return false


func _blackout_from_piles() -> void:
	var pool: Array[BattleCard] = []
	for card: BattleCard in draw_pile:
		if not card.is_unplayable() and not card.active_line_indices().is_empty():
			pool.append(card)
	if pool.is_empty():
		for card: BattleCard in discard_pile:
			if not card.is_unplayable() and not card.active_line_indices().is_empty():
				pool.append(card)
	if pool.is_empty():
		return
	_blackout_random_line(pool[rng.randi_range(0, pool.size() - 1)])


func _advance_enemy_move(enemy: BattleEnemy) -> void:
	if not enemy.opening.is_empty():
		enemy.move_id = enemy.opening.pop_front()
		return
	var pattern: Array = EnemyTable.DEFS[enemy.id]["pattern"]
	enemy.move_id = str(pattern[enemy.step % pattern.size()])
	enemy.step += 1


func _check_end() -> void:
	if over:
		return
	if alive_enemies().is_empty():
		over = true
		won = true
		_log("这一场打完了。")
		events.append({"type": "win"})


# =====================================================================
# 工具
# =====================================================================

func _new_card(card_id: StringName, upgraded: bool = false) -> BattleCard:
	return BattleCard.create(card_id, _take_uid(), upgraded)


func _take_uid() -> int:
	var uid: int = next_uid
	next_uid += 1
	return uid


func _find_in(pile: Array[BattleCard], uid: int) -> BattleCard:
	for card: BattleCard in pile:
		if card.uid == uid:
			return card
	return null


func _find_card_anywhere(uid: int) -> BattleCard:
	var found: BattleCard = _find_in(hand, uid)
	if found == null:
		found = _find_in(draw_pile, uid)
	if found == null:
		found = _find_in(discard_pile, uid)
	if found == null:
		found = _find_in(exhaust_pile, uid)
	return found


func _shuffle(cards: Array[BattleCard]) -> void:
	for index: int in range(cards.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var temp: BattleCard = cards[index]
		cards[index] = cards[swap_index]
		cards[swap_index] = temp


func _log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 120:
		log_lines.pop_front()


## 所有牌的总数（检查有没有丢牌、多牌）。
func total_card_count() -> int:
	var count: int = draw_pile.size() + hand.size() + discard_pile.size() + exhaust_pile.size() + power_zone.size() + buried.size()
	for enemy: BattleEnemy in enemies:
		count += enemy.sack.size()
	return count
