# OuterBase credits and sources

OuterBase was built by the OuterBase team for NASA Space Apps.

## Space weather

- [NASA CCMC DONKI](https://ccmc.gsfc.nasa.gov/DONKI/events/) documents the October 2024 solar flare and solar energetic particle events. The separate HTTP test queries the public `FLR` and `SEP` endpoints at `https://ccmc.gsfc.nasa.gov/DONKI-API/get/` for October 1–31, 2024.
- NOAA SWPC provides the observed proton flux, storm threshold and peak information used in the historical replay. [October 2024 weekly report](https://www.ngdc.noaa.gov/stp/space-weather/swpc-products/weekly_reports/PRFs_of_SGD/2024/10/prf2563.pdf) · [Solar proton event archive](https://www.ngdc.noaa.gov/stp/space-weather/interplanetary-data/solar-proton-events/archive/SEP%20page%20code.20241115.html)
- The mission reads `data/eventos_solares_octubre_2024.json` locally. Event dates, classifications and observed flux come from the cited records. The mission compresses time and simulates radiation dose, equipment failures, shelter protection and the response from Earth.

## Life on the International Space Station

- [NASA Astronaut Exercise](https://www.nasa.gov/missions/station/iss-research/astronaut-exercise/) informs the optional exercise activity.
- [NASA OSDR OSD-684](https://osdr.nasa.gov/bio/repo/data/studies/OSD-684) is cited in the Terminal. The study used human muscle tissue on chips sent to the ISS.
- [NASA Water Recovery](https://www.nasa.gov/missions/station/iss-research/nasa-achieves-water-recovery-milestone-on-international-space-station/) informs the water-recycling activity.

## AI assistance and artwork

- **OpenAI Codex** assisted with implementation and Godot MCP testing, including the delivery menu, English player text and export setup.
- **Google Antigravity** assisted with implementation outside the Codex and MCP work, according to the team's development declaration.
- **ChatGPT** · The team is confirming its contribution for the final disclosure.

| Graphic | Source file | Tool |
| --- | --- | --- |
| Solar panel drawing · **AI-generated** | `scripts/levels/SolarArray.gd` | Tool to confirm |
| Added wall faces and trim · **AI-generated** | `scripts/levels/ExteriorPerimeter.gd` | Tool to confirm |

These graphics are drawn by Godot scripts. The team still needs to confirm whether the upper interior-wall decoration includes a separate graphic, and confirm the external asset list, creators, source links and licenses.
