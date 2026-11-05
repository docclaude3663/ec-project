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
]

## Владельцы значений: kin, eng, cpl, chs (компоненты), rb (RigidBody3D), mat (его physics material),
## susp (SuspensionConfig вагона)
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
	["hard_stop_mult", "coupler_feel", "Жесткость упора, x", 1.0, 50.0, 0.1, "cpl", "", ""],
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
		for p in _params:
			_index[p.key] = p
	return _params


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
	var p := _def(key)
	return not p.is_empty() and _owner(entity, p.owner) != null


## Текущее значение или null, если у цели такого параметра нет
static func read(entity: Entity, key: String) -> Variant:
	var p := _def(key)
	if p.is_empty():
		return null
	var o := _owner(entity, p.owner)
	return o.get(key) if o else null


## Записывает значение. Без нужного компонента ничего не делает
static func write(entity: Entity, key: String, value: Variant) -> void:
	var p := _def(key)
	if p.is_empty():
		return
	var o := _owner(entity, p.owner, true)
	if o == null:
		return
	var v: Variant = bool(value) if p.kind == Kind.TOGGLE else float(value)
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
		var old: Variant = src.get(p.field)
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
		_passport_source(entity, d.dest, true).set(d.field, d.value)
	var setting := (entity.get_comp(C_Identity) as C_Identity).setting
	var err := ResourceSaver.save(setting, path)
	# Подвеска может лежать в своем .tres: тогда ее сохраняем отдельно
	if err == OK and cfg.suspension != null:
		var sp := cfg.suspension.resource_path
		if sp.ends_with(".tres") and not sp.contains("::"):
			err = ResourceSaver.save(cfg.suspension, sp)
	if err != OK:
		for d in diff:   # не оставляем в памяти значения, которых нет в файле
			_passport_source(entity, d.dest, true).set(d.field, d.old)
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


static func _body(entity: Entity) -> RigidBody3D:
	var kin := entity.get_comp(C_Kinematics) as C_Kinematics
	if kin == null or not is_instance_valid(kin.rb):
		return null
	return kin.rb
