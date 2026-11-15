# res://scripts/ui/TreadmillMinigame.gd
class_name TreadmillMinigame
extends Control

## TreadmillMinigame.gd - Minijuego de Cinta de Correr (NASA OSDR Protocol)
## Minijuego rápido de ritmo y cadencia motriz (Quick Time Event / Button Mash).
## Diseñado para niños de 7 a 12 años basado en los estudios de contramedidas de la NASA:
## En microgravedad, el astronauta debe correr con zancadas rítmicas para mantener
## la carga mecánica en los huesos y evitar la pérdida de masa ósea.
## Duración máxima: 8 a 10 segundos.

# ==============================================================================
# SEÑALES
# ==============================================================================

## Emitida cuando el jugador llena exitosamente la barra de ejercicio.
signal exercise_completed()

## Emitida si el tiempo de 10 segundos se agota sin alcanzar la meta de ejercicio.
signal exercise_failed()

## Emitida cuando el minijuego concluye y se cierra.
signal minigame_closed()

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Duración y Meta")
## Tiempo máximo total de la sesión de ejercicio en segundos (no más de 10s).
@export_range(5.0, 10.0, 0.5) var session_time_limit: float = 8.0

## Segundos acumulados requeridos dentro de la zona verde para ganar.
@export_range(3.0, 8.0, 0.5) var target_time_in_green_zone: float = 4.5

@export_group("Física de Cadencia y Esfuerzo (0 a 100)")
## Impulso que gana la barra por cada pulsación rítmica alternada correcta.
@export_range(5.0, 30.0, 1.0) var push_force: float = 14.0

## Velocidad a la que decae la barra hacia abajo por segundo si el jugador no corre.
@export_range(10.0, 60.0, 2.0) var decay_rate: float = 28.0

## Penalización por tropezar (presionar la misma tecla dos veces consecutivas).
@export_range(0.0, 20.0, 1.0) var misstep_penalty: float = 6.0

@export_group("Zona Verde Óptima (% de la barra)")
## Límite inferior de la zona verde de impacto osteogénico eficaz (40%).
@export_range(10.0, 50.0, 1.0) var green_zone_min: float = 40.0

## Límite superior de la zona verde antes de fatiga excesiva (75%).
@export_range(60.0, 95.0, 1.0) var green_zone_max: float = 75.0

@export_group("Configuración de Teclas")
## Acción izquierda (o teclas predeterminadas A / Flecha Izquierda).
@export var action_left: StringName = &"ui_left"
## Acción derecha (o teclas predeterminadas D / Flecha Derecha).
@export var action_right: StringName = &"ui_right"

# ==============================================================================
# REFERENCIAS A NODOS DE LA INTERFAZ
# ==============================================================================

@onready var timer_label: Label = get_node_or_null("MainPanel/MarginContainer/VBoxContainer/HeaderContainer/TimerLabel")
@onready var effort_slider: ProgressBar = get_node_or_null("MainPanel/MarginContainer/VBoxContainer/BarContainer/EffortBar")
@onready var green_zone_rect: ColorRect = get_node_or_null("MainPanel/MarginContainer/VBoxContainer/BarContainer/GreenZone")
@onready var workout_progress_bar: ProgressBar = get_node_or_null("MainPanel/MarginContainer/VBoxContainer/ProgressBarContainer/WorkoutProgressBar")
@onready var feedback_label: Label = get_node_or_null("MainPanel/MarginContainer/VBoxContainer/StatusFeedbackLabel")
@onready var key_left_btn: Button = get_node_or_null("MainPanel/MarginContainer/VBoxContainer/KeyPromptContainer/KeyLeftButton")
@onready var key_right_btn: Button = get_node_or_null("MainPanel/MarginContainer/VBoxContainer/KeyPromptContainer/KeyRightButton")

# ==============================================================================
# ESTADO INTERNO
# ==============================================================================

enum FootStep { NONE, LEFT, RIGHT }

var current_effort: float = 0.0          # Posición actual de la barra (0 a 100)
var workout_progress: float = 0.0        # Progreso acumulado hacia la victoria (0 a 100%)
var time_remaining: float = 8.0          # Cuenta regresiva
var next_expected_foot: FootStep = FootStep.NONE
var is_active: bool = false
var has_finished: bool = false

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	start_minigame()


