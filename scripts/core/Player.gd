# res://scripts/core/Player.gd
class_name PlayerController
extends CharacterBody2D

## Player.gd - Controlador Top-Down 2D del Astronauta
## Recibe señales desacopladas de AstronautNeeds para ajustar su velocidad dinámicamente.
## Si las necesidades básicas están bajas, el movimiento se percibe lento y pesado.
## Gestiona el estado de refugio y esclusa ante alertas de radiación solar (EventManager).

# ==============================================================================
# SEÑALES
# ==============================================================================

## Emitida cuando el estado de refugio del astronauta cambia (dentro o fuera).
signal shelter_state_changed(is_sheltered: bool)

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Movimiento")
## Velocidad base del astronauta en píxeles por segundo cuando está 100% sano.
@export var base_speed: float = 180.0

@export_group("Estado de Refugio")
## Si es verdadero, el astronauta comienza la partida dentro de la base blindada.
@export var starts_sheltered: bool = true

# ==============================================================================
# REFERENCIAS Y ESTADO
# ==============================================================================

@export var needs_component: AstronautNeeds
@export var animated_sprite: AnimatedSprite2D

var speed_multiplier: float = 1.0
var is_sheltered: bool = true
var can_move: bool = true

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	# Buscar el componente como hijo si no fue asignado en el Inspector
	if not needs_component:
		needs_component = get_node_or_null("AstronautNeeds")
	if not animated_sprite:
		animated_sprite = get_node_or_null("AnimatedSprite2D")
	
	if needs_component:
		needs_component.speed_multiplier_changed.connect(_on_speed_multiplier_changed)
		speed_multiplier = needs_component.get_speed_multiplier()
		
	is_sheltered = starts_sheltered
	if has_node("/root/EventManager"):
		get_node("/root/EventManager").set_player_sheltered(is_sheltered)
		
	if animated_sprite and animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation("idle"):
		animated_sprite.play("idle")


func _physics_process(_delta: float) -> void:
	if not can_move:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation(Vector2.ZERO)
		return
		
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# La velocidad se escala con el multiplicador calculado por el estado biológico
	var current_speed: float = base_speed * speed_multiplier
	velocity = direction * current_speed
	
	move_and_slide()
	
	_update_animation(direction)


func _update_animation(direction: Vector2) -> void:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return
		
	if direction.length_squared() > 0.001:
		if animated_sprite.sprite_frames.has_animation("walk"):
			animated_sprite.play("walk")
		if direction.x < 0.0:
			animated_sprite.flip_h = true
		elif direction.x > 0.0:
			animated_sprite.flip_h = false
	else:
		if animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.play("idle")

# ==============================================================================
# GESTIÓN DE REFUGIO Y SALIDA (ESCLUSA / AIRLOCK)
# ==============================================================================

## Ingresa al refugio de la base. SIEMPRE permitido, incluso bajo suspensión de salida.
func enter_shelter() -> bool:
	if has_node("/root/EventManager"):
		get_node("/root/EventManager").intentar_entrar_refugio()
	is_sheltered = true
	shelter_state_changed.emit(true)
	return true


## Intenta salir al exterior (EVA). Bloqueado si la salida está suspendida por evento solar S3.
func exit_to_exterior() -> bool:
	if has_node("/root/EventManager"):
		var em = get_node("/root/EventManager")
		if not em.intentar_salir():
			return false
	is_sheltered = false
	shelter_state_changed.emit(false)
	return true


## Consulta si el astronauta está actualmente a salvo en el refugio.
func is_in_shelter() -> bool:
	return is_sheltered

# ==============================================================================
# RECEPCIÓN DE SEÑALES
# ==============================================================================

func _on_speed_multiplier_changed(new_multiplier: float) -> void:
	speed_multiplier = new_multiplier
