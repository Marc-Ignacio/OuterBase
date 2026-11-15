extends Node

const EPISODIO_9 := "2024-10-09T05:05:00-SEP-001"
const EPISODIO_26 := "NOAA-SWPC-2024-10-26T19:10Z"
const FECHAS := [
	"2024-10-03T12:08Z", "2024-10-03T12:18Z", "2024-10-03T12:19Z",
	"2024-10-03T12:31:54Z", "2024-10-09T03:50Z", "2024-10-09T05:05Z",
	"2024-10-09T05:13Z", "2024-10-09T12:40Z", "2024-10-10T15:15Z",
	"2024-10-26T19:10Z", "2024-10-28T03:50Z",
]

var _recibidos: Array[Dictionary] = []
var _fallos := 0


func _ready() -> void:
	print("=== ARCHIVO LOCAL | prueba del calendario solar ===")
	var calendario := $CalendarioSolar
	calendario.hito_alcanzado.connect(_registrar_hito)

	calendario.avanzar_a(48.0)
	_comprobar(_recibidos.is_empty(), "Antes del primer hito no hay emisiones")
	calendario.avanzar_a(159.0)
	_comprobar(_fechas() == FECHAS.slice(0, 6), "El salto emite solo los hitos alcanzados, en orden")
	calendario.avanzar_a(159.0)
	calendario.avanzar_a(48.0)
	_comprobar(_recibidos.size() == 6, "Repetir el tiempo o retroceder no duplica hitos")
	calendario.avanzar_a(600.0)
	_comprobar(_fechas() == FECHAS, "Secuencia local completa en orden, con 11 hitos")
	_comprobar_episodios()

	var primera_partida := _recibidos.duplicate(true)
	_recibidos.clear()
	calendario.reiniciar()
	calendario.avanzar_a(600.0)
	_comprobar(_recibidos == primera_partida and _recibidos.size() == FECHAS.size(),
		"Reiniciar reproduce los mismos 11 hitos en un solo salto")
	print("Calendario solar: %d fallos" % _fallos)
	if "--salir-al-terminar" in OS.get_cmdline_user_args():
		get_tree().quit(1 if _fallos > 0 else 0)


func _comprobar_episodios() -> void:
	if _recibidos.size() != FECHAS.size():
		_comprobar(false, "Episodios históricos incompletos")
		return
	var deteccion := _recibidos[4]
	var inicio := _recibidos[5]
	var umbral := _recibidos[7]
	var pico := _recibidos[8]
	_comprobar(
		deteccion.id_episodio == EPISODIO_9 and inicio.id_episodio == EPISODIO_9
		and umbral.id_episodio == EPISODIO_9 and pico.id_episodio == EPISODIO_9,
		"Detección, inicio, S3 y pico del 9–10 comparten id_episodio")
	_comprobar(
		deteccion.canales_energia == [">100 MeV"] and inicio.canales_energia == [">10 MeV"]
		and umbral.nivel == "S3" and umbral.umbral_pfu == 1000 and not umbral.has("flujo_pfu")
		and pico.flujo_pfu == 1810 and pico.fuente == "NOAA SWPC"
		and is_equal_approx(pico.segundos_mision, 186.491935483871),
		"Canales, umbral y máximo conservan sus valores, fuente y proyección")
	_comprobar(
		_recibidos[9].id_episodio == EPISODIO_26 and _recibidos[10].id_episodio == EPISODIO_26
		and _recibidos[10].flujo_pfu == 364,
		"El episodio del 26–28 tiene su propio ID y pico de 364 pfu")


func _registrar_hito(hito: Dictionary) -> void:
	_recibidos.append(hito)
	print("  %7.3f s | %s | %s | %s | %s" % [
		hito.segundos_mision, hito.fecha_utc, hito.tipo_hito, hito.id_episodio, hito.fuente])


func _fechas() -> Array:
	return _recibidos.map(func(hito: Dictionary) -> String: return hito.fecha_utc)


func _comprobar(condicion: bool, descripcion: String) -> void:
	if condicion:
		print("OK | " + descripcion)
	else:
		_fallos += 1
		push_error("FALLO | " + descripcion)
