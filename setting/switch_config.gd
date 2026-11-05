class_name SwitchConfig extends TrackConfig

# XX claude-switch (новый файл)
########################
## Настройки стрелки (Switch / turnout). Наследует TrackConfig:
##   radius = длина по прямой ветке (как у прямого трака), deg = 0.
## Ответвление строится дугой от носка (начала). Геометрия процедурная, как у flex:
## C_SwitchShape строит кривые, C_SwitchVisual рисует меш и коллизии по TrackStyle.
########################

## Угол ответвления, градусы (модуль). Знак задает hand
@export var diverge_deg := 15.0
## Радиус ответвления, ю. 0 = L / sin(угла): конец ответвления лежит на одной линии с концом прямой,
## как у реальных стрелок (торцы выровнены)
@export var diverge_radius := 0.0
## +1 правая стрелка (ветка уходит вправо по ходу от носка), -1 левая
@export var hand := 1
## Стартовое положение: 0 = прямо, 1 = ответвление
@export var start_route := 0
## Управление: Manual (рычаг у носка, клик) или Remote (рычаг заблокирован, команды с пульта/привода)
@export_enum("Manual", "Remote") var control := 0
## Время перекладки, с. 0 = мгновенно. У дистанционного привода обычно 0.3 .. 3
@export var throw_time := 0.0
## E1: ток только на выбранную ветку (невыбранная мертвая, удобно для тупиков и депо). false: обе ветки под током
@export var power_routing := false
## E2: тип крестовины. Insulated: пластиковая, КЗ нет. Live fixed: токопроводящая, привязана к пути 0, на пути 1 при
## проезде КЗ. Live switched: полярность крестовины переключается вместе со стрелкой (контакты привода, реле).
## При power_routing КЗ нет в любом режиме
@export_enum("Insulated", "Live fixed", "Live switched") var frog := 0


## Типизированное чтение паспорта. null, если у сущности нет паспорта или в нем конфиг другого семейства
static func from_entity(entity: Entity) -> SwitchConfig:
	var idc := entity.get_comp(C_Identity) as C_Identity
	if idc == null:
		return null
	return idc.object_config as SwitchConfig
