# res://managers/EnergyEconomy.gd
extends Node

## EnergyEconomy.gd - Economía Energética Basada en el SOL (Autoload: EnergyEconomy)
## Reserva compartida de soles. La API conserva los nombres históricos en vatios.

# ==============================================================================
# SEÑALES (COMUNICACIÓN PURA DESACOPLADA DE LA UI)
# ==============================================================================

## Emitida de forma estricta cuando los Vatios de la base llegan a cero,
## identificando con exactitud qué módulo o sistema provocó el colapso energético.
signal energy_depleted(system_name: String)

## Emitida cada vez que la reserva de Vatios cambia (para barras de carga o medidores visuales).
signal energy_updated(current_watts: float, max_watts: float)

## Emitida cuando se recolecta energía solar o de otra fuente limpia.
signal energy_generated(amount_watts: float, source: String)

## Emitida cada vez que un sistema consume Vatios exitosamente.
signal energy_spent(amount_watts: float, system_name: String)

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Batería Central de la Base")
## Capacidad máxima de almacenamiento de energía en Vatios (W).
@export_range(100.0, 5000.0, 50.0) var max_energy_watts: float = 1000.0

## Vatios disponibles al comenzar la misión o día lunar.
@export_range(0.0, 5000.0, 1.0) var initial_energy_watts: float = 80.0

@export_group("Arreglo de Paneles Solares (Generación de SOL)")
## Cantidad de paneles solares operativos en la base.
@export_range(1, 16, 1) var active_solar_panels: int = 4

## Potencia de salida por panel individual en Vatios por segundo (W/s).
@export_range(1.0, 100.0, 1.0) var watts_per_panel: float = 12.5

## Eficiencia o intensidad de la radiación solar incidente (0.0 = noche/sombra, 1.0 = mediodía solar).
@export_range(0.0, 2.0, 0.05) var solar_radiation_intensity: float = 1.0

const SOLAR_INTERVAL_SECONDS := 6
const NOMINAL_PANEL_OUTPUT := 50.0
const NOMINAL_SOLAR_RECHARGE := 5
const NOMINAL_OPERATING_POWER := 18.0

# ==============================================================================
# ESTADO INTERNO
# ==============================================================================

var current_energy_watts: float = 0.0
var _last_remaining := 0.0
var _solar_elapsed := 0.0

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	DayManager.day_started.connect(_on_day_started)
	DayManager.day_restarted.connect(_reset_solar_interval)
	DayManager.day_time_updated.connect(_on_day_time_updated)
	reset_battery()


func reset_battery() -> void:
	_reset_solar_interval()
	current_energy_watts = clampf(initial_energy_watts, 0.0, max_energy_watts)
	energy_updated.emit(current_energy_watts, max_energy_watts)

# ==============================================================================
# GENERACIÓN DE ENERGÍA (PANELES SOLARES / SOL)
# ==============================================================================

func _on_day_started(_day: int) -> void:
	_reset_solar_interval()


func _reset_solar_interval() -> void:
	_last_remaining = DayManager.get_time_remaining()
	_solar_elapsed = 0.0


func _on_day_time_updated(remaining: float, _total: float) -> void:
	if DayManager.is_running and remaining <= _last_remaining:
		_solar_elapsed += _last_remaining - remaining
	elif remaining > _last_remaining:
		_solar_elapsed = 0.0
	_last_remaining = remaining
	var intervals := floori(_solar_elapsed / SOLAR_INTERVAL_SECONDS)
	if intervals > 0:
		var elapsed := intervals * SOLAR_INTERVAL_SECONDS
		_solar_elapsed -= elapsed
		generate_solar_energy_cycle(elapsed)


func _panel_output_ratio() -> float:
	return active_solar_panels * watts_per_panel * solar_radiation_intensity / NOMINAL_PANEL_OUTPUT


func get_solar_recharge_sols() -> int:
	return roundi(NOMINAL_SOLAR_RECHARGE * _panel_output_ratio())


