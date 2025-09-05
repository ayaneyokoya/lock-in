//
//  ContentView.swift
//

import SwiftUI
import UIKit
import FirebaseFirestore

// MARK: - Domain Model
struct TaskItem: Identifiable, Codable, Equatable {
    var id: String?
    var title: String
    var isDone: Bool = false
    var createdAt: Date = .now
    var details: String? = nil

    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isDone == rhs.isDone &&
        lhs.createdAt == rhs.createdAt &&
        lhs.details == rhs.details
    }
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
                self?.tasks = docs.compactMap { doc in
                    let data = doc.data()
                    let title = (data["title"] as? String) ?? ""
                    let isDone = (data["isDone"] as? Bool) ?? false

                    var created = Date()
                    if let ts = data["createdAt"] as? Timestamp {
                        created = ts.dateValue()
                    } else if let d = data["createdAt"] as? Date {
                        created = d
                    }

                    let details = data["details"] as? String

                    return TaskItem(
                        id: doc.documentID,
                        title: title,
                        isDone: isDone,
                        createdAt: created,
                        details: details
                    )
                }
            }
    }

    func add(_ title: String, details: String?) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var payload: [String: Any] = [
            "title": trimmed,
            "isDone": false,
            "createdAt": Timestamp(date: Date())
        ]
        if let d = details?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            payload["details"] = d
        }

        db.collection("tasks").addDocument(data: payload) { err in
            if let err = err { print("Add failed: \(err)") }
        }
    }
    func toggle(_ task: TaskItem) {
        guard let id = task.id else { return }
        db.collection("tasks").document(id).updateData(["isDone": !task.isDone]) { err in
            if let err = err { print("Toggle failed: \(err)") }
        }
    }

    func updateTitle(_ task: TaskItem, to newTitle: String) {
        guard let id = task.id else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        db.collection("tasks").document(id).updateData(["title": trimmed]) { err in
            if let err = err { print("Update failed: \(err)") }
        }
    }

    func updateDetails(_ task: TaskItem, to newDetails: String) {
        guard let id = task.id else { return }
        let trimmed = newDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow empty string to clear details
        db.collection("tasks").document(id).updateData(["details": trimmed]) { err in
            if let err = err { print("Update details failed: \(err)") }
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
    @State private var newDetails: String = ""
    @FocusState private var isTitleFocused: Bool
    @State private var newDetailsHeight: CGFloat = 32
    @State private var showCompletedSection: Bool = false
    @State private var newDetailsFocused: Bool = false

    // Editing state
    @State private var editingTask: TaskItem? = nil
    @State private var editedTitle: String = ""

    @State private var detailTask: TaskItem? = nil
    @State private var detailEditedTitle: String = ""
    @State private var detailEditedDetails: String = ""

    // Controls whether the details box is visible (animated)
    @State private var showDetails: Bool = false

    // Progress metrics
    private var totalCount: Int { store.tasks.count }
    private var doneCount: Int { store.tasks.filter { $0.isDone }.count }
    private var progress: Double { totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount) }

    var body: some View {
        NavigationStack {
            ZStack {
                // Subtle gradient background for a modern look
                LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    if totalCount > 0 {
                        ProgressHeader(done: doneCount, total: totalCount, progress: progress)
                            .padding(.horizontal)
                    }
                    // Add bar
                    HStack(spacing: 10) {
                        TextField("Add a task…", text: $newTitle)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .onSubmit(add)
                            .focused($isTitleFocused)
                            .onChange(of: newTitle) { oldValue, newValue in
                                let shouldShow = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                if shouldShow != showDetails {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showDetails = shouldShow
                                    }
                                }
                            }

                        Button {
                            add()
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)

                    Group {
                        if showDetails {
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                                AutoGrowingTextEditor(text: $newDetails,
                                                      calculatedHeight: $newDetailsHeight,
                                                      isFocused: $newDetailsFocused,
                                                      maxHeight: 140)
                                    .padding(8)
                                    .frame(height: max(32, newDetailsHeight))
                                if newDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Add details…")
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .allowsHitTesting(false)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(.tertiaryLabel), lineWidth: 0.5)
                            )
                            .padding(.horizontal)
                            .transition(.opacity)
                        }
                    }

                    // Task list
                    List {
                        // Active (to-do) tasks
                        Section {
                            ForEach(store.tasks.filter { !$0.isDone }) { task in
                                TaskRow(task: task,
                                        onToggle: { store.toggle(task) },
                                        onOpenDetails: {
                                            detailTask = task
                                            detailEditedTitle = task.title
                                            detailEditedDetails = task.details ?? ""
                                        })
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            store.remove(task)
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text("To Do")
                        } footer: {
                            Text("Tap a task to view or edit details.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        // Completed (collapsible)
                        if !store.tasks.filter({ $0.isDone }).isEmpty {
                            Section {
                                if showCompletedSection {
                                    ForEach(store.tasks.filter { $0.isDone }) { task in
                                        TaskRow(task: task,
                                                onToggle: { store.toggle(task) },
                                                onOpenDetails: {
                                                    detailTask = task
                                                    detailEditedTitle = task.title
                                                    detailEditedDetails = task.details ?? ""
                                                })
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) {
                                                    store.remove(task)
                                                } label: { Label("Delete", systemImage: "trash") }
                                            }
                                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                            .listRowBackground(Color.clear)
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            } header: {
                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                        showCompletedSection.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: showCompletedSection ? "chevron.down" : "chevron.right")
                                        Text("Completed")
                                        Spacer()
                                        Text("\(store.tasks.filter({ $0.isDone }).count)")
                                            .font(.caption2).bold()
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule().fill(Color(.tertiarySystemFill))
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden) // show our gradient instead of list bg
                }
            }
            .navigationTitle("Lock In")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
        }
        // Polished edit sheet
        .sheet(item: $editingTask) { task in
            EditTaskSheetModern(title: $editedTitle) {
                store.updateTitle(task, to: editedTitle)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $detailTask) { task in
            TaskDetailsSheet(title: $detailEditedTitle, details: $detailEditedDetails) {
                store.updateTitle(task, to: detailEditedTitle)
                store.updateDetails(task, to: detailEditedDetails)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func add() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(trimmed, details: newDetails)
        newTitle = ""
        newDetails = ""
        isTitleFocused = false
        showDetails = false
    }
}

// MARK: - Row
private struct TaskRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let task: TaskItem
    let onToggle: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.large)
                    .symbolEffect(.bounce, value: task.isDone)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .font(.body)
                .lineLimit(2)
                .strikethrough(task.isDone, pattern: .solid, color: .secondary)
                .foregroundStyle(task.isDone ? .secondary : .primary)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 12, x: 0, y: 6)
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetails() }
    }
}

