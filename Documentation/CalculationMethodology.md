# Calculation methodology

FuelSmart is a financial comparison tool, so every number it shows must be
auditable. This document states each equation in plain language, names the type
that implements it, and records the assumptions and the deliberate omissions.

**FuelSmart forecasts nothing.** There is no model of future fuel prices, future
electricity prices, or depreciation. Every figure is a consequence of values the
user supplied and ratings the government published.

---

## 1. Canonical units

The engine works in one set of units regardless of region, so there is exactly
one implementation of every calculation rather than a Canadian one and an
American one.

| Quantity | Canonical unit |
|---|---|
| Distance | kilometres |
| Liquid fuel consumption | litres per 100 km |
| Electrical consumption | kWh per 100 km |
| Fuel price | currency per litre |
| Electricity price | currency per kWh |
| Money | the region's own currency, never converted |

Conversion happens only at the two edges — data import, and user input/display.
`UnitConversionService` holds every constant, and each is an exact definition:

```
1 mile            = 1.609344 km
1 US gallon       = 3.785411784 L
1 Imperial gallon = 4.54609 L

US MPG       → L/100 km :  235.214583… ÷ MPG
Imperial MPG → L/100 km :  282.480936… ÷ MPG
kWh/100 mi   → kWh/100 km :  value ÷ 1.609344
```

> **Why not store MPG?** Fuel economy in MPG is a *reciprocal* rate, so it cannot
> be averaged by distance share: a trip that is half at 40 MPG and half at 20 MPG
> does not average 30 MPG. Consumption expressed per 100 km is a direct rate and
> blends linearly. Storing L/100 km makes the city/highway blend correct by
> construction.

> **Imperial is not U.S.** NRCan's `Combined (mpg)` column is Imperial gallons.
> At the same numeric MPG, an Imperial figure is the *worse* economy — treating
> the two as interchangeable misstates the value by about 20%. The column is
> carried for display only and never feeds a calculation.

**No currency conversion.** A Canadian comparison is entered and shown wholly in
CAD; a U.S. one wholly in USD. FuelSmart never mixes units, never shows a
conversion in parentheses, and has no exchange-rate dependency to go stale.

---

## 2. Effective consumption

`EnergyCostCalculator.blend` / `.adjusted`

### City / highway blend

```
blended = city × cityShare + highway × highwayShare
```

Shares always total 100% — `Split` stores one fraction and derives the other, so
the invariant cannot be broken.

**Fallback.** When a record lacks split ratings, the combined rating is used and
the result is flagged `usedCombinedFallback` so the UI can say so. When only one
of the two split figures exists it is used alone, also flagged. When nothing
exists, consumption is `nil` — never zero, never invented.

### Real-world adjustment

```
effective = blended × (1 + adjustment)
```

An optional, user-declared scenario assumption that raises *consumption*, which
is what cold weather, towing or aggressive driving actually do. Presets: Mild 0%,
Mixed +8%, Cold climate +18%, or a custom value.

The stored government rating is never modified, the adjustment applies to both
vehicles equally, and its magnitude is reported with every result.

---

## 3. Energy cost

`EnergyCostCalculator.breakdown`

### Liquid fuel

```
fuelCostPer100km = litresPer100km × pricePerLitre × fuelDistanceShare
annualFuelCost   = fuelCostPer100km × (annualKm ÷ 100)
```

Diesel vehicles are priced from the diesel rate, not the gasoline rate.

### Electricity

```
electricityCostPer100km = kWhPer100km × blendedRate × electricDistanceShare
annualElectricityCost   = electricityCostPer100km × (annualKm ÷ 100)
```

Electrical consumption always comes from the government's published kWh/100 km.
It is **never** derived from battery capacity ÷ advertised range, and never from
MPGe — MPGe is an energy equivalence, not a consumption rate.

### Charging blend

```
blendedRate = Σ(shareᵢ × priceᵢ) ÷ Σ(shareᵢ)
```

Simple mode is a single source at 100%. Advanced mode is home + public. Dividing
by the total share normalizes a set that does not quite sum to 1, so a
half-filled form cannot understate the rate. The calculators only ever ask for
`blendedElectricityPricePerKWh`, so a third category (workplace, destination) can
be added later without touching the engine.

### Plug-in hybrids

