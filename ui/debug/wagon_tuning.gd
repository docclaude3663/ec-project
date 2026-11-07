class_name WagonTuning extends RefCounted

###########################
## WagonTuning. Список ручек вагона и доступ к ним (U14)
###########################
## Единственное место, которое знает, где у вагона лежит каждый параметр: компоненты C_Kinematics, C_Engine,
## C_Coupler, C_Chassis, тело RigidBody3D и конфиг подвески. Группы повторяют категории паспорта (WagonConfig,
## SuspensionConfig). Вкладки DebugPanel строят строки по params() и ходят в вагон только через read / write / has.
## Ничего не знает про UI и ничего не хранит: цель приходит параметром.
##
## Поле "dest" у ручки: куда она записывается кнопкой «В паспорт»: "wagon" (WagonConfig) или "susp" (SuspensionConfig),
## "field": имя поля в паспорте, если оно отличается от имени ручки. Без "dest" ручка живет только на вагоне.

## Тип строки
enum Kind { SPIN, TOGGLE }

const TAB_TUNING := "tuning"
const TAB_SUSPENSION := "suspension"
const TAB_LAYOUT := "layout"
## Сколько тележек поддерживает вкладка Layout (у вагонов 1-2, у сочлененных больше)
const BOGIE_SLOTS := 4

## Группы по вкладкам в порядке показа. id, tab, title (как категория в инспекторе паспорта)
const GROUPS: Array[Dictionary] = [
	{"id": "kinematics", "tab": TAB_TUNING, "title": "Kinematics (Физика)"},
	{"id": "yaw", "tab": TAB_TUNING, "title": "Rotation Limits (YAW)"},
	{"id": "engine", "tab": TAB_TUNING, "title": "Engine Settings (Мотор)"},
	{"id": "coupler", "tab": TAB_TUNING, "title": "Coupler (Сцепка)"},
	{"id": "coupler_feel", "tab": TAB_TUNING, "title": "Coupler: ощущение (не в паспорте)"},
	{"id": "body", "tab": TAB_TUNING, "title": "Тело RigidBody (не в паспорте)"},
	{"id": "susp_switches", "tab": TAB_SUSPENSION, "title": "Включатели (не в паспорте)"},
	{"id": "susp_mass", "tab": TAB_SUSPENSION, "title": "Mass"},
	{"id": "susp_modes", "tab": TAB_SUSPENSION, "title": "Body modes (частота, демпфирование)"},
	{"id": "susp_limits", "tab": TAB_SUSPENSION, "title": "Travel limits (упоры)"},
	{"id": "susp_accel", "tab": TAB_SUSPENSION, "title": "Response to acceleration"},
	{"id": "susp_track", "tab": TAB_SUSPENSION, "title": "Track input (стыки и неровности)"},
	{"id": "susp_hunting", "tab": TAB_SUSPENSION, "title": "Hunting (рыскание тележек)"},
	{"id": "susp_geometry", "tab": TAB_SUSPENSION, "title": "Geometry"},
	{"id": "mesh", "tab": TAB_LAYOUT, "title": "Mesh (кузов)"},
	{"id": "bogies_all", "tab": TAB_LAYOUT, "title": "All bogies (все тележки сразу)"},
	{"id": "bogie0", "tab": TAB_LAYOUT, "title": "Bogie 1"},
	{"id": "bogie1", "tab": TAB_LAYOUT, "title": "Bogie 2"},
	{"id": "bogie2", "tab": TAB_LAYOUT, "title": "Bogie 3"},
	{"id": "bogie3", "tab": TAB_LAYOUT, "title": "Bogie 4"},
]

