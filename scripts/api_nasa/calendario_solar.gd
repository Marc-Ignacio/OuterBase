extends Node

signal hito_alcanzado(hito: Dictionary)

const LineaTiempo := preload("res://scripts/api_nasa/linea_tiempo_solar.gd")

var _hitos: Array[Dictionary] = []
var _siguiente := 0
var _emitiendo := false
var _tiempo_alcanzado := -1.0


func _ready() -> void:
	_hitos = LineaTiempo.construir_hitos(LineaTiempo.leer_seleccion_local())


func reiniciar() -> void:
	_siguiente = 0
	_tiempo_alcanzado = -1.0


func avanzar_a(segundos_mision: float) -> void:
	if not is_finite(segundos_mision) or segundos_mision < 0.0:
		return
	_tiempo_alcanzado = maxf(_tiempo_alcanzado, segundos_mision)
	if _emitiendo:
		return
	_emitiendo = true
	while _siguiente < _hitos.size():
		var hito := _hitos[_siguiente]
		if hito.segundos_mision > _tiempo_alcanzado:
			break
		_siguiente += 1
		hito_alcanzado.emit(hito.duplicate(true))
	_emitiendo = false
