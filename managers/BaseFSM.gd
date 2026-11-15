# res://managers/BaseFSM.gd
extends Node

## BaseFSM.gd - Máquina de Estados Finito de la Base Espacial (Autoload: BaseFSM)
## Controla el estado global de la estación lunar/marciana e influye
## en el consumo de recursos, eventos climáticos y supervivencia de la tripulación.

# ==============================================================================
# ENUMS Y SEÑALES
# ==============================================================================

enum BaseState {
	NORMAL,               ## Consumo y generación estándar.
	ALERTA_CLIMA,         ## Llamarada solar detectada. Fluctuación solar, preparación de tripulación.
	EMERGENCIA_RADIACION, ## Escudos de radiación activados. Consumo eléctrico al 300%. Riesgo de fallo de O2.
	FALLO_SISTEMATICO,    ## Apagón general (Blackout). Caída acelerada de soporte vital.
	RECUPERACION          ## Transición post-emergencia. Máquinas al 50% hasta reparación.
}

## Emitida cada vez que el estado global de la base cambia.
signal base_state_changed(new_state: BaseState)

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (BALANCE DE DIFICULTAD)
# ==============================================================================

@export_group("Multiplicadores de Estado")
## Multiplicador de consumo de energía en estado de EMERGENCIA_RADIACION (+300% = 3.0x de consumo base).
@export_range(1.0, 10.0, 0.1) var radiation_energy_consumption_mult: float = 3.0

## Eficiencia de generación y sistemas en estado de RECUPERACION (50% por defecto).
@export_range(0.1, 1.0, 0.05) var recovery_efficiency_mult: float = 0.5

## Multiplicador de caída de soporte vital en FALLO_SISTEMATICO.
@export_range(1.0, 5.0, 0.1) var blackout_decay_mult: float = 2.5

## Variabilidad de generación solar durante ALERTA_CLIMA (ej. 0.35 = +/- 35% fluctuación).
@export_range(0.0, 1.0, 0.05) var solar_instability_factor: float = 0.35

@export_group("Duraciones Automáticas")
## Duración automática de la fase de recuperación antes de volver a NORMAL (0 para manual).
@export var recovery_duration_seconds: float = 20.0

# ==============================================================================
# VARIABLES DE ESTADO INTERNO
# ==============================================================================

var current_state: BaseState = BaseState.NORMAL
var previous_state: BaseState = BaseState.NORMAL

var _recovery_timer: float = 0.0

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	current_state = BaseState.NORMAL
	previous_state = BaseState.NORMAL


func _process(delta: float) -> void:
	if current_state == BaseState.RECUPERACION and recovery_duration_seconds > 0.0:
		_recovery_timer -= delta
		if _recovery_timer <= 0.0:
			change_state(BaseState.NORMAL)

# ==============================================================================
# CONTROL DE ESTADOS Y TRANSICIONES
# ==============================================================================

## Intenta cambiar el estado actual. Valida y emite la señal base_state_changed.
func change_state(new_state: BaseState) -> bool:
	if current_state == new_state:
		return false
	
	previous_state = current_state
	current_state = new_state
	
	match current_state:
		BaseState.RECUPERACION:
			_recovery_timer = recovery_duration_seconds
		_:
			_recovery_timer = 0.0
	
	# Desacoplado: notificar a todos los escuchas (ResourceManager, TaskManager, UI)
	base_state_changed.emit(current_state)
	return true


## Retorna el estado actual.
func get_current_state() -> BaseState:
	return current_state


## Comprueba si la base se encuentra en un estado específico.
func is_in_state(state: BaseState) -> bool:
	return current_state == state


## Retorna el nombre en texto legible del estado (útil para logs y depuración).
func get_state_name(state: BaseState = current_state) -> String:
	match state:
		BaseState.NORMAL:
			return "NORMAL"
		BaseState.ALERTA_CLIMA:
			return "ALERTA_CLIMA"
		BaseState.EMERGENCIA_RADIACION:
			return "EMERGENCIA_RADIACION"
		BaseState.FALLO_SISTEMATICO:
			return "FALLO_SISTEMATICO"
		BaseState.RECUPERACION:
			return "RECUPERACION"
		_:
			return "DESCONOCIDO"

# ==============================================================================
# MULTIPLICADORES MATEMÁTICOS PARA EL GESTOR DE RECURSOS
# ==============================================================================

## Multiplicador de consumo eléctrico según el estado actual.
func get_energy_consumption_multiplier() -> float:
	match current_state:
		BaseState.EMERGENCIA_RADIACION:
			return radiation_energy_consumption_mult
		BaseState.RECUPERACION:
			return 1.0
		BaseState.FALLO_SISTEMATICO:
			return 0.1 # Reducción drástica por colapso de red
		_:
			return 1.0


## Multiplicador de eficiencia de generación (energía e invernadero).
func get_production_efficiency_multiplier() -> float:
	match current_state:
		BaseState.ALERTA_CLIMA:
			var fluctuation: float = randf_range(-solar_instability_factor, solar_instability_factor)
			return max(0.1, 1.0 + fluctuation)
		BaseState.RECUPERACION:
			return recovery_efficiency_mult
		BaseState.FALLO_SISTEMATICO:
			return 0.0 # Red fuera de servicio
		_:
			return 1.0
