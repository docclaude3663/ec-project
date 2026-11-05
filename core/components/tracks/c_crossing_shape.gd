class_name C_CrossingShape extends ICapability

# XX claude-switch (новый файл)
####################
## Способность. Форма кросса: два прямых пути, пересекающихся в центре под углом cross_deg.
####################
## Как C_SwitchShape, но оба маршрута активны одновременно (C_Path.set_routes(..., parallel = true)):
## вагон едет по тому, на который въехал (BogieData.route, выбирается по сокету входа или по курсору при посадке).
##   маршрут 0: вдоль -Z, как у прямого трака; маршрут 1: он же, повернутый вокруг центра на cross_deg.
## Сокеты (C_Socket строит их по маршрутам по порядку): [0] начало 0, [1] конец 0, [2] начало 1, [3] конец 1.
## Центр пересечения = середина маршрута 0, после центрирования C_Path он в начале координат Entity.
## Должен стоять в массиве компонентов ПОСЛЕ C_Path и ДО C_Socket.
## Пока только прямые пути (радиус на кроссе всегда INF).
## Электрика: CrossingConfig.separate_circuits (по умолчанию true) дает два независимых луча C_PowerTrack.
## Клип питания на кроссе питает путь 0, путь 1 получает ток от соседей (PGM ходит по лучам, см. power_grid_manager).

## Параметры задает CrossingShapeSettings из паспорта (CrossingConfig), компонент паспорт не читает
var length := 23.9
var cross_deg := 15.0
var separate_circuits := true


func on_entity_ready() -> void:
	var path := get_comp(C_Path) as C_Path
	if path == null:
		push_error("C_CrossingShape: нужен C_Path перед компонентом")
		return
	cross_deg = clampf(absf(cross_deg), 5.0, 90.0)

	# Геометрия ровно по паспорту, угол сам не меняется (соседние концы путей разнесены на L * sin(a / 2))
	path.set_routes(build_routes(path, length, cross_deg), 0, true)

	# Электрика: два независимых луча (путь 0 и путь 1). Сокеты получат свой луч при сборке (C_Socket идет после формы)
	var pt := get_comp(C_PowerTrack) as C_PowerTrack
	if pt and separate_circuits:
		pt.set_legs(2)


## Чистая функция: два пути. Путь 1 = путь 0, повернутый вокруг его середины на deg
static func build_routes(path: C_Path, len_straight: float, deg: float) -> Array[Curve3D]:
	var a := path.generate_track_curve(len_straight, 0.0)
	var center := a.sample_baked(a.get_baked_length() * 0.5)
	var rot := Basis(Vector3.UP, deg_to_rad(deg))
	var b: Curve3D = a.duplicate()
	for i in b.point_count:
		b.set_point_position(i, center + rot * (a.get_point_position(i) - center))
		b.set_point_in(i, rot * a.get_point_in(i))
		b.set_point_out(i, rot * a.get_point_out(i))
	var res: Array[Curve3D] = [a, b]
	return res
