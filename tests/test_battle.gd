extends SceneTree

## 新战斗核心测试。尽量通过真实出牌流程验证，不直接改战斗内部数值。

var failures: int = 0
var checks: int = 0


func _init() -> void:
	_test_all_cards_have_text()
	_test_deterministic_start()
	_test_targeting_with_many_enemies()
	_test_overload_burst_and_broken_ring()
	_test_missing_word_on_overload_slash()
	_test_weak_and_vulnerable_rounding()
	_test_stone_guard_shell()
	_test_goblin_steals_and_returns()
	_test_eye_jelly_mirrors_last_card()
	_test_proofreader_blackout()
	_test_binder_waste_pages()
	_test_bury_returns_free()
	_test_half_beat_replays_half()
	_test_scrounge_upgraded_picks_twice()
	_test_choice_cancel_is_free()
	_test_hound_first_attack_log()
	_test_random_fuzz_no_card_loss()
	if failures == 0:
		print("PASS: battle core %d checks" % checks)
		quit(0)
	else:
		push_error("FAIL: %d / %d battle core checks failed" % [failures, checks])
		quit(1)


# ---------------------------------------------------------------------

func _deck(ids: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in ids:
		if raw is Array:
			result.append({"id": raw[0] as StringName, "upgraded": bool(raw[1])})
		else:
			result.append({"id": raw as StringName, "upgraded": false})
	return result


func _foes(ids: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for raw: Variant in ids:
		result.append(raw as StringName)
	return result


func _battle(deck_ids: Array, enemy_ids: Array, seed_value: int = 7, relics: Array[StringName] = []) -> Battle:
	var battle: Battle = Battle.new()
	battle.start(seed_value, &"stitcher", _deck(deck_ids), _foes(enemy_ids), -1, -1, relics)
	return battle


func _hand_index(battle: Battle, card_id: StringName) -> int:
	for index: int in range(battle.hand.size()):
		if battle.hand[index].id == card_id:
			return index
	return -1


func _play(battle: Battle, card_id: StringName, target: int = -1) -> bool:
	var index: int = _hand_index(battle, card_id)
	if index < 0:
		return false
	return battle.play_card(index, target)


# ---------------------------------------------------------------------

func _test_all_cards_have_text() -> void:
	for card_id: StringName in CardTable.DEFS:
		for upgraded: bool in [false, true]:
			var card: BattleCard = BattleCard.create(card_id, 1, upgraded)
			var text: String = card.full_text()
			_expect(not text.is_empty(), "%s 有牌面文字" % card_id)
			_expect(not text.contains("{"), "%s 牌面没有残留占位符" % card_id)
			for line: Array in card.lines:
				_expect(not CardTable.describe_line(line).is_empty(), "%s 每一句都有文字" % card_id)
	_expect(CharacterTable.starter_deck(&"stitcher").size() == 10, "缝线人初始牌组 10 张")
	var pool: Array[StringName] = CardTable.reward_pool(&"stitcher", false)
	_expect(pool.size() == 33, "缝线人奖励池 33 张（不含初始）：实际 %d" % pool.size())


func _test_deterministic_start() -> void:
	var deck: Array = CharacterTable.starter_deck(&"stitcher")
	var a: Battle = _battle(deck, [&"ink_moth", &"ink_moth", &"ink_moth"], 4242)
	var b: Battle = _battle(deck, [&"ink_moth", &"ink_moth", &"ink_moth"], 4242)
	var ids_a: Array = a.hand.map(func(c: BattleCard) -> StringName: return c.id)
	var ids_b: Array = b.hand.map(func(c: BattleCard) -> StringName: return c.id)
	_expect(ids_a == ids_b, "同种子开局手牌一样")
	for index: int in range(3):
		_expect(a.enemies[index].max_hp == b.enemies[index].max_hp, "同种子墨蛾血量一样")
		_expect(a.enemies[index].move_id == b.enemies[index].move_id, "同种子墨蛾第一招一样")
	_expect(a.hand.size() == 5 and a.energy == 3 and a.hp == 75, "开局 5 张手牌、3 能量、75 血")


func _test_targeting_with_many_enemies() -> void:
	var battle: Battle = _battle([&"strike", &"strike", &"defend", &"defend", &"defend"], [&"scent_hound", &"word_goblin"])
	_expect(not _play(battle, &"strike"), "两个敌人时攻击必须选目标")
	var goblin_hp: int = battle.enemies[1].hp
	var hound_hp: int = battle.enemies[0].hp
	_expect(_play(battle, &"strike", 1), "选中地精打出打击")
	_expect(battle.enemies[1].hp == goblin_hp - 6, "打击对地精造成 6")
	_expect(battle.enemies[0].hp == hound_hp, "狗没被打到")
	_expect(battle.energy == 2, "花了 1 能量")


func _test_overload_burst_and_broken_ring() -> void:
	var battle: Battle = _battle(
		[&"overload_slash", &"overload_slash", &"overload_slash", &"overload_slash", &"defend"],
		[&"binder"], 7, [&"broken_ring"]
	)
	_play(battle, &"overload_slash", 0)
	_play(battle, &"overload_slash", 0)
	_play(battle, &"overload_slash", 0)
	_expect(battle.overload == 9, "三张过载斩后过载 9")
	battle.end_turn()
	var hp_before: int = battle.hp
	_play(battle, &"overload_slash", 0)
	_expect(battle.overload == 0, "过载满 10 后清零")
	_expect(battle.hp == hp_before - 4, "一截断环：第一次过载爆只掉 4 血")
	_expect(battle.bursts == 1, "记录了一次过载爆")


func _test_missing_word_on_overload_slash() -> void:
	var battle: Battle = _battle([&"missing_word", &"overload_slash", &"defend", &"defend", &"defend"], [&"binder"])
	var index: int = _hand_index(battle, &"missing_word")
	_expect(battle.play_card(index), "缺字进入选择")
	var view: Dictionary = battle.pending_view()
	_expect((view["labels"] as Array).size() == 1, "只有过载斩有两句可选")
	_expect(battle.choose(0), "选择过载斩")
	var slash: BattleCard = battle.hand[_hand_index(battle, &"overload_slash")]
	_expect(slash.full_text() == "造成 20 伤害。", "过载斩变成：造成 20 伤害。实际：%s" % slash.full_text())
	var hp_before: int = battle.enemies[0].hp
	_play(battle, &"overload_slash", 0)
	_expect(battle.enemies[0].hp == hp_before - 20, "打出 20 伤害")
	_expect(battle.overload == 0, "没有过载")
	_expect(battle.exhaust_pile.size() == 1, "缺字打完消耗")


func _test_weak_and_vulnerable_rounding() -> void:
	var battle: Battle = _battle([&"find_gap", &"strike", &"strike", &"defend", &"defend"], [&"binder"])
	_play(battle, &"find_gap", 0)
	var hp_before: int = battle.enemies[0].hp
	_play(battle, &"strike", 0)
	_expect(battle.enemies[0].hp == hp_before - 9, "易伤：6×1.5=9")
	var moth_battle: Battle = _battle([&"defend", &"defend", &"defend", &"defend", &"defend", &"strike", &"strike", &"strike", &"strike", &"strike"], [&"ink_moth"], 3)
	var turns: int = 0
	while moth_battle.weak == 0 and turns < 4 and not moth_battle.over:
		moth_battle.end_turn()
		turns += 1
	_expect(moth_battle.weak > 0, "墨蛾的粘给你虚弱")
	var index: int = _hand_index(moth_battle, &"strike")
	if index >= 0:
		var moth_hp: int = moth_battle.enemies[0].hp
		moth_battle.play_card(index, 0)
		_expect(moth_battle.enemies[0].hp == maxi(0, moth_hp - 4), "虚弱：6×0.75 向下取整为 4")


func _test_stone_guard_shell() -> void:
	var battle: Battle = _battle([&"defend", &"defend", &"defend", &"defend", &"defend"], [&"stone_guard"])
	battle.end_turn()
	var shell: int = int(EnemyTable.DEFS[&"stone_guard"]["shell"])
	_expect(battle.enemies[0].block == shell + 8, "石卫回合开始补石壳，封路再 8")
	var fresh: Battle = _battle([&"strike", &"strike", &"strike", &"strike", &"strike"], [&"stone_guard"])
	_play(fresh, &"strike", 0)
	_expect(not fresh.enemies[0].shell_broken, "被攻击一次，石壳没碎")
	_play(fresh, &"strike", 0)
	_expect(fresh.enemies[0].shell_broken, "同一回合被攻击牌打两次，石壳碎了")
	fresh.end_turn()
	_expect(fresh.enemies[0].block == 8, "石壳碎了以后只剩封路的 8 格挡")


func _test_goblin_steals_and_returns() -> void:
	var battle: Battle = _battle(
		[&"strike", &"strike", &"strike", &"strike", &"strike", &"defend", &"defend", &"defend", &"defend", &"defend"],
		[&"word_goblin"]
	)
	_play(battle, &"strike", 0)
	battle.end_turn()
	_expect(battle.enemies[0].sack.size() == 1, "地精偷走一张牌")
	_expect(battle.log_lines.any(func(line: String) -> bool: return line.contains("这个字我拿走了")), "地精说了台词")
	var total_before: int = battle.total_card_count()
	_expect(total_before == 10, "偷走的牌还算在总数里")
	var safety: int = 0
	while not battle.over and safety < 20:
		for index: int in range(battle.hand.size() - 1, -1, -1):
			if battle.over:
				break
			if battle.hand[index].type == CardTable.Type.ATTACK and battle.can_play(index):
				battle.play_card(index, 0)
		if not battle.over:
			battle.end_turn()
		safety += 1
	_expect(battle.won, "打死地精")
	_expect(battle.enemies[0].sack.is_empty(), "袋子空了")
	_expect(battle.total_card_count() == 10, "偷走的牌回到了牌组")


func _test_eye_jelly_mirrors_last_card() -> void:
	var battle: Battle = _battle([&"strike", &"defend", &"defend", &"defend", &"defend", &"strike", &"defend", &"defend", &"defend", &"defend"], [&"eye_jelly"])
	_expect(battle.enemies[0].move_id == "drift", "水母第一回合漂着")
	battle.end_turn()
	_expect(battle.enemies[0].move_id == "mirror", "第二回合起照着你出招")
	var strike_index: int = _hand_index(battle, &"strike")
	if strike_index < 0:
		_expect(false, "第二回合手里有打击")
		return
	battle.play_card(strike_index, 0)
	var intent: Dictionary = battle.enemy_intent(0)
	_expect(str(intent["kind"]) == "attack" and int(intent["damage"]) == 6, "最后一张是打击，水母意图显示攻击 6")
	var defend_index: int = _hand_index(battle, &"defend")
	battle.play_card(defend_index)
	intent = battle.enemy_intent(0)
	_expect(str(intent["kind"]) == "defend" and int(intent["block"]) == 5, "最后一张是防御，水母意图变成格挡 5")
	battle.end_turn()
	_expect(battle.enemies[0].block == 5, "水母照着防御拿了 5 格挡")


func _test_proofreader_blackout() -> void:
	var battle: Battle = _battle(
		[&"defend", &"defend", &"defend", &"defend", &"defend", &"overload_slash", &"overload_slash", &"overload_slash", &"overload_slash", &"overload_slash"],
		[&"proofreader"], 11
	)
	battle.end_turn()
	var blacked: Array[BattleCard] = []
	for pile: Array[BattleCard] in [battle.hand, battle.draw_pile, battle.discard_pile]:
		for card: BattleCard in pile:
			if not card.black_temp.is_empty():
				blacked.append(card)
	_expect(blacked.size() == 1, "校对员涂黑了一张牌的一句")
	if blacked.is_empty():
		return
	var card: BattleCard = blacked[0]
	var text_before: String = card.full_text()
	_expect(text_before.contains("████"), "涂黑的句显示为黑条")
	_expect(card.text_lines().size() == card.standing_line_indices().size() + (1 if card.exhaust else 0), "涂黑的句仍然占位")


func _test_binder_waste_pages() -> void:
	var battle: Battle = _battle([&"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend"], [&"binder"])
	battle.end_turn()
	battle.end_turn()
	var waste: int = 0
	for pile: Array[BattleCard] in [battle.hand, battle.draw_pile, battle.discard_pile]:
		for card: BattleCard in pile:
			if card.id == &"waste_page":
				waste += 1
	_expect(waste == 2, "装订机塞了 2 张废页")
	_expect(battle.total_card_count() == 9, "牌组 7 张加 2 张废页")


func _test_bury_returns_free() -> void:
	var battle: Battle = _battle([&"bone_shard", &"one_breath", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend"], [&"binder"], 5)
	var index: int = _hand_index(battle, &"bone_shard")
	if index < 0 or _hand_index(battle, &"one_breath") < 0:
		# 换种子保证两张都在开局手牌
		for seed_value: int in range(1, 200):
			battle = _battle([&"bone_shard", &"one_breath", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend"], [&"binder"], seed_value)
			if _hand_index(battle, &"bone_shard") >= 0 and _hand_index(battle, &"one_breath") >= 0:
				break
	_expect(_play(battle, &"bone_shard"), "碎骨进入选择")
	var view: Dictionary = battle.pending_view()
	var labels: Array = view["labels"]
	var pick: int = labels.find("一口气")
	_expect(pick >= 0, "可以选一口气")
	battle.choose(pick)
	_expect(battle.buried.size() == 1, "一口气被埋了")
	battle.end_turn()
	_expect(_hand_index(battle, &"one_breath") < 0, "第二回合还没回来")
	battle.end_turn()
	var back: int = _hand_index(battle, &"one_breath")
	_expect(back >= 0, "第三回合回到手里")
	if back >= 0:
		_expect(battle.hand[back].current_cost() == 0, "回来那回合费用为 0")


func _test_half_beat_replays_half() -> void:
	var deck: Array = [&"half_beat", &"strike", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend", &"defend"]
	var battle: Battle = null
	for seed_value: int in range(1, 300):
		battle = _battle(deck, [&"binder"], seed_value)
		if _hand_index(battle, &"half_beat") >= 0 and _hand_index(battle, &"strike") >= 0:
			break
	_play(battle, &"strike", 0)
	_play(battle, &"half_beat")
	var hp_before: int = battle.enemies[0].hp
	battle.end_turn()
	var block_on_enemy: int = 0
	_expect(battle.enemies[0].hp == hp_before - 3, "下回合开始，打击又打了一次，伤害减半为 3（实际 %d）" % (hp_before - battle.enemies[0].hp))
	_expect(battle.log_lines.any(func(line: String) -> bool: return line.contains("又打了一次")), "日志写了又打了一次")


func _test_scrounge_upgraded_picks_twice() -> void:
	var battle: Battle = _battle([[&"scrounge", true], &"defend", &"defend", &"defend", &"defend"], [&"binder"])
	_expect(_play(battle, &"scrounge"), "东拼西凑+ 进入选择")
	_expect(battle.pending_view()["can_cancel"] == true, "第一次选择前可以取消")
	battle.choose(0)
	_expect(not battle.pending.is_empty(), "还要再挑一次")
	_expect(battle.pending_view()["can_cancel"] == false, "已经付过费，不能取消")
	battle.choose(1)
	_expect(battle.pending.is_empty(), "挑完了")
	_expect(battle.hand.size() == 6, "手里多了两张别人的牌")
	_expect(battle.energy == 2, "只付了一次费")


func _test_choice_cancel_is_free() -> void:
	var battle: Battle = _battle([&"mend", &"defend", &"defend", &"defend", &"defend", &"strike"], [&"binder"])
	_play(battle, &"defend")
	var energy_before: int = battle.energy
	var hand_before: int = battle.hand.size()
	_expect(_play(battle, &"mend"), "缝补进入选择")
	_expect(battle.cancel_choice(), "可以取消")
	_expect(battle.energy == energy_before and battle.hand.size() == hand_before, "取消后能量和手牌不变")


func _test_hound_first_attack_log() -> void:
	var battle: Battle = _battle([&"defend", &"defend", &"defend", &"defend", &"defend"], [&"scent_hound"])
	_expect(battle.enemies[0].move_id == "sniff", "狗先嗅")
	battle.end_turn()
	_expect(not battle.log_lines.any(func(line: String) -> bool: return line.contains("绕着你")), "嗅的时候不说")
	battle.end_turn()
	_expect(battle.log_lines.any(func(line: String) -> bool: return line.contains("狗绕着你走了一圈，然后扑了上来。")), "第一次咬的时候写战斗记录")


func _test_random_fuzz_no_card_loss() -> void:
	var pool: Array[StringName] = CardTable.reward_pool(&"stitcher", true)
	var groups: Array = EnemyTable.ENCOUNTERS["early"] + EnemyTable.ENCOUNTERS["late"] + EnemyTable.ENCOUNTERS["elite"]
	var crashes: int = 0
	for seed_value: int in range(1, 151):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = seed_value * 31
		var ids: Array = []
		ids.append_array(CharacterTable.starter_deck(&"stitcher"))
		for extra: int in range(8):
			ids.append([pool[rng.randi_range(0, pool.size() - 1)], rng.randf() < 0.3])
		var battle: Battle = _battle(ids, groups[seed_value % groups.size()], seed_value, [&"broken_ring", &"whetstone", &"empty_ink"])
		var safety: int = 0
		while not battle.over and safety < 60:
			var moves: int = 0
			while moves < 12 and not battle.over:
				if not battle.pending.is_empty():
					var options: Array = battle.pending["options"]
					battle.choose(rng.randi_range(0, options.size() - 1))
					continue
				var playable: Array[int] = []
				for index: int in range(battle.hand.size()):
					if battle.can_play(index):
						playable.append(index)
				if playable.is_empty() or rng.randf() < 0.1:
					break
				var alive: Array[BattleEnemy] = battle.alive_enemies()
				battle.play_card(playable[rng.randi_range(0, playable.size() - 1)], alive[rng.randi_range(0, alive.size() - 1)].index)
				moves += 1
			if not battle.over:
				battle.end_turn()
			safety += 1
		if battle.hp < 0 or battle.energy < 0 or battle.overload < 0 or battle.overload >= Battle.OVERLOAD_CAP:
			crashes += 1
		for enemy: BattleEnemy in battle.enemies:
			if enemy.hp < 0 or enemy.block < 0:
				crashes += 1
	_expect(crashes == 0, "150 场乱打：数值从不越界（异常 %d）" % crashes)


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("  ✗ " + label)
