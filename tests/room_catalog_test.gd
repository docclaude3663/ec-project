extends Node

## ATTN_25 RM3: каталог комнат читает карточки из data/rooms/cards/. Запуск: открыть tests/room_catalog_test.tscn и нажать F6.
## Результат в Output: во всех строках OK, в конце ИТОГ: OK.
## Проверяет: папка карточек чистая (RoomCatalog.validate), порядок и состав списка, dev_only (стенд и куб не видны игроку),
## сцена у карточек attic и bench, процедурные kid_room_10 и cube без сцены, и что validate() ловит плохие карточки
## (временные файлы в user://, в проект ничего не пишется).

var _bad := 0


func check(label: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_bad += 1
	print("  %s %s %s" % ["OK " if cond else "ОШИБКА", label, detail])


func _ids(list: Array[Dictionary]) -> Array:
	return list.map(func(d: Dictionary) -> StringName: return d.id)


func _has_problem(problems: Array[String], part: String) -> bool:
	for p in problems:
		if part in p:
			return true
	return false


func _ready() -> void:
	print("== 1. Папка карточек data/rooms/cards")
	var problems := RoomCatalog.validate()
	check("validate: проблем нет", problems.is_empty(), str(problems))
	check("attic есть в каталоге", RoomCatalog.has(&"attic"))
	check("bench есть в каталоге", RoomCatalog.has(&"bench"))
	check("несуществующей комнаты нет", not RoomCatalog.has(&"no_such_room"))

	print("== 2. Список комнат")
	var all := RoomCatalog.entries()
	var ids := _ids(all)
	var seen := {}
	var dup_ids := 0
	for id in ids:
		if seen.has(id):
			dup_ids += 1
		seen[id] = true
	check("id не повторяются", dup_ids == 0, str(ids))
	for id in [&"kid_room_10", &"cube", &"bench", &"attic"]:
		check("в списке есть %s" % id, ids.has(id))
	check("встроенные идут первыми в своём порядке", ids.slice(0, 4) == [&"kid_room_10", &"cube", &"bench", &"attic"], str(ids))
	for e in all:
		check("у '%s' есть название" % e.id, String(e.title) != "")

	print("== 3. dev_only")
	check("bench: dev_only", RoomCatalog.is_dev_only(&"bench"))
	check("cube: dev_only", RoomCatalog.is_dev_only(&"cube"))
	check("attic: не dev_only", not RoomCatalog.is_dev_only(&"attic"))
	check("kid_room_10: не dev_only", not RoomCatalog.is_dev_only(&"kid_room_10"))
	check("неизвестная: не dev_only", not RoomCatalog.is_dev_only(&"no_such_room"))
	var player := _ids(RoomCatalog.entries(true))
	check("игроку не видны bench и cube", not player.has(&"bench") and not player.has(&"cube"), str(player))
	check("игроку видны kid_room_10 и attic", player.has(&"kid_room_10") and player.has(&"attic"), str(player))

	print("== 4. Карточки и сцены")
	var attic := RoomCatalog.make(&"attic")
	var bench := RoomCatalog.make(&"bench")
	check("attic: сцена из карточки", attic.scene != null and attic.id == &"attic", str(attic.scene))
	check("bench: сцена из карточки, dev_only", bench.scene != null and bench.dev_only)
	check("kid_room_10: процедурная, без сцены", RoomCatalog.make(&"kid_room_10").scene == null)
	check("cube: процедурная, без сцены, dev_only", RoomCatalog.make(&"cube").scene == null and RoomCatalog.make(&"cube").dev_only)
	check("неизвестный id: комната по умолчанию", RoomCatalog.make(&"no_such_room").id == RoomCatalog.DEFAULT_ID)

	print("== 5. validate ловит плохие карточки (user://)")
	var dir := "user://room_cards_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var written: Array[String] = []
	var no_scene := RoomConfig.new()
	no_scene.id = &"other"
	written.append(_save(no_scene, dir + "/foo.tres"))
	var wrong_path := RoomConfig.new()
	wrong_path.id = &"baz"
	wrong_path.title = "Baz"
	wrong_path.scene = attic.scene
	written.append(_save(wrong_path, dir + "/baz.tres"))
	var dup := RoomConfig.new()
	dup.id = &"baz"
	dup.title = "Dup"
	dup.scene = attic.scene
	written.append(_save(dup, dir + "/qux.tres"))
	var bad := RoomCatalog.validate(dir)
	check("id не равен имени файла", _has_problem(bad, "не равен имени файла"), str(bad))
	check("нет сцены", _has_problem(bad, "нет сцены"))
	check("сцена не там, где ожидается", _has_problem(bad, "ожидается"))
	check("повторный id", _has_problem(bad, "уже у"))
	for f in written:
		if f != "":
			DirAccess.remove_absolute(f)
	DirAccess.remove_absolute(dir)

	print("ИТОГ: ", "OK" if _bad == 0 else "ОШИБОК %d" % _bad)


func _save(c: RoomConfig, path: String) -> String:
	var err := ResourceSaver.save(c, path)
	check("временная карточка записана: %s" % path.get_file(), err == OK, "код %d" % err)
	return path if err == OK else ""