## Владельцы значений: kin, eng, cpl, chs (компоненты), rb (RigidBody3D), mat (его physics material),
## susp (SuspensionConfig вагона), layout (меш и тележки, см. _read_layout / _write_layout)
const _SPINS := [
	# key, group, label, min, max, step, owner, dest, field
	["mass", "kinematics", "Масса", 0.1, 10000.0, 0.1, "kin", "wagon", ""],
	["max_grip", "kinematics", "Max grip (реборда)", 0.0, 1000.0, 0.1, "kin", "wagon", ""],
	["roll_resistance", "kinematics", "Сопротивление качению", 0.0, 5.0, 0.01, "kin", "wagon", ""],
	["longitudinal_grip", "kinematics", "Продольное сцепление", 0.1, 10.0, 0.1, "kin", "wagon", ""],
	["min_curve_radius", "kinematics", "Мин. радиус кривой", 0.0, 100.0, 0.1, "kin", "wagon", ""],
	["slide_friction", "kinematics", "μ бокового скольжения", 0.0, 5.0, 0.01, "kin", "wagon", ""],
	["locked_wheel_friction", "kinematics", "μ юза локо", 0.0, 10.0, 0.1, "kin", "wagon", ""],
	["max_yaw_deg", "yaw", "Макс. поворот тележки, °", 0.0, 90.0, 1.0, "kin", "wagon", ""],
	["yaw_spring", "yaw", "Возвратная пружина yaw", 0.0, 50.0, 0.1, "kin", "wagon", ""],
	["max_tractive_force", "engine", "Макс. сила тяги, Н", 0.0, 10000.0, 0.1, "eng", "wagon", ""],
	["max_theoretical_speed", "engine", "Макс. скорость, м/с", 0.0, 1000.0, 0.1, "eng", "wagon", ""],
	["offset_z", "coupler", "От центра до торца, м", 0.0, 50.0, 0.1, "cpl", "wagon", "coupler_offset"],
	["slack", "coupler", "Свободный ход, м", 0.0, 2.0, 0.01, "cpl", "wagon", "coupler_slack"],
	["buffer_travel", "coupler", "Ход буфера, м", 0.0, 2.0, 0.01, "cpl", "wagon", "coupler_travel"],
	["strength", "coupler", "Сила разрыва, Н", 0.0, 100000.0, 1.0, "cpl", "wagon", "coupler_strength"],
	["couple_speed_max", "coupler", "Макс. скорость сцепки, м/с", 0.0, 100.0, 0.1, "cpl", "wagon", ""],
	["impact_dv_limit", "coupler", "Δv удара до схода, м/с", 0.0, 100.0, 0.1, "cpl", "wagon", ""],
	["omega", "coupler_feel", "Частота буфера, рад/с", 0.1, 100.0, 0.1, "cpl", "", ""],
	["buffer_zeta", "coupler_feel", "Демпфирование буфера", 0.0, 2.0, 0.01, "cpl", "", ""],
	["draw_zeta", "coupler_feel", "Демпфирование на растяжении", 0.0, 2.0, 0.01, "cpl", "", ""],
	["hard_stop_mult", "coupler_feel", "Жесткость упора, x", 0.0, 50.0, 0.1, "cpl", "", ""],
	["lateral_tol", "coupler_feel", "Допуск по боку, м", 0.0, 10.0, 0.05, "cpl", "", ""],
	["align_cos", "coupler_feel", "Соосность торцов (cos)", 0.0, 1.0, 0.01, "cpl", "", ""],
	["friction", "body", "Трение (physics material)", 0.0, 5.0, 0.01, "mat", "", ""],
	["linear_damp", "body", "Linear damp", 0.0, 10.0, 0.01, "rb", "", ""],
	["angular_damp", "body", "Angular damp", 0.0, 10.0, 0.01, "rb", "", ""],
	["effect_multiplier", "susp_switches", "Множитель эффектов", 0.0, 10.0, 0.1, "chs", "", ""],
	["ref_mass", "susp_mass", "Масса эталонного вагона", 0.01, 1000.0, 0.01, "susp", "susp", ""],
	["heave_hz", "susp_modes", "Вертикаль, Гц", 0.5, 8.0, 0.1, "susp", "susp", ""],
	["heave_zeta", "susp_modes", "Вертикаль, ζ", 0.05, 1.0, 0.01, "susp", "susp", ""],
	["pitch_hz", "susp_modes", "Кивок, Гц", 0.5, 8.0, 0.1, "susp", "susp", ""],
	["pitch_zeta", "susp_modes", "Кивок, ζ", 0.05, 1.0, 0.01, "susp", "susp", ""],
	["roll_hz", "susp_modes", "Крен, Гц", 0.5, 8.0, 0.1, "susp", "susp", ""],
	["roll_zeta", "susp_modes", "Крен, ζ", 0.05, 1.0, 0.01, "susp", "susp", ""],
	["sway_hz", "susp_modes", "Боковая качка, Гц", 0.5, 8.0, 0.1, "susp", "susp", ""],
	["sway_zeta", "susp_modes", "Боковая качка, ζ", 0.05, 1.0, 0.01, "susp", "susp", ""],
	["yaw_hz", "susp_modes", "Рыскание кузова, Гц", 0.5, 8.0, 0.1, "susp", "susp", ""],
	["yaw_zeta", "susp_modes", "Рыскание кузова, ζ", 0.05, 1.0, 0.01, "susp", "susp", ""],
	["limit_heave", "susp_limits", "Ход по вертикали, ю", 0.0, 1.0, 0.005, "susp", "susp", ""],
	["limit_sway", "susp_limits", "Боковой люфт, ю", 0.0, 1.0, 0.005, "susp", "susp", ""],
	["limit_pitch_deg", "susp_limits", "Кивок max, °", 0.0, 30.0, 0.1, "susp", "susp", ""],
	["limit_roll_deg", "susp_limits", "Крен max, °", 0.0, 30.0, 0.1, "susp", "susp", ""],
	["limit_yaw_deg", "susp_limits", "Рыскание max, °", 0.0, 30.0, 0.1, "susp", "susp", ""],
	["pitch_accel_deg", "susp_accel", "Кивок при насыщении, °", 0.0, 30.0, 0.1, "susp", "susp", ""],
	["pitch_accel_ref", "susp_accel", "Ускорение для ~76% кивка", 0.1, 50.0, 0.1, "susp", "susp", ""],
	["roll_accel_deg", "susp_accel", "Крен при насыщении, °", 0.0, 30.0, 0.1, "susp", "susp", ""],
	["roll_accel_ref", "susp_accel", "Ускорение для ~76% крена", 0.1, 50.0, 0.1, "susp", "susp", ""],
	["sway_accel_shift", "susp_accel", "Смещение наружу кривой, ю", 0.0, 1.0, 0.005, "susp", "susp", ""],
	["sway_roll_deg", "susp_accel", "Доп. крен от смещения, °", 0.0, 30.0, 0.1, "susp", "susp", ""],
	["joint_spacing", "susp_track", "Шаг стыков внутри трака, ю (0: нет)", 0.0, 100.0, 0.1, "susp", "susp", ""],
	["joint_kick", "susp_track", "Толчок на стыке", 0.0, 2.0, 0.01, "susp", "susp", ""],
	["joint_track_gain", "susp_track", "Усиление на границе траков, x", 0.0, 10.0, 0.1, "susp", "susp", ""],
	["joint_lateral_ratio", "susp_track", "Доля бокового толчка", 0.0, 2.0, 0.01, "susp", "susp", ""],
	["joint_speed_cap", "susp_track", "Скорость предела толчка, ю/с", 0.0, 100.0, 0.5, "susp", "susp", ""],
	["irregularity_vertical", "susp_track", "Неровности по вертикали, ю", 0.0, 0.2, 0.001, "susp", "susp", ""],
	["irregularity_lateral", "susp_track", "Неровности в сторону, ю", 0.0, 0.2, 0.001, "susp", "susp", ""],
	["irregularity_wavelength", "susp_track", "Длина волны неровностей, ю", 0.1, 100.0, 0.1, "susp", "susp", ""],
	["hunting_v_crit", "susp_hunting", "Критическая скорость, ю/с", 0.1, 100.0, 0.5, "susp", "susp", ""],
	["hunting_wavelength", "susp_hunting", "Длина волны, ю", 0.5, 100.0, 0.5, "susp", "susp", ""],
	["hunting_amp", "susp_hunting", "Амплитуда, ю", 0.0, 0.5, 0.002, "susp", "susp", ""],
	["hunting_curve_gain", "susp_hunting", "Подпитка от кривой", 0.0, 2.0, 0.01, "susp", "susp", ""],
	["pivot_height", "susp_geometry", "Высота оси качания, ю", 0.0, 5.0, 0.05, "susp", "susp", ""],
]