func _process(delta: float) -> void:
	if not is_active or has_finished:
		return
	
	# 1. Cuenta regresiva del tiempo de sesión
	time_remaining -= delta
	if timer_label:
		timer_label.text = "%.1fs" % maxf(0.0, time_remaining)
		if time_remaining <= 2.5:
			timer_label.modulate = Color(1.0, 0.3, 0.3)
	
	# 2. Decaimiento natural de la barra de esfuerzo
	current_effort = maxf(0.0, current_effort - (decay_rate * delta))
	
	# 3. Comprobar si está en la Zona Verde
	var in_green_zone: bool = (current_effort >= green_zone_min and current_effort <= green_zone_max)
	
	if in_green_zone:
		# Acumular progreso osteogénico
		var fill_speed: float = (100.0 / target_time_in_green_zone) * delta
		workout_progress = minf(100.0, workout_progress + fill_speed)
		if feedback_label:
			feedback_label.text = "¡ZONA VERDE ÓPTIMA! ¡PROTEGIENDO HUESOS!"
			feedback_label.modulate = Color(0.2, 1.0, 0.4)
	elif current_effort > green_zone_max:
		if feedback_label:
			feedback_label.text = "¡Demasiado rápido! Reduce un poco el ritmo"
			feedback_label.modulate = Color(1.0, 0.8, 0.2)
	else:
		if feedback_label:
			feedback_label.text = "¡Pisa con ritmo! Alterna PIE IZQUIERDO y DERECHO"
			feedback_label.modulate = Color(0.9, 0.9, 0.9)
	
	# 4. Actualizar elementos visuales
	_update_ui_bars()
	
	# 5. Condición de Victoria
	if workout_progress >= 100.0:
		_finish_minigame(true)
		return
	
	# 6. Condición de Derrota por tiempo agotado
	if time_remaining <= 0.0:
		_finish_minigame(false)

# ==============================================================================
# ENTRADA DE USUARIO (BUTTON MASH / QTE ALTERNADO)
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if not is_active or has_finished:
		return
	
	if not (event is InputEventKey and event.is_pressed() and not event.is_echo()):
		return
	
	var key_event := event as InputEventKey
	
	# Detección flexible: Teclas A / D, Flechas Izquierda / Derecha, o Actions
	var pressed_left: bool = (key_event.keycode == KEY_A or key_event.keycode == KEY_LEFT or event.is_action_pressed(action_left))
	var pressed_right: bool = (key_event.keycode == KEY_D or key_event.keycode == KEY_RIGHT or event.is_action_pressed(action_right))
	
	if pressed_left:
		_handle_footstep(FootStep.LEFT)
	elif pressed_right:
		_handle_footstep(FootStep.RIGHT)


func _handle_footstep(foot: FootStep) -> void:
	# El primer paso puede ser cualquiera
	if next_expected_foot == FootStep.NONE or foot == next_expected_foot:
		# Zancada correcta y alternada
		current_effort = minf(100.0, current_effort + push_force)
		next_expected_foot = FootStep.RIGHT if foot == FootStep.LEFT else FootStep.LEFT
		_highlight_key(foot, true)
	else:
		# Tropiezo: presionó la misma pierna dos veces seguidas
		current_effort = maxf(0.0, current_effort - misstep_penalty)
		_highlight_key(foot, false)
		if feedback_label:
			feedback_label.text = "¡Tropiezo! Recuerda alternar un pie tras otro"
			feedback_label.modulate = Color(1.0, 0.4, 0.4)

# ==============================================================================
# CONTROL Y FINALIZACIÓN
# ==============================================================================

## Inicia o reinicia la sesión del minijuego.
func start_minigame() -> void:
	time_remaining = session_time_limit
	current_effort = 15.0
	workout_progress = 0.0
	next_expected_foot = FootStep.NONE
	has_finished = false
	is_active = true
	
	if timer_label:
		timer_label.modulate = Color(1.0, 1.0, 1.0)
	
	_position_green_zone()
	_update_ui_bars()


func _finish_minigame(victory: bool) -> void:
	has_finished = true
	is_active = false
	
	if victory:
		if feedback_label:
			feedback_label.text = "¡SESIÓN COMPLETADA CON ÉXITO! (+45% MASA ÓSEA)"
			feedback_label.modulate = Color(0.1, 1.0, 0.4)
		exercise_completed.emit()
	else:
		if feedback_label:
			feedback_label.text = "Tiempo agotado. La atrofia no se detuvo."
			feedback_label.modulate = Color(1.0, 0.3, 0.3)
		exercise_failed.emit()
	
	# Auto-cierre con retardo tras feedback
	var timer := get_tree().create_timer(1.2)
	timer.timeout.connect(func():
		minigame_closed.emit()
		queue_free()
	)

# ==============================================================================
# HELPERS VISUALES (ACTUALIZACIÓN DE BARRAS)
# ==============================================================================

func _position_green_zone() -> void:
	if not green_zone_rect:
		return
	# Ubicar visualmente la zona verde mediante anclas proporcionales verticales
	green_zone_rect.anchor_top = 1.0 - (green_zone_max / 100.0)
	green_zone_rect.anchor_bottom = 1.0 - (green_zone_min / 100.0)
	green_zone_rect.offset_top = 0.0
	green_zone_rect.offset_bottom = 0.0


func _update_ui_bars() -> void:
	if effort_slider:
		effort_slider.value = current_effort
	if workout_progress_bar:
		workout_progress_bar.value = workout_progress


func _highlight_key(foot: FootStep, is_correct: bool) -> void:
	var target_btn: Button = key_left_btn if foot == FootStep.LEFT else key_right_btn
	var other_btn: Button = key_right_btn if foot == FootStep.LEFT else key_left_btn
	
	if target_btn:
		target_btn.modulate = Color(0.2, 1.0, 0.4) if is_correct else Color(1.0, 0.3, 0.3)
	if other_btn:
		other_btn.modulate = Color(1.0, 1.0, 1.0)
