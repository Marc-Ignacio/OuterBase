# res://scripts/utils/test_mision_solar.gd
extends Node

## test_mision_solar.gd - Suite de verificación de integración del Calendario Solar
## Comprueba:
## 1. Conexión del calendario histórico al reloj de la misión real (DayManager).
## 2. Cruce de 2:44 -> 2:45 con jugador fuera: orden «Regresa al refugio», bloqueo de salida y entrada al refugio.
## 3. Cruce a 3:06: actualización del mismo aviso con pico de 1,810 pfu sin reiniciar tiempo de retorno.
## 4. Repetición con jugador dentro: orden «Salida suspendida» e intento de salida bloqueado.
## 5. Segundo episodio en 8:19 - 8:46: aviso de salida restringida y pico de 364 pfu.
## 6. Diferenciación entre flujo observado en pfu y exposición simulada en mSv.
## 7. Reinicio de partida y reproducción íntegra de la secuencia.
## 8. Verificación de juego 100% sin conexión (offline, JSON local).

var _fallos: int = 0
var _notices_received: Array[Dictionary] = []
var _last_order: String = ""
var _last_order_sheltered: bool = true

func _ready() -> void:
	print("==================================================================")
	print(">>> INICIANDO TEST DE INTEGRACIÓN: MISIÓN SOLAR OUTERBASE <<<")
	print("==================================================================")
	
	# Asegurar escala de misión a 600 segundos (10 minutos)
	DayManager.set_day_duration(600.0)
	DayManager.start_day()
	EventManager.use_solar_calendar = true
	
	# Conectar escuchas para pruebas
	EventManager.solar_notice_posted.connect(_on_notice_posted)
	EventManager.solar_notice_updated.connect(_on_notice_updated)
	EventManager.shelter_order_issued.connect(_on_shelter_order)
	
	# Ejecutar batería de pruebas
	_ejecutar_pruebas()
	
	print("==================================================================")
	if _fallos == 0:
		print(">>> TODOS LOS TESTS DE LA MISIÓN SOLAR PASARON (0 FALLOS) <<<")
		print("==================================================================")
		get_tree().quit(0)
	else:
		push_error(">>> SE ENCONTRARON %d FALLOS EN EL TEST DE MISIÓN SOLAR <<<" % _fallos)
		print("==================================================================")
		get_tree().quit(1)


func _ejecutar_pruebas() -> void:
	_test_1_reloj_y_offline()
	_test_2_episodio_1_vigilancia_49s()
	_test_3_episodio_2_jugador_fuera_245_y_pico_306()
	_test_4_episodio_2_jugador_dentro_245_y_bloqueo()
	_test_5_episodio_3_salida_restringida_819_846()
	_test_6_diferenciacion_pfu_vs_msv()
	_test_7_reinicio_partida()
	_test_8_tablero_ui()


func _test_1_reloj_y_offline() -> void:
	print("\n[TEST 1] Verificando reloj de misión (DayManager) y modo offline:")
	_comprobar(DayManager.day_duration_seconds == 600.0, "DayManager configurado a 600.0s (10 min)")
	_comprobar(EventManager.use_solar_calendar == true, "EventManager con use_solar_calendar activo")
	
	# Verificar que el JSON local existe y tiene los registros históricos
	var json_eventos = LineaTiempoSolar.leer_seleccion_local()
	_comprobar(json_eventos.size() == 4, "Modo offline: se cargaron los 4 registros históricos (3 episodios) desde res://data/eventos_solares_octubre_2024.json")


func _test_2_episodio_1_vigilancia_49s() -> void:
	print("\n[TEST 2] Verificando Episodio 1 (3 de octubre, X9.0 a ~0:49):")
	EventManager.reiniciar_calendario()
	
	# Avanzar hasta 49.0s (abarca los 4 hitos entre 48.495 y 48.816s)
	EventManager.avanzar_calendario_a(49.0)
	
	var aviso = EventManager.get_notice_by_episode("2024-10-03T12:08:00-FLR-001")
	_comprobar(not aviso.is_empty(), "Aviso de episodio 3 de octubre publicado")
	_comprobar(aviso.get("estado_salida") == "VIGILANCIA", "Estado de salida es VIGILANCIA")
	_comprobar(EventManager.get_exit_restriction_name() == "VIGILANCIA", "Restricción global es VIGILANCIA")
	_comprobar(EventManager.can_player_exit() == true, "El astronauta PUEDE continuar tareas y salir")
	_comprobar(BaseFSM.current_state == BaseFSM.BaseState.ALERTA_CLIMA, "BaseFSM transicionó a ALERTA_CLIMA")


