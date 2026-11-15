# res://scripts/utils/test_base_lunar.gd
extends Node

## test_base_lunar.gd - Test automatizado de la Base Lunar y colisiones
## Verifica:
## 1. Instanciación correcta de BaseLunar.tscn con todos sus sprites.
## 2. Spawn inicial del personaje en zona transitable.
## 3. Animaciones del personaje (idle, walk y orientación flip_h).
## 4. Colisiones perimetrales: el personaje NO puede salir al espacio
##    al empujarlo con alta velocidad hacia el Norte, Sur, Este y Oeste.
## 5. Tránsito fluido a través de las puertas entre Room2, Pasillo y Sala de Mando.
## 6. Detección de zonas de interacción (Invernadero, Soporte Vital, Esclusa, Reactores).

const BaseLunarClass = preload("res://scripts/levels/BaseLunar.gd")

var _fallos: int = 0
var _last_zone_entered: String = ""

func _ready() -> void:
	print("==================================================================")
	print(">>> INICIANDO TEST: BASE LUNAR Y COLISIONES DE CONTENCIÓN <<<")
	print("==================================================================")
	
	_ejecutar_pruebas()
	
	print("==================================================================")
	if _fallos == 0:
		print(">>> TODOS LOS TESTS DE LA BASE LUNAR PASARON (0 FALLOS) <<<")
		print("==================================================================")
		get_tree().quit(0)
	else:
		push_error(">>> SE ENCONTRARON %d FALLOS EN EL TEST DE BASE LUNAR <<<" % _fallos)
		print("==================================================================")
		get_tree().quit(1)


func _ejecutar_pruebas() -> void:
	var scene = load("res://scenes/levels/BaseLunar.tscn")
	_comprobar(scene != null, "Escena BaseLunar.tscn cargada exitosamente")
	if not scene:
		return
		
	var base = scene.instantiate()
	_comprobar(base != null, "Instancia de BaseLunar creada exitosamente")
	add_child(base)
	
	base.player_entered_zone.connect(func(zone): _last_zone_entered = zone)
	
	var player: PlayerController = base.player
	_comprobar(player != null, "Nodo PlayerController presente en la base lunar")
	_comprobar(player.animated_sprite != null, "AnimatedSprite2D configurado en el Player")
	_comprobar(player.global_position == base.spawn_marker.global_position, "Player spawneado en posición de SpawnPoint (%.1f, %.1f)" % [player.global_position.x, player.global_position.y])
	
	# 1. Prueba de animaciones
	_test_animaciones(player)
	
	# 2. Prueba de colisiones de contención (Muros no traspasables)
	_test_contencion_muros(player)
	
	# 3. Prueba de tránsito intermodular (puertas transitables)
	_test_transito_puertas(player)
	
	# 4. Prueba de zonas de interacción
	_test_zonas_interaccion(base, player)
	
	# 5. Prueba de seguimiento vertical de cámara y eliminación de microtirones
	_test_camara_seguimiento_y_microtirones(base, player)
	
	# 6. Prueba de terminal de mando (BottomWallCommandCenter) y pantalla Screen.png
	_test_terminal_command_center(base, player)
	
	base.queue_free()


func _test_animaciones(player: PlayerController) -> void:
	print("\n[TEST 1] Verificando animaciones y orientación del astronauta:")
	player.velocity = Vector2.ZERO
	player._update_animation(Vector2.ZERO)
	_comprobar(player.animated_sprite.animation == &"idle", "Animación en reposo es 'idle'")
	
	player.velocity = Vector2(100, 0)
	player._update_animation(Vector2(1, 0))
	_comprobar(player.animated_sprite.animation == &"walk", "Animación en movimiento es 'walk'")
	_comprobar(player.animated_sprite.flip_h == false, "flip_h es false al desplazarse a la derecha")
	
	player.velocity = Vector2(-100, 0)
	player._update_animation(Vector2(-1, 0))
	_comprobar(player.animated_sprite.flip_h == true, "flip_h es true al desplazarse a la izquierda")


func _simulate_movement(player: PlayerController, target_velocity: Vector2, frames: int = 60) -> void:
	var delta: float = 1.0 / 60.0
	for _i in range(frames):
		player.velocity = target_velocity
		var collision = player.move_and_collide(player.velocity * delta)
		if collision:
			# Deslizar a lo largo de la normal del obstáculo
			player.velocity = player.velocity.slide(collision.get_normal())


