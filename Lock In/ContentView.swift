//
//  ContentView.swift
//  Lock In
//
//  Created by Ayane Yokoya on 9/4/25.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Domain Model
struct TaskItem: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var isDone: Bool = false
    var createdAt: Date = .now
}

// MARK: - Firestore Store
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    init() {
        listen()
    }

    deinit {
        listener?.remove()
    }

    private func listen() {
        listener = db.collection("tasks")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let docs = snapshot?.documents, error == nil else {
                    print("Snapshot error: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                self?.tasks = docs.compactMap { try? $0.data(as: TaskItem.self) }
            }
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let t = TaskItem(title: trimmed, isDone: false, createdAt: .now)
        do {
            _ = try db.collection("tasks").addDocument(from: t)
        } catch {
            print("Add failed: \(error)")
        }
    }

    func toggle(_ task: TaskItem) {
        guard let id = task.id else { return }
        db.collection("tasks").document(id).updateData(["isDone": !task.isDone]) { err in
            if let err = err { print("Toggle failed: \(err)") }
        }
    }

    func remove(_ task: TaskItem) {
        guard let id = task.id else { return }
        db.collection("tasks").document(id).delete { err in
            if let err = err { print("Delete failed: \(err)") }
        }
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject private var store = TaskStore()
    @State private var newTitle: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Add a task...", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .onSubmit(add)

                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)

                List {
                    ForEach(store.tasks) { task in
                        HStack {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            Text(task.title)
                                .strikethrough(task.isDone)
                                .foregroundStyle(task.isDone ? .secondary : .primary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { store.toggle(task) }
                    }
                    .onDelete { idxSet in
                        idxSet.map { store.tasks[$0] }.forEach { store.remove($0) }
                    }
                }
            }
            .navigationTitle("Lock In")
        }
    }

    private func add() {
        store.add(newTitle)
        newTitle = ""
    }
}

#Preview {
    ContentView()
}
