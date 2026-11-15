# res://managers/EventManager.gd
extends Node

## EventManager.gd - Generador de Eventos Dinámicos y Clima Espacial (Autoload: EventManager)
## Administra eventos programados y aleatorios basados en pesos de probabilidad,
## y se integra con el Calendario Solar histórico (NASA DONKI / NOAA SWPC)
## desarrollado por el Programador 2.
## Controla el Tablero de Avisos, restricciones de salida y refugio del astronauta.

# ==============================================================================
# ENUMS
# ==============================================================================

enum ExitRestriction {
	PERMITIDA,    ## Salida libre / normal
	VIGILANCIA,   ## Salida permitida bajo aviso de vigilancia
	SUSPENDIDA,   ## Prohibido salir; si está fuera debe regresar al refugio inmediatamente
	RESTRINGIDA   ## Salida restringida con mayor riesgo de exposición
}

# ==============================================================================
# SEÑALES (DESACOPLADAS PARA UI Y OTROS MANAGERS)
# ==============================================================================

## Emitida cuando se detecta un evento entrante con anticipación (genérico o aleatorio).
signal event_warning_received(event_data: Dictionary)

## Emitida cuando el evento impacta o comienza activamente.
signal event_started(event_type: StringName)

## Emitida cuando el evento concluye o ha sido mitigado.
signal event_ended(event_type: StringName)

# --- Señales del Calendario Solar Histórico y Tablero de Avisos ---

## Emitida cuando se publica un nuevo aviso en el tablero de eventos solares.
signal solar_notice_posted(notice: Dictionary)

## Emitida cuando un aviso existente se actualiza (por ejemplo, al llegar al pico).
signal solar_notice_updated(notice: Dictionary)

## Emitida al alcanzar cualquier hito del calendario solar histórico.
signal solar_milestone_reached(milestone: Dictionary)

## Emitida cuando cambia la restricción de salida al exterior.
signal exit_restriction_changed(new_state: String, reason: String)

## Emitida con la orden activa para la tripulación (ej. «Regresa al refugio»).
signal shelter_order_issued(order_text: String, is_sheltered: bool, time_to_shelter: float)

## Emitida periódicamente con el flujo medido (pfu) y la dosis acumulada simulada (mSv).
signal radiation_exposure_updated(flux_pfu: float, dose_msv: float, dose_rate_msv_s: float)

## Emitida al reiniciar el calendario solar y limpiar avisos.
signal solar_calendar_restarted()

# ==============================================================================
# TIPOS DE EVENTOS CONSTANTES
# ==============================================================================

const EVENT_SOLAR_FLARE: StringName = &"solar_flare"
const EVENT_MICROMETEORITES: StringName = &"micrometeorites"
const EVENT_OXYGEN_LEAK: StringName = &"oxygen_leak"

# ==============================================================================
# PARÁMETROS DE GAME DESIGN (@export)
# ==============================================================================

@export_group("Calendario Solar Histórico (NASA)")
## Si está activo, el sistema reproduce los eventos solares de octubre de 2024.
@export var use_solar_calendar: bool = true

## Si está activo, proyecta proporcionalmente la duración del día a 600s.
## Si es falso, 1 segundo de misión = 1 segundo de proyección histórica.
@export var scale_to_day_duration: bool = false

## Duración en segundos tras el pico para declarar la alerta como finalizada (Simulación).
@export_range(10.0, 120.0, 5.0) var simulated_alert_duration_after_peak: float = 45.0

## Factor de conversión de flujo de protones (pfu) a tasa de dosis simulada (mSv/s) en EVA.
@export_range(0.001, 0.1, 0.001) var radiation_dose_factor: float = 0.005

@export_group("Generación Automática de Eventos Aleatorios")
## Determina si el sistema genera eventos periódicos automáticos si no se usa calendario.
@export var auto_generate_events: bool = false

## Tiempo mínimo en segundos entre eventos.
@export_range(20.0, 300.0, 5.0) var min_time_between_events: float = 60.0

## Tiempo máximo en segundos entre eventos.
@export_range(40.0, 600.0, 5.0) var max_time_between_events: float = 120.0

@export_group("Pesos de Probabilidad (Modo Aleatorio)")
@export_range(1, 100, 1) var weight_solar_flare: int = 60
@export_range(1, 100, 1) var weight_micrometeorites: int = 25
@export_range(1, 100, 1) var weight_oxygen_leak: int = 15

