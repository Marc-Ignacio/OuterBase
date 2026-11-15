# res://scripts/core/AstronautNeeds.gd
class_name AstronautNeeds
extends Node

## AstronautNeeds.gd - Simulación del Estado Físico y Necesidades del Astronauta
## Administra la Alimentación, Aseo/Agua y Densidad Ósea (Ejercicio).
## Cuando cualquiera de estas variables desciende por debajo del 30%, se calcula
## una penalización continua que reduce el speed_multiplier enviado al Player.gd.
## Comunicación 100% mediante Señales, sin menús ni texto en pantalla.

# ==============================================================================
# SEÑALES (DESACOPLADAS DEL JUGADOR Y DE LA UI)
# ==============================================================================

## Emitida hacia Player.gd cada vez que cambia el multiplicador de velocidad.
signal speed_multiplier_changed(new_multiplier: float)

## Emitida periódicamente con los valores actuales (0 a 100) para feedback visual o sonoro.
signal needs_updated(nutrition: float, hygiene: float, bone_density: float)

## Emitida cuando una necesidad entra en estado crítico (< 30%).
signal need_critical(need_type: StringName, current_value: float)

## Emitida cuando una necesidad se recupera por encima del umbral crítico (>= 30%).
signal need_recovered(need_type: StringName, current_value: float)

# ==============================================================================
# CONSTANTES DE IDENTIFICACIÓN
# ==============================================================================

const NEED_NUTRITION: StringName = &"nutrition"
const NEED_HYGIENE: StringName = &"hygiene"
const NEED_BONE_DENSITY: StringName = &"bone_density"

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Valores Iniciales (0 a 100)")
@export_range(0.0, 100.0, 1.0) var initial_nutrition: float = 100.0
@export_range(0.0, 100.0, 1.0) var initial_hygiene: float = 100.0
@export_range(0.0, 100.0, 1.0) var initial_bone_density: float = 100.0

@export_group("Tasas de Decaimiento (Puntos por segundo)")
## Pérdida de nutrición por segundo (hambre).
@export_range(0.01, 2.0, 0.05) var nutrition_decay_rate: float = 0.35
## Pérdida de higiene/agua por segundo.
@export_range(0.01, 2.0, 0.05) var hygiene_decay_rate: float = 0.25
## Pérdida de densidad ósea por microgravedad sin ejercicio.
@export_range(0.01, 2.0, 0.05) var bone_density_decay_rate: float = 0.30

@export_group("Umbrales y Penalizaciones de Velocidad")
## Umbral porcentual a partir del cual se aplican penalizaciones de movimiento (30%).
@export_range(10.0, 50.0, 1.0) var critical_threshold: float = 30.0

## Multiplicador mínimo de velocidad para evitar que el astronauta quede inmóvil (ej. 35%).
@export_range(0.1, 0.8, 0.05) var min_speed_multiplier: float = 0.35

## Penalización máxima a la velocidad por desnutrición (hasta -30%).
@export_range(0.05, 0.5, 0.05) var max_nutrition_penalty: float = 0.30

## Penalización máxima a la velocidad por atrofia muscular/ósea (sensación pesada, hasta -40%).
@export_range(0.05, 0.6, 0.05) var max_bone_penalty: float = 0.40

## Penalización máxima a la velocidad por falta de aseo/deshidratación (hasta -15%).
@export_range(0.05, 0.3, 0.05) var max_hygiene_penalty: float = 0.15

# ==============================================================================
# ESTADO INTERNO
# ==============================================================================

var nutrition: float = 100.0
var hygiene: float = 100.0
var bone_density: float = 100.0

var current_speed_multiplier: float = 1.0

# Registro de si estaban críticas para emitir señales de alerta/recuperación una sola vez
var _is_nutrition_critical: bool = false
var _is_hygiene_critical: bool = false
var _is_bone_critical: bool = false

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	nutrition = clampf(initial_nutrition, 0.0, 100.0)
	hygiene = clampf(initial_hygiene, 0.0, 100.0)
	bone_density = clampf(initial_bone_density, 0.0, 100.0)
	
	_recalculate_speed_multiplier(true)
	needs_updated.emit(nutrition, hygiene, bone_density)


func _process(delta: float) -> void:
	# 1. Disminución gradual en el tiempo
	var prev_nutrition := nutrition
	var prev_hygiene := hygiene
	var prev_bone := bone_density
	
	nutrition = maxf(0.0, nutrition - (nutrition_decay_rate * delta))
	hygiene = maxf(0.0, hygiene - (hygiene_decay_rate * delta))
	bone_density = maxf(0.0, bone_density - (bone_density_decay_rate * delta))
	
	# 2. Verificar transiciones de estado crítico
	_check_threshold_transitions(prev_nutrition, prev_hygiene, prev_bone)
	
	# 3. Recalcular penalización continua sobre la velocidad
	_recalculate_speed_multiplier()
	
	# 4. Emitir valores actualizados
	needs_updated.emit(nutrition, hygiene, bone_density)

# ==============================================================================
# CÁLCULO MATEMÁTICO DE VELOCIDAD Y PENALIZACIONES
# ==============================================================================

