class_name CrossingConfig extends TrackConfig

# XX claude-switch (новый файл)
########################
## Настройки кросса (Crossing, ромбовидное пересечение двух путей).
## radius = длина каждого пути (как у прямого трака), deg = 0.
########################

## Угол пересечения путей, градусы. Путь 0 идет вдоль -Z, путь 1 повернут на этот угол вокруг центра
@export var cross_deg := 15.0
## Раздельные цепи: два пути кросса электрически независимы (свой контур и полярность у каждого), как у кросса
## с изолированными рамками. false: один проводник на оба пути, один контур и одна полярность (ошибка полярности = КЗ)
@export var separate_circuits := true


## Типизированное чтение паспорта. null, если у сущности нет паспорта или в нем конфиг другого семейства
static func from_entity(entity: Entity) -> CrossingConfig:
	var idc := entity.get_comp(C_Identity) as C_Identity
	if idc == null:
		return null
	return idc.object_config as CrossingConfig