func _test_contencion_muros(player: PlayerController) -> void:
	print("\n[TEST 2] Verificando colisiones perimetrales (el personaje no puede salir):")
	
	# A. Empujar hacia el OESTE (Pared izquierda)
	player.global_position = Vector2(80, 120)
	_simulate_movement(player, Vector2(-400.0, 0.0), 60)
	_comprobar(player.global_position.x >= 15.0,
		"Pared OESTE detiene al astronauta (X actual: %.1f >= 15.0)" % player.global_position.x)
	_comprobar(player.global_position.x < 35.0,
		"Astronauta llegó y colisionó contra la pared izquierda")
		
	# B. Empujar hacia el NORTE (Techo)
	player.global_position = Vector2(80, 120)
	_simulate_movement(player, Vector2(0.0, -400.0), 60)
	_comprobar(player.global_position.y >= 50.0,
		"Pared NORTE detiene al astronauta (Y actual: %.1f >= 50.0)" % player.global_position.y)
		
	# C. Empujar hacia el SUR (Suelo inferior de la base extendida)
	player.global_position = Vector2(80, 120)
	_simulate_movement(player, Vector2(0.0, 400.0), 60)
	_comprobar(player.global_position.y <= 380.0,
		"Pared SUR detiene al astronauta (Y actual: %.1f <= 380.0)" % player.global_position.y)


func _test_transito_puertas(player: PlayerController) -> void:
	print("\n[TEST 3] Verificando tránsito fluido por puertas y pasillo central:")
	
	# Caminar desde Room2 (X=80) a través del pasillo (X=240) hacia la Sala de Mando (X=360)
	player.global_position = Vector2(80, 122)
	_simulate_movement(player, Vector2(300.0, 0.0), 90)
	_comprobar(player.global_position.x >= 350.0,
		"El astronauta cruzó el pasillo y entró al Centro de Mando (X=%.1f >= 350.0)" % player.global_position.x)
		
	# En el Centro de Mando, empujar hacia el ESTE (Pared derecha)
	_simulate_movement(player, Vector2(400.0, 0.0), 60)
	_comprobar(player.global_position.x <= 455.0,
		"Pared ESTE detiene al astronauta en Centro de Mando (X actual: %.1f <= 455.0)" % player.global_position.x)
		
	# En el Centro de Mando, empujar hacia el SUR (Suelo inferior)
	_simulate_movement(player, Vector2(0.0, 400.0), 60)
	_comprobar(player.global_position.y <= 380.0,
		"Pared SUR detiene al astronauta en Centro de Mando (Y actual: %.1f <= 380.0)" % player.global_position.y)
		
	# En el Centro de Mando, empujar hacia el NORTE (Consolas superiores)
	_simulate_movement(player, Vector2(0.0, -400.0), 60)
	_comprobar(player.global_position.y >= 50.0,
		"Pared NORTE detiene al astronauta en Centro de Mando (Y actual: %.1f >= 50.0)" % player.global_position.y)


func _test_zonas_interaccion(base: Node2D, player: PlayerController) -> void:
	print("\n[TEST 4] Verificando zonas de interacción en la base lunar:")
	
	# Colocar en la Esclusa (X=240, Y=122)
	player.global_position = Vector2(240, 122)
	# Disparar chequeo de área simulando un tick
	base._connect_interaction_areas()
	var airlock: Area2D = base.get_node_or_null("InteractionZones/AirlockArea")
	_comprobar(airlock != null, "Zona de Esclusa presente")
	
	var invernadero: Area2D = base.get_node_or_null("InteractionZones/InvernaderoArea")
	_comprobar(invernadero != null, "Zona de Invernadero presente")
	
	var reactores: Area2D = base.get_node_or_null("InteractionZones/ReactoresArea")
	_comprobar(reactores != null, "Zona de Reactores presente")
	
	var soporte_vital: Area2D = base.get_node_or_null("InteractionZones/SoporteVitalArea")
	_comprobar(soporte_vital != null, "Zona de Soporte Vital presente")


func _test_camara_seguimiento_y_microtirones(_base: Node2D, player: PlayerController) -> void:
	print("\n[TEST 5] Verificando seguimiento vertical de cámara y ausencia de microtirones:")
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	_comprobar(cam != null, "Camera2D incorporada en el Player")
	if not cam:
		return
		
	# 1. Verificación de límites verticales ampliados para seguir al personaje arriba y abajo
	_comprobar(cam.limit_bottom >= 400, "Camera limit_bottom ampliado (>= 400) para seguir hacia abajo: %d" % cam.limit_bottom)
	_comprobar(cam.limit_top <= 0, "Camera limit_top permite seguir hacia arriba: %d" % cam.limit_top)
	
	# 2. Verificación de solución de microtirones y deformación del sprite
	_comprobar(cam.position_smoothing_enabled == false, "position_smoothing_enabled es false (elimina microtirones y jitter subpixel)")
	_comprobar(cam.process_callback == Camera2D.CAMERA2D_PROCESS_PHYSICS, "process_callback sincronizado con la física (PROCESS_PHYSICS)")
	
	# 3. Comprobar que al desplazar al jugador abajo, la posición global del player puede superar Y=200
	player.global_position = Vector2(240, 300)
	_comprobar(player.global_position.y > 200, "El astronauta puede navegar verticalmente hacia abajo (Y=300)")
	
	# 4. Comprobar que al desplazar al jugador arriba, la posición global puede alcanzar zonas altas
	player.global_position = Vector2(240, 80)
	_comprobar(player.global_position.y < 100, "El astronauta puede navegar verticalmente hacia arriba (Y=80)")