## Potencia que se usa directamente antes de recurrir a la batería compartida.
func get_operating_solar_power() -> float:
	return NOMINAL_OPERATING_POWER * _panel_output_ratio()


## Carga el excedente de los paneles y devuelve el aumento real de la batería.
func generate_solar_energy_cycle(delta_time: float) -> float:
	var before := current_energy_watts
	add_energy(get_solar_recharge_sols() * delta_time / SOLAR_INTERVAL_SECONDS, "Paneles solares")
	return current_energy_watts - before


## Añade una cantidad fija de Vatios provenientes de una fuente identificable.
func add_energy(amount_watts: float, source: String = "SOL") -> void:
	if amount_watts <= 0.0:
		return
	
	var added := minf(amount_watts, max_energy_watts - current_energy_watts)
	if added <= 0.0:
		return
	current_energy_watts += added
	energy_generated.emit(added, source)
	energy_updated.emit(current_energy_watts, max_energy_watts)


## Permite al jugador instalar o reparar paneles solares para aumentar la generación de SOL.
func add_solar_panels(count: int = 1) -> void:
	active_solar_panels = maxi(0, active_solar_panels + count)

# ==============================================================================
# CONSUMO ESTRICTO DE ENERGÍA (LA MONEDA DEL JUEGO)
# ==============================================================================

## Función estricta de gasto de energía.
## Descuenta la cantidad especificada en Vatios (W).
## Si los Vatios llegan a cero (o no alcanzan), se emite energy_depleted(system_name)
## indicando qué sistema consumió el último vatio o sobrepasó la capacidad de la batería.
func spend_energy(amount: float, system_name: String) -> bool:
	if amount <= 0.0:
		return true
	
	# Caso 1: La batería ya está completamente en cero
	if current_energy_watts <= 0.0:
		energy_depleted.emit(system_name)
		return false
	
	# Caso 2: El costo supera la energía disponible restante
	if amount > current_energy_watts:
		current_energy_watts = 0.0
		energy_spent.emit(current_energy_watts, system_name)
		energy_updated.emit(0.0, max_energy_watts)
		energy_depleted.emit(system_name)
		return false
	
	# Caso 3: Gasto solventado por la reserva
	current_energy_watts -= amount
	energy_spent.emit(amount, system_name)
	energy_updated.emit(current_energy_watts, max_energy_watts)
	
	# Si exactamente llegó a cero tras este consumo
	if is_zero_approx(current_energy_watts) or current_energy_watts <= 0.0:
		current_energy_watts = 0.0
		energy_depleted.emit(system_name)
	
	return true

# ==============================================================================
# MÉTODOS DE CONSULTA Y MATEMÁTICA PURA
# ==============================================================================

## Retorna los Vatios actualmente disponibles en las baterías de la base.
func get_current_watts() -> float:
	return current_energy_watts


## Retorna la capacidad total de almacenamiento.
func get_max_watts() -> float:
	return max_energy_watts


## Retorna el porcentaje de batería disponible (0.0 a 1.0).
func get_energy_ratio() -> float:
	if max_energy_watts <= 0.0:
		return 0.0
	return clampf(current_energy_watts / max_energy_watts, 0.0, 1.0)


## Comprueba si la base tiene suficientes Vatios para costear una operación sin gastarlos.
func can_afford_energy(amount: float) -> bool:
	return current_energy_watts >= amount


func try_spend_energy(amount: float, system_name: String) -> bool:
	return can_afford_energy(amount) and spend_energy(amount, system_name)


func format_sols(amount: int) -> String:
	return "%d %s" % [amount, "sol" if amount == 1 else "soles"]


func format_shortfall(cost: float) -> String:
	var missing := maxi(0, ceili(cost - current_energy_watts))
	var verb := "Te falta" if missing == 1 else "Te faltan"
	return "%s %s" % [verb, format_sols(missing)]
