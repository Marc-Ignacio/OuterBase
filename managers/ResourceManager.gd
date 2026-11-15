# res://managers/ResourceManager.gd
extends Node

## ResourceManager.gd - Gestor Central de Recursos de la Base Espacial (Autoload: ResourceManager)
## Administra el ciclo matemático de producción, almacenamiento e interdependencia
## de Energía, Agua, Comida y Oxígeno. Comunicación exclusiva mediante Señales.

# ==============================================================================
# SEÑALES (ESTRICTAMENTE DESACOPLADAS)
# ==============================================================================

## Emitida cada vez que la cantidad de un recurso cambia en el ciclo o por acción externa.
signal resource_updated(type: StringName, amount: float)
signal oxygen_leak_changed(active: bool)

## Emitida cuando un recurso cruza hacia abajo el umbral crítico de reserva.
signal resource_critical(type: StringName)

## Emitida cuando la energía de las baterías se agota completamente (apagón general).
signal blackout_triggered()

# ==============================================================================
# CONSTANTES DE IDENTIFICACIÓN DE RECURSOS
# ==============================================================================

const RES_ENERGY: StringName = &"energy"
const RES_WATER: StringName = &"water"
const RES_FOOD: StringName = &"food"
const RES_OXYGEN: StringName = &"oxygen"

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Ciclo de Simulación")
## Frecuencia de actualización matemática de los recursos en segundos (1.0 = cada segundo).
@export_range(0.1, 5.0, 0.1) var tick_rate: float = 1.0

@export_group("Capacidades Máximas de Almacenamiento")
@export var max_water: float = 500.0
@export var max_food: float = 300.0
@export var max_oxygen: float = 1000.0

@export_group("Valores Iniciales")
@export var initial_water: float = 400.0
@export var initial_food: float = 250.0
@export var initial_oxygen: float = 900.0

@export_group("Generación Base (por segundo)")
## Comida producida por el módulo de cultivo (+Y/s).
@export var greenhouse_food_generation: float = 1.5
## Oxígeno producido por la fotosíntesis del invernadero (+Z/s).
@export var greenhouse_oxygen_generation: float = 2.0

@export_group("Consumo Base de Módulos (por segundo)")
## Energía requerida por el soporte vital para funcionar (-X/s).
@export var life_support_energy_cost: float = 10.0
## Energía requerida por las lámparas y bombas del invernadero (-A/s).
@export var greenhouse_energy_cost: float = 5.0
## Agua consumida por el sistema hidropónico del invernadero (-B/s).
@export var greenhouse_water_cost: float = 2.0

@export_group("Consumo de Tripulación (por segundo)")
## Oxígeno consumido por los astronautas.
@export var crew_oxygen_consumption: float = 2.5
## Agua potable consumida por la tripulación.
@export var crew_water_consumption: float = 1.0
## Raciones de alimento consumidas por la tripulación.
@export var crew_food_consumption: float = 0.8

@export_group("Umbrales Críticos (% de capacidad)")
## Porcentaje (0.0 a 1.0) bajo el cual se emite alerta crítica.
@export_range(0.05, 0.5, 0.01) var critical_threshold_ratio: float = 0.20

# ==============================================================================
# ALMACENAMIENTO INTERNO DE RECURSOS
# ==============================================================================

var _resources: Dictionary = {
	RES_WATER: 0.0,
	RES_FOOD: 0.0,
	RES_OXYGEN: 0.0
}

var _critical_state: Dictionary = {
	RES_ENERGY: false,
	RES_WATER: false,
	RES_FOOD: false,
	RES_OXYGEN: false
}

var _tick_timer: Timer
var _oxygen_leak_active := false

# Modificadores temporales aplicados por tareas u otros sistemas
var life_support_efficiency_bonus: float = 1.0
var greenhouse_efficiency_bonus: float = 1.0

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	reset_reserves()
	_connect_shared_energy.call_deferred()

	_tick_timer = Timer.new()
	_tick_timer.name = "ResourceTickTimer"
	_tick_timer.wait_time = tick_rate
	_tick_timer.one_shot = false
	_tick_timer.autostart = true
	_tick_timer.timeout.connect(_on_tick_timeout)
	add_child(_tick_timer)


func reset_reserves() -> void:
	set_oxygen_leak_active(false)
	_resources[RES_WATER] = clampf(initial_water, 0.0, max_water)
	_resources[RES_FOOD] = clampf(initial_food, 0.0, max_food)
	_resources[RES_OXYGEN] = clampf(initial_oxygen, 0.0, max_oxygen)
	
	for resource in _critical_state:
		_critical_state[resource] = false
	set_life_support_bonus(1.0)
	set_greenhouse_bonus(1.0)
	# Sincronización inicial para UI
	_emit_all_resources()