@export_group("Llamarada Solar (Modo Clásico)")
@export_range(5.0, 60.0, 1.0) var solar_flare_warning_duration: float = 15.0
@export_range(10.0, 120.0, 2.0) var solar_flare_active_duration: float = 30.0

# ==============================================================================
# ESTADO INTERNO
# ==============================================================================

var _event_timer: Timer
var _active_event: StringName = &""
var _warning_active: bool = false
var _event_phase_timer: float = 0.0

# Instancia del Calendario Solar
const CalendarioSolarClass := preload("res://scripts/api_nasa/calendario_solar.gd")
var _calendario_solar: Node

# Tablero de avisos y estado de refugio
var _avisos_solares: Dictionary = {} # id_episodio -> Dictionary
var _estado_salida: ExitRestriction = ExitRestriction.PERMITIDA
var _is_player_sheltered: bool = true
var _flujo_pfu_actual: float = 0.0
var _exposicion_simulada_msv: float = 0.0
var _tiempo_para_refugiarse: float = 0.0
var _peak_recovery_timer: float = 0.0
var _ultimo_tiempo_mision: float = 0.0
var _orden_activa: String = ""

# ==============================================================================
# CICLO DE VIDA
# ==============================================================================

func _ready() -> void:
	_event_timer = Timer.new()
	_event_timer.name = "EventSchedulerTimer"
	_event_timer.one_shot = true
	_event_timer.timeout.connect(_on_scheduler_timeout)
	add_child(_event_timer)
	
	_inicializar_calendario_solar()
	_conectar_con_day_manager.call_deferred()
	
	if auto_generate_events and not use_solar_calendar:
		_schedule_next_event()


func _process(delta: float) -> void:
	# 1. Simulación de dosis y temporizadores de refugio
	if _flujo_pfu_actual > 0.0 or _exposicion_simulada_msv > 0.0:
		var tasa_msv_s: float = 0.0
		if not _is_player_sheltered:
			# Fuera del refugio: acumula dosis según flujo observado
			tasa_msv_s = (_flujo_pfu_actual / 100.0) * radiation_dose_factor
			_exposicion_simulada_msv += tasa_msv_s * delta
		radiation_exposure_updated.emit(_flujo_pfu_actual, _exposicion_simulada_msv, tasa_msv_s)
	
	# 2. Descuento del tiempo para regresar al refugio (si está fuera bajo suspensión)
	if _tiempo_para_refugiarse > 0.0:
		if not _is_player_sheltered and _estado_salida == ExitRestriction.SUSPENDIDA:
			_tiempo_para_refugiarse = maxf(0.0, _tiempo_para_refugiarse - delta)
			shelter_order_issued.emit(_orden_activa, false, _tiempo_para_refugiarse)
		elif _is_player_sheltered:
			_tiempo_para_refugiarse = 0.0
	
	# 3. Temporizador simulado de conclusión de alerta post-pico
	if _peak_recovery_timer > 0.0:
		_peak_recovery_timer -= delta
		if _peak_recovery_timer <= 0.0:
			_finalizar_alerta_simulada()
			
	# 4. Modo de eventos genéricos / aleatorios
	if not use_solar_calendar:
		if _warning_active:
			_event_phase_timer -= delta
			if _event_phase_timer <= 0.0:
				_execute_event_impact(_active_event)
		elif _active_event != &"":
			_event_phase_timer -= delta
			if _event_phase_timer <= 0.0:
				end_active_event()

# ==============================================================================
# INTEGRACIÓN CON CALENDARIO SOLAR HISTÓRICO Y DAYMANAGER
# ==============================================================================

func _inicializar_calendario_solar() -> void:
	if not _calendario_solar:
		_calendario_solar = CalendarioSolarClass.new()
		_calendario_solar.name = "CalendarioSolar"
		add_child(_calendario_solar)
		_calendario_solar.hito_alcanzado.connect(_on_solar_milestone)


func _conectar_con_day_manager() -> void:
	if has_node("/root/DayManager"):
		var dm: Node = get_node("/root/DayManager")
		if dm.has_signal("day_time_updated") and not dm.day_time_updated.is_connected(_on_day_time_updated):
			dm.day_time_updated.connect(_on_day_time_updated)
		if dm.has_signal("day_started") and not dm.day_started.is_connected(_on_day_started):
			dm.day_started.connect(_on_day_started)
		if dm.has_signal("day_restarted") and not dm.day_restarted.is_connected(_on_day_restarted):
			dm.day_restarted.connect(_on_day_restarted)


