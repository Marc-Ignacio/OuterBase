extends Node

const LineaTiempo := preload("res://scripts/api_nasa/linea_tiempo_solar.gd")
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
	var eventos := LineaTiempo.leer_seleccion_local()
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
	var hitos := LineaTiempo.construir_hitos(eventos)
	print("--- %s | línea de tiempo (%d hitos) ---" % [origen, hitos.size()])
	for hito in hitos:
		var detalle := ""
		if hito.tipo_hito == "aviso_publicado":
			detalle = " | %s" % hito.id_fuente
		if hito.has("flujo_pfu"):
			detalle = " | %s pfu (%s)" % [hito.flujo_pfu, hito.fuente]
		print("%9.3f s | %s | %s | %s | %s%s" % [
			hito.segundos_mision, hito.fecha_utc, hito.tipo, hito.id_episodio,
			hito.tipo_hito.replace("_", " "), detalle])