func _test_3_episodio_2_jugador_fuera_245_y_pico_306() -> void:
	print("\n[TEST 3] Verificando Episodio 2 con astronauta FUERA (2:44 -> 2:45 -> 3:06):")
	EventManager.reiniciar_calendario()
	
	# 1. Astronauta sale al exterior a 2:44 (164.0s)
	EventManager.avanzar_calendario_a(164.0)
	EventManager.set_player_sheltered(false)
	_comprobar(EventManager.is_player_sheltered() == false, "Astronauta se encuentra fuera en el exterior (EVA) a 2:44")
	
	# 2. Cruza a 2:45 (165.1s, hito S3 en 165.054s)
	EventManager.avanzar_calendario_a(165.1)
	
	var aviso = EventManager.get_notice_by_episode("2024-10-09T05:05:00-SEP-001")
	_comprobar(not aviso.is_empty(), "Aviso del episodio 9-10 de octubre registrado")
	_comprobar(aviso.get("nivel") == "S3", "Hito umbral clasificado como S3")
	_comprobar(EventManager.get_exit_restriction_name() == "SUSPENDIDA", "Estado de salida SUSPENDIDA al cruzar S3")
	_comprobar("Regresa al refugio" in _last_order, "Orden activa emitida: «Regresa al refugio» para jugador fuera")
	_comprobar(EventManager.can_player_exit() == false, "can_player_exit() retorna false durante suspensión S3")
	_comprobar(EventManager.intentar_salir() == false, "intentar_salir() denegado durante suspensión S3")
	
	# Simular un tiempo para regresar antes del pico
	EventManager._tiempo_para_refugiarse = 30.0
	var tiempo_previo_retorno = EventManager._tiempo_para_refugiarse
	
	# 3. El astronauta entra al refugio
	var entro_ok = EventManager.intentar_entrar_refugio()
	_comprobar(entro_ok == true, "intentar_entrar_refugio() PERMITIDO para ponerse a salvo")
	_comprobar(EventManager.is_player_sheltered() == true, "Astronauta ahora está a salvo dentro del refugio")
	
	# Volver a poner fuera temporalmente para probar que el pico a 3:06 no reinicia tiempo si estuviera fuera
	EventManager._is_player_sheltered = false
	EventManager._tiempo_para_refugiarse = 25.0
	tiempo_previo_retorno = 25.0
	
	# 4. Cruza a 3:06 (187.0s, pico en 186.492s de 1,810 pfu)
	EventManager.avanzar_calendario_a(187.0)
	
	var aviso_pico = EventManager.get_notice_by_episode("2024-10-09T05:05:00-SEP-001")
	_comprobar(aviso_pico.get("tipo_hito") == "pico", "Mismo aviso actualizado a tipo_hito: pico")
	_comprobar(aviso_pico.get("flujo_pfu") == 1810.0, "Flujo pico actualizado a 1,810 pfu")
	_comprobar(aviso_pico.get("fuente") == "NOAA SWPC", "Fuente conservada: NOAA SWPC")
	_comprobar(aviso_pico.get("id_fuente") == "NOAA-SWPC-2024-10-09T05:05Z", "ID fuente conservado")
	_comprobar(aviso_pico.get("fecha_utc") == "2024-10-10T15:15Z", "Fecha UTC conservada")
	_comprobar(not aviso_pico.get("url_fuente", "").is_empty(), "URL fuente conservada")
	_comprobar(EventManager._tiempo_para_refugiarse <= tiempo_previo_retorno,
		"El pico NO reinició el tiempo para regresar (conservó cuenta regresiva)")


func _test_4_episodio_2_jugador_dentro_245_y_bloqueo() -> void:
	print("\n[TEST 4] Verificando Episodio 2 con astronauta DENTRO (2:44 -> 2:45 -> 3:06):")
	EventManager.reiniciar_calendario()
	
	# Astronauta dentro del refugio
	EventManager.set_player_sheltered(true)
	EventManager.avanzar_calendario_a(164.0)
	
	# Cruza 2:45
	EventManager.avanzar_calendario_a(165.1)
	_comprobar("Salida suspendida" in _last_order, "Orden activa emitida: «Salida suspendida» para jugador dentro")
	_comprobar(EventManager.intentar_salir() == false, "Salida bloqueada activamente al intentar salir")
	_comprobar(EventManager.is_player_sheltered() == true, "Astronauta permanece protegido dentro")
	
	# Cruza 3:06
	EventManager.avanzar_calendario_a(187.0)
	var aviso = EventManager.get_notice_by_episode("2024-10-09T05:05:00-SEP-001")
	_comprobar(aviso.get("flujo_pfu") == 1810.0, "Pico de 1,810 pfu actualizado correctamente con jugador dentro")