var _solar_day_offset := 0.0


func _on_day_time_updated(time_remaining: float, total_time: float) -> void:
	if not use_solar_calendar or not _calendario_solar:
		return
	
	var elapsed: float = maxf(0.0, total_time - time_remaining)
	var segundos_mision: float = elapsed
	if scale_to_day_duration and total_time > 0.0:
		segundos_mision = (elapsed / total_time) * 600.0
	
	_ultimo_tiempo_mision = _solar_day_offset + segundos_mision
	_calendario_solar.avanzar_a(_ultimo_tiempo_mision)


func _on_day_started(_day_number: int) -> void:
	if DayManager.continuing_mission:
		_solar_day_offset = _ultimo_tiempo_mision
		return
	reiniciar_calendario()


func _on_day_restarted() -> void:
	reiniciar_calendario()


## Reinicia el calendario solar y limpia el estado del tablero de avisos.
func reiniciar_calendario() -> void:
	_solar_day_offset = 0.0
	if _calendario_solar and _calendario_solar.has_method("reiniciar"):
		_calendario_solar.reiniciar()
	
	_avisos_solares.clear()
	_estado_salida = ExitRestriction.PERMITIDA
	_flujo_pfu_actual = 0.0
	_exposicion_simulada_msv = 0.0
	_tiempo_para_refugiarse = 0.0
	_peak_recovery_timer = 0.0
	_ultimo_tiempo_mision = 0.0
	_orden_activa = ""
	
	exit_restriction_changed.emit("PERMITIDA", "Misión reiniciada")
	shelter_order_issued.emit("", _is_player_sheltered, 0.0)
	radiation_exposure_updated.emit(0.0, 0.0, 0.0)
	solar_calendar_restarted.emit()


## Permite avanzar manualmente el tiempo de calendario (ideal para pruebas y escenas de test).
func avanzar_calendario_a(segundos_mision: float) -> void:
	if _calendario_solar:
		_ultimo_tiempo_mision = segundos_mision
		_calendario_solar.avanzar_a(segundos_mision)

# ==============================================================================
# PROCESAMIENTO DE HITOS DEL CALENDARIO SOLAR HISTÓRICO
# ==============================================================================

func _on_solar_milestone(hito: Dictionary) -> void:
	solar_milestone_reached.emit(hito)
	
	var ep_id: String = hito.get("id_episodio", hito.get("id_fuente", ""))
	var tipo_hito: String = hito.get("tipo_hito", "")
	var tipo: String = hito.get("tipo", "")
	
	match ep_id:
		"2024-10-03T12:08:00-FLR-001":
			_procesar_episodio_octubre_3(hito, ep_id, tipo_hito)
		"2024-10-09T05:05:00-SEP-001":
			_procesar_episodio_octubre_9_10(hito, ep_id, tipo_hito)
		"NOAA-SWPC-2024-10-26T19:10Z":
			_procesar_episodio_octubre_26_28(hito, ep_id, tipo_hito)
		_:
			_procesar_episodio_generico(hito, ep_id, tipo_hito, tipo)


func _procesar_episodio_octubre_3(hito: Dictionary, ep_id: String, tipo_hito: String) -> void:
	# 3 de octubre: Fulguración solar X9.0. Solo vigilancia. No restringe salida.
	if not _avisos_solares.has(ep_id):
		var aviso := _crear_estructura_aviso(hito, ep_id)
		aviso["titulo"] = "VIGILANCIA: Fulguración Solar Clase " + str(hito.get("clase", "X9.0"))
		aviso["mensaje"] = "Aviso de vigilancia: Fulguración solar detectada. Operaciones normales permitidas."
		aviso["estado_salida"] = "VIGILANCIA"
		_avisos_solares[ep_id] = aviso
		
		_set_estado_salida(ExitRestriction.VIGILANCIA, "Fulguración solar X9.0 observada")
		if has_node("/root/BaseFSM"):
			get_node("/root/BaseFSM").change_state(BaseFSM.BaseState.ALERTA_CLIMA)
		
		solar_notice_posted.emit(aviso)
	else:
		# Actualizar el mismo aviso con datos de pico o boletines de alerta DONKI
		var aviso: Dictionary = _avisos_solares[ep_id]
		_actualizar_datos_fuente(aviso, hito)
		if tipo_hito == "pico":
			aviso["mensaje"] = "Pico de fulguración X9.0 registrado a las %s. Mantener vigilancia." % hito.get("fecha_utc", "")
		elif tipo_hito == "aviso_publicado":
			aviso["mensaje"] = "Aviso DONKI emitido (%s). Situación bajo monitoreo continuo." % hito.get("id_fuente", "")
		solar_notice_updated.emit(aviso)


