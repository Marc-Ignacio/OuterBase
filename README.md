# OuterBase

OuterBase is a lunar base game for NASA Space Apps. Keep the base running during a solar storm, restore drinking water and get a reply from Earth.

## Play

1. Open the project in Godot 4.7 with the Compatibility renderer and press **F5**.
2. Select **Start Mission**. Use the arrow keys to move and **E** to use nearby equipment. Press **E** or **Esc** to close the Terminal.
3. Check the Terminal for objectives and Sun alerts. During the storm, use the green **SHELTER** entrance near the O₂ tank. Press **E** at the ladder to return.
4. Repair the water tank, recycle water, and get a message confirmed by Earth. Select **End day** in the Terminal to see the result.

## Data

The game replays selected October 2024 records from NASA CCMC DONKI and NOAA SWPC using the bundled historical JSON. Radiation dose, equipment failures and communication delay are simulated. The optional developer scene `scripts/api_nasa/prueba_donki.tscn` separately queries DONKI's public `FLR` and `SEP` endpoints. The playable build works offline and requires no API key.

See [Credits and Sources](CREDITS.md) for scientific and educational references.

## Export for NASA Space Apps

Install the matching Godot export templates. From a checkout of the delivery changes, create `build/web` and use **Project → Export → NASA Space Apps Web → Export Project** with **Export With Debug** disabled. Serve the resulting files together over HTTP. The preset includes `data/eventos_solares_octubre_2024.json` and excludes local tools and overrides.

Godot AI MCP can be configured locally in the ignored `override.cfg`. The delivery project can be opened and exported from a clean checkout without MCP.
