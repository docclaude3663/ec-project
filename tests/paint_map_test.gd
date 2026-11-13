extends Node

# XX claude-terra 13.13 K1 (новый файл)
## Тест данных кисти: PaintMap (штамп, спад, маска, стирание, сумма весов, отмена мазка, сейв).
## Сцены и TGM не нужно. Запуск: tests/paint_map_test.tscn, F6, строки PASS / FAIL в Output.

var _fails := 0
var _signals := 0
var _last_keys: Array = []


func check(name: String, ok: bool, info := "") -> void:
	if ok:
		print("PASS  ", name)
	else:
		_fails += 1
		print("FAIL  ", name, "  ", info)


func _on_changed(keys: Array) -> void:
	_signals += 1
	_last_keys = keys


func _sum(w: Color) -> float:
	return w.r + w.g + w.b + w.a


func _fresh() -> PaintMap:
	var m := PaintMap.new()
	m.ensure_cell(0.5)
	m.changed.connect(_on_changed)
	return m


func _ready() -> void:
	# спад кисти
	check("falloff: центр 1", is_equal_approx(PaintMap.falloff(0.0, 4.0, 0.5), 1.0))
	check("falloff: внутри жёсткой части 1", is_equal_approx(PaintMap.falloff(2.0, 4.0, 0.5), 1.0))
	check("falloff: на радиусе 0", PaintMap.falloff(4.0, 4.0, 0.5) == 0.0)
	check("falloff: середина спада 0.5", absf(PaintMap.falloff(3.0, 4.0, 0.5) - 0.5) < 0.001)
	check("falloff: жёсткость 1 без спада", PaintMap.falloff(3.99, 4.0, 1.0) == 1.0)
	check("falloff: радиус 0", PaintMap.falloff(0.0, 0.0, 0.5) == 0.0)

	# ячейка и чанки
	var m := PaintMap.new()
	m.ensure_cell(0.5)
	check("ensure_cell: пустая карта берёт размер", m.cell == 0.5)
	check("chunk_of: отрицательные индексы", PaintMap.chunk_of(-1, 0) == Vector2i(-1, 0) and PaintMap.chunk_of(-16, -17) == Vector2i(-1, -2) and PaintMap.chunk_of(16, 15) == Vector2i(1, 0))
	check("stamp без размера ячейки ничего не делает", PaintMap.new().stamp(Vector2.ZERO, 2.0, 0.5, PaintMap.GRASS) == 0)

	# покраска
	m = _fresh()
	var n := m.stamp(Vector2(0.25, 0.25), 2.0, 1.0, PaintMap.GRASS, 1.0)
	check("stamp: ячейки закрашены", n > 0, str(n))
	var w := m.weights(0, 0)
	check("stamp: центр полной травой", is_equal_approx(w.r, 1.0) and w.g == 0.0 and w.b == 0.0, str(w))
	check("stamp: вне радиуса пусто", _sum(m.weights(20, 20)) == 0.0)
	check("stamp: сигнал и ключ чанка", _signals == 1 and _last_keys.has(Vector2i(0, 0)) and _last_keys.has(Vector2i(-1, -1)), str(_last_keys))
	check("dominant: трава", m.dominant(0, 0) == PaintMap.GRASS)
	check("dominant: нет краски", m.dominant(30, 30) == -1)

	# смена класса: сумма не больше 255
	m.stamp(Vector2(0.25, 0.25), 2.0, 1.0, PaintMap.ROCK, 0.5)
	w = m.weights(0, 0)
	check("смена класса: смесь травы и скалы", w.r > 0.3 and w.g > 0.3, str(w))
	check("смена класса: сумма не больше 1", _sum(w) <= 1.001, str(_sum(w)))
	for k in 6:
		m.stamp(Vector2(0.25, 0.25), 2.0, 1.0, PaintMap.GRAVEL, 0.7)
	w = m.weights(0, 0)
	check("повторные мазки: гравий полностью, хвостов нет", w.b == 1.0 and w.r == 0.0 and w.g == 0.0, str(w))

	# мягкий край и накопление
	m = _fresh()
	for k in 8:
		m.stamp(Vector2.ZERO, 3.0, 0.3, PaintMap.GRASS, 0.5)
	check("накопление: центр полный", m.weights(0, 0).r == 1.0 or m.weights(-1, -1).r == 1.0)
	var edge := 0.0
	for i in range(5, 7):
		edge = maxf(edge, m.weights(i, 0).r)
	check("мягкий край: у границы слабее центра", edge < 1.0)

	# маска
	m = _fresh()
	var mask := func(p: Vector2) -> bool: return p.x > 0.0
	m.stamp(Vector2.ZERO, 3.0, 1.0, PaintMap.ROCK, 1.0, mask)
	check("маска: левая половина пуста", _sum(m.weights(-2, 0)) == 0.0)
	check("маска: правая половина закрашена", m.weights(2, 0).g == 1.0)

	# стирание
	m = _fresh()
	m.stamp(Vector2.ZERO, 3.0, 1.0, PaintMap.GRASS, 1.0)
	m.stamp(Vector2.ZERO, 3.0, 1.0, PaintMap.ERASE, 0.5)
	w = m.weights(1, 1)
	check("стирание: ослабляет краску", w.r > 0.3 and w.r < 0.7, str(w))
	for k in 12:
		m.stamp(Vector2.ZERO, 3.0, 1.0, PaintMap.ERASE, 0.5)
	check("стирание: до нуля без хвостов", _sum(m.weights(1, 1)) == 0.0, str(m.weights(1, 1)))
	var e := PaintMap.new()
	e.ensure_cell(0.5)
	check("стирание на пустой карте не создаёт чанков", e.stamp(Vector2.ZERO, 3.0, 1.0, PaintMap.ERASE) == 0 and e.is_empty())
	check("неизвестный класс", m.stamp(Vector2.ZERO, 3.0, 1.0, 9) == 0)

	# отмена мазка
	m = _fresh()
	m.stamp(Vector2.ZERO, 3.0, 1.0, PaintMap.GRASS, 1.0)
	var before := m.save_data()
	m.begin_stroke()
	m.stamp(Vector2.ZERO, 3.0, 1.0, PaintMap.ROCK, 1.0)
	m.stamp(Vector2(20, 20), 3.0, 1.0, PaintMap.GRAVEL, 1.0)   # новый чанк
	var rec := m.end_stroke()
	check("мазок: запись не пуста, два чанка и больше", rec.size() >= 2, str(rec.size()))
	check("мазок: краска сменилась", m.weights(0, 0).g == 1.0 and m.weights(40, 40).b == 1.0)
	m.restore(rec)
	check("отмена: прежняя трава", m.weights(0, 0).r == 1.0 and m.weights(0, 0).g == 0.0)
	check("отмена: новый чанк исчез", _sum(m.weights(40, 40)) == 0.0)
	check("отмена: данные как до мазка", m.save_data() == before)
	m.begin_stroke()
	check("пустой мазок: запись пуста", m.end_stroke().is_empty())

	# сейв
	m = _fresh()
	m.stamp(Vector2(1.0, 2.0), 3.0, 0.5, PaintMap.GRASS, 1.0)
	m.stamp(Vector2(-9.0, -7.0), 2.0, 1.0, PaintMap.ROCK, 1.0)
	m.stamp(Vector2(-9.0, -7.0), 1.0, 1.0, PaintMap.ERASE, 1.0)   # чанк с остатком
	var d := m.save_data()
	check("save: версия и ячейка", int(d.get("v", 0)) == PaintMap.FORMAT and is_equal_approx(float(d["cell"]), 0.5))
	var m2 := PaintMap.new()
	m2.load_data(d)
	var same := m2.cell == m.cell
	for key in m.chunk_keys():
		for j in PaintMap.CHUNK:
			for i in PaintMap.CHUNK:
				if m.weights(key.x * 16 + i, key.y * 16 + j) != m2.weights(key.x * 16 + i, key.y * 16 + j):
					same = false
	check("save/load: все веса совпали", same)
	var empty := PaintMap.new()
	empty.ensure_cell(0.5)
	check("save: пустая карта даёт пустой словарь", empty.save_data().is_empty())
	var blank := _fresh()
	blank.stamp(Vector2.ZERO, 2.0, 1.0, PaintMap.GRASS, 1.0)
	blank.stamp(Vector2.ZERO, 3.0, 1.0, PaintMap.ERASE, 1.0)
	check("save: стёртая краска не пишется", blank.save_data().is_empty())
	m2.load_data({})
	check("load пустого очищает карту", m2.is_empty() and m2.cell == 0.0)
	var bad := {"v": 1, "cell": 0.5, "chunks": [[1]]}
	m2.load_data(bad)
	check("load: короткая запись чанка пропущена", m2.is_empty())

	# clear
	m = _fresh()
	m.stamp(Vector2.ZERO, 3.0, 1.0, PaintMap.GRASS, 1.0)
	_signals = 0
	m.clear()
	check("clear: карта пуста, сигнал, ячейка сброшена", m.is_empty() and _signals == 1 and m.cell == 0.0)

	print("---- paint_map_test: ", "ВСЕ PASS" if _fails == 0 else "ПРОВАЛОВ: %d" % _fails)