func _procesar_episodio_octubre_9_10(hito: Dictionary, ep_id: String, tipo_hito: String) -> void:
	# 9–10 de octubre: Tormenta de radiación solar S3 (Pico 1,810 pfu)
	if not _avisos_solares.has(ep_id):
		var aviso := _crear_estructura_aviso(hito, ep_id)
		aviso["titulo"] = "DETECCIÓN: Tormenta de Protones Solares (>100 MeV)"
		aviso["mensaje"] = "Detección temprana DONKI de partículas solares energéticas. Monitoreando radiación."
		aviso["estado_salida"] = "VIGILANCIA"
		_avisos_solares[ep_id] = aviso
		solar_notice_posted.emit(aviso)
		return
	
	var aviso: Dictionary = _avisos_solares[ep_id]
	_actualizar_datos_fuente(aviso, hito)
	
	match tipo_hito:
		"inicio", "aviso_publicado":
			aviso["mensaje"] = "Inicio de evento SEP registrado por GOES (>10 MeV). Notificación DONKI en curso."
			solar_notice_updated.emit(aviso)
			
		"umbral":
			# Cruce a S3 (~2:45 / 165.054s)
			aviso["nivel"] = hito.get("nivel", "S3")
			aviso["umbral_pfu"] = hito.get("umbral_pfu", 1000)
			_flujo_pfu_actual = float(aviso["umbral_pfu"])
			aviso["flujo_pfu"] = _flujo_pfu_actual
			aviso["titulo"] = "ALERTA S3: Tormenta de Radiación Solar Fuerte (NOAA SWPC)"
			aviso["estado_salida"] = "SUSPENDIDA"
			
			_set_estado_salida(ExitRestriction.SUSPENDIDA, "Cruce a nivel S3 (>1000 pfu)")
			
			if not _is_player_sheltered:
				_orden_activa = "«Regresa al refugio»"
				if _tiempo_para_refugiarse <= 0.0:
					_tiempo_para_refugiarse = 45.0
				aviso["mensaje"] = "«Regresa al refugio»: ¡Cruce de umbral S3 (>1000 pfu)! Regresa de inmediato a la base."
				shelter_order_issued.emit(_orden_activa, false, _tiempo_para_refugiarse)
			else:
				_orden_activa = "«Salida suspendida»"
				aviso["mensaje"] = "«Salida suspendida»: Nivel S3 activo (>1000 pfu). Permanecer dentro del refugio blindado."
				shelter_order_issued.emit(_orden_activa, true, 0.0)
			
			if has_node("/root/BaseFSM"):
				get_node("/root/BaseFSM").change_state(BaseFSM.BaseState.EMERGENCIA_RADIACION)
			if has_node("/root/TaskManager"):
				get_node("/root/TaskManager").assign_emergency_solar_flare_task()
				
			solar_notice_updated.emit(aviso)
			
		"pico":
			# Pico máximo de radiación: 1,810 pfu (~3:06 / 186.492s)
			# DEBE actualizar el mismo aviso sin reiniciar el tiempo para regresar
			_flujo_pfu_actual = float(hito.get("flujo_pfu", 1810.0))
			aviso["flujo_pfu"] = _flujo_pfu_actual
			aviso["titulo"] = "PICO S3: Máximo de Radiación Solar de 1,810 pfu (NOAA SWPC)"
			
			if not _is_player_sheltered:
				_orden_activa = "«Regresa al refugio»"
				aviso["mensaje"] = "«Regresa al refugio»: Flujo pico registrado de 1,810 pfu. ¡Ponte a salvo de inmediato!"
				# NOTA CRÍTICA: NO reiniciar _tiempo_para_refugiarse; se conserva el conteo restante
				shelter_order_issued.emit(_orden_activa, false, _tiempo_para_refugiarse)
			else:
				_orden_activa = "«Salida suspendida»"
				aviso["mensaje"] = "«Salida suspendida»: Flujo pico registrado de 1,810 pfu. Tripulación protegida en el refugio."
				shelter_order_issued.emit(_orden_activa, true, 0.0)
				
			_peak_recovery_timer = simulated_alert_duration_after_peak
			solar_notice_updated.emit(aviso)


