import SwiftUI
import FuelSmartCore

/// Price, acquisition extras, financing, recurring costs and resale for one side.
///
/// The screen opens with the one field that matters — what you will actually pay
/// — and hides everything else behind disclosure rows, so a user who only has a
/// price can finish in one tap.
struct CostInputScreen: View {

    @Bindable var draft: ComparisonDraft
    let side: ComparisonSideIdentifier

    @Environment(AppModel.self) private var model
    @Environment(\.fsTheme) private var theme

    @State private var showTradeIn = false
    @State private var showIncentives = false
    @State private var showFees = false
    @State private var showCharger = false
    @State private var showFinancing = false
    @State private var showRecurring = false
    @State private var showResale = false

    /// The kept vehicle in keep-vs-replace has no acquisition cost at all, so
    /// the price section is replaced by an explanation rather than shown and
    /// then ignored by the engine.
    private var isSunkCost: Bool { draft.mode == .keepVsReplace && side == .a }

    private var formatter: ValueFormatter { ValueFormatter(region: draft.region) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let vehicle = draft.vehicle(for: side) {
                    FSVehicleBadge(vehicle: vehicle, isAccented: side == .b, formatter: formatter)
                }

                if isSunkCost {
                    sunkCostExplanation
                } else {
                    priceCard
                    financingCard
                }

                recurringCard
                resaleCard

                if draft.vehicle(for: side)?.powertrain == .phev {
                    phevCard
                }
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle(draft.label(for: side))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Sunk cost

    private var sunkCostExplanation: some View {
        FSInsightCard(
            kind: .caveat,
            label: "Sunk cost",
            message: "You already own this vehicle, so what you paid for it is not charged again. Only what it costs you from here — energy, and any ownership costs you add below — counts against keeping it. Its trade-in value belongs to the replacement.",
            systemImage: "info.circle"
        )
    }

    // MARK: - Price

    private var priceCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("What will you actually pay for this vehicle?")
                        .font(FSFont.headline)
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Negotiated new price, used asking price, private sale — whatever is real for you. Government data doesn't know your deal.")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                FSMoneyField(
                    label: "Vehicle price",
                    value: binding(\.purchasePrice),
                    currencyCode: formatter.currencyCode,
                    isProminent: true,
                    isOptional: false
                )

                VStack(spacing: 10) {
                    FSDisclosureRow(
                        label: "Taxes & fees",
                        value: optionalDisplay(acquisition.salesTax + acquisition.dealerFees + acquisition.otherOneTimeFees),
                        isExpanded: $showFees
                    ) {
                        VStack(spacing: 10) {
                            FSMoneyField(label: "Sales tax", value: binding(\.salesTax), currencyCode: formatter.currencyCode)
                            FSMoneyField(label: "Dealer / admin fees", value: binding(\.dealerFees), currencyCode: formatter.currencyCode)
                            FSMoneyField(label: "Other one-time fees", value: binding(\.otherOneTimeFees), currencyCode: formatter.currencyCode)
                        }
                    }

                    FSDisclosureRow(
                        label: "Rebates & incentives",
                        value: optionalDisplay(-(acquisition.rebate + acquisition.governmentIncentive + acquisition.manufacturerIncentive)),
                        isExpanded: $showIncentives
                    ) {
                        VStack(spacing: 10) {
                            FSMoneyField(label: "Rebate", value: binding(\.rebate), currencyCode: formatter.currencyCode)
                            FSMoneyField(label: "Government incentive", value: binding(\.governmentIncentive), currencyCode: formatter.currencyCode)
                            FSMoneyField(label: "Manufacturer incentive", value: binding(\.manufacturerIncentive), currencyCode: formatter.currencyCode)
                        }
                    }

                    FSDisclosureRow(
                        label: "Trade-in value",
                        value: optionalDisplay(-acquisition.tradeInValue),
                        isExpanded: $showTradeIn
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            FSMoneyField(
                                label: "Trade-in credit",
                                caption: draft.mode == .keepVsReplace
                                    ? "What a dealer will give you for the vehicle you own today."
                                    : nil,
                                value: binding(\.tradeInValue),
                                currencyCode: formatter.currencyCode
                            )
                        }
                    }