## Включатели (C_Chassis). key, group, label, tip
const _TOGGLES := [
	["enable_suspension", "susp_switches", "Подвеска включена", "Выключение гасит входы подвески, кузов плавно возвращается в покой"],
	["debug_susp_vertical", "susp_switches", "Вертикаль (стыки, неровности)", ""],
	["debug_susp_pitch", "susp_switches", "Кивок (разгон, торможение)", ""],
	["debug_susp_roll", "susp_switches", "Крен в кривых", ""],
	["debug_susp_lateral", "susp_switches", "Боковая раскачка", ""],
	["debug_susp_hunting", "susp_switches", "Рыскание тележек", ""],
]

## Подсказки ручек с пояснением (key -> текст)
const _TIPS := {
	"mass": "Пишется и в C_Kinematics, и в RigidBody (сцепка берет массу тела); подвеска пересчитывается",
	"longitudinal_grip": "Выше этого значения колеса уходят в пробуксовку",
	"offset_z": "Влияет на положение торца для сцепки; модель вагона не перестраивается",
	"ref_mass": "Масса, для которой заданы частоты. Тяжелее вагон: ниже частоты и слабее удары",
	"joint_spacing": "0: стыки только на границах траков. Больше нуля: и внутри длинного трака через N юнитов",
	"hunting_wavelength": "Две тележки качаются со сдвигом фаз база/длина волны; около 2x базы кузов почти только рыскает",
}

