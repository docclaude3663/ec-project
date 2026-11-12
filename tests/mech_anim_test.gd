extends Node

## Проверка Actuator.ANIM (ATTN_24 §24.6, шаг S3): механизм ведёт анимацию из модели по состоянию 0..1.
## Запуск: открыть tests/mech_anim_test.tscn и нажать F6. Итог в Output: строки PASS/FAIL и «Mech anim: n/m».
## Модель собирается кодом: родитель, узел-деталь и AnimationPlayer с анимацией mech_test (сдвиг детали на 3 по оси Z за 2 с).
## Сущность и InfoPanel не нужны: проверяются Mech и _setup_anim напрямую.

var _ok := 0
var _all := 0


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var part := Node3D.new()
	part.name = "Part"
	root.add_child(part)

	var anim := Animation.new()
	anim.length = 2.0
	var tr := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(tr, NodePath("Part"))
	anim.position_track_insert_key(tr, 0.0, Vector3.ZERO)
	anim.position_track_insert_key(tr, 2.0, Vector3(0, 0, 3))
	var lib := AnimationLibrary.new()
	lib.add_animation(&"mech_test", anim)
	var src := AnimationPlayer.new()
	root.add_child(src)
	src.root_node = NodePath("..")
	src.add_animation_library(&"", lib)

	# Свой плеер механизма: то же, что делает C_Mechanisms._setup_anim (повторено здесь, чтобы не собирать сущность)
	var comp := C_Mechanisms.new()
	var cfg := MechanismConfig.new()
	cfg.id = &"test"
	cfg.actuator = MechanismConfig.Actuator.ANIM
	var m := C_Mechanisms.Mech.new()
	m.cfg = cfg
	var vis := C_Visual.new()
	vis.instance = root
	comp._setup_anim(m, vis)

	_check("ANIM: плеер механизма создан, найдена", m.found() and m.player != null)
	_check("ANIM: длина анимации взята из ресурса", is_equal_approx(m.anim_len, 2.0))
	_check("ANIM: плеер механизма стоит рядом с плеером модели", m.player != null and m.player.get_parent() == root)
	_check("ANIM: поза покоя (t = 0)", part.position.is_equal_approx(Vector3.ZERO))

	m.t = 1.0
	m.target = 1.0
	m.apply()
	_check("ANIM: t = 1, деталь в рабочем положении (почти конец анимации)", part.position.z > 2.99)
	m.t = 0.5
	m.apply()
	_check("ANIM: t = 0.5, середина хода (smoothstep даёт 0.5)", absf(part.position.z - 1.5) < 0.01)
	m.t = 0.0
	m.apply()
	_check("ANIM: возврат в покой", part.position.is_equal_approx(Vector3.ZERO))

	var missing := C_Mechanisms.Mech.new()
	var cfg2 := MechanismConfig.new()
	cfg2.id = &"nope"
	cfg2.actuator = MechanismConfig.Actuator.ANIM
	missing.cfg = cfg2
	comp._setup_anim(missing, vis)
	_check("ANIM: нет такой анимации, механизм не найден и apply не падает", not missing.found())
	missing.apply()

	_check("ANIM: старые значения enum не сдвинулись", MechanismConfig.Actuator.SLIDE == 0 and MechanismConfig.Actuator.ROTATE == 1
		and MechanismConfig.Actuator.ANIM == 6)

	print("Mech anim: %d/%d" % [_ok, _all])
	get_tree().quit(0 if _ok == _all else 1)


func _check(title: String, cond: bool) -> void:
	_all += 1
	if cond:
		_ok += 1
		print("PASS ", title)
	else:
		print("FAIL ", title)
