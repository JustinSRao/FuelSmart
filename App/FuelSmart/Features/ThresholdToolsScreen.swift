import SwiftUI
import FuelSmartCore

/// "What would change this?" — each line answers a question in reverse.
///
/// Every answer holds everything else constant. They are sensitivities, not
/// predictions: no fuel or electricity price forecast is built into FuelSmart.
struct ThresholdToolsScreen: View {

    let scenario: ComparisonScenario

    @Environment(\.fsTheme) private var theme

    @State private var outcomes: [ThresholdCalculator.Variable: ThresholdCalculator.Outcome] = [:]
    @State private var isCalculating = true

    private let solver = ThresholdCalculator()
    private var formatter: ValueFormatter { ValueFormatter(region: scenario.region) }
    private var horizonYears: Int { Int(scenario.horizon.years) }

    private var nameA: String { scenario.sideA.vehicle.shortDisplayName }
    private var nameB: String { scenario.sideB.vehicle.shortDisplayName }

    /// Only the variables that are meaningful for these two vehicles.
    private var variables: [ThresholdCalculator.Variable] {
        var list: [ThresholdCalculator.Variable] = []
        let usesFuel = scenario.sideA.vehicle.powertrain.usesLiquidFuel
            || scenario.sideB.vehicle.powertrain.usesLiquidFuel
        let usesElectricity = scenario.sideA.vehicle.powertrain.usesElectricity
            || scenario.sideB.vehicle.powertrain.usesElectricity

        if usesFuel { list.append(.gasolinePricePerLitre) }
        list.append(.annualKilometres)
        if !scenario.sideB.isAlreadyOwned { list.append(.purchasePriceB) }
        if usesElectricity { list.append(.blendedElectricityPricePerKWh) }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                intro

                if isCalculating {
                    ForEach(0..<3, id: \.self) { _ in
                        FSCard { FSSkeleton(height: 54) }
                    }
                } else {
                    ForEach(variables, id: \.self) { variable in
                        thresholdCard(variable)
                    }
                }

                FSInsightCard(
                    kind: .caveat,
                    label: "How to read these",
                    message: "Each answer holds everything else constant. They are sensitivities, not predictions — no fuel or electricity price forecast is built into FuelSmart.",
                    systemImage: "info.circle"
                )
            }
            .padding(.horizontal, Nocturne.Space.gutter)
            .padding(.bottom, 32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle("What would change this")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await solve() }
    }

    private var intro: some View {
        Text("Each line answers a question in reverse: what value would put the two vehicles level at your \(horizonYears)-year horizon?")
            .font(FSFont.footnote)
            .foregroundStyle(theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private func thresholdCard(_ variable: ThresholdCalculator.Variable) -> some View {
        FSCard {
            VStack(alignment: .leading, spacing: 7) {
                Label(title(for: variable), systemImage: icon(for: variable))
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)

                Text(sentence(for: variable))
                    .font(FSFont.body)
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(currentValueSentence(for: variable))
                    .font(FSFont.footnote)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Copy

    private func title(for variable: ThresholdCalculator.Variable) -> String {
        switch variable {
        case .gasolinePricePerLitre: "Break-even fuel price"
        case .blendedElectricityPricePerKWh: "Break-even electricity price"
        case .annualKilometres: "Break-even distance"
        case .purchasePriceB, .purchasePriceA: "Break-even purchase price"
        }
    }

    private func icon(for variable: ThresholdCalculator.Variable) -> String {
        switch variable {
        case .gasolinePricePerLitre: "fuelpump"
        case .blendedElectricityPricePerKWh: "bolt"
        case .annualKilometres: "road.lanes"
        case .purchasePriceB, .purchasePriceA: "tag"
        }
    }

    /// The sentence naming the threshold, written so neither vehicle is implied
    /// to be the right choice.
    private func sentence(for variable: ThresholdCalculator.Variable) -> String {
        guard let outcome = outcomes[variable] else { return "Calculating…" }

        switch outcome {
        case .solution(let value):
            switch variable {
            case .gasolinePricePerLitre:
                return "Fuel would have to average \(formatter.fuelPrice(value)) for the two to come out level within \(horizonYears) years."
            case .blendedElectricityPricePerKWh:
                return "Blended charging could reach \(formatter.electricityPrice(value)) before the two come out level within \(horizonYears) years."
            case .annualKilometres:
                return "You'd need to drive about \(formatter.approximateDistance(value)) a year for the two to come out level within \(horizonYears) years."
            case .purchasePriceB:
                return "At \(formatter.currency(value)) the \(nameB) would be level with the \(nameA) at \(horizonYears) years."
            case .purchasePriceA:
                return "At \(formatter.currency(value)) the \(nameA) would be level with the \(nameB) at \(horizonYears) years."
            }

        case .noSolutionInRange(let cheaper, let searched):
            let cheaperName = cheaper == .a ? nameA : nameB
            let otherName = cheaper == .a ? nameB : nameA
            let rangeText = describe(searched, for: variable)
            return "The \(otherName) stays more expensive than the \(cheaperName) across the whole tested range (\(rangeText)). No value in that range brings them level at \(horizonYears) years."

        case .alreadyLevel:
            return "These two are already level at \(horizonYears) years, so there is nothing to solve for."

        case .insufficientData:
            return "There isn't enough information to answer this yet."
        }
    }

    private func describe(_ range: ClosedRange<Double>, for variable: ThresholdCalculator.Variable) -> String {
        switch variable {
        case .gasolinePricePerLitre:
            "\(formatter.fuelPrice(range.lowerBound)) to \(formatter.fuelPrice(range.upperBound))"
        case .blendedElectricityPricePerKWh:
            "\(formatter.electricityPrice(range.lowerBound)) to \(formatter.electricityPrice(range.upperBound))"
        case .annualKilometres:
            "\(formatter.distance(range.lowerBound)) to \(formatter.distance(range.upperBound)) a year"
        case .purchasePriceB, .purchasePriceA:
            "\(formatter.currency(range.lowerBound)) to \(formatter.currency(range.upperBound))"
        }
    }

    private func currentValueSentence(for variable: ThresholdCalculator.Variable) -> String {
        switch variable {
        case .gasolinePricePerLitre:
            "You entered \(formatter.fuelPrice(scenario.energyPrices.gasolinePricePerLitre))."
        case .blendedElectricityPricePerKWh:
            "Your blend is \(formatter.electricityPrice(scenario.energyPrices.blendedElectricityPricePerKWh))."
        case .annualKilometres:
            "You entered \(formatter.distance(scenario.driving.annualKilometres)) a year."
        case .purchasePriceB:
            "Asking price \(formatter.currency(scenario.sideB.acquisition.purchasePrice))."
        case .purchasePriceA:
            "Asking price \(formatter.currency(scenario.sideA.acquisition.purchasePrice))."
        }
    }

    // MARK: - Solving

    /// Each threshold is ~50 evaluations of the full engine, so the set is solved
    /// off the main actor and delivered once rather than blocking the first frame.
    private func solve() async {
        let scenario = self.scenario
        let variables = self.variables
        let solver = self.solver

        let solved = await Task.detached(priority: .userInitiated) {
            var results: [ThresholdCalculator.Variable: ThresholdCalculator.Outcome] = [:]
            for variable in variables {
                results[variable] = solver.solve(for: variable, in: scenario)
            }
            return results
        }.value

        outcomes = solved
        isCalculating = false
    }
}
