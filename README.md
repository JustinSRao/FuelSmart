# FuelSmart

**What will these vehicles actually cost me, and when does one become cheaper
than the other?**

FuelSmart compares the real financial consequences of two vehicles — purchase
price, fuel or electricity, financing, insurance, maintenance, incentives,
trade-in, charging behaviour and ownership horizon — and shows when, or whether,
one overtakes the other.

It is **financially neutral**. It never assumes an EV is better, that gasoline is
worse, that an EV eventually breaks even, or that the more efficient vehicle is
the better financial choice. It shows the mathematics and lets you decide.

> FuelSmart is an informational comparison tool, not financial advice.

---

## Status

| Layer | State |
|---|---|
| Data ingestion pipeline | **Complete and verified** — runs against live government data |
| Bundled vehicle database | **Generated** — 36,435 records (11,678 CA / 24,757 US) |
| Domain models | **Complete** |
| Calculation engine | **Complete** — energy, financing, ownership, break-even, thresholds |
| Data layer | **Complete** — repositories, prefix search index, VIN, persistence, export/import |
| Design system | **Complete** — Nocturne tokens, components, light + dark |
| SwiftUI application | **Complete** — onboarding, home, compare flow, picker, detail, results, Scenario Lab, thresholds, saved library, settings, share, PDF |
| Python pipeline tests | **Passing** — 36/36 |
| Swift engine tests | **Passing** — 89/89 across 7 suites |
| App build | **Compiles on iOS and macOS** in CI |
| UI critical path | **Passing** — 6/6 on a simulator |

> ### Build environment note
>
> This repository is authored on Windows, where no Swift toolchain exists. The
> compile and test loop runs on GitHub's macOS runners instead — see
> [`Documentation/Releasing.md`](Documentation/Releasing.md).
>
> Current CI state:
>
> | Job | Result |
> |---|---|
> | Core package (`swift build` + `swift test`) | 89/89 tests passing |
> | App build, iOS | compiles |
> | App build, macOS | compiles |
> | Data pipeline | 36/36 tests passing |
> | UI critical path | 6/6 passing on a simulator |
>
> The UI suite drives the real app end to end: launch, pick two vehicles from
> the bundled dataset, read the result and chart, save, and reopen. Its passing
> confirms on-device behaviour that cannot be checked any other way — notably
> that the 13 MB vehicle database decodes and the prefix search index answers a
> query fast enough to be usable.
>
> The first CI run surfaced ~400 errors from a single cause — the
> `InternalImportsByDefault` upcoming feature, which makes `import Foundation`
> internal and so rejects every public signature built from `Date`, `UUID` or
> `Bundle`. The rest were a handful of genuine mistakes: `Result<_, String>`
> (`String` is not an `Error`), a `??` chain past the type-checker's budget, a
> name collision with **Foundation's own** `ComparisonResult`, a non-`Sendable`
> `Schema` static, a macOS-only `List` initialiser, a declaration inside a
> `ViewBuilder`, and `self` captured before initialisation.
>
> Numeric constants in the Swift tests were derived from an independent
> reference implementation rather than recorded from a run. That cross-check
> caught two real bugs before any compiler did: an inverted "which vehicle is
> catching up" branch in `BreakEvenCalculator`, and a backwards Imperial-vs-US
> MPG assertion.

---

## Platforms

One codebase, adaptive layouts — not three applications.

| Platform | Navigation |
|---|---|
| iPhone | Tab bar + navigation stack |
| iPad | Sidebar + split view, persistent assumptions inspector |
| macOS | Sidebar window, chart and inspector side by side |

Minimum: iOS 17, macOS 14.

## Zero recurring cost

FuelSmart has **no backend and no paid dependency**. It would keep working if
every commercial service on the internet disappeared.

| | |
|---|---|
| Servers we operate | none |
| Secret API keys | none |
| Third-party SDKs | none |
| Analytics | none |
| Accounts | none |
| Recurring infrastructure cost | **$0** |

The only network calls are two optional, unauthenticated public government
endpoints — NHTSA vPIC for VIN decoding, and the dataset refresh. Neither is
required: the vehicle database is bundled, and comparison, charts, saving, export
and settings all work offline.

