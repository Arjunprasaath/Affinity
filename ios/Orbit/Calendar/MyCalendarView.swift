// MyCalendarView.swift — Owner: Teammate C. PLACEHOLDER: replace with the day timeline + EventKit export.
// Data: APIClient.shared.schedule(pid:) returns Schedule (items + free blocks).

import SwiftUI

struct MyCalendarView: View {
    @Environment(AppState.self) private var appState
    @State private var schedule: Schedule?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let schedule {
                    Section("Saved talks") {
                        ForEach(schedule.items) { item in
                            HStack {
                                Text(item.start.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                                Text(item.title).foregroundStyle(item.clash ? .red : .primary)
                            }
                        }
                    }
                    Section("Free") {
                        ForEach(schedule.free) { block in
                            Text("\(block.start.formatted(date: .omitted, time: .shortened)) – \(block.end.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                }
            }
            .overlay {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding() }
            }
            .navigationTitle("My calendar")
            .task {
                guard let pid = appState.profile?.pid else { return }
                do { schedule = try await APIClient.shared.schedule(pid: pid) } catch { errorMessage = error.localizedDescription }
            }
        }
    }
}