func _recalculate_speed_multiplier(force_emit: bool = false) -> void:
	var total_penalty: float = 0.0
	
	# Penalización por nutrición baja (< 30%)
	if nutrition < critical_threshold:
		var deficit_ratio: float = (critical_threshold - nutrition) / critical_threshold
		total_penalty += deficit_ratio * max_nutrition_penalty
		
	# Penalización por densidad ósea baja (< 30%) - astronauta pesado y torpe
	if bone_density < critical_threshold:
		var deficit_ratio: float = (critical_threshold - bone_density) / critical_threshold
		total_penalty += deficit_ratio * max_bone_penalty
		
	# Penalización por aseo/agua bajo (< 30%)
	if hygiene < critical_threshold:
		var deficit_ratio: float = (critical_threshold - hygiene) / critical_threshold
		total_penalty += deficit_ratio * max_hygiene_penalty
		
	var new_multiplier: float = clampf(1.0 - total_penalty, min_speed_multiplier, 1.0)
	
	# Emitir únicamente si hay un cambio apreciable o se fuerza
	if force_emit or not is_equal_approx(new_multiplier, current_speed_multiplier):
		current_speed_multiplier = new_multiplier
		speed_multiplier_changed.emit(current_speed_multiplier)


func _check_threshold_transitions(_prev_nut: float, _prev_hyg: float, _prev_bone: float) -> void:
	# Nutrición
	if nutrition < critical_threshold and not _is_nutrition_critical:
		_is_nutrition_critical = true
		need_critical.emit(NEED_NUTRITION, nutrition)
	elif nutrition >= critical_threshold and _is_nutrition_critical:
		_is_nutrition_critical = false
		need_recovered.emit(NEED_NUTRITION, nutrition)
		
	# Higiene
	if hygiene < critical_threshold and not _is_hygiene_critical:
		_is_hygiene_critical = true
		need_critical.emit(NEED_HYGIENE, hygiene)
	elif hygiene >= critical_threshold and _is_hygiene_critical:
		_is_hygiene_critical = false
		need_recovered.emit(NEED_HYGIENE, hygiene)
		
	# Densidad Ósea
	if bone_density < critical_threshold and not _is_bone_critical:
		_is_bone_critical = true
		need_critical.emit(NEED_BONE_DENSITY, bone_density)
	elif bone_density >= critical_threshold and _is_bone_critical:
		_is_bone_critical = false
		need_recovered.emit(NEED_BONE_DENSITY, bone_density)

# ==============================================================================
# RELLENO DE NECESIDADES (INTERACCIÓN CON ESTACIONES DEL MAPA)
# ==============================================================================

## Rellena alimentación al consumir alimentos frescos del Invernadero.
func replenish_nutrition(amount: float) -> void:
	if amount <= 0.0:
		return
	nutrition = minf(100.0, nutrition + amount)
	_recalculate_speed_multiplier()
	needs_updated.emit(nutrition, hygiene, bone_density)


## Rellena aseo/agua al usar la Ducha de circuito cerrado.
func replenish_hygiene(amount: float) -> void:
	if amount <= 0.0:
		return
	hygiene = minf(100.0, hygiene + amount)
	_recalculate_speed_multiplier()
	needs_updated.emit(nutrition, hygiene, bone_density)


## Rellena densidad ósea al ejercitarse en la Cinta de Correr (Treadmill).
func replenish_bone_density(amount: float) -> void:
	if amount <= 0.0:
		return
	bone_density = minf(100.0, bone_density + amount)
	_recalculate_speed_multiplier()
	needs_updated.emit(nutrition, hygiene, bone_density)


## Función unificada para recibir interacción con cualquier estación.
func replenish_need(need_type: StringName, amount: float) -> void:
	match need_type:
		NEED_NUTRITION:
			replenish_nutrition(amount)
		NEED_HYGIENE:
			replenish_hygiene(amount)
		NEED_BONE_DENSITY:
			replenish_bone_density(amount)

# ==============================================================================
# SLOTS / RECEPTORES DIRECTOS DE SEÑALES DE ESTACIONES
# ==============================================================================

## Callback para conectar con la señal del Invernadero: greenhouse.harvested / food_eaten
func _on_greenhouse_interacted(amount: float = 35.0) -> void:
	replenish_nutrition(amount)


## Callback para conectar con la señal de la Ducha: shower.used
func _on_shower_interacted(amount: float = 40.0) -> void:
	replenish_hygiene(amount)


## Callback para conectar con la señal de la Cinta de Correr: treadmill.exercise_finished
func _on_treadmill_interacted(amount: float = 45.0) -> void:
	replenish_bone_density(amount)

# ==============================================================================
# MÉTODOS DE CONSULTA
# ==============================================================================

func get_speed_multiplier() -> float:
	return current_speed_multiplier


func get_nutrition() -> float:
	return nutrition


func get_hygiene() -> float:
	return hygiene


func get_bone_density() -> float:
	return bone_density


func is_any_need_critical() -> bool:
	return _is_nutrition_critical or _is_hygiene_critical or _is_bone_critical