static var _params: Array[Dictionary] = []
static var _index: Dictionary = {}
static var _default_susp: SuspensionConfig


## Все ручки: {key, group, tab, kind, label, tip, min, max, step, owner, dest, field}
static func params() -> Array[Dictionary]:
	if _params.is_empty():
		var tab_of := {}
		for g in GROUPS:
			tab_of[g.id] = g.tab
		for t in _TOGGLES:
			_params.append({"key": t[0], "group": t[1], "tab": tab_of[t[1]], "kind": Kind.TOGGLE, "label": t[2],
					"tip": t[3], "owner": "chs", "dest": "", "field": t[0]})
		for r in _SPINS:
			_params.append({"key": r[0], "group": r[1], "tab": tab_of[r[1]], "kind": Kind.SPIN, "label": r[2],
					"tip": _TIPS.get(r[0], ""), "min": r[3], "max": r[4], "step": r[5], "owner": r[6],
					"dest": r[7], "field": r[8] if r[8] != "" else r[0]})
		_add_layout_params()
		for p in _params:
			_index[p.key] = p
	return _params


## Ручки вкладки Layout: высота меша и тележки. bogie: номер тележки (-1: нет, -2: все сразу), prop: что правим
static func _add_layout_params() -> void:
	_params.append({"key": "offset_mesh_y", "group": "mesh", "tab": TAB_LAYOUT, "kind": Kind.SPIN,
			"label": "Высота меша над началом вагона, м", "tip": "WagonConfig.offset_mesh_y. Коллизия кузова не двигается",
			"min": -2.0, "max": 5.0, "step": 0.005, "owner": "layout", "dest": "wagon", "field": "offset_mesh_y",
			"bogie": -1, "prop": "offset_mesh_y"})
	var items := [
		["wheel_y", "Радиус колеса = высота тележки, м", "Y в wheel_pair_position: радиус колеса без реборды, он же высота тележки над началом вагона", 0.05, 3.0, "wheel_pair_position:y"],
		["wheel_z", "Смещение оси от центра тележки, м", "Z в wheel_pair_position. 0: ось одна; одна или две оси решается при сборке вагона", 0.0, 5.0, "wheel_pair_position:z"],
	]
	for it in items:
		_params.append({"key": "all_" + it[0], "group": "bogies_all", "tab": TAB_LAYOUT, "kind": Kind.SPIN,
				"label": it[1], "tip": "Пишется во все тележки сразу. " + it[2], "min": it[3], "max": it[4], "step": 0.005,
				"owner": "layout", "dest": "", "field": it[5], "bogie": -2, "prop": it[0]})
	items.push_front(["b_offset_z", "Смещение тележки по Z, м", "b_offset_z. После правки перепоставьте вагон на рельс: расстановка тележек по траку считается при посадке", -30.0, 30.0, "b_offset_z"])
	for i in BOGIE_SLOTS:
		for it in items:
			_params.append({"key": "bogie%d_%s" % [i, it[0]], "group": "bogie%d" % i, "tab": TAB_LAYOUT, "kind": Kind.SPIN,
					"label": it[1], "tip": it[2], "min": it[3], "max": it[4], "step": 0.005, "owner": "layout",
					"dest": "bogie:%d" % i, "field": it[5], "bogie": i, "prop": it[0]})


