import SwiftUI
import UIKit
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

// MARK: - Domain Model
struct TaskItem: Identifiable, Codable, Equatable {
    var id: String?
    var title: String
    var isDone: Bool = false
    var createdAt: Date = .now
    var details: String? = nil
    var category: String? = nil
    var dueDate: Date? = nil
    
    var boundLat: Double?
    var boundLon: Double?
    var boundPlace: String?

    static func == (lhs: TaskItem, rhs: TaskItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isDone == rhs.isDone &&
        lhs.createdAt == rhs.createdAt &&
        lhs.details == rhs.details &&
        lhs.category == rhs.category &&
        lhs.dueDate == rhs.dueDate
    }
}

// MARK: - Firestore Store
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var uid: String? = nil

    init() {
    }

    deinit {
        listener?.remove()
    }

    private func listen(for uid: String) {
        listener?.remove()
        listener = db.collection("users").document(uid).collection("tasks")
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
                    let category = data["category"] as? String
                    let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()

                    let boundLat = data["boundLat"] as? Double
                    let boundLon = data["boundLon"] as? Double
                    let boundPlace = data["boundPlace"] as? String

                    return TaskItem(
                        id: doc.documentID,
                        title: title,
                        isDone: isDone,
                        createdAt: created,
                        details: details,
                        category: category,
                        dueDate: dueDate,
                        boundLat: boundLat,
                        boundLon: boundLon,
                        boundPlace: boundPlace
                    )
                }
                .sorted { lhs, rhs in
                    let lDue = lhs.dueDate ?? .distantFuture
                    let rDue = rhs.dueDate ?? .distantFuture
                    if lDue != rDue { return lDue < rDue }
                    return lhs.createdAt < rhs.createdAt
                }
            }
    }

    func setUser(uid: String?) {
        self.uid = uid
        listener?.remove()
        tasks = []
        guard let uid else { return }
        listen(for: uid)
    }

    func add(_ title: String,
             details: String?,
             category: String?,
             dueDate: Date?,
             boundLat: Double? = nil,
             boundLon: Double? = nil,
             boundPlace: String? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let uid = uid else {
            print("Add aborted: no authenticated user")
            return
        }

        var payload: [String: Any] = [
            "title": trimmed,
            "isDone": false,
            "createdAt": Timestamp(date: Date())
        ]
        if let d = details?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            payload["details"] = d
        }
        if let c = category, !c.isEmpty { payload["category"] = c }          // NEW
        if let dd = dueDate { payload["dueDate"] = Timestamp(date: dd) }
        if let boundLat { payload["boundLat"] = boundLat }
        if let boundLon { payload["boundLon"] = boundLon }
        if let boundPlace, !boundPlace.isEmpty { payload["boundPlace"] = boundPlace }

        db.collection("users").document(uid).collection("tasks")
            .addDocument(data: payload) { err in
                if let err = err { print("Add failed: \(err)") }
            }
    }

    func toggle(_ task: TaskItem) {
        guard let id = task.id else { return }
        guard let uid = uid else { return }
        db.collection("users").document(uid).collection("tasks").document(id).updateData(["isDone": !task.isDone]) { err in
            if let err = err { print("Toggle failed: \(err)") }
        }
    }

    func updateTitle(_ task: TaskItem, to newTitle: String) {
        guard let id = task.id else { return }
        guard let uid = uid else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != task.title else { return }
        db.collection("users").document(uid).collection("tasks").document(id).updateData(["title": trimmed]) { err in
            if let err = err { print("Update failed: \(err)") }
        }
    }

    func updateDetails(_ task: TaskItem, to newDetails: String) {
        guard let id = task.id else { return }
        guard let uid = uid else { return }
        let trimmed = newDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        db.collection("users").document(uid).collection("tasks").document(id).updateData(["details": trimmed]) { err in
            if let err = err { print("Update details failed: \(err)") }
        }
    }

    func remove(_ task: TaskItem) {
        guard let id = task.id else { return }
        guard let uid = uid else { return }
        db.collection("users").document(uid).collection("tasks").document(id).delete { err in
            if let err = err { print("Delete failed: \(err)") }
        }
    }

    func clearCompleted() {
        let completed = tasks.filter { $0.isDone }
        guard !completed.isEmpty else { return }
        guard let uid = uid else { return }
        let batch = db.batch()
        for t in completed {
            if let id = t.id {
                let ref = db.collection("users").document(uid).collection("tasks").document(id)
                batch.deleteDocument(ref)
            }
        }
        batch.commit { err in
            if let err = err { print("Clear completed failed: \(err)") }
        }
    }
}

