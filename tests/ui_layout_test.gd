extends Node

# U8 (ATTN_17 §17.4): новый файл
## Тест раскладки HUD без игры: берёт шаблон `hud_layout_template_b.tscn`, кладёт его в SubViewport
## разных размеров и печатает пересечения зон и выход за экран.
## Запуск: tests/ui_layout_test.tscn, F6. Результат в Output: PASS / FAIL и итог.
## L1 каждая видимая зона целиком внутри экрана
## L2 зоны не пересекаются (кроме допустимых пар: SideDock выезжает поверх DC)
## L3 нижние края CategoriesPanel и ToolDock на одной линии
## Когда появится `ui/hud.tscn`, поменять TEMPLATE и ZONES.

const TEMPLATE := "res://ui/templates/hud_layout_template_b.tscn"

## База 1920×1080; остальные: шире (ultrawide), выше (16:10) и окно разработки без масштаба.
const SIZES: Array[Vector2i] = [
	Vector2i(1920, 1080), Vector2i(2560, 1080), Vector2i(1920, 1200), Vector2i(1600, 900),
]

const ZONES: Array[String] = [
	"HUD/TopBar", "HUD/DcIndicators", "HUD/DcPanelPlaceholder", "HUD/HintBarTopRight",
	"HUD/Toast", "HUD/RightColumn", "HUD/DockRow/CategoriesPanel", "HUD/DockRow/DockColumn",
	"HUD/SideDock",
]

const ALLOWED: Array = [
	["HUD/SideDock", "HUD/DcPanelPlaceholder"],
	["HUD/SideDock", "HUD/DcIndicators"],
]

var _fails := 0


func _ready() -> void:
	for size in SIZES:
		await _check(size)
	print("ui_layout_test итог: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _check(size: Vector2i) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var root: Node = (load(TEMPLATE) as PackedScene).instantiate()
	vp.add_child(root)
	await get_tree().process_frame
	await get_tree().process_frame

	var screen := Rect2(Vector2.ZERO, Vector2(size))
	var rects := {}
	for z in ZONES:
		var c := root.get_node_or_null(z) as Control
		if c == null:
			_fail(size, "нет узла %s" % z)
			continue
		if not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		rects[z] = r
		if not screen.grow(0.5).encloses(r):
			_fail(size, "L1 %s выходит за экран: %s" % [z, r])

	var names: Array = rects.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: String = names[i]
			var b: String = names[j]
			if _allowed(a, b):
				continue
			if (rects[a] as Rect2).intersects(rects[b]):
				_fail(size, "L2 пересечение %s %s и %s %s" % [a, rects[a], b, rects[b]])

	var cat := root.get_node_or_null("HUD/DockRow/CategoriesPanel") as Control
	var dock := root.get_node_or_null("HUD/DockRow/DockColumn/ToolDock") as Control
	if cat and dock and absf(cat.get_global_rect().end.y - dock.get_global_rect().end.y) > 1.0:
		_fail(size, "L3 нижние края не совпадают: %s и %s" % [cat.get_global_rect().end.y, dock.get_global_rect().end.y])

	print("%s: проверено зон %d" % [size, rects.size()])
	vp.queue_free()


func _allowed(a: String, b: String) -> bool:
	for pair in ALLOWED:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


func _fail(size: Vector2i, msg: String) -> void:
	_fails += 1
	print("FAIL %s: %s" % [size, msg])