private struct ProgressHeader: View {
    let done: Int
    let total: Int
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Progress", systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                Spacer()
                Text(total > 0 ? "\(Int((progress * 100).rounded()))%" : "0%")
                    .font(.caption2).monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding(12)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.6), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Modern Edit Sheet View
private struct EditTaskSheetModern: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("Task title", text: $title)
                        .autocorrectionDisabled(false)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Task Details Sheet
private struct TaskDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    @Binding var details: String
    var onSave: () -> Void

    @State private var editorHeight: CGFloat = 90
    @State private var detailsIsFocused: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title").font(.footnote).foregroundStyle(.secondary)
                    TextField("Task title", text: $title)
                        .autocorrectionDisabled(false)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Details").font(.footnote).foregroundStyle(.secondary)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                        AutoGrowingTextEditor(text: $details,
                                              calculatedHeight: $editorHeight,
                                              isFocused: $detailsIsFocused,
                                              maxHeight: 240)
                            .padding(8)
                            .frame(height: max(90, editorHeight))
                        if details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Add more context, steps, or notes…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 14)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(.tertiaryLabel), lineWidth: 0.5)
                    )
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        hideKeyboard()
                    }
                }
            }
        }
    }
}

// MARK: - Auto-Growing TextEditor (UIKit-backed)
private struct AutoGrowingTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var calculatedHeight: CGFloat
    @Binding var isFocused: Bool
    var maxHeight: CGFloat? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = true
        tv.backgroundColor = .clear
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.delegate = context.coordinator
        tv.textContainerInset = UIEdgeInsets(top: 11, left: 1, bottom: 2, right: 0)
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.keyboardDismissMode = .interactive
        let tb = UIToolbar()
        tb.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Done", style: .done, target: context.coordinator, action: #selector(Coordinator.doneTapped))
        ]
        tb.sizeToFit()
        tv.inputAccessoryView = tb
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if isFocused {
            if !uiView.isFirstResponder { uiView.becomeFirstResponder() }
        } else {
            if uiView.isFirstResponder { uiView.resignFirstResponder() }
        }
        Self.recalculateHeight(view: uiView, result: $calculatedHeight, maxHeight: maxHeight)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $calculatedHeight, isFocused: $isFocused, maxHeight: maxHeight)
    }

    static func recalculateHeight(view: UITextView, result: Binding<CGFloat>, maxHeight: CGFloat?) {
        let fitted = view.sizeThatFits(CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)).height
        let clamped = maxHeight.map { min(fitted, $0) } ?? fitted
        if result.wrappedValue != clamped {
            DispatchQueue.main.async {
                result.wrappedValue = clamped
            }
        }
        // Only allow internal scrolling when content exceeds the cap
        if let mh = maxHeight {
            view.isScrollEnabled = fitted > mh - 0.5
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var height: Binding<CGFloat>
        var isFocused: Binding<Bool>
        var maxHeight: CGFloat?

        init(text: Binding<String>, height: Binding<CGFloat>, isFocused: Binding<Bool>, maxHeight: CGFloat?) {
            self.text = text
            self.height = height
            self.isFocused = isFocused
            self.maxHeight = maxHeight
        }

        func textViewDidChange(_ textView: UITextView) {
            self.text.wrappedValue = textView.text
            AutoGrowingTextEditor.recalculateHeight(view: textView, result: height, maxHeight: maxHeight)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused.wrappedValue = false
        }

        @objc func doneTapped() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

private extension View {
    func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

#Preview {
    ContentView()
}
