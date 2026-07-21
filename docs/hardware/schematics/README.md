# Schematics (vendored PDF export)

The Pocket-CM5's actual PCB schematic lives on
[OSHWLab](https://oshwlab.com/amarullz/pibrick-pocketcm5) (EasyEDA Pro), owned by the upstream
`amarullz/piBrick` project — see [`../piBrick-hw-repo.md`](../piBrick-hw-repo.md). OSHWLab renders
the schematic in a JS canvas editor with no static content, so it can't be fetched or grepped for
electrical details. These PDFs are a manually-exported snapshot (2026-07-21) checked in here so
that connector/power/pinout details can actually be looked up instead of re-derived by hand each
time.

**If something here looks stale or wrong for the current hardware revision**, re-export from
OSHWLab and diff — this directory is a snapshot, not a live source.

## Files

| File | Pages | Covers |
|---|---|---|
| `pocket-cm5-mainboard.pdf` | 8 | Main board — see page map below |
| `display-5.48inch.pdf` | 1 | Display panel board |
| `display-flex.pdf` | 1 | Display flex connector |
| `gpio-breakout.pdf` | 1 | GPIO breakout board |
| `speaker-board.pdf` | 1 | Speaker board |
| `speaker-board-flex.pdf` | 1 | Speaker board flex |
| `speaker-gpio.pdf` | 1 | Speaker GPIO |

### `pocket-cm5-mainboard.pdf` page map

| Page | Content |
|---|---|
| 1 | Raspberry Pi CM5 pinout |
| 2 | USB-C / CH334P USB hub, CC1/CC2 signals |
| 3 | Full-size HDMI, power inductors |
| 4 | Display backlight MOSFET, GPIO |
| 5 | **M.2 NVMe connector + PCIe power regulator**, SD card |
| 6 | BQ25895 battery charger, USB-C charging |
| 7 | USER RGB indicator, UART |
| 8 | Audio regulators |

## Confirmed facts

Findings already dug out of these schematics — append here rather than re-deriving next time.

**M.2 NVMe slot** (`pocket-cm5-mainboard.pdf`, page 5): PCIe Gen 2/3, single lane. Connector spec
per its own schematic label: *"1x PCIE 2/3 - 3V 3A Power - 2.5mm Connector Height | Support 2230 &
2242"*. That's a ~9W power budget at the connector — comfortably above what any 2230/2242 NVMe SSD
actually draws (~2-3W under load), so drive power draw isn't a real constraint when picking an
SSD. Power section is labeled "PCIE POWER REGULATOR" on the same page. 2.5mm clearance means
single-sided drives only.