func _connect_shared_energy() -> void:
	EnergyEconomy.energy_updated.connect(_on_shared_energy_updated)
	_on_shared_energy_updated(EnergyEconomy.get_current_watts(), EnergyEconomy.get_max_watts())


func _on_shared_energy_updated(current: float, _capacity: float) -> void:
	resource_updated.emit(RES_ENERGY, current)


# ==============================================================================
# CÁLCULO MATEMÁTICO DEL CICLO (CADA SEGUNDO)
# ==============================================================================

func _on_tick_timeout() -> void:
	if DayManager.is_running:
		_calculate_resource_cycle(tick_rate)


func _calculate_resource_cycle(delta_time: float) -> void:
	# 1. Obtener multiplicadores de la BaseFSM si está presente
	var energy_multiplier: float = 1.0
	var production_multiplier: float = 1.0
	var is_blackout: bool = false
	var is_emergency: bool = false
	
	if has_node("/root/BaseFSM"):
		var fsm: Node = get_node("/root/BaseFSM")
		if fsm.has_method("get_energy_consumption_multiplier"):
			energy_multiplier = fsm.get_energy_consumption_multiplier()
		if fsm.has_method("get_production_efficiency_multiplier"):
			production_multiplier = fsm.get_production_efficiency_multiplier()
		if "current_state" in fsm:
			is_blackout = (fsm.current_state == BaseFSM.BaseState.FALLO_SISTEMATICO)
			is_emergency = (fsm.current_state == BaseFSM.BaseState.EMERGENCIA_RADIACION)

	# -------------------------------------------------------------------------
	# 2. Potencia solar de uso directo. EnergyEconomy acredita el excedente.
	# -------------------------------------------------------------------------
	var recovering := BaseFSM.is_in_state(BaseFSM.BaseState.RECUPERACION)
	# Los paneles vuelven a alimentar la base al terminar la alerta.
	# La eficiencia reducida aún se aplica a la producción de los módulos.
	var solar_multiplier := 1.0 if recovering else production_multiplier
	var direct_power := EnergyEconomy.get_operating_solar_power() * solar_multiplier * delta_time
	
	# -------------------------------------------------------------------------
	# 3. CONSUMOS DE ENERGÍA INTERDEPENDIENTES
	# -------------------------------------------------------------------------
	var life_support_energy_needed: float = life_support_energy_cost * energy_multiplier * delta_time
	var greenhouse_energy_needed: float = greenhouse_energy_cost * delta_time
	var life_support_deficit := maxf(0.0, life_support_energy_needed - direct_power)
	var life_support_active := EnergyEconomy.try_spend_energy(life_support_deficit, "Soporte vital")
	var remaining_power := maxf(0.0, direct_power - life_support_energy_needed)
	var greenhouse_deficit := maxf(0.0, greenhouse_energy_needed - remaining_power)
	var greenhouse_powered := life_support_active and EnergyEconomy.try_spend_energy(
		greenhouse_deficit, "Invernadero automático")

	# La recuperación tiene su propio temporizador. Un déficit transitorio
	# durante esa fase no debe interrumpir el regreso a producción normal.
	if not life_support_active and not is_blackout and not recovering:
		blackout_triggered.emit()
		if has_node("/root/BaseFSM"):
			var fsm: Node = get_node("/root/BaseFSM")
			if fsm.has_method("change_state"):
				fsm.change_state(BaseFSM.BaseState.FALLO_SISTEMATICO)

	# -------------------------------------------------------------------------
	# 4. INVERNADERO (Comida y Oxígeno)
	# -------------------------------------------------------------------------
	var greenhouse_water_needed: float = greenhouse_water_cost * delta_time
	var greenhouse_water_available: bool = _resources[RES_WATER] >= greenhouse_water_needed
	
	if greenhouse_powered and greenhouse_water_available:
		_modify_resource(RES_WATER, -greenhouse_water_needed)
		
		var food_gen: float = greenhouse_food_generation * production_multiplier * greenhouse_efficiency_bonus * delta_time
		var o2_gen: float = greenhouse_oxygen_generation * production_multiplier * greenhouse_efficiency_bonus * delta_time
		
		_modify_resource(RES_FOOD, food_gen)
		_modify_resource(RES_OXYGEN, o2_gen)

	# -------------------------------------------------------------------------
	# 5. SOPORTE VITAL Y CONSUMO DE TRIPULACIÓN
	# -------------------------------------------------------------------------
	var crew_o2_loss: float = crew_oxygen_consumption * delta_time
	var crew_h2o_loss: float = crew_water_consumption * delta_time
	var crew_food_loss: float = crew_food_consumption * delta_time
	
	if not life_support_active or is_blackout:
		var failure_decay_penalty: float = 3.0
		crew_o2_loss *= failure_decay_penalty
	elif is_emergency and EnergyEconomy.get_energy_ratio() < 0.15:
		crew_o2_loss *= 1.8
	else:
		crew_o2_loss /= life_support_efficiency_bonus
	
	var oxygen_leak_loss := 8.0 * delta_time if _oxygen_leak_active else 0.0
	_modify_resource(RES_OXYGEN, -crew_o2_loss - oxygen_leak_loss)
	_modify_resource(RES_WATER, -crew_h2o_loss)
	_modify_resource(RES_FOOD, -crew_food_loss)
	
	# -------------------------------------------------------------------------
	# 6. VERIFICACIÓN DE ESTADOS CRÍTICOS
	# -------------------------------------------------------------------------
	_check_critical_levels()

