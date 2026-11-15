# Contexto del Proyecto: Junior Astronaut Mission Trainer
**Evento:** NASA Space Apps Challenge 2026
**Motor:** Godot Engine 4.x (GDScript)

## Propósito
Desarrollar un simulador interactivo donde los estudiantes administren una base lunar o marciana[cite: 1]. El objetivo principal es mantener la supervivencia de la misión equilibrando demandas competitivas: soporte vital, protección contra la radiación, energía y producción de alimentos[cite: 1].

## Arquitectura y Reglas de Desarrollo
- **Modularidad:** Cada sistema (Energía, Soporte Vital, Interfaz) se desarrolla en escenas separadas (`.tscn`) para evitar conflictos de fusión en el repositorio.
- **Comunicación Desacoplada:** Los sistemas no se referencian directamente; la comunicación entre la lógica y la interfaz de usuario (UI) ocurre estrictamente a través de Señales (Signals).
- **Estructura de Directorios:** 
  - `res://managers/`: Nodos invisibles (Autoloads/Singletons) con matemática y balance de recursos.
  - `res://scripts/api_nasa/`: Conexión HTTP y procesamiento de datos de radiación solar.
  - `res://scenes/ui/`: Componentes gráficos del dashboard interactivo.

## División del Equipo (5 Integrantes)
1. **Programador 1 (Lógica Central):** Desarrolla los sistemas de supervivencia, consumo y generación de recursos.
2. **Programador 2 (Datos/Eventos):** Gestiona la API de NASA, el clima espacial y detona las emergencias por radiación.
3. **Programador 3 (Arte Técnico):** Construye la UI, ensambla las escenas principales y vincula las señales visuales.
4. **Expositora 1 (Game Design/Documentación):** Define las reglas matemáticas de los recursos, redacta la documentación técnica y el GDD.
5. **Expositora 2 (UX/QA/Pitch):** Crea wireframes del dashboard, ejecuta pruebas de usabilidad y estructura el guion de presentación.

## Sistema de Terminal del Centro de Mando (TerminalScreen)
- **Disparador y Ubicación:** `BottomWallCommandCenter` (`Area2D` en `res://scenes/levels/BaseLunar.tscn` en la consola de mando frente al monitor de `scenescreen.png` en `X=448, Y=119`).
- **Interacción y Controles:**
  - Al entrar al área, se activa el indicador visual flotante `[E] TERMINAL`.
  - Presionar `[E]` abre la terminal `TerminalScreen`.
  - Presionar `[E]` nuevamente (o `[ESC]`) cierra y oculta la terminal.
  - Al alejarse de la zona, la terminal se auto-cierra si estaba abierta.
  - Mientras la terminal está desplegada, el movimiento del astronauta se pausa (`player.can_move = false`) para facilitar la lectura.
- **Estética Retro CRT:**
  - Marco de pantalla renderizado con `res://assets/sprites/Screen.png` (NinePatchRect con márgenes calibrados al bisel CRT).
  - Tipografía monoespaciada (`SystemFont` Monospace / Courier) con fósforo verde terminal (`#00ff66`), fondo CRT verde oscuro (`#0d2700`) y acentos de alerta en ámbar (`#ffd91a`) y rojo (`#ff4040`).
- **Integración de Datos:**
  - **Misiones y Tareas:** Conectado a `TaskManager.gd` mediante `get_active_tasks_data()`, mostrando título, ID, ubicación, nivel de urgencia, descripción y tiempo límite restante.
  - **Eventos y Clima Espacial:** Conectado a `EventManager.gd` y NASA DONKI/SWPC mediante `get_active_notices()`, telemetría de flujo solar en tiempo real (`pfu`), dosis simulada acumulada (`mSv`), estado de salida (`PERMITIDA`, `VIGILANCIA`, `SUSPENDIDA`, `RESTRINGIDA`) y orden activa de refugio.
  - **Reloj de Misión:** Vinculado a `DayManager.gd` (`day_time_updated`) en formato `T+ MM:SS UTC`.