func _procesar_episodio_octubre_26_28(hito: Dictionary, ep_id: String, tipo_hito: String) -> void:
	# 26–28 de octubre: Segundo episodio SEP (Pico 364 pfu). Salida restringida.
	if not _avisos_solares.has(ep_id):
		var aviso := _crear_estructura_aviso(hito, ep_id)
		aviso["titulo"] = "ADVERTENCIA: Segundo Evento de Protones Solares (NOAA SWPC)"
		aviso["mensaje"] = "Aviso de salida restringida: Evento solar moderado en curso. Salir al exterior aumenta la exposición simulada."
		aviso["estado_salida"] = "RESTRINGIDA"
		_flujo_pfu_actual = 50.0
		aviso["flujo_pfu"] = _flujo_pfu_actual
		_avisos_solares[ep_id] = aviso
		
		_set_estado_salida(ExitRestriction.RESTRINGIDA, "Segundo evento SEP en desarrollo")
		_orden_activa = "Salida restringida"
		shelter_order_issued.emit(_orden_activa, _is_player_sheltered, 0.0)
		solar_notice_posted.emit(aviso)
	else:
		var aviso: Dictionary = _avisos_solares[ep_id]
		_actualizar_datos_fuente(aviso, hito)
		if tipo_hito == "pico":
			_flujo_pfu_actual = float(hito.get("flujo_pfu", 364.0))
			aviso["flujo_pfu"] = _flujo_pfu_actual
			aviso["titulo"] = "PICO SEGUNDO EVENTO: Flujo de 364 pfu (NOAA SWPC)"
			aviso["mensaje"] = "Salida restringida: Flujo máximo de 364 pfu alcanzado. Decida entre esperar o asumir mayor exposición simulada."
			_peak_recovery_timer = simulated_alert_duration_after_peak
		solar_notice_updated.emit(aviso)


func _procesar_episodio_generico(hito: Dictionary, ep_id: String, tipo_hito: String, tipo: String) -> void:
	if not _avisos_solares.has(ep_id):
		var aviso := _crear_estructura_aviso(hito, ep_id)
		aviso["titulo"] = "EVENTO SOLAR: %s (%s)" % [tipo, ep_id]
		aviso["mensaje"] = "Hito %s detectado. Fuente: %s" % [tipo_hito, hito.get("fuente", "")]
		_avisos_solares[ep_id] = aviso
		solar_notice_posted.emit(aviso)
	else:
		var aviso: Dictionary = _avisos_solares[ep_id]
		_actualizar_datos_fuente(aviso, hito)
		solar_notice_updated.emit(aviso)


func _crear_estructura_aviso(hito: Dictionary, ep_id: String) -> Dictionary:
	return {
		"id_episodio": ep_id,
		"id_fuente": hito.get("id_fuente", ep_id),
		"tipo": hito.get("tipo", ""),
		"tipo_hito": hito.get("tipo_hito", ""),
		"fecha_utc": hito.get("fecha_utc", ""),
		"fuente": hito.get("fuente", ""),
		"url_fuente": hito.get("url_fuente", ""),
		"procedencia": hito.get("procedencia", ""),
		"nivel": hito.get("nivel", ""),
		"flujo_pfu": float(hito.get("flujo_pfu", 0.0)),
		"umbral_pfu": int(hito.get("umbral_pfu", 0)),
		"clase": hito.get("clase", ""),
		"canales_energia": hito.get("canales_energia", []).duplicate(),
		"titulo": "",
		"mensaje": "",
		"estado_salida": "PERMITIDA",
		"tiempo_emision_mision": _ultimo_tiempo_mision,
		"activa": true
	}


