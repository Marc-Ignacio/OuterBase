extends Node

const ARCHIVO := "res://data/eventos_solares_octubre_2024.json"
const INICIO := "2024-10-01T00:00:00Z"
const FIN := "2024-11-01T00:00:00Z"
const DURACION_PARTIDA := 600.0
const X9 := "2024-10-03T12:08:00-FLR-001"
const AVISO_X9 := "20241003-AL-002"
const SEP_GOES := "2024-10-09T05:05:00-SEP-001"

var _respuestas_http := 0
var _eventos_http: Array[Dictionary] = []


func _ready() -> void:
	_probar_archivo()
	print("\n=== HTTP NASA CCMC DONKI ===")
	$ClienteDonki.consulta_completada.connect(_al_recibir_endpoint)
	$ClienteDonki.consultar_octubre()


func _probar_archivo() -> void:
	print("=== ARCHIVO LOCAL ===")
	var archivo := FileAccess.open(ARCHIVO, FileAccess.READ)
	if archivo == null:
		push_error("ARCHIVO LOCAL: %s" % error_string(FileAccess.get_open_error()))
		return
	var json := JSON.new()
	if json.parse(archivo.get_as_text()) != OK or not json.data is Array:
		push_error("ARCHIVO LOCAL: se esperaba una lista JSON válida")
		return
	var eventos: Array[Dictionary] = []
	for fila in json.data:
		if fila is Dictionary:
			eventos.append(fila)
	print("ARCHIVO LOCAL: %d registros" % eventos.size())
	_imprimir_muestra(eventos, 3)
	_imprimir_linea_de_tiempo("ARCHIVO LOCAL", eventos)


func _al_recibir_endpoint(informe: Dictionary, eventos: Array[Dictionary]) -> void:
	print("HTTP NASA CCMC DONKI ", JSON.stringify(informe))
	_imprimir_muestra(eventos, 2)
	if informe.estado in ["ok", "lista_vacia", "registros_invalidos"]:
		_verificar_candidatos(informe.endpoint, eventos)
	else:
		print("HTTP %s: verificación del candidato pendiente (%s)" %
			[informe.endpoint, informe.estado])
	_eventos_http.append_array(eventos)
	_respuestas_http += 1
	if _respuestas_http == 2:
		_imprimir_linea_de_tiempo("HTTP NASA CCMC DONKI", _eventos_http)
		if "--salir-al-terminar" in OS.get_cmdline_user_args():
			get_tree().quit()


func _verificar_candidatos(endpoint: String, eventos: Array[Dictionary]) -> void:
	var candidato := X9 if endpoint == "FLR" else SEP_GOES
	for evento in eventos:
		if evento.id_fuente == candidato:
			print("HTTP %s: %s presente" % [endpoint, candidato])
			print(JSON.stringify(evento))
			if endpoint == "FLR":
				var aviso_presente := false
				for aviso in evento.avisos:
					if aviso.id_fuente == AVISO_X9:
						aviso_presente = true
						break
				print("HTTP FLR: %s %s" % [
					AVISO_X9, "presente" if aviso_presente else "ausente de la respuesta"])
			return
	print("HTTP %s: %s ausente de la respuesta" % [endpoint, candidato])
	if endpoint == "FLR":
		print("HTTP FLR: %s ausente del registro candidato" % AVISO_X9)


func _imprimir_muestra(eventos: Array[Dictionary], cantidad: int) -> void:
	for indice in range(mini(eventos.size(), cantidad)):
		print(JSON.stringify(eventos[indice]))


func _imprimir_linea_de_tiempo(origen: String, eventos: Array[Dictionary]) -> void:
	var hitos: Array[Dictionary] = []
	for evento in eventos:
		_agregar_hito(hitos, evento, evento, "inicio")
		if evento.has("pico"):
			_agregar_hito(hitos, evento, evento.pico, "pico")
		for aviso in evento.get("avisos", []):
			_agregar_hito(hitos, evento, aviso, "aviso publicado")
	hitos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.unix < b.unix)
	print("--- %s | línea de tiempo (%d hitos) ---" % [origen, hitos.size()])
	var inicio := _unix_utc(INICIO)
	var fin := _unix_utc(FIN)
	for hito in hitos:
		var segundos: float = DURACION_PARTIDA * float(hito.unix - inicio) / (fin - inicio)
		print("%9.3f s | %s | %s | %s | %s%s" % [
			segundos, hito.fecha_utc, hito.tipo, hito.id_episodio, hito.fase, hito.detalle])


func _agregar_hito(hitos: Array[Dictionary], episodio: Dictionary, datos: Dictionary,
		fase: String) -> void:
	var fecha: Variant = datos.get("fecha_utc")
	if not fecha is String or fecha.is_empty():
		return
	var detalle := ""
	if fase == "aviso publicado":
		detalle = " | %s" % datos.id_fuente
	if datos.has("flujo_pfu"):
		detalle = " | %s pfu (%s)" % [datos.flujo_pfu, datos.fuente]
	hitos.append({
		"unix": _unix_utc(fecha),
		"fecha_utc": fecha,
		"id_episodio": episodio.id_fuente,
		"tipo": episodio.tipo,
		"fase": fase,
		"detalle": detalle,
	})


func _unix_utc(fecha: String) -> int:
	var fecha_sin_z := fecha.trim_suffix("Z")
	if fecha_sin_z.length() == 16:
		fecha_sin_z += ":00"
	return Time.get_unix_time_from_datetime_string(fecha_sin_z)
