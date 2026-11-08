class_name C_MultiSelected extends Component

# XX claude-switch (новый файл)
#######################
## 💡 State. Объект входит в группу, выбранную рамкой (GroupSelection). Его добавляет и снимает GroupSelection.
#######################
## Отличие от C_Selected: это НЕ одиночный выбор. Группа не открывает инфопанель, не показывает ручки flex, не принимает T стрелки и т.п.
## Визуал красит ее состоянием Outline.S.MULTI (фиолетовый контур) и выбранным оверлеем (C_Visual.update_visual).

func on_added() -> void:
	name = 'C_MultiSelected'


func _init() -> void:
	is_state = true