A PHEV is the only vehicle that draws both energy types at once. The user
declares what share of *distance* runs on electricity, and each energy cost is
charged over its own share:

```
electricShare = user-set (default 70%)
fuelShare     = 1 − electricShare

cost/100km = kWhPer100km × blendedRate × electricShare
           + litresPer100km × fuelPrice × fuelShare
```

An optional estimator suggests a share from daily distance, electric range and
charging frequency:

```
share = min( (electricRange × chargesPerWeek) ÷ (dailyKm × 7), 1 )
```

The estimator is an aid only. The manual share is always available and always
wins when set.

---

## 4. Acquisition cost

`AcquisitionCost.net`

```
net = purchasePrice + salesTax + dealerFees + otherFees
    + homeCharger + panelUpgrade + otherOneTime
    − rebate − governmentIncentive − manufacturerIncentive − tradeIn
```

Clamped at zero: incentives exceeding the price make a vehicle free, not a source
of income.

Every field beyond `purchasePrice` is optional and defaults to no effect.

**Prices are never invented.** FuelSmart does not know what a car costs and does
not ask a model, a dealer, or a pricing API. It asks the user what they will
actually pay — a negotiated price, a used listing, a private sale, or MSRP if
they choose it. Efficiency data and price stay conceptually separate.

---

## 5. Keep vs replace — the sunk-cost rule

`ComparisonSide.chargeableAcquisition`

```
chargeableAcquisition = isAlreadyOwned ? 0 : acquisition.net
```

In **buy vs buy**, both acquisition costs count.

In **keep vs replace**, what the user already paid for the vehicle they own is
sunk and is never charged again. Only what happens next counts:

```
kept side        : 0 acquisition, 0 financing, energy and recurring costs only
replacement side : price + taxes/fees + charger − trade-in − incentives
```

The trade-in value of the kept vehicle is credited to the **replacement**, where
the money actually changes hands — not deducted from the vehicle being given up.

This single rule lives in one place so no screen can get it wrong.

---

## 6. Financing

`FinancingCalculator`

Standard amortized loan:

```
principal = max(netAcquisition − downPayment, 0)
r         = APR ÷ 12
payment   = principal × r × (1+r)ⁿ ÷ ((1+r)ⁿ − 1)
```

**Only interest is a cost.** The principal is already counted in net acquisition,
so adding loan payments to the cumulative curve would charge the user for the car
twice. The monthly payment is computed for display; the *interest* alone enters
the cost model.

Interest is tabulated month by month against the outstanding balance, because it
is front-loaded rather than linear. A horizon shorter than the loan term
therefore charges the interest genuinely accrued by then, not a pro-rata slice.

Handled explicitly:

| Case | Behaviour |
|---|---|
| Cash purchase | no loan, no interest |
| 0% APR | payment = principal ÷ term; the amortization formula's division by zero is avoided by a separate branch |
| Down payment ≥ price | nothing financed |
| Horizon < term | only interest accrued by the horizon is charged; flagged to the user |
| Horizon > term | interest stops accruing at term end |

---

## 7. Recurring costs

`RecurringCostProfile`

Optional per-vehicle annual figures: insurance, maintenance, registration,
parking, other. Accrued monthly (`annual ÷ 12`) so a partial year is charged
proportionally.

**Labelling is not cosmetic.** A supplied value of zero counts as supplied — the
user said "nothing", which differs from "unknown".

| What the user entered | What the headline is called |
|---|---|
| Acquisition + energy only | **Purchase + energy cost** |
| Any recurring cost supplied | **Estimated ownership cost** |

FuelSmart never calls an incomplete calculation "total cost of ownership".

---

## 8. Resale value

`ResaleAssumption`

FuelSmart does **not** forecast depreciation. If the user supplies an expected
resale value at their horizon, it is subtracted **once, at the horizon**:

```
total(horizon) = cumulativeCost(horizon) − resaleCredit
```

It is deliberately *not* amortized into the curve. Spreading it across the months
would make the vehicle appear progressively cheaper to run than it is, and would
corrupt the break-even search.

The assumption is always shown as the user's own.

---

## 9. Cumulative cost over time

`OwnershipCostCalculator.simulate`

The month-by-month curve is the single source of truth — the chart, the totals,
the breakdown and the break-even search all read it, so no two parts of the app
can disagree about a number.