# ==============================================================================
# MANIPULACIÓN Y CONSULTA DE RECURSOS (MÉTODOS PÚBLICOS)
# ==============================================================================

## Agrega una cantidad positiva de un recurso.
func add_resource(type: StringName, amount: float) -> void:
	if type == RES_ENERGY:
		EnergyEconomy.add_energy(amount, "Recursos")
		return
	if amount <= 0.0 or not _resources.has(type):
		return
	_modify_resource(type, amount)


## Consume una cantidad de recurso si hay suficiente disponible. Retorna true si tuvo éxito.
func consume_resource(type: StringName, amount: float) -> bool:
	if type == RES_ENERGY:
		return amount > 0.0 and EnergyEconomy.try_spend_energy(amount, "Recursos")
	if amount <= 0.0 or not _resources.has(type):
		return false
	if _resources[type] < amount:
		return false
	
	_modify_resource(type, -amount)
	return true


func has_oxygen_leak() -> bool:
	return _oxygen_leak_active


func set_oxygen_leak_active(active: bool) -> void:
	if _oxygen_leak_active != active:
		_oxygen_leak_active = active
		oxygen_leak_changed.emit(active)


## Obtiene la cantidad actual de un recurso específico.
func get_resource(type: StringName) -> float:
	if type == RES_ENERGY:
		return EnergyEconomy.get_current_watts()
	return _resources.get(type, 0.0)


## Obtiene el valor máximo de un recurso.
func get_max_resource(type: StringName) -> float:
	match type:
		RES_ENERGY: return EnergyEconomy.get_max_watts()
		RES_WATER: return max_water
		RES_FOOD: return max_food
		RES_OXYGEN: return max_oxygen
		_: return 100.0


## Retorna el porcentaje (0.0 a 1.0) disponible de un recurso.
func get_resource_ratio(type: StringName) -> float:
	var max_val: float = get_max_resource(type)
	if max_val <= 0.0:
		return 0.0
	return clampf(get_resource(type) / max_val, 0.0, 1.0)


## Bonificadores de eficiencia temporales.
func set_life_support_bonus(multiplier: float) -> void:
	life_support_efficiency_bonus = maxf(0.1, multiplier)


func set_greenhouse_bonus(multiplier: float) -> void:
	greenhouse_efficiency_bonus = maxf(0.1, multiplier)

# ==============================================================================
# PRIVADOS Y SEÑALES
# ==============================================================================

func _set_resource(type: StringName, value: float) -> void:
	var max_val: float = get_max_resource(type)
	var clamped_value: float = clampf(value, 0.0, max_val)
	_resources[type] = clamped_value
	resource_updated.emit(type, clamped_value)


func _modify_resource(type: StringName, delta_amount: float) -> void:
	var new_value: float = _resources[type] + delta_amount
	_set_resource(type, new_value)


func _check_critical_levels() -> void:
	for res_type: StringName in _critical_state:
		var current_val := get_resource(res_type)
		var max_val: float = get_max_resource(res_type)
		var ratio: float = current_val / max_val if max_val > 0.0 else 0.0
		
		var is_critical: bool = ratio <= critical_threshold_ratio
		
		if is_critical and not _critical_state[res_type]:
			_critical_state[res_type] = true
			resource_critical.emit(res_type)
		elif not is_critical and _critical_state[res_type]:
			_critical_state[res_type] = false


func _emit_all_resources() -> void:
	for res_type: StringName in _resources.keys():
		resource_updated.emit(res_type, _resources[res_type])
