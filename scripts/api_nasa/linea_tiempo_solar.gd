extends RefCounted

const ARCHIVO := "res://data/eventos_solares_octubre_2024.json"
const INICIO := "2024-10-01T00:00:00Z"
const FIN := "2024-11-01T00:00:00Z"
const DURACION_PARTIDA := 600.0


static func leer_seleccion_local() -> Array[Dictionary]:
	var archivo := FileAccess.open(ARCHIVO, FileAccess.READ)
	if archivo == null:
		push_error("ARCHIVO LOCAL: %s" % error_string(FileAccess.get_open_error()))
		return []
	var json := JSON.new()
	if json.parse(archivo.get_as_text()) != OK or not json.data is Array:
		push_error("ARCHIVO LOCAL: se esperaba una lista JSON válida")
		return []
	var eventos: Array[Dictionary] = []
	for fila in json.data:
		if not fila is Dictionary or not fila.has_all(
				["id_fuente", "tipo", "fecha_utc", "fuente", "url_fuente"]):
			push_error("ARCHIVO LOCAL: registro incompleto")
			return []
		eventos.append(fila)
	return eventos


static func construir_hitos(eventos: Array[Dictionary]) -> Array[Dictionary]:
	var hitos: Array[Dictionary] = []
	for evento in eventos:
		_agregar_hito(hitos, evento, evento, evento.get("tipo_hito", "inicio"))
		if evento.has("pico"):
			_agregar_hito(hitos, evento, evento.pico, "pico")
		for aviso in evento.get("avisos", []):
			_agregar_hito(hitos, evento, aviso, "aviso_publicado")
		for adicional in evento.get("hitos_adicionales", []):
			_agregar_hito(hitos, evento, adicional, adicional.tipo_hito)
	hitos.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.segundos_mision < b.segundos_mision)
	return hitos


static func _agregar_hito(hitos: Array[Dictionary], episodio: Dictionary,
		datos: Dictionary, tipo_hito: String) -> void:
	var fecha: Variant = datos.get("fecha_utc")
	if not fecha is String or fecha.is_empty():
		return
	var hito := datos.duplicate(true)
	for campo in ["pico", "avisos", "hitos_adicionales"]:
		hito.erase(campo)
	hito.id_episodio = episodio.get("id_episodio", episodio.id_fuente)
	hito.id_fuente = datos.get("id_fuente", episodio.id_fuente)
	hito.tipo = episodio.tipo
	hito.tipo_hito = tipo_hito
	hito.fuente = datos.get("fuente", episodio.fuente)
	hito.url_fuente = datos.get("url_fuente", episodio.url_fuente)
	var procedencia: Dictionary = episodio.get("procedencia", {})
	var campo_procedencia := "avisos" if tipo_hito == "aviso_publicado" else tipo_hito
	hito.procedencia = datos.get("procedencia", procedencia.get(campo_procedencia))
	if tipo_hito == "pico" and not hito.has("canales_energia") and episodio.has("canales_energia"):
		hito.canales_energia = episodio.canales_energia.duplicate()
	var inicio := _unix_utc(INICIO)
	var fin := _unix_utc(FIN)
	hito.segundos_mision = DURACION_PARTIDA * float(_unix_utc(fecha) - inicio) / (fin - inicio)
	hitos.append(hito)


static func _unix_utc(fecha: String) -> int:
	var fecha_sin_z := fecha.trim_suffix("Z")
	if fecha_sin_z.length() == 16:
		fecha_sin_z += ":00"
	return Time.get_unix_time_from_datetime_string(fecha_sin_z)