static func _def(key: String) -> Dictionary:
	params()
	return _index.get(key, {})


## Где в коде лежит параметр (для режима «Переменные» в DebugPanel)
static func var_name(key: String) -> String:
	var p := _def(key)
	if p.is_empty():
		return key
	match p.owner:
		"kin": return "C_Kinematics." + key + (" (+ rb.mass)" if key == "mass" else "")
		"eng": return "C_Engine." + key
		"cpl": return "C_Coupler." + key
		"chs": return "C_Chassis." + key
		"mat": return "rb.physics_material_override." + key
		"rb": return "rb." + key
		"susp": return "SuspensionConfig." + key
		"layout":
			if p.prop == "offset_mesh_y":
				return "C_TrainVisual.mesh_nodes[0].position.y"
			return "BogieConfig%s.%s" % ["[%d]" % p.bogie if p.bogie >= 0 else "[все]", p.field.replace(":", ".")]
	return key


# --- доступ к вагону ---

## Объект, в котором лежит параметр. for_write: подвеска отдается как собственная копия вагона
static func _owner(entity: Entity, which: String, for_write := false) -> Object:
	if not is_instance_valid(entity):
		return null
	match which:
		"kin": return entity.get_comp(C_Kinematics)
		"eng": return entity.get_comp(C_Engine)
		"cpl": return entity.get_comp(C_Coupler)
		"chs": return entity.get_comp(C_Chassis)
		"rb": return _body(entity)
		"mat":
			var rb := _body(entity)
			return rb.physics_material_override if rb else null
		"susp":
			var chassis := entity.get_comp(C_Chassis) as C_Chassis
			if chassis == null:
				return null
			return chassis.get_tunable_suspension() if for_write else chassis.get_suspension_config()
	return null


## Есть ли у цели то, где лежит параметр (нужные компоненты и тело)
static func has(entity: Entity, key: String) -> bool:
	return read(entity, key) != null


## Текущее значение или null, если у цели такого параметра нет
static func read(entity: Entity, key: String) -> Variant:
	var p := _def(key)
	if p.is_empty():
		return null
	if p.owner == "layout":
		return _read_layout(entity, p)
	var o := _owner(entity, p.owner)
	return o.get(key) if o else null


## Записывает значение. Без нужного компонента ничего не делает
static func write(entity: Entity, key: String, value: Variant) -> void:
	var p := _def(key)
	if p.is_empty():
		return
	if p.owner == "layout":
		_write_layout(entity, p, float(value))
		return
	var o := _owner(entity, p.owner, true)
	if o == null:
		return
	var v: Variant
	if p.kind == Kind.TOGGLE:
		v = bool(value)
	else:
		v = float(value)
	o.set(key, v)
	if key == "mass":
		var kin := o as C_Kinematics
		if is_instance_valid(kin.rb):
			kin.rb.mass = maxf(float(value), 0.001)   # RigidBody3D не принимает массу <= 0
	# Подвеска считает частоты от массы и градусы в радианы при сборке: после правки пересобираем
	if p.owner == "susp" or key == "mass":
		var chassis := entity.get_comp(C_Chassis) as C_Chassis
		if chassis:
			chassis.rebuild_suspension()