// MARK: - Auth
final class AuthViewModel: ObservableObject {
    @Published var user: FirebaseAuth.User? = Auth.auth().currentUser
    @Published var authError: String? = nil
    @Published var authInfo: String? = nil
    @Published var lastAuthError: NSError? = nil

    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
            }
        }
    }

    deinit { if let h = handle { Auth.auth().removeStateDidChangeListener(h) } }

    private func setAuthError(_ error: Error?) {
        if let err = error as NSError? {
            self.lastAuthError = err
            self.authError = AuthViewModel.humanMessage(for: err)
        } else {
            self.lastAuthError = nil
            self.authError = nil
        }
    }

    static func humanMessage(for err: NSError) -> String {
        // Confirm it’s an Auth error and convert to an AuthErrorCode
        guard err.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: err.code) else {
            return err.localizedDescription
        }

        switch code {
        case .invalidEmail:
            return "That email address looks invalid."
        case .emailAlreadyInUse:
            return "An account with this email already exists."
        case .weakPassword:
            return "Password is too weak. Try at least 8 characters with letters and numbers."
        case .wrongPassword,
                 .invalidCredential:
                return "The email address or password is incorrect. Please try again."
        case .networkError:
            return "Network error. Check your connection and try again."
        case .internalError:
            return "Authentication service had a hiccup. Try again in a moment."
        default:
            return err.localizedDescription
        }
    }

    func signIn(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            if let e = error as NSError? { print("Auth signIn error: \(e) userInfo=\(e.userInfo)") }
            DispatchQueue.main.async { self?.setAuthError(error) }
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String) {
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        if let current = Auth.auth().currentUser, current.isAnonymous {
            // Upgrade anonymous → permanent account (keeps same UID and tasks)
            current.link(with: credential) { [weak self] result, error in
                self?.finishProfileSetup(result: result, error: error, firstName: firstName, lastName: lastName, email: email)
            }
        } else {
            Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
                self?.finishProfileSetup(result: result, error: error, firstName: firstName, lastName: lastName, email: email)
            }
        }
    }

    private func finishProfileSetup(result: AuthDataResult?, error: Error?, firstName: String, lastName: String, email: String) {
        if let error = error {
            DispatchQueue.main.async { self.setAuthError(error) }
            return
        }
        guard let user = result?.user else { return }

        let change = user.createProfileChangeRequest()
        let fullName = "\(firstName.trimmingCharacters(in: .whitespacesAndNewlines)) \(lastName.trimmingCharacters(in: .whitespacesAndNewlines))".trimmingCharacters(in: .whitespaces)
        change.displayName = fullName
        change.commitChanges(completion: nil)

        let profile: [String: Any] = [
            "firstName": firstName,
            "lastName": lastName,
            "email": email,
            "createdAt": Timestamp(date: Date())
        ]
        Firestore.firestore().collection("users").document(user.uid).setData(profile, merge: true)

        DispatchQueue.main.async { self.authError = nil }
    }

    func sendPasswordReset(to email: String) {
        Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authInfo = nil
                    self?.setAuthError(error)
                } else {
                    self?.authError = nil
                    self?.authInfo = "Password reset email sent to \(email)."
                }
            }
        }
    }

    func signInAnonymously() {
        Auth.auth().signInAnonymously { [weak self] result, error in
            if let e = error as NSError? { print("Auth anon signIn error: \(e) userInfo=\(e.userInfo)") }
            DispatchQueue.main.async { self?.setAuthError(error) }
        }
    }

    func signOut() {
        do { try Auth.auth().signOut() } catch { authError = error.localizedDescription }
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject private var store = TaskStore()
    @StateObject private var auth = AuthViewModel()
    @State private var newTitle: String = ""
    @State private var newDetails: String = ""
    @FocusState private var isTitleFocused: Bool
    @State private var newDetailsHeight: CGFloat = 32
    @State private var showCompletedSection: Bool = false
    @State private var showClearConfirm: Bool = false
    @State private var newDetailsFocused: Bool = false
    // Category selection
    @State private var selectedCategory: String = "Personal"
    private let categories = ["Personal", "Work", "School", "Errands"]

    // Due Date
    @State private var hasDueDate: Bool = false
    @State private var selectedDueDate: Date = Date()

    // Category Filter (nil = All tasks)
    @State private var selectedFilterCategory: String? = nil

    // Editing state
    @State private var editingTask: TaskItem? = nil
    @State private var editedTitle: String = ""

    @State private var detailTask: TaskItem? = nil
    @State private var detailEditedTitle: String = ""
    @State private var detailEditedDetails: String = ""

    // Controls if the details box is visible
    @State private var showDetails: Bool = false

    // Progress metrics
    private var totalCount: Int { store.tasks.count }
    private var doneCount: Int { store.tasks.filter { $0.isDone }.count }
    private var progress: Double { totalCount == 0 ? 0 : Double(doneCount) / Double(totalCount) }

    @State private var showAuth: Bool = false
    
    // Location
    @State private var currentLocationName = ""
    private let geocoder = CLGeocoder()
    @StateObject private var tracker = LocationTracker()
    @State private var mustDoHereToggle = false
    @State private var redTaskIDs: Set<String> = []

    // Pre-filtered task arrays
    private var activeTasks: [TaskItem] { store.tasks.filter { !$0.isDone } }
    private var completedTasks: [TaskItem] { store.tasks.filter { $0.isDone } }
    
    private var boundIDs: Set<String> {
        Set(store.tasks.compactMap { ($0.boundLat != nil) ? $0.id : nil })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                
                VStack(spacing: 12) {
                    header
                    inputRow
                    detailsBox
                    taskList
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Lock In")
                            .font(.headline.weight(.semibold))

                        Text("• \(currentLocationName.isEmpty ? "Locating…" : currentLocationName)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTitleFocused = false
                        newDetailsFocused = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if auth.user != nil {
                        Button("Sign Out") { auth.signOut() }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
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
        
        .onReceive(tracker.$coordinate) { coord in
            print("coord update:", String(describing: coord))
            if let coord { reverseGeocode(coord) }  // your nav title name
            reevaluateHereRulesAndNotify()
        }

        .onReceive(store.$tasks) { _ in
            reevaluateHereRulesAndNotify()
        }
        
        .onAppear {
            if let coord = tracker.coordinate { reverseGeocode(coord) }
        }

        .onChange(of: store.tasks) { _, _ in
            reevaluateHereRulesAndNotify()
        }

        .task {
            await Notifier.requestAuthorization()
            tracker.requestAlwaysAuthorization()
            tracker.kick()

        }
        .onAppear {
            showAuth = auth.user == nil
            store.setUser(uid: auth.user?.uid)
            if let coord = tracker.coordinate {
                reverseGeocode(coord)
            }
        }
    
        .onChange(of: auth.user?.uid) { _, newUid in
            showAuth = (auth.user == nil)
            store.setUser(uid: newUid)
        }
        .fullScreenCover(isPresented: $showAuth) {
            AuthSheet(auth: auth)
                .interactiveDismissDisabled(auth.user == nil)
        }
    }

    private func add() {
        guard auth.user != nil else { showAuth = true; return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var place: String? = currentLocationName.isEmpty ? nil : currentLocationName
        if place == nil, let c = tracker.coordinate {
            place = String(format: "%.4f, %.4f", c.latitude, c.longitude)
        }

        if mustDoHereToggle, let c = tracker.coordinate {
            store.add(
                trimmed,
                details: newDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newDetails,
                category: selectedCategory,
                dueDate: hasDueDate ? selectedDueDate : nil,
                boundLat: c.latitude,
                boundLon: c.longitude,
                boundPlace: place
            )
        } else {
            store.add(
                trimmed,
                details: newDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : newDetails,
                category: selectedCategory,
                dueDate: hasDueDate ? selectedDueDate : nil
            )
        }

        newTitle = ""
        newDetails = ""
        mustDoHereToggle = false
        isTitleFocused = false
        showDetails = false
        hasDueDate = false
        selectedDueDate = Date()
    }


    private let boundThresholdMeters: Double = 100

    private func isFar(current: CLLocationCoordinate2D?, task: TaskItem) -> Bool {
        guard
            let c = current,
            let lat = task.boundLat,
            let lon = task.boundLon,
            task.isDone == false
        else { return false }

        let here  = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let there = CLLocation(latitude: lat,       longitude: lon)
        return here.distance(from: there) > boundThresholdMeters
    }

    private func reevaluateHereRulesAndNotify() {
        let cur = tracker.coordinate
        var next: Set<String> = []
        for t in store.tasks where !t.isDone {
            if isFar(current: cur, task: t) { next.insert(t.id ?? "") }
        }

        let newlyRed = next.subtracting(redTaskIDs)
        for id in newlyRed {
            if let t = store.tasks.first(where: { $0.id == id }) {
                Notifier.send(
                    title: "You left without finishing... 🥲",
                    body: "“\(t.title)” was marked to do before leaving."
                )
            }
        }

        redTaskIDs = next
    }

    @ViewBuilder private var header: some View {
        if totalCount > 0 {
            ProgressHeader(done: doneCount, total: totalCount, progress: progress)
                .padding(.horizontal)
        }
    }

    @ViewBuilder private var inputRow: some View {
        HStack(spacing: 10) {
            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit(add)
                .focused($isTitleFocused)
                .onChange(of: newTitle) { oldValue, newValue in
                    let shouldShow = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if shouldShow != showDetails {
                        withAnimation(.easeInOut(duration: 0.2)) { showDetails = shouldShow }
                    }
                }

            Button { add() } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.top, 4)
        
        Toggle(isOn: $mustDoHereToggle) {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "mappin.and.ellipse")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Location Feature")
                        .font(.headline)

                    Text("Complete before leaving current location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder private var detailsBox: some View {
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

            // Category
            HStack {
                Text("Category")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .padding(.horizontal)

            // Due Date toggle
            Toggle("Add Due Date", isOn: $hasDueDate)
                .padding(.horizontal)
                .padding(.top, 2)

            // Date & time picker (shown only if toggle is ON)
            if hasDueDate {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Due Date")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "Select Due Date",
                        selection: $selectedDueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }
                .padding(.horizontal)
            }

            // ▲▲▲ End of inserted block ▲▲▲
        }
    }

    @ViewBuilder private var taskList: some View {
        List {
            Section {
                QuoteCardView().listRowBackground(Color.clear)
            }

            ActiveTasksSection(
                tasks: activeTasks,
                redIDs: redTaskIDs,
                boundIDs: boundIDs,
                onToggle: { store.toggle($0) },
                onDelete: { store.remove($0) },
                onOpen: { t in
                    detailTask = t
                    detailEditedTitle = t.title
                    detailEditedDetails = t.details ?? ""
                }
            )

            if !completedTasks.isEmpty {
                CompletedTasksSection(
                    tasks: completedTasks,
                    isExpanded: $showCompletedSection,
                    onToggle: { store.toggle($0) },
                    onDelete: { store.remove($0) },
                    onOpen: { t in
                        detailTask = t
                        detailEditedTitle = t.title
                        detailEditedDetails = t.details ?? ""
                    },
                    onClear: { showClearConfirm = true }
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            "Clear all completed tasks?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        )
        {
            Button("Clear All", role: .destructive) { store.clearCompleted() }
            Button("Cancel", role: .cancel) {}
        }
    }
    private func reverseGeocode(_ coord: CLLocationCoordinate2D) {
        let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(loc) { placemarks, error in
            if let error {
                print("Reverse geocode error:", error.localizedDescription)
            }

            if let p = placemarks?.first {
                let neighborhood = p.subLocality
                let city = p.locality ?? p.administrativeArea ?? p.country
                let composed = [neighborhood, city].compactMap { $0 }.joined(separator: ", ")
                DispatchQueue.main.async {
                    self.currentLocationName = composed.isEmpty ? (p.name ?? city ?? "") : composed
                }
            } else {
                let lat = String(format: "%.4f", coord.latitude)
                let lon = String(format: "%.4f", coord.longitude)
                DispatchQueue.main.async {
                    self.currentLocationName = "\(lat), \(lon)"
                }
            }
        }
    }


}

// MARK: - Auth Sheet UI
private struct AuthSheet: View {
    @ObservedObject var auth: AuthViewModel
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var isSignUp: Bool = false

    // Password policy (signup)
    private var meetsLength: Bool { password.count >= 8 }
    private var hasUppercase: Bool { password.range(of: "[A-Z]", options: .regularExpression) != nil }
    private var hasLowercase: Bool { password.range(of: "[a-z]", options: .regularExpression) != nil }
    private var hasDigit: Bool { password.range(of: "[0-9]", options: .regularExpression) != nil }
    private var passwordValid: Bool { meetsLength && hasUppercase && hasLowercase && hasDigit }
    private var passwordsMatch: Bool { !password.isEmpty && password == confirmPassword }
    private var signupFormValid: Bool {
        !email.isEmpty && !firstName.trimmingCharacters(in: .whitespaces).isEmpty && !lastName.trimmingCharacters(in: .whitespaces).isEmpty && passwordValid && passwordsMatch
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("Mode", selection: $isSignUp) {
                    Text("Sign In").tag(false)
                    Text("Sign Up").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: isSignUp) { _, _ in
                    confirmPassword = ""
                }

                if isSignUp {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("First Name").font(.footnote).foregroundStyle(.secondary)
                            TextField("John", text: $firstName)
                                .textContentType(.givenName)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Last Name").font(.footnote).foregroundStyle(.secondary)
                            TextField("Doe", text: $lastName)
                                .textContentType(.familyName)
                                .textInputAutocapitalization(.words)
                                .padding(12)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Email").font(.footnote).foregroundStyle(.secondary)
                    TextField("name@example.com", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Password").font(.footnote).foregroundStyle(.secondary)
                    SecureField("••••••••", text: $password)
                        .textContentType(.password)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !isSignUp {
                    HStack {
                        Spacer()
                        Button("Forgot password?") {
                            guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            auth.sendPasswordReset(to: email)
                        }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.plain)
                    }
                }

                if isSignUp {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password").font(.footnote).foregroundStyle(.secondary)
                        SecureField("••••••••", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding(12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Password requirements
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: meetsLength ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(meetsLength ? .green : .secondary)
                            Text("At least 8 characters").font(.footnote)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: hasUppercase ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(hasUppercase ? .green : .secondary)
                            Text("Contains an uppercase letter").font(.footnote)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: hasLowercase ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(hasLowercase ? .green : .secondary)
                            Text("Contains a lowercase letter").font(.footnote)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: hasDigit ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(hasDigit ? .green : .secondary)
                            Text("Contains a number").font(.footnote)
                        }
                        if !confirmPassword.isEmpty && !passwordsMatch {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                Text("Passwords do not match").font(.footnote)
                            }
                        }
                    }
                }

                if let err = auth.authError, !err.isEmpty {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let info = auth.authInfo, !info.isEmpty {
                    Text(info)
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    if isSignUp {
                        auth.signUp(email: email, password: password, firstName: firstName, lastName: lastName)
                    } else {
                        auth.signIn(email: email, password: password)
                    }
                } label: {
                    HStack { Spacer(); Text(isSignUp ? "Create Account" : "Sign In").bold(); Spacer() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSignUp ? !signupFormValid : (email.isEmpty || password.isEmpty))

                Button {
                    auth.signInAnonymously()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                        Text("Continue as Guest")
                    }
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Row
private struct TaskRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let task: TaskItem
    let onToggle: () -> Void
    let onOpenDetails: () -> Void
    var isRed: Bool
    var isBound: Bool = false   // NEW

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

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body)
                    .lineLimit(2)
                    .strikethrough(task.isDone, pattern: .solid, color: .secondary)
                    .foregroundColor(task.isDone ? .secondary : (isRed ? .red : .primary))
                //  Category, Due Date,
                HStack(spacing: 8) {
                    if let category = task.category, !category.isEmpty {
                        Text(category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let due = task.dueDate {
                        Text("Due: \(due.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lat = task.boundLat, let lon = task.boundLon {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Location bound")
                        
                        Text("• \(task.boundPlace ?? String(format: "%.4f, %.4f", lat, lon))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if isRed {
                    Text("Away from required location")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.85))
                }
            }

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
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.06),
                radius: 12, x: 0, y: 6)
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

private struct ActiveTasksSection: View {
    let tasks: [TaskItem]
    let redIDs: Set<String>
    let boundIDs: Set<String>
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onOpen: (TaskItem) -> Void

    var body: some View {
        Section {
            ForEach(tasks) { task in
                TaskRow(
                    task: task,
                    onToggle: { onToggle(task) },
                    onOpenDetails: { onOpen(task) },
                    isRed: redIDs.contains(task.id ?? ""),
                    isBound: boundIDs.contains(task.id ?? "")
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) { onDelete(task) } label: {
                        Label("Delete", systemImage: "trash")
                    }
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
    }
}

private struct CompletedTasksSection: View {
    let tasks: [TaskItem]
    @Binding var isExpanded: Bool
    let onToggle: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onOpen: (TaskItem) -> Void
    let onClear: () -> Void

    var body: some View {
        Section {
            if isExpanded {
                ForEach(tasks) { task in
                    TaskRow(
                        task: task,
                        onToggle: { onToggle(task) },
                        onOpenDetails: { onOpen(task) },
                        isRed: false
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { onDelete(task) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        } header: {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        Text("Completed")
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(tasks.count)")
                    .font(.caption2).bold()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))

                Button {
                    onClear()
                } label: {
                    Image(systemName: "trash").imageScale(.medium)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear completed")
            }
        }
    }
}

#Preview {
    ContentView()
}