## Architecture

```
FuelSmart/
├── Scripts/                     Data ingestion (Python, stdlib only)
│   ├── sources.json               official dataset URLs + licences
│   ├── fetch_datasets.py          download raw government CSVs
│   ├── build_dataset.py           parse → normalize → validate → emit
│   ├── test_pipeline.py           pipeline test suite
│   └── fuelsmart_data/            units, model, nrcan, epa, emit, validate
├── DataSources/                 Raw downloads (gitignored, reproducible)
├── GeneratedData/               Bundled output — committed
│   ├── vehicles-CA.json  catalog-CA.json
│   ├── vehicles-US.json  catalog-US.json
│   └── manifest.json              versions, checksums, attribution
├── Packages/FuelSmartCore/      Domain + calculations (Foundation only)
│   ├── Sources/FuelSmartCore/
│   │   ├── Domain/                Vehicle, profiles, scenario, result
│   │   ├── Calculation/           energy, financing, ownership, break-even,
│   │   │                          scenario, thresholds
│   │   ├── Data/                  repositories, VIN, persistence
│   │   └── Support/               units
│   └── Tests/FuelSmartCoreTests/
├── App/FuelSmart/               SwiftUI application
│   ├── App/                       entry point, navigation, state, persistence
│   ├── DesignSystem/              Nocturne tokens, components, fields
│   ├── Features/                  one folder-level screen per feature
│   └── Resources/                 Info.plist, entitlements
├── Tests/FuelSmartUITests/      critical-path UI tests
├── project.yml                  XcodeGen project definition
├── .github/workflows/           CI + TestFlight (macOS runners)
└── Documentation/
    ├── CalculationMethodology.md  every equation, in plain language
    ├── Releasing.md               TestFlight path, signing, cost
    └── SecurityAudit.md           prototype audit + remediation
```

`FuelSmartCore` depends on Foundation and nothing else — no UI framework, no
network client, no third-party package. The financial model is testable in
isolation and a view cannot reach into the mathematics.

## Building

The calculation engine builds and tests on its own, with no Xcode project:

```bash
cd Packages/FuelSmartCore
swift build
swift test
```

The app is described by `project.yml` rather than a checked-in `.xcodeproj`,
which merges badly and is painful to hand-edit:

```bash
brew install xcodegen
xcodegen generate
open FuelSmart.xcodeproj
```

Requires Xcode 16 or later. One application target serves iPhone, iPad and
macOS — the layouts adapt, rather than there being three projects.

### No Mac? Use CI

Both workflows run on GitHub's macOS runners, so the first compile does not
require owning a Mac:

- **Actions → CI** — builds and tests the core package, builds the app for iOS
  and macOS, runs the UI tests.
- **Actions → TestFlight** — archives and uploads, once CI is green.

macOS runner minutes are free for public repositories and billed at a 10×
multiplier for private ones. See
[`Documentation/Releasing.md`](Documentation/Releasing.md) for the cost details
and the one-time App Store Connect setup.

> TestFlight is not a shortcut around the build: an upload *starts* with a full
> compile, so run CI first.

## Data ingestion

```bash
python Scripts/fetch_datasets.py     # download official CSVs → DataSources/
python Scripts/build_dataset.py      # normalize + validate → GeneratedData/
python Scripts/test_pipeline.py      # 36 tests
```

Standard library only — nothing to install.

The build **fails rather than emitting output it cannot vouch for**: it checks
record counts, id collisions, powertrain coverage, and that every battery-electric
record carries real published consumption. Individual malformed government rows
are dropped with a reported reason; one bad row never costs the user the dataset.

### Official data sources

| Region | Source | Licence |
|---|---|---|
| Canada | Natural Resources Canada — Fuel Consumption Ratings (conventional, battery-electric, plug-in hybrid) | Open Government Licence – Canada |
| United States | U.S. DOE / EPA — FuelEconomy.gov vehicle data | U.S. Government work (public domain) |
| VIN decode | NHTSA vPIC API (optional, no key) | U.S. Government work |

All are direct machine-readable downloads. **FuelSmart never scrapes websites.**