## Меш и тележки. Меш читается с узла, тележка с конфига (у вагона своя копия после первой правки)
static func _read_layout(entity: Entity, p: Dictionary) -> Variant:
	if p.prop == "offset_mesh_y":
		var vis := entity.get_comp(C_TrainVisual) as C_TrainVisual
		return vis.get_mesh_offset_y() if vis else null
	var bc := entity.get_comp(C_Bogie) as C_Bogie
	if bc == null:
		return null
	var cfg := bc.bogie_config(maxi(p.bogie, 0))   # -2: «все», показываем первую
	if cfg == null:
		return null
	match p.prop:
		"b_offset_z": return cfg.b_offset_z
		"wheel_y": return cfg.wheel_pair_position.y
		"wheel_z": return cfg.wheel_pair_position.z
	return null


static func _write_layout(entity: Entity, p: Dictionary, value: float) -> void:
	var vis := entity.get_comp(C_TrainVisual) as C_TrainVisual
	if vis == null:
		return
	if p.prop == "offset_mesh_y":
		vis.set_mesh_offset_y(value)
		return
	var bc := entity.get_comp(C_Bogie) as C_Bogie
	if bc == null:
		return
	var indices: Array[int] = []
	if p.bogie >= 0:
		indices.append(p.bogie)
	else:
		for b in bc.bogies_data:
			indices.append(b.id)
	for i in indices:
		var cfg := bc.tunable_bogie_config(i)
		if cfg == null:
			continue
		match p.prop:
			"b_offset_z": cfg.b_offset_z = value
			"wheel_y": cfg.wheel_pair_position.y = value
			"wheel_z": cfg.wheel_pair_position.z = value
		vis.apply_bogie_layout(i, cfg)


## Значения всех доступных цели ручек: key -> значение. Для кнопки «вернуть»
static func snapshot(entity: Entity) -> Dictionary:
	var snap := {}
	for p in params():
		var v: Variant = read(entity, p.key)
		if v != null:
			snap[p.key] = v
	return snap


## Возвращает значения из snapshot()
static func restore(entity: Entity, snap: Dictionary) -> void:
	for key in snap:
		write(entity, key, snap[key])


## Вагон ли это: есть кинематика (тело и масса). Остальные компоненты у вагона разные (мотор только у локо)
static func is_wagon(entity: Entity) -> bool:
	return is_instance_valid(entity) and entity.get_comp(C_Kinematics) != null


## Почему группы нет у цели: подпись компонента, которого не хватает (для строки «нет у этого объекта»)
static func missing_reason(group_id: String) -> String:
	match group_id:
		"engine": return "нет мотора (C_Engine, он только у локомотива)"
		"coupler", "coupler_feel": return "нет сцепки (C_Coupler)"
		"body": return "нет тела или physics material"
		"kinematics", "yaw": return "нет кинематики (C_Kinematics)"
		"mesh": return "нет визуала вагона (C_TrainVisual)"
		"bogies_all", "bogie0", "bogie1", "bogie2", "bogie3": return "нет такой тележки (или нет C_Bogie)"
	return "нет шасси (C_Chassis)"


# --- Паспорт (WagonConfig и его SuspensionConfig в .tres типа вагона) ---

## Паспорт вагона (общий для всех вагонов этого типа) или null
static func passport(entity: Entity) -> WagonConfig:
	if not is_instance_valid(entity):
		return null
	return WagonConfig.from_entity(entity)


## Путь .tres, в котором лежит паспорт (EntitySetting типа вагона). Пусто, если записать некуда
static func passport_path(entity: Entity) -> String:
	var idc := entity.get_comp(C_Identity) as C_Identity if is_instance_valid(entity) else null
	if idc == null or idc.setting == null:
		return ""
	var path := idc.setting.resource_path
	# «файл::Resource_id» это вложенный ресурс, отдельно его не сохранить
	return path if path.ends_with(".tres") and not path.contains("::") else ""


## Объект паспорта, куда пишется ручка. Подвеска в паспорте может быть пустой (значения по умолчанию):
## для сравнения берем эталонные значения, при записи (create) заводим SuspensionConfig
static func _passport_source(entity: Entity, which: String, create := false) -> Object:
	var cfg := passport(entity)
	if cfg == null:
		return null
	if which == "wagon":
		return cfg
	if which.begins_with("bogie:"):
		var i := int(which.get_slice(":", 1))
		return cfg.bogie_configs[i] if i < cfg.bogie_configs.size() else null
	if cfg.suspension == null:
		if not create:
			if _default_susp == null:
				_default_susp = SuspensionConfig.new()
			return _default_susp
		cfg.suspension = SuspensionConfig.new()
	return cfg.suspension