func _test_5_episodio_3_salida_restringida_819_846() -> void:
	print("\n[TEST 5] Verificando Episodio 3 (26–28 de octubre, 8:19 - 8:46):")
	EventManager.reiniciar_calendario()
	
	# Avanzar hasta 8:19 (500.0s, inicio en 499.328s)
	EventManager.avanzar_calendario_a(500.0)
	var aviso = EventManager.get_notice_by_episode("NOAA-SWPC-2024-10-26T19:10Z")
	_comprobar(not aviso.is_empty(), "Aviso del segundo episodio SEP publicado")
	_comprobar(EventManager.get_exit_restriction_name() == "RESTRINGIDA", "Estado de salida: RESTRINGIDA")
	_comprobar(EventManager.can_player_exit() == true, "Salida permitida bajo riesgo advertido")
	
	# Avanzar hasta 8:46 (526.0s, pico en 525.672s)
	EventManager.avanzar_calendario_a(526.0)
	var aviso_pico = EventManager.get_notice_by_episode("NOAA-SWPC-2024-10-26T19:10Z")
	_comprobar(aviso_pico.get("flujo_pfu") == 364.0, "Mismo aviso actualizado con pico de 364 pfu")
	_comprobar(aviso_pico.get("tipo_hito") == "pico", "Hito pico alcanzado en segundo episodio")


func _test_6_diferenciacion_pfu_vs_msv() -> void:
	print("\n[TEST 6] Verificando diferenciación entre flujo medido (pfu) y dosis simulada (mSv):")
	EventManager.reiniciar_calendario()
	
	# En el pico S3 (1,810 pfu)
	EventManager.avanzar_calendario_a(187.0)
	_comprobar(EventManager.get_current_flux_pfu() == 1810.0, "Flujo ambiental NOAA medido en pfu = 1,810 pfu")
	
	# 1. Dentro del refugio: la dosis NO sube
	EventManager.set_player_sheltered(true)
	EventManager._exposicion_simulada_msv = 0.0
	EventManager._process(2.0)
	_comprobar(EventManager.get_accumulated_simulated_dose_msv() == 0.0,
		"Dentro del refugio protegido la dosis simulada se mantiene en 0.00 mSv")
	
	# 2. Fuera del refugio: la dosis acumulada simulada aumenta proporcionalmente al flujo
	EventManager.set_player_sheltered(false)
	EventManager._process(2.0)
	_comprobar(EventManager.get_accumulated_simulated_dose_msv() > 0.0,
		"Fuera del refugio la dosis acumulada aumenta (%.3f mSv)" % EventManager.get_accumulated_simulated_dose_msv())


func _test_7_reinicio_partida() -> void:
	print("\n[TEST 7] Verificando reinicio de partida y secuencia completa:")
	EventManager.reiniciar_calendario()
	_comprobar(EventManager.get_active_notices().is_empty(), "Avisos limpios al reiniciar")
	_comprobar(EventManager.get_exit_restriction_name() == "PERMITIDA", "Restricción vuelve a PERMITIDA al reiniciar")
	
	# Volver a avanzar al final de la misión (600s)
	_notices_received.clear()
	EventManager.avanzar_calendario_a(600.0)
	var avisos = EventManager.get_active_notices()
	_comprobar(avisos.size() == 3, "Los 3 episodios se reproducen en orden al avanzar nuevamente")


func _test_8_tablero_ui() -> void:
	print("\n[TEST 8] Verificando instanciación y enlace del Tablero de Avisos (UI):")
	var tablero_scene = load("res://scenes/ui/TableroAvisosSolares.tscn")
	_comprobar(tablero_scene != null, "Escena TableroAvisosSolares.tscn cargada exitosamente")
	var tablero = tablero_scene.instantiate()
	_comprobar(tablero != null, "Instancia de TableroAvisosSolares creada")
	add_child(tablero)
	
	# Verificar que el tablero refleja el estado actual
	_comprobar(tablero.status_badge_label.text.contains("SALIDA"), "Badge de estado muestra texto de salida")
	_comprobar(tablero.flux_value_label != null, "Medidor de flujo pfu enlazado")
	_comprobar(tablero.dose_value_label != null, "Medidor de dosis mSv enlazado")
	
	# Probar botones de la interfaz
	tablero._on_enter_shelter_pressed()
	_comprobar(EventManager.is_player_sheltered() == true, "Botón 'Entrar al Refugio' funciona")
	tablero.queue_free()


# ==============================================================================
# HELPERS DE CAPTURA Y VERIFICACIÓN
# ==============================================================================

func _on_notice_posted(notice: Dictionary) -> void:
	_notices_received.append(notice)


func _on_notice_updated(_notice: Dictionary) -> void:
	pass


func _on_shelter_order(order_text: String, is_sheltered: bool, _time_left: float) -> void:
	_last_order = order_text
	_last_order_sheltered = is_sheltered


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("  [OK] " + descripcion)
	else:
		_fallos += 1
		push_error("  [FALLO] " + descripcion)
		print("  [FALLO] " + descripcion)


const LineaTiempoSolar = preload("res://scripts/api_nasa/linea_tiempo_solar.gd")