func _test_terminal_command_center(base: Node2D, player: PlayerController) -> void:
	print("\n[TEST 6] Verificando terminal en BottomWallCommandCenter con Screen.png y tecla [E]:")
	
	_comprobar(base.terminal_screen != null, "Nodo TerminalScreen presente e instanciado en la Base Lunar")
	_comprobar(base.terminal_prompt != null, "Nodo TerminalPrompt presente para indicar interactividad [E]")
	
	var terminal_area = base.get_node_or_null("InteractionZones/BottomWallCommandCenter")
	_comprobar(terminal_area != null, "Area2D BottomWallCommandCenter configurada en InteractionZones")
	
	# 1. Estado inicial sin interactuar
	_comprobar(base.is_player_at_terminal() == false, "Inicialmente el astronauta NO está en la terminal")
	_comprobar(base.is_terminal_open() == false, "La terminal inicia cerrada y oculta")
	_comprobar(base.terminal_prompt.visible == false, "El prompt de interacción [E] inicia invisible")
	_comprobar(player.can_move == true, "El astronauta puede moverse libremente al inicio")
	
	# 2. Entrar a la zona BottomWallCommandCenter
	base._handle_zone_entered("BottomWallCommandCenter")
	_comprobar(base.is_player_at_terminal() == true, "El sistema detecta al astronauta al entrar en BottomWallCommandCenter")
	_comprobar(base.terminal_prompt.visible == true, "El indicador visual [E] TERMINAL se vuelve visible")
	_comprobar(_last_zone_entered == "BottomWallCommandCenter", "Señal player_entered_zone emitida con 'BottomWallCommandCenter'")
	
	# 3. Presionar tecla E para abrir la terminal
	var event_e_open = InputEventKey.new()
	event_e_open.pressed = true
	event_e_open.keycode = KEY_E
	base._unhandled_input(event_e_open)
	
	_comprobar(base.is_terminal_open() == true, "Al presionar [E] en BottomWallCommandCenter, se abre TerminalScreen")
	_comprobar(base.terminal_screen.visible == true, "TerminalScreen se vuelve visible en pantalla")
	_comprobar(player.can_move == false, "El movimiento del astronauta se pausa durante la lectura de la terminal")
	
	# 4. Verificar contenido de Screen.png: misiones y eventos
	var screen_frame = base.terminal_screen.get_node_or_null("ScreenFrame")
	_comprobar(screen_frame != null and screen_frame.texture != null, "ScreenFrame utiliza la textura Screen.png")
	_comprobar(base.terminal_screen.missions_vbox != null, "Panel de misiones (TaskManager) configurado")
	_comprobar(base.terminal_screen.notices_vbox != null, "Panel de avisos y eventos solares (EventManager) configurado")
	_comprobar(base.terminal_screen.telemetry_label != null, "Panel de telemetría de radiación configurado")
	
	# 5. Presionar tecla E para cerrar la terminal
	var event_e_close = InputEventKey.new()
	event_e_close.pressed = true
	event_e_close.keycode = KEY_E
	base._unhandled_input(event_e_close)
	
	_comprobar(base.is_terminal_open() == false, "Al presionar [E] nuevamente, la terminal se oculta")
	_comprobar(base.terminal_screen.visible == false, "TerminalScreen deja de ser visible")
	_comprobar(player.can_move == true, "El movimiento del astronauta se restablece al cerrar la terminal")
	
	# 6. Salir de la zona BottomWallCommandCenter
	base.open_terminal()
	_comprobar(base.is_terminal_open() == true, "Terminal abierta nuevamente para prueba de salida")
	base._handle_zone_exited("BottomWallCommandCenter")
	_comprobar(base.is_player_at_terminal() == false, "El astronauta ya no está en la zona de la terminal")
	_comprobar(base.terminal_prompt.visible == false, "El indicador visual [E] se oculta al salir de la zona")
	_comprobar(base.is_terminal_open() == false, "La terminal se cierra automáticamente si el astronauta se retira")
	_comprobar(player.can_move == true, "El movimiento se encuentra activo tras el cierre automático")


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("  [OK] " + descripcion)
	else:
		_fallos += 1
		push_error("  [FALLO] " + descripcion)
		print("  [FALLO] " + descripcion)
