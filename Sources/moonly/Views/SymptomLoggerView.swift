import SwiftUI

/// Collapsible quick-log surface: period + flow, symptoms, mood, and energy.
/// Collapsed by default (with a summary of what's logged) to keep the dropdown
/// compact; tap to expand and log.
struct SymptomLoggerView: View {
    @EnvironmentObject var store: CycleStore
    let date: Date

    @State private var expanded = false
    @State private var showingCustomSymptomField = false
    @State private var customSymptomName = ""
    @State private var showingNotes = false

    private static let notesMaxLength = 200

    private var today: DailyLog { store.log(on: date) }
    private let chipColumns = [GridItem(.adaptive(minimum: 92), spacing: 6)]

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content.padding(.top, 8)
        } label: {
            label
        }
        .disclosureGroupStyle(.automatic)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Collapsed label / summary

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            Text("Log today").font(.callout.weight(.semibold))
            Spacer()
            summary.font(.callout)
        }
    }

    @ViewBuilder private var summary: some View {
        if today.isEmpty {
            Text("Nothing yet").foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                if today.isPeriod {
                    Text("💧")
                    if let f = today.flow { FlowDots(level: f.dots) }
                }
                ForEach(Array(today.symptoms).prefix(4)) { Text($0.emoji) }
                if today.symptoms.count > 4 {
                    Text("+\(today.symptoms.count - 4)").foregroundStyle(.tertiary).font(.caption)
                }
                if let m = today.mood { Text(m.emoji) }
                if let e = today.energy { Text(e.emoji) }
            }
        }
    }

    // MARK: - Expanded content

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Period + flow
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Period")
                HStack {
                    Chip(label: today.isPeriod ? "Bleeding" : "Log period",
                         systemImage: "drop.fill",
                         isOn: today.isPeriod,
                         tint: CyclePhase.menstrual.tint) {
                        store.setPeriod(!today.isPeriod, flow: today.flow, on: date)
                    }
                    Spacer()
                    if today.isPeriod {
                        HStack(spacing: 6) {
                            ForEach(Flow.allCases) { flow in
                                Button { store.setPeriod(true, flow: flow, on: date) } label: {
                                    FlowDots(level: flow.dots)
                                        .padding(.vertical, 5).padding(.horizontal, 7)
                                        .background(
                                            Capsule().fill(today.flow == flow
                                                ? CyclePhase.menstrual.tint.opacity(0.20)
                                                : Color.primary.opacity(0.06)))
                                }
                                .buttonStyle(.plain)
                                .help(flow.label)
                            }
                        }
                    }
                }
            }

            // Symptoms
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Symptoms")
                LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 6) {
                    ForEach(store.allSymptoms) { symptom in
                        Chip(label: symptom.label,
                             leading: symptom.emoji,
                             isOn: today.symptoms.contains(symptom)) {
                            store.toggleSymptom(symptom, on: date)
                        }
                    }
                }

                if showingCustomSymptomField {
                    HStack(spacing: 6) {
                        TextField("Symptom name", text: $customSymptomName)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                            .onSubmit { addCustomSymptom() }
                        Button("Add") { addCustomSymptom() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(customSymptomName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") {
                            showingCustomSymptomField = false
                            customSymptomName = ""
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } else {
                    Button {
                        showingCustomSymptomField = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add custom symptom")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }

            // Mood
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Mood")
                LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 6) {
                    ForEach(Mood.allCases) { mood in
                        Chip(label: mood.label, leading: mood.emoji,
                             isOn: today.mood == mood) {
                            store.setMood(mood, on: date)
                        }
                    }
                }
            }

            // Energy
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Energy")
                HStack(spacing: 6) {
                    ForEach(Energy.allCases) { energy in
                        Chip(label: energy.label, leading: energy.emoji,
                             isOn: today.energy == energy) {
                            store.setEnergy(energy, on: date)
                        }
                    }
                    Spacer()
                }
            }

            // Notes
            if showingNotes || !today.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Notes")
                    TextEditor(text: Binding(
                        get: { today.notes },
                        set: { newValue in
                            let clamped = String(newValue.prefix(Self.notesMaxLength))
                            store.mutate(date) { $0.notes = clamped }
                        }
                    ))
                    .font(.callout)
                    .frame(minHeight: 48, maxHeight: 80)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.1)))

                    Text("\(today.notes.count)/\(Self.notesMaxLength)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                Button {
                    showingNotes = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add a note")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private func addCustomSymptom() {
        let name = customSymptomName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.addCustomSymptom(name)
        customSymptomName = ""
        showingCustomSymptomField = false
    }
}
