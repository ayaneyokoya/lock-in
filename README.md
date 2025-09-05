# LockIn To‑Do App


## Overview
LockIn is a simple to-do list app built with SwiftUI. It uses Firebase to save tasks and handle login, so each user gets their own private task list that works across devices. Tasks live in `users/{uid}/tasks` inside Firestore.

##  Demo Video

https://github.com/user-attachments/assets/2743f9d9-7dce-45ae-a25b-f1db3f23fd2a


## Prerequisites
- Xcode 15+ (with SwiftUI).
- iOS 17 or newer.
- A Firebase account + project.
- Internet (for pulling in packages).


## Firebase project setup
1. **Make a project** – Go to the [Firebase console](https://console.firebase.google.com) and create a new project (or reuse one you already have).
2. **Add an iOS app** – Register your app’s bundle ID (like `com.example.LockIn`) and download the `GoogleService-Info.plist`. Drop it into your Xcode project.
3. **Turn on Auth** – In **Authentication → Sign-in method**, enable:
   - **Email/Password**
   - **Anonymous sign-in** (optional, for guest accounts)
4. **Set up Firestore** – Create a Firestore database in **Native** mode. Use rules so users can only see their own tasks, for example:
   ```js
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{uid}/tasks/{taskId} {
         allow read, write: if request.auth != null && request.auth.uid == uid;
       }
     }
   }

## Installing dependencies
1. Open your project in Xcode.
2. Navigate to **File → Add Packages**.
3. Enter the Firebase Apple platforms SDK repository URL `https://github.com/firebase/firebase-ios-sdk.git`.
4. Choose the **latest** SDK version and select at least **FirebaseAuth** and **FirebaseFirestore** to pull in Authentication and Firestore features.
5. Xcode resolves and downloads the packages automatically.


## App initialization
1. Import Firebase modules in your code:
```swift
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth
```
2. Create an `AppDelegate` that calls `FirebaseApp.configure()` in `application(_:didFinishLaunchingWithOptions:)` and set the app’s language with `Auth.auth().useAppLanguage()` to display auth emails in the user’s locale.
3. When using SwiftUI, register your app delegate using `@UIApplicationDelegateAdaptor` in your `App` struct and provide a top‑level `AuthViewModel` as an environment object:
```swift
@main
struct LockInApp: App {
@UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
@StateObject private var auth = AuthViewModel()


var body: some Scene {
    WindowGroup {
      ContentView()
      .environmentObject(auth)
    }
  }
}
```
The documentation recommends attaching the app delegate this way when integrating Firebase into SwiftUI apps.


## Running the app
1. Run the app in the simulator or on a device.
2. **Sign up** – New users provide their first name, last name, email and a strong password. The app enforces a password policy (minimum eight characters, including uppercase, lowercase and a digit). If a guest user signs up, their anonymous UID is linked to the new account so their tasks are preserved.
3. **Sign in** – Existing users can sign in with their email and password. A “Forgot password?” link sends a reset email via `sendPasswordReset`.
4. **Continue as guest** – Users may tap “Continue as Guest” to sign in anonymously. They can later upgrade to a permanent account; the app links credentials so their tasks remain.
5. Once signed in, tasks are synced with Cloud Firestore in real time. You can add tasks, edit titles and details, toggle completion, filter tasks into a To Do section and a collapsible Completed section, and delete tasks with swipe actions.


## Notes
- This app uses the `users/{uid}/tasks` collection pattern and subscribes to live updates with Firestore snapshot listeners. When the auth state changes, `TaskStore.setUser(uid:)` rebuilds the listener and clears local state.
- The `AuthViewModel` exposes sign‑in, sign‑up, password‑reset and sign‑out functions and stores the current user state.
- The UI includes a progress bar showing completed vs total tasks, supports dynamic placeholder text in editors, and collapses completed tasks.
- The project includes a Keychain access requirement on macOS; if you target macOS Catalyst, enable the Keychain Sharing capability as noted in the Firebase setup guide.


## Troubleshooting
- **Build errors** – Ensure you added the correct `GoogleService‑Info.plist` file for your bundle identifier and that packages are resolved.
- **Authentication fails** – Verify that email/password and anonymous providers are enabled in the console. The app reports common errors (invalid email, duplicate account, weak password, network errors).
- **Firestore permission errors** – Confirm that Firestore security rules match your collection structure and that you are using a **Native** mode database. Reset rules as shown above if necessary.


With these steps, you should be able to configure Firebase, build, and run the LockIn to‑do app successfully.
