# res://managers/DayManager.gd
extends Node

## DayManager.gd - Gestor del Ciclo de Supervivencia y Día Lunar (Autoload: DayManager)
## Administra las partidas adaptadas para el público infantil (7 a 12 años).
## Controla el temporizador de la misión espacial ('Día Lunar') y emite la señal
## day_survived() al completarse el ciclo con éxito.

# ==============================================================================
# SEÑALES (DESACOPLADAS DE LA UI)
# ==============================================================================

## Emitida cuando el tiempo del Día Lunar expira y la tripulación sobrevive.
signal day_survived()

## Emitida al comenzar un nuevo día lunar.
signal day_started(day_number: int)

## Emitida al reiniciar el día actual.
signal day_restarted()

## Emitida continuamente para que la interfaz gráfica (UI) actualice el reloj/temporizador.
signal day_time_updated(time_remaining: float, total_time: float)

## Emitida si la simulación se pausa o reanuda.
signal day_paused(is_paused: bool)

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Duración de la Misión")
## Duración del ciclo del Día Lunar en segundos.
## 180.0s = Ciclo rápido de 3 minutos exactos (ideal para niños de 7-12 años).
## 300.0s = Ciclo estándar de 5 minutos (modo extendido).
@export_range(60.0, 600.0, 10.0) var day_duration_seconds: float = 180.0

## Si es verdadero, el temporizador comienza automáticamente al cargar la escena.
@export var auto_start: bool = true

## Si es verdadero, al sobrevivir un día arranca automáticamente el siguiente.
@export var auto_advance_next_day: bool = false

# ==============================================================================
# ESTADO INTERNO
# ==============================================================================

var current_day: int = 1
var time_remaining: float = 0.0
var is_running: bool = false
var is_day_completed: bool = false
var continuing_mission := false

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	time_remaining = day_duration_seconds
	if auto_start:
		start_day(1)


func _process(delta: float) -> void:
	if not is_running or is_day_completed:
		return
	
	time_remaining -= delta
	day_time_updated.emit(maxf(0.0, time_remaining), day_duration_seconds)
	
	if time_remaining <= 0.0:
		finish_day()

# ==============================================================================
# CONTROL DEL DÍA LUNAR
# ==============================================================================

## Inicia el día lunar especificado (o el actual).
func start_day(day_number: int = current_day, continue_mission: bool = false) -> void:
	continuing_mission = continue_mission
	current_day = day_number
	time_remaining = day_duration_seconds
	is_running = true
	is_day_completed = false
	
	day_started.emit(current_day)
	day_time_updated.emit(time_remaining, day_duration_seconds)


## Pausa el transcurso del tiempo de la partida.
func pause_day() -> void:
	if is_running:
		is_running = false
		day_paused.emit(true)


## Reanuda el transcurso del tiempo.
func resume_day() -> void:
	if not is_running and not is_day_completed:
		is_running = true
		day_paused.emit(false)


## Reinicia el día actual desde el tiempo total.
func restart_day() -> void:
	continuing_mission = false
	time_remaining = day_duration_seconds
	is_running = true
	is_day_completed = false
	day_restarted.emit()
	day_time_updated.emit(time_remaining, day_duration_seconds)


## Configura dinámicamente la duración del día (ej: 180s para 3 min, 300s para 5 min).
func set_day_duration(seconds: float) -> void:
	day_duration_seconds = maxf(10.0, seconds)
	if not is_running:
		time_remaining = day_duration_seconds

# ==============================================================================
# FINALIZACIÓN DEL DÍA
# ==============================================================================

func finish_day() -> void:
	if is_day_completed:
		return
	time_remaining = maxf(0.0, time_remaining)
	is_running = false
	is_day_completed = true
	
	# Emitir señal principal requerida
	day_survived.emit()
	
	if auto_advance_next_day:
		start_day(current_day + 1)

# ==============================================================================
# GETTERS Y UTILIDADES (SIN INTERFAZ GRÁFICA)
# ==============================================================================

## Retorna el tiempo restante en segundos.
func get_time_remaining() -> float:
	return maxf(0.0, time_remaining)


## Retorna el porcentaje transcurrido del día (0.0 al inicio, 1.0 al finalizar).
func get_day_progress_ratio() -> float:
	if day_duration_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - (time_remaining / day_duration_seconds), 0.0, 1.0)


## Retorna el tiempo restante formateado en texto mm:ss (helper sin acoplamiento a nodos UI).
func get_formatted_time() -> String:
	var total_secs: int = int(ceil(get_time_remaining()))
	var minutes: int = total_secs / 60
	var seconds: int = total_secs % 60
	return "%02d:%02d" % [minutes, seconds]
