# res://managers/EnergyEconomy.gd
extends Node

## EnergyEconomy.gd - Economía Energética Basada en el SOL (Autoload: EnergyEconomy)
## En este simulador espacial, el SOL (Energía) es la ÚNICA moneda del juego.
## No existen monedas, créditos ni puntos ficticios: los Vatios (W) representan
## el poder adquisitivo y el soporte vital de toda la base lunar/marciana.

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
@export_range(50.0, 5000.0, 25.0) var initial_energy_watts: float = 500.0

@export_group("Arreglo de Paneles Solares (Generación de SOL)")
## Cantidad de paneles solares operativos en la base.
@export_range(1, 16, 1) var active_solar_panels: int = 4

## Potencia de salida por panel individual en Vatios por segundo (W/s).
@export_range(1.0, 100.0, 1.0) var watts_per_panel: float = 12.5

## Eficiencia o intensidad de la radiación solar incidente (0.0 = noche/sombra, 1.0 = mediodía solar).
@export_range(0.0, 2.0, 0.05) var solar_radiation_intensity: float = 1.0

# ==============================================================================
# ESTADO INTERNO
# ==============================================================================

var current_energy_watts: float = 0.0

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	reset_battery()


func reset_battery() -> void:
	current_energy_watts = clampf(initial_energy_watts, 0.0, max_energy_watts)
	energy_updated.emit(current_energy_watts, max_energy_watts)

# ==============================================================================
# GENERACIÓN DE ENERGÍA (PANELES SOLARES / SOL)
# ==============================================================================

## Genera energía a partir de los paneles solares instalados en la base durante un delta de tiempo.
## Retorna la cantidad neta de Vatios producidos.
func generate_solar_energy_cycle(delta_time: float) -> float:
	var total_generated: float = (active_solar_panels * watts_per_panel * solar_radiation_intensity) * delta_time
	add_energy(total_generated, "Paneles Solares")
	return total_generated


## Añade una cantidad fija de Vatios provenientes de una fuente identificable.
func add_energy(amount_watts: float, source: String = "SOL") -> void:
	if amount_watts <= 0.0:
		return
	
	current_energy_watts = minf(current_energy_watts + amount_watts, max_energy_watts)
	energy_generated.emit(amount_watts, source)
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
