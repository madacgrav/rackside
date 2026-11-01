import SwiftUI

struct ClientDetailView: View {
    @State var viewModel: ClientDetailViewModel
    @State private var showingEdit = false
    @State private var confirmingArchive = false
    @State private var screeningSheet: ScreeningSheet?
    @State private var assessmentSheet: AssessmentSheet?
    /// Created once in `.task`, so share-sheet state survives reloads.
    @State private var waiverViewModel: ClientWaiverViewModel?
    @State private var showingIntake = false
    @AppStorage("defaultWeightUnit") private var defaultWeightUnit: String = Unit.lb.rawValue

    private var weightUnit: Unit { Unit(rawValue: defaultWeightUnit) ?? .lb }

    /// Which assessment the sheet edits (nil = a new one).
    private struct AssessmentSheet: Identifiable {
        let id = UUID()
        let existing: AssessmentDTO?
    }

    /// Which screening the sheet edits (nil = a new one).
    private struct ScreeningSheet: Identifiable {
        let id = UUID()
        let existing: HealthScreeningDTO?
    }

    var body: some View {
        List {
            ErrorBanner(message: viewModel.errorMessage)
                .themedRows()
            Section("Contact") {
                if !viewModel.client.isSelf {
                    LabeledContent("Phone", value: viewModel.client.phoneE164)
                }
                if let goal = viewModel.client.goal {
                    LabeledContent("Goal", value: goal)
                }
                if let injuries = viewModel.client.injuries {
                    LabeledContent("Injuries", value: injuries)
                }
                if let notes = viewModel.client.notes {
                    LabeledContent("Notes", value: notes)
                }
            }
            .themedRows()
            if viewModel.client.hasProfile {
                Section("Profile") {
                    if let dob = viewModel.client.dateOfBirth {
                        LabeledContent("Age", value: Self.ageText(dob))
                    }
                    if let occupation = viewModel.client.occupation {
                        LabeledContent("Occupation", value: occupation)
                    }
                    if let history = viewModel.client.trainingHistory {
                        LabeledContent("Training history", value: history)
                    }
                    if let availability = viewModel.client.availability {
                        LabeledContent("Availability", value: availability)
                    }
                    if let emergency = Self.contactText(
                        name: viewModel.client.emergencyName,
                        detail: viewModel.client.emergencyRelationship,
                        phone: viewModel.client.emergencyPhoneE164
                    ) {
                        LabeledContent("Emergency", value: emergency)
                    }
                    if let physician = Self.contactText(
                        name: viewModel.client.physicianName,
                        detail: nil,
                        phone: viewModel.client.physicianPhoneE164
                    ) {
                        LabeledContent("Physician", value: physician)
                    }
                }
                .themedRows()
            }
            Section("Health & Clearance") {
                ClearanceBadge(status: viewModel.clearance)
                if viewModel.screeningReviewDue {
                    Label("Screening is over 12 months old — review it", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(Theme.Colors.warning)
                }
                if let latest = viewModel.screenings.first {
                    Button {
                        screeningSheet = ScreeningSheet(existing: latest)
                    } label: {
                        LabeledContent("Latest screening", value: latest.completedOn.formatted(date: .abbreviated, time: .omitted))
                    }
                    .foregroundStyle(.primary)
                }
                Button("New screening", systemImage: "plus") {
                    screeningSheet = ScreeningSheet(existing: nil)
                }
            }
            .themedRows()
            if let waiverViewModel {
                ClientWaiverSection(viewModel: waiverViewModel)
                    .themedRows()
            }
            Section("Assessments") {
                Button("New assessment", systemImage: "plus") {
                    assessmentSheet = AssessmentSheet(existing: nil)
                }
                ForEach(Array(viewModel.assessments.enumerated()), id: \.element.id) { index, assessment in
                    let previous = viewModel.assessments.indices.contains(index + 1) ? viewModel.assessments[index + 1] : nil
                    NavigationLink {
                        AssessmentDetailView(
                            assessment: assessment,
                            previous: previous,
                            weightUnit: weightUnit,
                            onEdit: { assessmentSheet = AssessmentSheet(existing: assessment) }
                        )
                    } label: {
                        TitleCaptionRow(
                            title: assessment.performedOn.formatted(date: .abbreviated, time: .omitted),
                            caption: assessment.sections.caption
                        )
                    }
                }
            }
            .themedRows()
            Section("Upcoming Sessions") {
                if viewModel.upcomingSessions.isEmpty {
                    Text("Nothing scheduled").foregroundStyle(.secondary)
                }
                ForEach(viewModel.upcomingSessions) { session in
                    sessionLink(session)
                }
            }
            .themedRows()
            Section("Recent Sessions") {
                if viewModel.recentSessions.isEmpty {
                    Text("No sessions yet").foregroundStyle(.secondary)
                }
                ForEach(viewModel.recentSessions) { session in
                    sessionLink(session)
                }
            }
            .themedRows()
            Section("Progress Reports") {
                NavigationLink("View progress") {
                    ClientReportView(viewModel: ClientReportViewModel(
                        reporting: viewModel.reporting,
                        exerciseRepo: viewModel.exerciseRepo,
                        client: viewModel.client
                    ))
                }
            }
            .themedRows()
            if viewModel.client.isArchived {
                Section {
                    Label("This client is archived", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                }
                .themedRows()
            }
        }
        .themedScreen()
        .navigationTitle(viewModel.client.isSelf ? "\(viewModel.client.name) (You)" : viewModel.client.name)
        .toolbar {
            Menu {
                Button("Edit") { showingEdit = true }
                if !viewModel.client.isSelf {
                    Button("Start intake", systemImage: "list.bullet.clipboard") { showingIntake = true }
                }
                Button(
                    viewModel.client.isArchived ? "Unarchive" : "Archive",
                    systemImage: "archivebox"
                ) {
                    confirmingArchive = true
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
            }
            .accessibilityLabel("More actions")
        }
        .confirmationDialog(
            viewModel.client.isArchived ? "Unarchive \(viewModel.client.name)?" : "Archive \(viewModel.client.name)?",
            isPresented: $confirmingArchive,
            titleVisibility: .visible
        ) {
            Button(
                viewModel.client.isArchived ? "Unarchive" : "Archive",
                role: viewModel.client.isArchived ? nil : .destructive
            ) {
                Task { await viewModel.toggleArchived() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.client.isArchived
                 ? "The client returns to the roster and the client picker."
                 : "Archived clients leave the roster and the client picker. Their history is kept.")
        }
        .sheet(isPresented: $showingEdit) {
            ClientEditView(repo: viewModel.repository, existing: viewModel.client) {
                Task { await viewModel.reload() }
            }
        }
        .sheet(item: $screeningSheet) { sheet in
            HealthScreeningEditView(
                repo: viewModel.intake.health,
                clientId: viewModel.client.id,
                existing: sheet.existing
            ) {
                Task { await viewModel.reload() }
            }
        }
        .sheet(isPresented: $showingIntake) {
            IntakeFlowView(
                viewModel: IntakeFlowViewModel(
                    client: viewModel.client,
                    clientRepo: viewModel.repository,
                    intake: viewModel.intake,
                    weightUnit: weightUnit
                ),
                onFinished: {
                    Task {
                        await viewModel.reload()
                        await waiverViewModel?.load()
                    }
                }
            )
        }
        .sheet(item: $assessmentSheet) { sheet in
            AssessmentEditView(
                repo: viewModel.intake.assessments,
                clientId: viewModel.client.id,
                existing: sheet.existing,
                weightUnit: weightUnit
            ) {
                Task { await viewModel.reload() }
            }
        }
        .task {
            if waiverViewModel == nil {
                waiverViewModel = ClientWaiverViewModel(
                    repo: viewModel.intake.waivers, clientRepo: viewModel.repository, client: viewModel.client
                )
            }
            await viewModel.reload()
        }
    }

    /// "34 (Mar 4, 1991)".
    static func ageText(_ dob: Date, now: Date = .now) -> String {
        let years = Calendar.current.dateComponents([.year], from: dob, to: now).year ?? 0
        return "\(years) (\(dob.formatted(date: .abbreviated, time: .omitted)))"
    }

    /// "Alex Lee (Spouse) · +15551234567", or nil when nothing is set.
    static func contactText(name: String?, detail: String?, phone: String?) -> String? {
        var head = name ?? ""
        if let detail { head += head.isEmpty ? detail : " (\(detail))" }
        let parts = [head, phone ?? ""].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func sessionLink(_ session: SessionDTO) -> some View {
        NavigationLink {
            SessionRunView(viewModel: SessionRunViewModel(
                sessionRepo: viewModel.sessionRepo,
                exerciseRepo: viewModel.exerciseRepo,
                clientRepo: viewModel.repository,
                session: session,
                clientName: viewModel.client.name,
                clientPhone: viewModel.client.phoneE164,
                clientInjuries: viewModel.client.injuries,
                healthRepo: viewModel.intake.health,
                onStatusChanged: { await viewModel.reload() }
            ))
        } label: {
            SessionRow(session: session, clientName: session.startAt.formatted(date: .abbreviated, time: .omitted))
        }
    }
}

#Preview("Client detail") {
    let repos = PreviewFixtures.repositories()
    NavigationStack {
        ClientDetailView(viewModel: ClientDetailViewModel(
            repo: repos.clients,
            exerciseRepo: repos.exercises,
            sessionRepo: repos.sessions,
            reporting: repos.reporting,
            reminders: repos.reminders,
            intake: repos.intake,
            client: PreviewFixtures.client
        ))
    }
}
