extends SceneTree

## 第一幕数值模拟。一个"还算会玩"的机器人打每组遭遇，统计回合数和掉血。
## 只用来找明显偏离目标的地方，最终数值以真人试玩为准。
##
## 目标（design/ACT1_CONTENT.md 第一节）：
##   前 3 层普通：3～5 回合，掉血 3～10
##   之后普通：4～6 回合，掉血 6～15
##   精英：6～8 回合，掉血 15～30

const RUNS: int = 40


func _init() -> void:
	var pool: Array[StringName] = CardTable.reward_pool(&"stitcher", true)
	print("组别 | 遭遇 | 胜率 | 平均回合 | 平均掉血")
	for bracket: String in ["early", "late", "elite"]:
		var extra_cards: int = {"early": 0, "late": 4, "elite": 5}[bracket]
		for group: Variant in EnemyTable.ENCOUNTERS[bracket]:
			var names: Array[String] = []
			for enemy_id: Variant in group:
				names.append(str(EnemyTable.DEFS[enemy_id]["name"]))
			var wins: int = 0
			var turns_total: int = 0
			var hp_loss_total: int = 0
			for run: int in range(RUNS):
				var rng: RandomNumberGenerator = RandomNumberGenerator.new()
				rng.seed = 1000 + run
				var deck: Array[Dictionary] = Battle.deck_from_ids(CharacterTable.starter_deck(&"stitcher"))
				for extra: int in range(extra_cards):
					deck.append({"id": pool[rng.randi_range(0, pool.size() - 1)], "upgraded": false})
				var foes: Array[StringName] = []
				for enemy_id: Variant in group:
					foes.append(enemy_id as StringName)
				var battle: Battle = Battle.new()
				battle.start(5000 + run, &"stitcher", deck, foes, -1, -1, [&"broken_ring"])
				_play_out(battle)
				if battle.won:
					wins += 1
				turns_total += battle.turn
				hp_loss_total += battle.max_hp - battle.hp
			print("%s | %s | %d%% | %.1f | %.1f" % [
				bracket, "+".join(names), wins * 100 / RUNS,
				float(turns_total) / RUNS, float(hp_loss_total) / RUNS,
			])
	quit(0)


func _play_out(battle: Battle) -> void:
	var safety: int = 0
	while not battle.over and safety < 40:
		_take_turn(battle)
		if not battle.over:
			battle.end_turn()
		safety += 1


func _incoming(battle: Battle) -> int:
	var total: int = 0
	for enemy: BattleEnemy in battle.alive_enemies():
		var intent: Dictionary = battle.enemy_intent(enemy.index)
		total += int(intent["damage"]) * maxi(1, int(intent["times"])) if int(intent["damage"]) > 0 else 0
	return total


func _lowest_enemy(battle: Battle) -> int:
	var best: int = -1
	var best_hp: int = 99999
	for enemy: BattleEnemy in battle.alive_enemies():
		if enemy.hp + enemy.block < best_hp:
			best_hp = enemy.hp + enemy.block
			best = enemy.index
	return best


func _gains_overload(card: BattleCard) -> int:
	for op: Dictionary in card.active_ops():
		if str(op["k"]) == "overload":
			return int(op["a"])
	return 0


func _take_turn(battle: Battle) -> void:
	var guard: int = 0
	while not battle.over and guard < 20:
		guard += 1
		if not battle.pending.is_empty():
			battle.choose(0)
			continue
		var choice: int = _pick(battle)
		if choice < 0:
			return
		battle.play_card(choice, _lowest_enemy(battle))


func _pick(battle: Battle) -> int:
	var need_block: bool = _incoming(battle) > battle.block
	var best: int = -1
	var best_score: float = -1.0
	for index: int in range(battle.hand.size()):
		if not battle.can_play(index):
			continue
		var card: BattleCard = battle.hand[index]
		var score: float = 0.0
		var overload_gain: int = _gains_overload(card)
		if overload_gain > 0 and battle.overload + overload_gain >= Battle.OVERLOAD_CAP and battle.hp < 30:
			continue
		match card.type:
			CardTable.Type.POWER:
				score = 9.0
			CardTable.Type.ATTACK:
				score = 5.0 + float(card.printed_damage()[0]) / 4.0
			CardTable.Type.SKILL:
				var block_value: int = card.printed_block()
				score = (7.0 if need_block else 1.5) + float(block_value) / 5.0 if block_value > 0 else 4.0
		score -= float(overload_gain) * 0.3
		score -= float(card.current_cost()) * 0.2
		if score > best_score:
			best_score = score
			best = index
	return best