                    FSDisclosureRow(
                        label: "Charger & electrical",
                        value: optionalDisplay(acquisition.homeChargerInstallation + acquisition.electricalPanelUpgrade + acquisition.otherOneTimeCost),
                        isExpanded: $showCharger
                    ) {
                        VStack(spacing: 10) {
                            FSMoneyField(label: "Home charger installed", value: binding(\.homeChargerInstallation), currencyCode: formatter.currencyCode)
                            FSMoneyField(label: "Electrical panel upgrade", value: binding(\.electricalPanelUpgrade), currencyCode: formatter.currencyCode)
                            FSMoneyField(label: "Other one-time cost", value: binding(\.otherOneTimeCost), currencyCode: formatter.currencyCode)
                        }
                    }
                }

                Divider().overlay(theme.divider)

                HStack(alignment: .firstTextBaseline) {
                    Text("Net acquisition cost")
                        .font(FSFont.body)
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    Text(formatter.currency(acquisition.net))
                        .font(FSFont.figureMedium)
                        .foregroundStyle(side == .b ? theme.accentText : theme.text)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Financing

    private var financingCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("Financing")

                FSToggleRow(
                    title: "Finance this vehicle",
                    caption: "Off means a cash purchase.",
                    isOn: Binding(
                        get: { financing.isFinanced },
                        set: { isOn in
                            var updated = financing
                            updated.termMonths = isOn ? (updated.termMonths == 0 ? 60 : updated.termMonths) : 0
                            draft.setFinancing(updated, for: side)
                        }
                    )
                )

                if financing.isFinanced {
                    FSMoneyField(
                        label: "Down payment",
                        value: Binding(
                            get: { financing.downPayment == 0 ? nil : financing.downPayment },
                            set: { newValue in
                                var updated = financing
                                updated.downPayment = newValue ?? 0
                                draft.setFinancing(updated, for: side)
                            }
                        ),
                        currencyCode: formatter.currencyCode
                    )

                    FSNumberField(
                        label: "APR",
                        value: Binding(
                            get: { financing.annualPercentageRate * 100 },
                            set: { newValue in
                                var updated = financing
                                updated.annualPercentageRate = newValue / 100
                                draft.setFinancing(updated, for: side)
                            }
                        ),
                        unit: "%",
                        fractionDigits: 0...2,
                        plausibleRange: 0...30
                    )

                    FSNumberField(
                        label: "Term",
                        value: Binding(
                            get: { Double(financing.termMonths) },
                            set: { newValue in
                                var updated = financing
                                updated.termMonths = max(Int(newValue), 0)
                                draft.setFinancing(updated, for: side)
                            }
                        ),
                        unit: "months",
                        fractionDigits: 0...0,
                        plausibleRange: 6...120
                    )

                    financingSummary
                }
            }
        }
    }

    private var financingSummary: some View {
        let breakdown = FinancingCalculator.breakdown(
            acquisition: acquisition.net,
            financing: financing,
            months: draft.horizon.months_
        )
        return VStack(alignment: .leading, spacing: 8) {
            FSInsetRow(padding: 12) {
                HStack {
                    Text("Monthly payment")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.accentMuted)
                    Spacer()
                    Text(formatter.currency(breakdown.monthlyPayment))
                        .font(FSFont.figureMedium)
                        .foregroundStyle(theme.accentText)
                }
            }
            Text("Interest is added to total cost; the principal is not double-counted. Total interest over the full term is \(formatter.currency(breakdown.totalInterest)).")
                .font(FSFont.footnote)
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Recurring

    private var recurringCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("Ownership costs")
                Text("All optional. Leave them empty and FuelSmart compares purchase + energy only. Fill any of them and the result is relabelled estimated ownership cost.")
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                FSDisclosureRow(
                    label: "Annual costs",
                    value: recurring.isEnabled ? formatter.currency(recurring.annualTotal) : nil,
                    isExpanded: $showRecurring
                ) {
                    VStack(spacing: 10) {
                        FSMoneyField(label: "Insurance / year", value: recurringBinding(\.annualInsurance), currencyCode: formatter.currencyCode)
                        FSMoneyField(label: "Maintenance / year", value: recurringBinding(\.annualMaintenance), currencyCode: formatter.currencyCode)
                        FSMoneyField(label: "Registration / year", value: recurringBinding(\.annualRegistration), currencyCode: formatter.currencyCode)
                        FSMoneyField(label: "Parking / year", value: recurringBinding(\.annualParking), currencyCode: formatter.currencyCode)
                        FSMoneyField(label: "Other annual cost", value: recurringBinding(\.annualOther), currencyCode: formatter.currencyCode)
                    }
                }
            }
        }
    }

    // MARK: - Resale

    private var resaleCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("Resale")

                FSDisclosureRow(
                    label: "Expected resale at \(Int(draft.horizon.years)) years",
                    value: resale.map { formatter.currency($0.expectedValue) },
                    isExpanded: $showResale
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        FSMoneyField(
                            label: "Expected resale value",
                            caption: "Your assumption — FuelSmart does not forecast depreciation.",
                            value: Binding(
                                get: { resale?.expectedValue },
                                set: { newValue in
                                    guard let newValue else { setResale(nil); return }
                                    setResale(ResaleAssumption(
                                        expectedValue: newValue,
                                        isIncludedInTotals: resale?.isIncludedInTotals ?? true
                                    ))
                                }
                            ),
                            currencyCode: formatter.currencyCode
                        )

                        if let current = resale {
                            FSToggleRow(
                                title: "Subtract resale from totals",
                                caption: "Applied once at your horizon, never spread across the years.",
                                isOn: Binding(
                                    get: { current.isIncludedInTotals },
                                    set: { setResale(ResaleAssumption(expectedValue: current.expectedValue, isIncludedInTotals: $0)) }
                                )
                            )
                        }
                    }
                }

                FSInsightCard(
                    kind: .caveat,
                    label: "Assumption",
                    message: "Resale values are yours, not ours. FuelSmart does not forecast depreciation.",
                    systemImage: "info.circle"
                )
            }
        }
    }

    // MARK: - PHEV

    private var phevCard: some View {
        FSCard {
            VStack(alignment: .leading, spacing: 12) {
                FSSectionLabel("Plug-in hybrid · electric share")

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(phevShare.primaryPercent.rounded())) %")
                        .font(FSFont.display)
                        .foregroundStyle(theme.text)
                    Text("of distance driven on electricity")
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.secondaryText)
                }

                Slider(
                    value: Binding(
                        get: { phevShare.primaryPercent },
                        set: { draft.setPhevShare(Split(primaryPercent: $0), for: side) }
                    ),
                    in: 0...100, step: 5
                )
                .tint(theme.accent)
                .accessibilityLabel("Electric driving share")
                .accessibilityValue("\(Int(phevShare.primaryPercent.rounded())) percent")

                HStack {
                    Text("All gasoline").font(FSFont.footnote).foregroundStyle(theme.tertiaryText)
                    Spacer()
                    Text("All electric").font(FSFont.footnote).foregroundStyle(theme.tertiaryText)
                }

                if let estimate = phevEstimate {
                    Button {
                        draft.setPhevShare(estimate.split, for: side)
                    } label: {
                        FSInsetRow(padding: 11) {
                            HStack {
                                Text("Estimate it from my driving")
                                    .font(FSFont.footnote)
                                    .foregroundStyle(theme.text)
                                Spacer()
                                Text("\(Int(estimate.split.primaryPercent.rounded())) %")
                                    .font(FSFont.figureSmall)
                                    .foregroundStyle(theme.accentText)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Text(estimate.explanation)
                        .font(FSFont.footnote)
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var phevEstimate: (split: Split, explanation: String)? {
        guard let vehicle = draft.vehicle(for: side),
              let range = vehicle.efficiency.electricRangeKm,
              draft.driving.annualKilometres > 0 else { return nil }
        let daily = draft.driving.annualKilometres / 365.25
        guard let split = EnergyCostCalculator.estimatePHEVElectricShare(
            dailyKilometres: daily, electricRangeKm: range, chargesPerWeek: 7
        ) else { return nil }
        let explanation = "With \(formatter.distance(daily))/day, a \(formatter.distance(range)) electric range and nightly charging, roughly \(Int(split.primaryPercent.rounded())) % of your distance would be electric. Adjust if you charge less often."
        return (split, explanation)
    }

    // MARK: - Bindings

    private var acquisition: AcquisitionCost { draft.acquisition(for: side) }
    private var financing: FinancingProfile { draft.financing(for: side) }
    private var recurring: RecurringCostProfile { draft.recurring(for: side) }
    private var resale: ResaleAssumption? { side == .a ? draft.resaleA : draft.resaleB }
    private var phevShare: Split { draft.phevShare(for: side) }

    private func setResale(_ value: ResaleAssumption?) {
        if side == .a { draft.resaleA = value } else { draft.resaleB = value }
    }

    /// A binding to one money field of the acquisition record, mapping 0 to
    /// "empty" so an untouched optional field shows its placeholder.
    private func binding(_ keyPath: WritableKeyPath<AcquisitionCost, Double>) -> Binding<Double?> {
        Binding(
            get: {
                let value = draft.acquisition(for: side)[keyPath: keyPath]
                return value == 0 ? nil : value
            },
            set: { newValue in
                var updated = draft.acquisition(for: side)
                updated[keyPath: keyPath] = newValue ?? 0
                draft.setAcquisition(updated, for: side)
            }
        )
    }

    /// Recurring costs are genuinely optional, so this binding preserves nil.
    private func recurringBinding(_ keyPath: WritableKeyPath<RecurringCostProfile, Double?>) -> Binding<Double?> {
        Binding(
            get: { draft.recurring(for: side)[keyPath: keyPath] },
            set: { newValue in
                var updated = draft.recurring(for: side)
                updated[keyPath: keyPath] = newValue
                draft.setRecurring(updated, for: side)
            }
        )
    }

    private func optionalDisplay(_ value: Double) -> String? {
        value == 0 ? nil : formatter.currency(value)
    }
}