func _actualizar_datos_fuente(aviso: Dictionary, hito: Dictionary) -> void:
	aviso["id_fuente"] = hito.get("id_fuente", aviso["id_fuente"])
	aviso["tipo_hito"] = hito.get("tipo_hito", aviso["tipo_hito"])
	aviso["fecha_utc"] = hito.get("fecha_utc", aviso["fecha_utc"])
	aviso["fuente"] = hito.get("fuente", aviso["fuente"])
	aviso["url_fuente"] = hito.get("url_fuente", aviso["url_fuente"])
	if hito.has("procedencia"):
		aviso["procedencia"] = hito["procedencia"]
	if hito.has("canales_energia"):
		aviso["canales_energia"] = hito["canales_energia"].duplicate()


func _finalizar_alerta_simulada() -> void:
	_flujo_pfu_actual = 0.0
	_set_estado_salida(ExitRestriction.PERMITIDA, "Alerta finalizada (Simulación)")
	_orden_activa = ""
	shelter_order_issued.emit("", _is_player_sheltered, 0.0)
	
	if has_node("/root/BaseFSM"):
		var fsm: Node = get_node("/root/BaseFSM")
		if fsm.has_method("change_state"):
			fsm.change_state(BaseFSM.BaseState.RECUPERACION)

# ==============================================================================
# GESTIÓN DE SALIDA, ESCLUSA Y REFUGIO DEL ASTRONAUTA
# ==============================================================================

func _set_estado_salida(nuevo_estado: ExitRestriction, motivo: String) -> void:
	_estado_salida = nuevo_estado
	exit_restriction_changed.emit(get_exit_restriction_name(), motivo)


## Consulta si el astronauta se encuentra actualmente dentro del refugio protegido.
func is_player_sheltered() -> bool:
	return _is_player_sheltered


## Define el estado de refugio del jugador.
func set_player_sheltered(sheltered: bool) -> void:
	_is_player_sheltered = sheltered
	if _is_player_sheltered and _estado_salida == ExitRestriction.SUSPENDIDA:
		_orden_activa = "«Salida suspendida»"
		_tiempo_para_refugiarse = 0.0
		shelter_order_issued.emit(_orden_activa, true, 0.0)
	elif not _is_player_sheltered and _estado_salida == ExitRestriction.SUSPENDIDA:
		_orden_activa = "«Regresa al refugio»"
		shelter_order_issued.emit(_orden_activa, false, _tiempo_para_refugiarse)


## Consulta si las reglas de la base permiten la salida al exterior en este momento.
func can_player_exit() -> bool:
	return _estado_salida != ExitRestriction.SUSPENDIDA


## Intento del astronauta de salir al exterior a través de la esclusa.
## Retorna false si la salida está suspendida por tormenta de radiación S3.
func intentar_salir() -> bool:
	if not can_player_exit():
		return false
	set_player_sheltered(false)
	return true


## Intento del astronauta de entrar al refugio.
## SIEMPRE se permite entrar para ponerse a salvo, incluso bajo suspensión de salida.
func intentar_entrar_refugio() -> bool:
	set_player_sheltered(true)
	return true


## Retorna el nombre legible del estado de salida.
func get_exit_restriction_name() -> String:
	match _estado_salida:
		ExitRestriction.PERMITIDA:
			return "PERMITIDA"
		ExitRestriction.VIGILANCIA:
			return "VIGILANCIA"
		ExitRestriction.SUSPENDIDA:
			return "SUSPENDIDA"
		ExitRestriction.RESTRINGIDA:
			return "RESTRINGIDA"
		_:
			return "DESCONOCIDO"


## Retorna una lista con todos los avisos solares publicados en el tablero.
func get_active_notices() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for k in _avisos_solares.keys():
		list.append(_avisos_solares[k].duplicate(true))
	return list


## Retorna un aviso solar por su ID de episodio histórico.
func get_notice_by_episode(id_episodio: String) -> Dictionary:
	if _avisos_solares.has(id_episodio):
		return _avisos_solares[id_episodio].duplicate(true)
	return {}


## Retorna el flujo medido actual en pfu (NOAA SWPC).
func get_current_flux_pfu() -> float:
	return _flujo_pfu_actual


## Retorna la dosis de radiación acumulada simulada del jugador en mSv.
func get_accumulated_simulated_dose_msv() -> float:
	return _exposicion_simulada_msv

# ==============================================================================
# PROGRAMACIÓN DE EVENTOS ALEATORIOS (COMPATIBILIDAD HACIA ATRÁS)
# ==============================================================================

func _schedule_next_event() -> void:
	var next_time: float = randf_range(min_time_between_events, max_time_between_events)
	_event_timer.start(next_time)