## Чем вагон отличается от паспорта на вкладке tab: [{key, dest, field, old, value}]
static func passport_diff(entity: Entity, tab: String) -> Array[Dictionary]:
	var diff: Array[Dictionary] = []
	for p in params():
		if p.tab != tab or p.dest == "":
			continue
		var now: Variant = read(entity, p.key)
		var src := _passport_source(entity, p.dest)
		if now == null or src == null:
			continue
		var old: Variant = _field_get(src, p.field)
		if not is_equal_approx(float(old), float(now)):
			diff.append({"key": p.key, "dest": p.dest, "field": p.field, "old": float(old), "value": float(now)})
	return diff


## Пишет отличия в паспорт и сохраняет .tres. Возвращает {ok: bool, message: String}.
## Уже стоящие вагоны этого типа не меняются (значения копируются в компоненты при создании), новые берут новые значения.
## Работает там, где res:// доступен для записи (запуск из редактора); в собранной игре вернет ошибку записи
static func save_to_passport(entity: Entity, tab: String) -> Dictionary:
	var cfg := passport(entity)
	var path := passport_path(entity)
	if cfg == null:
		return {"ok": false, "message": "У вагона нет паспорта (WagonConfig)."}
	if path == "":
		return {"ok": false, "message": "Паспорт не лежит в отдельном .tres, записывать некуда."}
	var diff := passport_diff(entity, tab)
	if diff.is_empty():
		return {"ok": true, "message": "Паспорт уже совпадает с вагоном."}
	var susp_was_null := cfg.suspension == null
	for d in diff:
		_field_set(_passport_source(entity, d.dest, true), d.field, d.value)
	var setting := (entity.get_comp(C_Identity) as C_Identity).setting
	var err := ResourceSaver.save(setting, path)
	# Подвеска может лежать в своем .tres: тогда ее сохраняем отдельно
	if err == OK and cfg.suspension != null:
		var sp := cfg.suspension.resource_path
		if sp.ends_with(".tres") and not sp.contains("::"):
			err = ResourceSaver.save(cfg.suspension, sp)
	if err != OK:
		for d in diff:   # не оставляем в памяти значения, которых нет в файле
			_field_set(_passport_source(entity, d.dest, true), d.field, d.old)
		if susp_was_null:
			cfg.suspension = null
		return {"ok": false, "message": "Не записано в %s: %s." % [path, error_string(err)]}
	return {"ok": true, "message": "Записано в %s: %d знач." % [path, diff.size()]}


## Отличия текстом «поле = значение» (для буфера обмена: вставить в инспектор паспорта руками)
static func passport_diff_text(entity: Entity, tab: String) -> String:
	var lines: PackedStringArray = []
	for d in passport_diff(entity, tab):
		lines.append("%s%s = %s" % ["suspension." if d.dest == "susp" else "", d.field, String.num(d.value, 4)])
	return "\n".join(lines)


## Поле паспорта по имени; «wheel_pair_position:y» это компонента вектора
static func _field_get(src: Object, field: String) -> Variant:
	if field.contains(":"):
		var v: Vector3 = src.get(field.get_slice(":", 0))
		return v[_axis(field.get_slice(":", 1))]
	return src.get(field)


static func _field_set(src: Object, field: String, value: float) -> void:
	if field.contains(":"):
		var fname := field.get_slice(":", 0)
		var v: Vector3 = src.get(fname)
		v[_axis(field.get_slice(":", 1))] = value
		src.set(fname, v)
	else:
		src.set(field, value)


static func _axis(c: String) -> int:
	return {"x": 0, "y": 1, "z": 2}.get(c, 1)


static func _body(entity: Entity) -> RigidBody3D:
	var kin := entity.get_comp(C_Kinematics) as C_Kinematics
	if kin == null or not is_instance_valid(kin.rb):
		return null
	return kin.rb
