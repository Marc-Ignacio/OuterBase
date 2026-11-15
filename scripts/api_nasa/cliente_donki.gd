extends Node

signal consulta_completada(informe: Dictionary, eventos: Array[Dictionary])

const BASE_URL := "https://ccmc.gsfc.nasa.gov/DONKI-API/get/"
const RANGO := "?startDate=2024-10-01&endDate=2024-10-31"


func consultar_octubre() -> void:
	for endpoint in ["FLR", "SEP"]:
		var solicitud := HTTPRequest.new()
		solicitud.timeout = 15.0
		add_child(solicitud)
		solicitud.request_completed.connect(_al_completar.bind(endpoint, solicitud))
		var error := solicitud.request(BASE_URL + endpoint + RANGO, ["Accept: application/json"])
		if error != OK:
			solicitud.queue_free()
			_publicar(endpoint, "error_inicio", 0, 0, [], error_string(error))


func _al_completar(resultado: int, codigo: int, _cabeceras: PackedStringArray,
		cuerpo: PackedByteArray, endpoint: String, solicitud: HTTPRequest) -> void:
	solicitud.queue_free()
	if resultado != HTTPRequest.RESULT_SUCCESS:
		var estado := "error_conexion"
		if resultado == HTTPRequest.RESULT_TIMEOUT:
			estado = "tiempo_agotado"
		_publicar(endpoint, estado, codigo, 0, [], "Resultado HTTPRequest %d" % resultado)
		return
	if codigo < 200 or codigo >= 300:
		_publicar(endpoint, "error_http", codigo, 0, [])
		return

	var json := JSON.new()
	if json.parse(cuerpo.get_string_from_utf8()) != OK:
		_publicar(endpoint, "json_invalido", codigo, 0, [],
			"Línea %d: %s" % [json.get_error_line(), json.get_error_message()])
		return
	if not json.data is Array:
		_publicar(endpoint, "formato_inesperado", codigo, 0, [], "Se esperaba una lista")
		return

	var filas: Array = json.data
	var eventos: Array[Dictionary] = []
	for fila in filas:
		if fila is Dictionary:
			var evento := _normalizar(endpoint, fila)
			if not evento.is_empty():
				eventos.append(evento)

	var estado := "ok"
	if filas.is_empty():
		estado = "lista_vacia"
	elif eventos.size() != filas.size():
		estado = "registros_invalidos"
	_publicar(endpoint, estado, codigo, filas.size(), eventos)


func _publicar(endpoint: String, estado: String, codigo: int, recibidos: int,
		eventos: Array[Dictionary], detalle: String = "") -> void:
	consulta_completada.emit({
		"endpoint": endpoint,
		"estado": estado,
		"http": codigo if codigo > 0 else null,
		"recibidos": recibidos,
		"normalizados": eventos.size(),
		"detalle": detalle,
	}, eventos)


func _normalizar(endpoint: String, fila: Dictionary) -> Dictionary:
	var es_flr := endpoint == "FLR"
	var campo_id := "flrID" if es_flr else "sepID"
	var campo_fecha := "beginTime" if es_flr else "eventTime"
	if not _texto_valido(fila.get(campo_id)) or not _texto_valido(fila.get(campo_fecha)):
		return {}

	var evento := {
		"id_fuente": fila[campo_id],
		"tipo": endpoint,
		"fecha_utc": fila[campo_fecha],
		"fuente": "NASA CCMC DONKI",
		"url_fuente": fila.get("link"),
		"instrumentos": [],
		"avisos": [],
		"procedencia": {},
	}
	# Los canales de energía de SEP aparecen en el nombre del instrumento.
	var instrumentos: Variant = fila.get("instruments")
	if instrumentos is Array:
		for instrumento in instrumentos:
			if instrumento is Dictionary and _texto_valido(instrumento.get("displayName")):
				evento.instrumentos.append(instrumento.displayName)
		if not evento.instrumentos.is_empty():
			evento.procedencia.instrumentos = "instruments[].displayName"
			if not es_flr:
				_agregar_canales(evento)

	if es_flr:
		if _texto_valido(fila.get("classType")):
			evento.clase = fila.classType
			evento.procedencia.clase = "classType"
		if _texto_valido(fila.get("peakTime")):
			evento.pico = {"fecha_utc": fila.peakTime}
			evento.procedencia.pico = "peakTime"

	var avisos: Variant = fila.get("sentNotifications")
	if avisos is Array:
		for aviso in avisos:
			if aviso is Dictionary and _texto_valido(aviso.get("messageID")):
				evento.avisos.append({
					"id_fuente": aviso.messageID,
					"fecha_utc": aviso.get("messageIssueTime"),
					"url_fuente": aviso.get("messageURL"),
				})
		if not evento.avisos.is_empty():
			evento.procedencia.avisos = "sentNotifications[].messageIssueTime"
	return evento


func _agregar_canales(evento: Dictionary) -> void:
	var canales: Array[String] = []
	for instrumento: String in evento.instrumentos:
		var unidad := instrumento.find(" MeV")
		if unidad >= 0:
			var separador := instrumento.rfind(" ", unidad - 1)
			canales.append(instrumento.substr(separador + 1, unidad + 3 - separador))
	if not canales.is_empty():
		evento.canales_energia = canales
		evento.procedencia.canales_energia = "instruments[].displayName"


func _texto_valido(valor: Variant) -> bool:
	return valor is String and not valor.is_empty()