func _on_scheduler_timeout() -> void:
	if _active_event != &"" or _warning_active:
		_schedule_next_event()
		return
	
	var chosen_event: StringName = _choose_random_event()
	trigger_event(chosen_event)


func _choose_random_event() -> StringName:
	var total_weight: int = weight_solar_flare + weight_micrometeorites + weight_oxygen_leak
	var roll: int = randi_range(1, total_weight)
	
	if roll <= weight_solar_flare:
		return EVENT_SOLAR_FLARE
	elif roll <= weight_solar_flare + weight_micrometeorites:
		return EVENT_MICROMETEORITES
	else:
		return EVENT_OXYGEN_LEAK


## Detona un evento específico (usado en pruebas o modo procedural).
func trigger_event(event_type: StringName, custom_warning_time: float = -1.0) -> void:
	if _active_event != &"" or _warning_active:
		return
	
	_active_event = event_type
	var warning_time: float = custom_warning_time if custom_warning_time > 0.0 else solar_flare_warning_duration
	
	match event_type:
		EVENT_SOLAR_FLARE:
			_start_solar_flare_sequence(warning_time)
		EVENT_MICROMETEORITES:
			_start_generic_event(event_type, "Alerta: Lluvia de Micrometeoritos en trayectoria", 10.0, 20.0)
		EVENT_OXYGEN_LEAK:
			_start_generic_event(event_type, "Peligro: Despresurización y fuga en soporte vital", 8.0, 25.0)
		_:
			_start_generic_event(event_type, "Alerta espacial no clasificada", 10.0, 20.0)


func _start_solar_flare_sequence(warning_time: float) -> void:
	_warning_active = true
	_event_phase_timer = warning_time
	
	if has_node("/root/BaseFSM"):
		var fsm: Node = get_node("/root/BaseFSM")
		if fsm.has_method("change_state"):
			fsm.change_state(BaseFSM.BaseState.ALERTA_CLIMA)
	
	var warning_data: Dictionary = {
		"type": EVENT_SOLAR_FLARE,
		"title": "LLAMARADA SOLAR DETECTADA",
		"description": "Una eyección de masa coronal se aproxima. Se prevé interferencia y radiación crítica.",
		"warning_duration": warning_time,
		"severity": 3
	}
	
	event_warning_received.emit(warning_data)


func _start_generic_event(event_type: StringName, title: String, warning_time: float, active_time: float) -> void:
	_warning_active = true
	_event_phase_timer = warning_time
	
	if has_node("/root/BaseFSM"):
		var fsm: Node = get_node("/root/BaseFSM")
		if fsm.has_method("change_state"):
			fsm.change_state(BaseFSM.BaseState.ALERTA_CLIMA)
			
	var warning_data: Dictionary = {
		"type": event_type,
		"title": title,
		"warning_duration": warning_time,
		"active_duration": active_time,
		"severity": 2
	}
	
	event_warning_received.emit(warning_data)


func _execute_event_impact(event_type: StringName) -> void:
	_warning_active = false
	
	match event_type:
		EVENT_SOLAR_FLARE:
			_event_phase_timer = solar_flare_active_duration
			if has_node("/root/BaseFSM"):
				var fsm: Node = get_node("/root/BaseFSM")
				if fsm.has_method("change_state"):
					fsm.change_state(BaseFSM.BaseState.EMERGENCIA_RADIACION)
		_:
			_event_phase_timer = 20.0
	
	event_started.emit(event_type)


## Finaliza el evento activo y transiciona la base a fase de recuperación.
func end_active_event() -> void:
	if _active_event == &"":
		return
		
	var finished_event: StringName = _active_event
	_active_event = &""
	_warning_active = false
	_event_phase_timer = 0.0
	
	if has_node("/root/BaseFSM"):
		var fsm: Node = get_node("/root/BaseFSM")
		if fsm.has_method("change_state"):
			fsm.change_state(BaseFSM.BaseState.RECUPERACION)
	
	event_ended.emit(finished_event)
	
	if auto_generate_events and not use_solar_calendar:
		_schedule_next_event()


## Consulta el evento activo actual (o &"" si no hay ninguno).
func get_active_event() -> StringName:
	return _active_event


## Indica si actualmente hay una advertencia previa activa antes del impacto.
func is_warning_phase() -> bool:
	return _warning_active
