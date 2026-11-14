class_name RoomControl extends Node

########################
## Метка управляемого объекта комнаты (ATTN_25 §25.6)
########################
## Дочерний узел любой Light3D, Node3D или AnimationPlayer в сцене комнаты. Родитель и есть управляемый объект.
## Без метки (и без описания из .glb, RM8) объект не управляется ни Room Studio, ни Observe.
## Примеры: OmniLight3D с RoomControl (id = lamp_test, kind = TOGGLE) получает переключатель во вкладке «Объекты» студии;
## штора на AnimationPlayer с анимацией mech_blind: kind = MECH и MechanismConfig с actuator = ANIM.
## Собирает метки RoomControlRegistry, сам узел логики не имеет.
##
## group: несколько узлов под одним управлением. Метки с одинаковой непустой group сливаются в одно управление
## (id и подпись берутся у первой, kind и scope должны совпадать), например все потолочные лампы одним переключателем.

enum Kind {
	TOGGLE,   ## вкл/выкл: свет, свечение, видимость узла
	SLIDER,   ## 0..1: энергия света (множитель от энергии в сцене)
	MECH,     ## механизм 0..1: SLIDE, ROTATE по оси или ANIM по анимации mech_<id>; нужен mechanism
}

enum Scope {
	STUDIO,    ## только Room Studio
	OBSERVE,   ## ещё и карточка Observe → Light (RM6)
}

## Уникальный в комнате, snake_case
@export var id: StringName = &""
@export var kind: Kind = Kind.TOGGLE
@export var scope: Scope = Scope.STUDIO
## Подпись; пусто: id
@export var title := ""
## Начальное значение: для TOGGLE 0 или 1, для SLIDER и MECH 0..1
@export_range(0.0, 1.0) var default_value := 1.0
## Общее управление нескольких узлов (см. выше)
@export var group: StringName = &""
## Только MECH. SLIDE и ROTATE двигают родителя (Node3D) по axis на travel; ANIM берёт анимацию из плеера внутри родителя
@export var mechanism: MechanismConfig


## Название для списков
func display_title() -> String:
	return title if title != "" else String(id)