```
cost(m) = netAcquisition                       (charged at month 0)
        + cumulativeInterest(m)
        + (annualEnergy ÷ 12) × m
        + (annualRecurring ÷ 12) × m
```

Categories are stored separately at every month — acquisition, one-time costs,
financing interest, fuel, electricity, insurance, maintenance, registration,
parking, other — so any breakdown can be read without recomputation.

The simulation always runs at least 120 months, even for a three-year horizon, so
a crossover beyond the chosen horizon is still visible rather than silently
truncated.

**Rounding.** Intermediates are never rounded. Rounding happens at presentation
only: whole currency units, except per-100 km rates (2 dp) and fuel prices
(2–3 dp).

---

## 10. Break-even

`BreakEvenCalculator.analyse`

The search walks the two cumulative curves looking for a sign change in
`costA(m) − costB(m)`, rather than solving `Δacquisition ÷ Δannual`. The closed
form is only correct when both curves are straight lines; financing interest is
front-loaded and a resale credit is a step, so the shortcut gives the wrong month
whenever either is present.

Neither side is assumed to be electric, cheaper, or destined to catch up. Five
outcomes are all first-class answers:

| Status | Meaning |
|---|---|
| `breakEvenOccurs` | the curves cross; month, distance and date are reported |
| `vehicleAAlwaysAhead` | A starts cheaper and stays cheaper — no crossover |
| `vehicleBAlwaysAhead` | B starts cheaper and stays cheaper — no crossover |
| `noCrossingWithinHorizon` | the gap is narrowing but does not close inside the simulated period |
| `identical` | the two cost the same throughout |
| `insufficientData` | inputs cannot support the question (e.g. zero distance) |

"Never catches up" is a real answer, not an error, and the UI says so.

`noCrossingWithinHorizon` is distinguished from "always ahead" by asking whether
the gap at the end of the simulation is smaller than at the start.

### Distance and date

```
breakEvenKm   = annualKm × month ÷ 12
breakEvenDate = startDate + month months
```

The start date is carried on the scenario rather than read from the clock, so
results are reproducible and testable.

### Energy-only break-even

The same analysis is always run a second time on acquisition + energy alone, with
financing, recurring costs and resale stripped out. This lets a user see the core
fuel-versus-electricity economics separately from softer assumptions.

---

## 11. Threshold (inverse) calculations

`ThresholdCalculator`

Answers *what value would put these two level at the horizon?* for: gas price,
blended electricity price, annual distance, and either purchase price.

Solved by **bisection over the same engine the results screen uses**, not by a
parallel closed form. The model stops being linear as soon as financing or resale
is involved, and maintaining two versions of the truth would let them drift.
Bisection needs no derivative, cannot diverge, and resolves these ranges well
below a cent in 50 iterations.

Each variable is searched over a bounded, documented range. When the same side is
cheaper at both ends of that range, there is no solution and the tool says so
plainly — "the B vehicle remains more expensive across the tested range" — rather
than extrapolating a fantasy number.

Solving for electricity price scales every charging source by a common factor, so
the home/public ratio the user chose is preserved.

**Every answer holds everything else constant.** These are sensitivities, not
predictions.

---

## 12. What FuelSmart deliberately does not do

| Not done | Why |
|---|---|
| Forecast fuel or electricity prices | No free, reliable, non-commercial source exists, and a wrong forecast would be worse than none. |
| Model depreciation | Same. Resale is the user's own assumption. |
| Supply vehicle prices | No free authoritative source. Prices are what the user will actually pay. |
| Convert between currencies | Regions are self-contained; a hard-coded rate is how the prototype went wrong. |
| Recommend a purchase | It reports costs under stated assumptions and lets the reader decide. |

---

## 13. Verification

- **Swift:** `Packages/FuelSmartCore/Tests/FuelSmartCoreTests` — energy, blending,
  PHEV, financing (including 0% APR and front-loading), acquisition, the
  sunk-cost rule, resale, all five break-even outcomes, thresholds, conversions,
  and degenerate inputs. Fixtures are hand-written and fixed, so no test depends
  on live government data.
- **Python:** `Scripts/test_pipeline.py` — parsing, unit normalization, record
  identity, duplicate handling, validation gates and emitted output.

Expected values in the tests were derived independently of the implementation
rather than recorded from a run, so they test the mathematics rather than the
code's memory of itself.
