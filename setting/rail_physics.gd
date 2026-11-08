class_name RailPhysics extends RefCounted

########################
## Общие константы и формулы для C_Chassis (рельсы) и C_Kinematics (стол).
## Меняешь здесь - меняется и там, и там.
########################

## g для качения/тяги (как было в шасси, roll_resistance не ломается)
const G_ROLL := 9.8
## Тот же временной масштаб, что у вертикального ассиста (C_Kinematics._assist_vertical)
const VERTICAL_SCALE := 80.0
## g для скольжения корпусом / боковой юз
const G_SLIDE := 9.8 * VERTICAL_SCALE
## Пинок: J = power_kick * K [Н*с], dv = J / m. Одинаково на рельсах и на столе
const KICK_IMPULSE_K := 2.0

## Пробуксовка на рельсах (C_Chassis). Колёса в срыве - отдельное состояние со своей скоростью
## Сила трения в срыве относительно предела сцепления (m*g*longitudinal_grip): срыв держится дольше, чем страгивание
const SLIP_KINETIC := 0.85
## Постоянная времени раскрутки колёс мотором (с): за ~3 таких интервала колёса выходят на обороты холостого хода
const WHEEL_SPINUP_TAU := 0.15
## Сцепление возвращается, когда колёса и рельс отличаются меньше этого (м/с) и мотор снова укладывается в предел
const SLIP_REGAIN_DV := 0.3


## dv за шаг от кулоновского трения. Не даёт трению развернуть скорость.
static func friction_dv(v: float, mu: float, g: float, dt: float) -> float:
	return -signf(v) * minf(mu * g * dt, absf(v))

# XX claude-terra
## Множитель уклона для C_Chassis (incline_force). 1 = "честная" физика, 5 = горка заметна
const GRADE_K := 5.0
