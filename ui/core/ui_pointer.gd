class_name UIPointer extends RefCounted

#########################
## Курсор над UI?
#########################
## Мир и инструменты спрашивают сюда, чтобы не реагировать на объекты за панелью.
## Controls с mouse_filter = IGNORE (подсказки, прозрачные обёртки панелей) не считаются.
## Клик по панели до инструментов и так не доходит (они работают через _unhandled_input),
## поэтому метод нужен для того, что опрашивает мышь само: ховер, луч каждый кадр.

static func is_over_ui(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	return viewport.gui_get_hovered_control() != null


## U10: открыто ли модальное окно (диалог). Инструменты и камера тогда не читают клавиши
static func modal_open() -> bool:
	return WindowStack.has_open()