Attribution is carried per record through to the app's Data Sources screen and
must not be removed during UI work.

### Refreshing

Re-run the two scripts and commit `GeneratedData/`. The app can optionally check
the official endpoints for a newer dataset, but:

- the bundled data is always the fallback;
- no server of ours is ever required;
- a download is validated before it replaces local data;
- a schema change degrades to the bundled data rather than breaking the app.

The dataset version and date are shown in Settings.

## Calculation methodology

Full derivations in **[`Documentation/CalculationMethodology.md`](Documentation/CalculationMethodology.md)**. In brief:

- **Canonical units.** Everything is computed in km, L/100 km, kWh/100 km — one
  implementation for both regions. Conversion happens only at input and display.
  Consumption is stored per-distance rather than as MPG because MPG is a
  reciprocal rate and cannot be blended by distance share.
- **Currency is never converted.** Canadian comparisons are wholly CAD, U.S.
  wholly USD.
- **Electricity** uses the government's published kWh/100 km — never battery
  capacity ÷ range, never MPGe.
- **Financing adds interest only.** Principal is already in acquisition; counting
  payments too would charge for the car twice.
- **Keep vs replace** treats the owned vehicle's original price as sunk: zero
  acquisition, zero financing. Its trade-in is credited to the replacement.
- **Resale** is the user's own figure, subtracted once at the horizon, never
  amortized. FuelSmart does not forecast depreciation.
- **Break-even** walks the simulated curves rather than solving a formula,
  because interest is front-loaded. Five outcomes are all real answers, including
  *no break-even exists*.
- **Thresholds** are solved numerically against the same engine, and report "no
  solution in range" instead of extrapolating.

### Units by region

| | Canada | United States |
|---|---|---|
| Distance | km | miles |
| Fuel economy | L/100 km | MPG |
| Fuel price | $/L | $/gallon |
| EV consumption | kWh/100 km | kWh/100 mi |
| Currency | CAD | USD |

One region is active at a time and every figure on screen belongs to it.
FuelSmart never mixes units or shows a conversion in parentheses.

## Testing

```bash
cd Packages/FuelSmartCore && swift test   # calculation engine + export/import
python Scripts/test_pipeline.py           # data pipeline (36 tests, passing)
xcodebuild test -scheme FuelSmart   -destination 'platform=iOS Simulator,name=iPhone 16'   # UI critical path
```

Fixtures are deterministic and hand-written — gas sedan, hybrid, diesel truck,
PHEV, BEV — so no test depends on live government data. Expected values were
derived independently of the implementation, so they test the mathematics rather
than the code's memory of itself.

## Privacy

No account. No tracking SDKs. No behavioural advertising. No analytics. Nothing
is sold. Comparisons never leave the device unless you deliberately perform a VIN
lookup, a dataset update, or a share/export.

## Known limitations

- **No price data.** There is no free authoritative source, so FuelSmart asks
  what you will actually pay rather than guessing.
- **No depreciation model.** Resale is your assumption, shown as such.
- **No fuel-price forecast.** Threshold tools show sensitivities, not
  predictions.
- **Government ratings are laboratory tests.** Real consumption varies with
  climate, terrain, load and driving style. The optional real-world adjustment is
  a declared scenario assumption applied to both vehicles, never a silent
  correction to the official rating.
- **Hybrid detection in Canadian data** relies on the model name, because NRCan's
  conventional file has no hybrid flag.
- **NRCan model/configuration split** is a presentation heuristic: the dataset has
  no separate trim column.
- **Swift sources are uncompiled** — see the build-environment note above.

## Attribution

Contains information licensed under the
[Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada).
Fuel consumption ratings: Natural Resources Canada.

Fuel economy data: U.S. Department of Energy and U.S. Environmental Protection
Agency, fueleconomy.gov — a work of the U.S. Government.

VIN decoding: U.S. National Highway Traffic Safety Administration vPIC.

## Disclaimer

Calculations are estimates. Government efficiency ratings are standardized
laboratory tests and may differ from real-world use. Prices and future energy
costs change. Maintenance, insurance and depreciation assumptions vary widely.
FuelSmart is an informational comparison tool and does not provide financial
advice.
