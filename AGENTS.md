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
