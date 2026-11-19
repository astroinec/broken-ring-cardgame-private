extends SceneTree

const OUT_DIR: String = "/tmp/br_shots"
var main: Control


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var suffix: String = "%d" % OS.get_process_id()
	var save_manager: SaveManager = SaveManager.new("user://review_capture_save_%s.json" % suffix)
	var profile_manager: ProfileManager = ProfileManager.new("user://review_capture_profile_%s.json" % suffix)
	save_manager.delete()
	profile_manager.delete()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_manager = save_manager
	main.profile_manager = profile_manager
	root.add_child(main)
	await _settle()
	await _shot("01_title")
	main._start_new_run_with_seed(73103)
	await _settle()
	await _shot("02_map")
	var first_id: StringName = main.run_model.available_node_ids[0]
	main._on_map_node_pressed(first_id)
	await _settle()
	await _shot("03_first_node")
	if main.ui_mode == &"combat":
		main._on_card_pressed(0)
		await _settle()
		await _shot("04_combat_after_play")
	main._show_deck_screen()
	await _settle()
	await _shot("05_deck")
	main._show_profile_archive()
	await _settle()
	await _shot("06_card_codex")
	# event screen
	main.run_model.selected_event_id = &"authorless_book"
	main.run_model.event_resolved = false
	main._show_event_screen()
	await _settle()
	await _shot("07_event")
	main.run_model.current_node_id = &"d04_01"
	main.run_model.pending_shop_stock = ShopCatalog.generate(73103, main.run_model.shop_remove_count, main.run_model.relics)
	main._show_shop_screen()
	await _settle()
	await _shot("08_shop")
	main._show_rest_screen()
	await _settle()
	await _shot("09_rest")
	# boss battle
	main.is_test_mode = false
	main.model = CombatModel.new()
	var no_bonus: Array[StringName] = []
	var no_relics: Array[StringName] = []
	main.model.start_battle(91, 9, no_bonus, &"name_eraser", no_relics, main.run_model.get_deck_instances(), 60, 80, {})
	main.ui_mode = &"combat"
	main._build_combat_screen()
	main._refresh_combat()
	await _settle()
	await _shot("10_boss")
	main._show_test_arena_menu()
	await _settle()
	await _shot("11_test_arena")
	save_manager.delete()
	profile_manager.delete()
	quit(0)


func _settle() -> void:
	for i: int in range(6):
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, name])
	print("SHOT %s %s" % [name, main.ui_mode])
