# Kingslayer – Godot 4 Grundgerüst

Minimales, startbares Basissetup für ein isometrisches 2D-Nahkampfspiel in Godot 4.

## Struktur

```text
project_root/
├─ scenes/
│  ├─ Main.tscn
│  ├─ World.tscn
│  └─ units/
│     └─ Unit.tscn
├─ scripts/
│  ├─ managers/
│  │  ├─ game_manager.gd
│  │  ├─ world_manager.gd
│  │  ├─ kingdom_manager.gd
│  │  ├─ spawn_manager.gd
│  │  └─ loot_manager.gd
│  └─ units/
│     └─ unit.gd
├─ art/
├─ ui/
├─ data/
└─ README.md
```

## Zweck der Basiskomponenten

- **Main.tscn**: Startszene; hält die `World`-Instanz und alle zentralen Managerknoten.
- **World.tscn**: Leerer World-Container für spätere Karten-/Territoriumslogik.
- **Unit** (`Unit.tscn` + `unit.gd`): Minimale Basisklasse für spätere Ableitungen (freier Ritter, Gefährte, Königsritter, Herrscher).
- **Manager**: Platzhalter mit klarer Trennung der Verantwortungen.

## Architektur-Leitlinie (für spätere Iterationen)

- **Daten**: statische/konfigurierbare Inhalte in `data/`.
- **Simulation**: Spiellogik über `scripts/managers/` und spätere Simulationsskripte.
- **Darstellung**: Szenen und visuelle Nodes in `scenes/`, Assets in `art/`, UI in `ui/`.

Es ist bewusst **keine** Kampfmechanik, KI, Dynastie-, Quest- oder tiefe Simulationslogik enthalten.
