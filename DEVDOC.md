# Folio — Developer Documentation

Folio is a native SwiftUI CMS client for managing the content of a Node.js/Express portfolio site. It targets macOS 26 and iOS 26 from a single build target (not Catalyst).

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Tech Stack & Requirements](#2-tech-stack--requirements)
3. [Architecture](#3-architecture)
4. [File Structure](#4-file-structure)
5. [Configuration & Settings](#5-configuration--settings)
6. [Data Layer](#6-data-layer)
7. [Networking](#7-networking)
8. [View Layer](#8-view-layer)
9. [Markdown Editor](#9-markdown-editor)
10. [Draft System](#10-draft-system)
11. [Media Handling](#11-media-handling)
12. [Apps Feature](#12-apps-feature)
13. [Patterns & Conventions](#13-patterns--conventions)
14. [Known Gotchas](#14-known-gotchas)

---

## 1. Project Overview

Folio CMS manages three kinds of content against a REST API:

| Tab | Content | API prefix |
|-----|---------|------------|
| Projects | Portfolio projects with hero image, description, tech stack, links, and media gallery | `/api/projects` |
| Posts | Blog posts with markdown content, tags, series, and hero image | `/api/posts` |
| Apps | Per-app privacy policy and support pages | `/api/apps/:id` |

All three tabs support full CRUD. There is no direct database access — everything goes through the portfolio site's HTTP API.

---

## 2. Tech Stack & Requirements

- **Xcode 26+**, single multiplatform target
- **Swift 6**, approachable concurrency mode
- **SwiftUI** — iOS 26 / macOS 26 minimum deployment
- **Textual** (SPM) — `StructuredText` component used for markdown preview in the post editor
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — all types are `@MainActor` by default; no annotation needed
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` — enables Swift 6 approachable concurrency rules
- `PBXFileSystemSynchronizedRootGroup` — new files added to the `Folio/` directory are included in the build automatically; no need to manually add them to the project

**No xcconfig files.** The project previously used `Dev.xcconfig` / `Prod.xcconfig` to inject secrets at build time. This has been removed. All configuration is now entered manually in the Settings tab at runtime.

---

## 3. Architecture

### Layer diagram

```
Views  ──────────►  ViewModels  ──────────►  Repositories  ──────────►  URLProcessor
  │                     │                        │
  │ SwiftUI bindings     │ @Observable             │ typed throws(APIError)
  │ @State / @Binding    │ scheduleAutosave()       │ encode / decode JSON
  │                      │ DraftStore               │ multipart upload
  └──────────────────────┴────────────────────────-─┘
```

### Key design decisions

- **Single target** — one binary runs on iOS and macOS. Platform-specific code is gated with `#if os(macOS)`.
- **`@Observable`** — all ViewModels use the `@Observable` macro (not `ObservableObject`/`@Published`). Views observe only what they actually read, so updates are precise.
- **Typed throws** — the networking layer declares `throws(APIError)` throughout, so callers never need to cast errors and the compiler enforces exhaustive handling.
- **No navigation router** — navigation is handled directly by `NavigationStack` + `List(selection:)` + `.navigationDestination(item:)`. State is owned at the list level.
- **No global state** — there is no environment-injected app state. Each tab owns its own ViewModel.

---

## 4. File Structure

```
Folio/
├── Resources/
│   └── FolioApp.swift          @main entry point, WindowGroup + Settings scene
│
├── Models/
│   ├── HTTPRequestMethod.swift  URLRequest extension for .httpMethodType
│   ├── Media.swift              MediaType, MediaContext, MediaItem
│   ├── Post.swift               PostPreview, PostDetail, PostNav
│   ├── Project.swift            ProjectPreview, ProjectDetail, ProjectNav, ProjectStatus
│   └── App.swift                AppPrivacyPolicy, AppSupport, AppRecord
│
├── APIError.swift               Error enum used by all repository calls
├── KeychainService.swift        FolioStorageKey constants + Keychain CRUD
├── URLProcessor.swift           HTTP client, JSON coder, URL helpers
├── DraftStore.swift             File-backed draft persistence + diff utility
│
├── ProjectRepository.swift      CRUD for projects (ProjectUpdate partial payload)
├── PostRepository.swift         CRUD for posts (PostUpdate partial payload)
├── MediaRepository.swift        File upload + delete for media assets
├── AppsRepository.swift         CRUD for app privacy policy and support pages
│
├── ProjectsViewModel.swift      List-level VM for the Projects tab
├── ProjectFormViewModel.swift   Edit/Create VM for a single project
├── PostsViewModel.swift         List-level VM for the Posts tab
├── PostEditorViewModel.swift    Edit/Create VM for a single post
│
├── ContentView.swift            Root TabView (.sidebarAdaptable)
├── ProjectsView.swift           List + NavigationStack for projects
├── ProjectFormView.swift        Form + inspector panel for a project
├── ProjectPreview.swift         ProjectListRow + ProjectStatusBadge
├── PostsView.swift              List + NavigationStack for posts
├── PostEditorView.swift         Editor + inspector + markdown preview for a post
├── PostListRow.swift            Single row in the posts list
├── MediaManagerView.swift       Drag-to-reorder media gallery with upload
├── MarkdownEditorView.swift     NSViewRepresentable / UIViewRepresentable text editor
├── AppsView.swift               Apps list + AppsViewModel (UserDefaults-backed)
├── AppDetailView.swift          Per-app detail: links to privacy + support editors
├── AppPrivacyPolicyEditorView.swift
├── AppSupportEditorView.swift
└── SettingsView.swift           Dev/Prod environment picker + URL/key entry
```

---

## 5. Configuration & Settings

### Environments

The app supports two environments switchable at runtime via a segmented picker in Settings. There is no build-time configuration.

| Setting | Storage | Key |
|---------|---------|-----|
| Active environment (`"dev"` or `"prod"`) | UserDefaults | `folio.activeEnvironment` |
| Dev base URL | UserDefaults | `folio.dev.baseURL` |
| Prod base URL | UserDefaults | `folio.prod.baseURL` |
| Dev API key | Keychain | `folio.dev.apiKey` |
| Prod API key | Keychain | `folio.prod.apiKey` |

All constants live in `FolioStorageKey` (in `KeychainService.swift`).

### How the active environment is resolved

`URLProcessor.fromSettings()` and the URL helper functions (`mediaURL(for:)`, `resolveMarkdownImageURLs(_:)`) all call the file-private `activeBaseURLString()` function in `URLProcessor.swift`, which reads the active environment from UserDefaults and returns the appropriate stored URL. Switching the picker in Settings takes effect immediately for all subsequent requests; no restart required.

### `Info.plist`

Contains only `NSAppTransportSecurity` (allowing HTTP to `localhost` for local dev). There are no build-variable injections.

### Keychain

`KeychainService` is a thin wrapper around `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`. It stores one string per key under `kSecClassGenericPassword`. The API key "Save" button in Settings is explicit — the key is not written to Keychain on every keystroke.

---

## 6. Data Layer

### Models overview

**Projects**

```swift
ProjectPreview   // Used in the list: id, title, tagline, heroImage, category, status, featured, createdAt, updatedAt
ProjectDetail    // Full project: everything in Preview + description, media, techStack, links
ProjectNav       // Minimal: id, title, status (used for related-project pickers elsewhere)
ProjectStatus    // .active | .inProgress | .archived
```

`ProjectDetail` extends `ProjectPreview` via a convenience initialiser and exposes `.preview` and `.nav` computed properties to avoid re-fetching when only a subset is needed after a save.

**Posts**

```swift
PostPreview      // id, title, excerpt, heroImage?, tags, createdAt, updatedAt?, readingTime, series?
PostDetail       // Adds: content
PostNav          // id, title, tags, createdAt, series?
```

**Apps**

```swift
AppPrivacyPolicy // id (= app slug), appName, lastUpdated (yyyy-MM-dd string), content (markdown), contactUrl?, contactText?
AppSupport       // id, appName, version, subtitle, content (markdown), contactUrl?, contactText?
AppRecord        // id only — the local list of known app slugs stored in UserDefaults
```

### Dates

All `Date` fields are encoded/decoded as ISO 8601 strings. The `URLProcessor`'s shared encoder/decoder both use `.iso8601` strategy. `AppPrivacyPolicy.lastUpdated` is the exception — it stores a plain `yyyy-MM-dd` string and is converted to/from `Date` inside `AppPrivacyPolicyEditorViewModel` using a static `DateFormatter` with a POSIX locale.

### Partial update payloads

Editing uses partial PATCH-style PUT payloads (`ProjectUpdate`, `PostUpdate`) rather than sending the full model. Each has a custom `encode(to:)` that uses `encodeIfPresent`, so only non-nil fields are sent to the server. This prevents unintentionally clearing optional fields.

```swift
struct ProjectUpdate: Encodable {
    var title: String?
    var description: String?
    var createdAt: Date?
    // ... all fields optional
}
```

The `createdAt` field is included — editing it via the inspector DatePicker sends the new date to the server on save.

---

## 7. Networking

### `URLProcessor`

The central HTTP client. Each call requires constructing a fresh `URLProcessor` via `URLProcessor.fromSettings()`, which reads the active environment's URL and API key. This means environment switches take effect immediately without restarting.

```swift
let p = try URLProcessor.fromSettings()  // throws .invalidURL if URL is empty/malformed
let data = try await p.get(url)
let decoded = try p.decode(MyType.self, from: data)
```

Available methods: `get`, `post`, `put`, `delete`, `upload`. All throw `APIError` typed errors.

### `APIError`

```swift
enum APIError: Error {
    case unauthorized       // 401 — "check your API key in Settings"
    case notFound           // 404
    case conflict           // 409 — duplicate ID
    case httpError(Int)     // other 4xx/5xx
    case encodingFailed     // JSON encode failure
    case decodingFailed     // JSON decode failure
    case networkFailed      // URLSession error
    case invalidURL         // empty or malformed base URL
}
```

`error.isCancellation` returns true when a task was cancelled (i.e. the user navigated away). Cancellation errors are not shown to the user.

### Multipart upload

`URLProcessor.upload(to:fileData:fileName:mimeType:context:id:)` constructs a `multipart/form-data` body with three fields: `context` (e.g. `"projects"`), `id` (the resource slug), and `file`. An optional `overwrite: true` field can be included for replace-in-place uploads.

### HTTP method convention

`URLRequest.httpMethodType` is a computed property (defined in `Models/HTTPRequestMethod.swift`) that converts between the `HTTPRequestMethod` enum and the `String`-typed `httpMethod` property.

---

## 8. View Layer

### Navigation structure

```
ContentView  (TabView .sidebarAdaptable)
├── ProjectsView  (NavigationStack)
│   └── ProjectFormView  (edit or create)
│       └── .inspector  ProjectFormView inspector panel
├── PostsView  (NavigationStack)
│   └── PostEditorView  (edit or create)
│       └── .inspector  PostEditorView inspector panel
├── AppsView  (NavigationStack)
│   └── AppDetailView
│       ├── AppPrivacyPolicyEditorView
│       └── AppSupportEditorView
└── SettingsView
```

On macOS, `SettingsView` is also presented via `Settings { }` in the standard Preferences window (accessed via ⌘,).

### List → detail pattern

Each list view owns:
- `@State private var selectedID: String?` — bound to `List(selection:)`
- `@State private var isCreatingNew = false`
- `.navigationDestination(item: $selectedID) { id in EditorView(...mode: .edit(id: id)) }`
- `.navigationDestination(isPresented: $isCreatingNew) { EditorView(...mode: .create) }`

**Critical:** When tapping "New" while an item is already selected, `selectedID` must be cleared first:

```swift
Button("New Project", systemImage: "plus") {
    selectedProjectID = nil   // Clear before setting isCreatingNew
    isCreatingNew = true
}
```

Without this, both `navigationDestination` modifiers are active simultaneously, and SwiftUI resolves to the `item:` destination (the already-selected edit view) instead of the create form.

`.onDisappear { selectedID = nil }` clears the selection when switching tabs, preventing stale navigation state from re-opening the detail view when returning to the tab.

### ViewModel lifetime

ViewModels are held in `@State var vm: SomeViewModel` inside the destination view, not in the list view. This means each navigation push creates a fresh VM. The VM's `load()` is called from `.task { await vm.load() }` in the view's body.

```
List view owns: selectedID, isCreatingNew, listVM
Detail view owns: formVM (fresh per push)
```

### Inspector panel

Both `ProjectFormView` and `PostEditorView` use SwiftUI's `.inspector(isPresented:)` modifier. On macOS this becomes a trailing sidebar panel; on iOS it slides up as a sheet. The inspector contains status controls, date editors, and the delete button. It does not affect the main form — both regions are always live.

### `@Observable` ViewModels

All ViewModels use the `@Observable` macro. Annotate the stored property, not the type — the macro handles synthesis. Because the project has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, all VM methods and properties are automatically `@MainActor` without annotation.

```swift
@Observable
class ProjectFormViewModel {
    var title = ""   // No @Published needed
    // ...
}
```

---

## 9. Markdown Editor

`MarkdownEditorView` is a `NSViewRepresentable` (macOS) / `UIViewRepresentable` (iOS) that wraps a plain-text `NSTextView` / `UITextView`.

### Public API

```swift
MarkdownEditorView(
    text: $vm.description,            // Binding<String>
    pendingAction: $vm.pendingDescriptionAction,  // Binding<EditorAction?>
    highlightRanges: diffRanges        // [NSRange], default []
)
```

### `EditorAction`

Toolbar buttons communicate with the text view through a `pendingAction` binding rather than direct method calls (which would require storing a reference to the view, which isn't safe in SwiftUI).

```swift
enum EditorAction {
    case insertText(String)                                  // Insert at cursor / replace selection
    case wrap(prefix: String, suffix: String, placeholder: String)  // Bold, italic, code, link
    case prependLine(String)                                 // Heading prefixes (# , ## , etc.)
}
```

The action is consumed inside `updateNSView`/`updateUIView`: the binding is set to `nil` **before** mutating the text view to prevent a re-entry loop (`textDidChange` → `updateNSView` → action still set → apply again).

### Re-entry guard

`Coordinator.isUpdating` is set to `true` during programmatic text updates (both action application and text sync). The `textDidChange` / `textViewDidChange` delegate method is a no-op while `isUpdating` is true, so it doesn't write back to the binding and trigger another `updateNSView`.

### macOS teardown

`static func dismantleNSView(_ scrollView:, coordinator:)` nils the `NSTextView`'s delegate before teardown. Without this, AppKit may call delegate methods on a deallocated coordinator, causing `EXC_BAD_ACCESS`.

### Diff highlighting

When the "Show Changes" toolbar toggle is on, `highlightRanges` is set to the output of `computeChangedLineRanges(from:to:)`. On macOS, `NSLayoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.25))` is used — temporary attributes are display-only and don't affect the underlying `NSTextStorage`, so they're compatible with `isRichText = false`.

The Coordinator caches `lastHighlightRanges` and skips the layout manager call if the ranges haven't changed, avoiding unnecessary redraws on every keystroke.

`computeChangedLineRanges(from:to:)` (in `DraftStore.swift`) uses `CollectionDifference` to find inserted/changed lines, then walks the current text to convert line indices to `NSRange` character offsets.

### Image URL resolution for preview

Markdown content stores images as relative paths: `![alt](/media/posts/slug/uuid.webp)`. The `resolveMarkdownImageURLs(_:)` free function (in `URLProcessor.swift`) rewrites these to absolute URLs before passing content to `StructuredText`. Already-absolute URLs pass through unchanged. **Do not store absolute URLs in content** — the base URL changes between dev and prod.

---

## 10. Draft System

`DraftStore` persists in-progress edits to disk so they survive app termination. Drafts are stored as JSON files in `~/Library/Application Support/Folio/drafts/`.

### Draft keys

| Context | Key |
|---------|-----|
| New project | `project-new` |
| Editing project `slug` | `project-slug` |
| New post | `post-new` |
| Editing post `slug` | `post-slug` |

### Autosave trigger

Every form field that should participate in drafts has a `didSet` that calls `scheduleAutosave()`. The autosave task is debounced 2 seconds and uses `[weak self]` to avoid retain cycles:

```swift
var title = "" { didSet { scheduleAutosave() } }

func scheduleAutosave() {
    guard !isPopulating else { return }  // Skip during population
    autosaveTask?.cancel()
    autosaveTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return }
        self?.saveDraft()
    }
}
```

### `isPopulating` flag

When a VM loads data from the server or restores a draft, it sets `isPopulating = true` before writing fields and back to `false` after. `scheduleAutosave()` and `createdAt.didSet`'s sync logic both check this flag and skip their side effects. Without it, every field assignment during load would schedule an autosave and overwrite the draft with partially populated data.

### Load sequence (edit mode)

1. Fetch server data → `populate(from detail:)` (sets `serverContent`/`serverDescription` for diff, then all form fields)
2. If a draft exists for this key → `populateFromDraft(_:)` (overwrites server data with in-progress changes)
3. Set `hasDraft = true` if a draft was found

The server data is always fetched first so `serverContent`/`serverDescription` reflect the last published state (used for diff highlighting). The draft is layered on top.

### Draft vs. server content

`serverContent` (posts) and `serverDescription` (projects) are `private(set)` properties set during `populate(from:)` but **not** overwritten by `populateFromDraft`. They always reflect the last-saved server state, which is required for `computeDiffRanges()` to show what has changed.

### Discard draft

Clears the file via `DraftStore.clear(key:)`. For create mode, resets all fields programmatically. For edit mode, re-fetches from the server.

---

## 11. Media Handling

### Upload flow

`MediaRepository.upload(fileData:fileName:mimeType:context:id:)` posts to `POST /api/media/upload` with a multipart body. The server returns `{ "url": "/media/projects/slug/uuid.webp" }`. The returned path is a **relative** server path, stored as-is.

### Relative paths

All stored media URLs are relative (e.g. `/media/projects/slug/uuid.webp`). Two helpers resolve them at display time:

- `mediaURL(for path: String) -> URL?` — returns an absolute `URL` for use in `AsyncImage`. Prepends the active environment's base URL.
- `resolveMarkdownImageURLs(_ content: String) -> String` — rewrites `![alt](/path)` patterns in markdown before passing to `StructuredText`.

Never store absolute URLs. The base URL differs between dev and prod, so absolute paths would break when switching environments.

### Hero images

Hero images follow the same relative-path rule. The hero image field stores a path like `/media/projects/slug/uuid.webp`. `ProjectFormView` and `PostEditorView` display it via `AsyncImage(url: mediaURL(for: vm.heroImage))`.

A `PendingImage` struct holds image data selected from Photos or Files before upload. Upload happens at save time, not selection time. This avoids uploading images for forms that are never saved.

```swift
struct PendingImage {
    var data: Data
    var mimeType: String
    var ext: String
}
```

### File picker on macOS

SwiftUI's `.fileImporter` silently fails when nested inside `Form > Section` on macOS (can't find the window context). Use `NSOpenPanel().runModal()` directly instead:

```swift
Button("Select from Files…") {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    loadHeroFromFileURL(url)
}
```

This pattern is used in `ProjectFormView`, `PostEditorView`, and `MediaManagerView`.

### Drag-to-reorder in media gallery

`MediaManagerView` renders media rows in a `VStack` (not a `List`, since `List` applies its own layout and doesn't compose well inside a `Form`). Reorder is implemented with `.draggable(item.id)` and `.dropDestination(for: String.self)` on each row:

```swift
.dropDestination(for: String.self) { droppedIDs, _ in
    guard let droppedID = droppedIDs.first, droppedID != item.id,
          let from = media.firstIndex(where: { $0.id == droppedID }),
          let to   = media.firstIndex(where: { $0.id == item.id })
    else { return false }
    withAnimation {
        let moved = media.remove(at: from)
        media.insert(moved, at: from < to ? to - 1 : to)
    }
    return true
}
```

The index adjustment `from < to ? to - 1 : to` corrects for the array shift that occurs after `remove(at: from)`.

---

## 12. Apps Feature

### Why UserDefaults for the app list

The portfolio API has no "list all apps" endpoint. The list of known app slugs is stored locally in UserDefaults as JSON-encoded `[AppRecord]` under the key `"folio.apps"`. The user manually adds/removes app slugs via an alert dialog. Each `AppRecord` contains only an `id` (the slug).

### Page load

`AppDetailViewModel.load()` fetches the privacy policy and support page **sequentially**, not concurrently. Each fetch can independently fail with `.notFound` (page doesn't exist yet) or a network error. The VM tracks four states per page type: `missing`, `failed`, the loaded value, and loading. The view renders the appropriate UI for each state.

### `lastUpdated` date handling

`AppPrivacyPolicy.lastUpdated` is a `String` in `yyyy-MM-dd` format, not a `Date`, because the API stores it as a plain date string. `AppPrivacyPolicyEditorViewModel` converts to/from `Date` using a static `DateFormatter` with `Locale(identifier: "en_US_POSIX")` and `TimeZone(secondsFromGMT: 0)` to ensure consistent parsing regardless of the user's locale.

---

## 13. Patterns & Conventions

### `saved` and `deleted` properties

Editor ViewModels signal completion via observable properties rather than callbacks in the VM itself:

```swift
var saved: ProjectPreview?   // Set after a successful save
var deleted = false          // Set after a successful delete
```

Views watch these with `.onChange(of:)` and call the appropriate parent callbacks:

```swift
.onChange(of: vm.saved) { _, preview in
    if let preview { onSave(preview) }
}
.onChange(of: vm.deleted) { _, gone in
    if gone { onDelete(); dismiss() }
}
```

This keeps the VM free of SwiftUI dependencies (`dismiss`, closures from parents) and makes it easier to test.

### `appendOrReplace`

List ViewModels expose `appendOrReplace(_ preview:)` to handle both create and update from the same callback:

```swift
func appendOrReplace(_ preview: ProjectPreview) {
    if let idx = projects.firstIndex(where: { $0.id == preview.id }) {
        projects[idx] = preview   // Update in place
    } else {
        projects.insert(preview, at: 0)   // Newly created
    }
}
```

### `createdAt` / `updatedAt` editing

Both posts and projects allow editing `createdAt` via a `DatePicker` in the inspector. `updatedAt` is read-only. When `createdAt` is changed to a date newer than `updatedAt`, the VM automatically sets `updatedAt = createdAt`:

```swift
var createdAt: Date? {
    didSet {
        scheduleAutosave()
        guard !isPopulating, let created = createdAt,
              let updated = updatedAt, created > updated else { return }
        updatedAt = created
    }
}
```

The `isPopulating` guard prevents this sync from firing during the initial data load (where `createdAt` is set before `updatedAt`).

### Error display

All errors surface through an `error: APIError?` property on the ViewModel. Views bind this to a standard `.alert` via a `Binding<Bool>`:

```swift
.alert("Error", isPresented: Binding(
    get: { vm.error != nil },
    set: { if !$0 { vm.error = nil } }
)) {
    Button("OK", role: .cancel) { vm.error = nil }
} message: {
    Text(vm.error?.localizedDescription ?? "")
}
```

### `deinit` / task cancellation

All autosave tasks are cancelled in `deinit`:

```swift
deinit { autosaveTask?.cancel() }
```

Long-running async calls (fetches, saves) use `Task { }` inside view `.task` modifiers, which are automatically cancelled when the view disappears. Cancellation errors are detected with `error.isCancellation` and silently discarded.

---

## 14. Known Gotchas

### SourceKit incremental analysis errors

After editing any Swift file, SourceKit often reports "Cannot find type X in scope" errors in other files. These are incremental analysis artifacts. A full build (`⌘B`) always succeeds and clears them. Do not treat them as real compilation errors.

### `navigationDestination` conflict

Having both `navigationDestination(item:)` and `navigationDestination(isPresented:)` active simultaneously on the same `NavigationStack` causes SwiftUI to resolve to the `item:` destination. Always nil out `selectedID` before setting `isCreatingNew = true`.

### `.fileImporter` in nested views on macOS

SwiftUI's `.fileImporter` cannot find its window context when applied inside `Form > Section`. Use `NSOpenPanel().runModal()` directly. This affects any file-picker button that lives inside a form.

### `.onMove` requires `List`

`.onMove` only works on `ForEach` inside a `List`. In `MediaManagerView`, media rows are in a `VStack` inside a `Form`, so drag-to-reorder is implemented with `.draggable` / `.dropDestination` instead.

### `NSTextView` delegate and teardown

Always nil the delegate in `dismantleNSView`. If the delegate is still set when AppKit tears down the scroll view, a delegate callback fires on a deallocated coordinator, causing `EXC_BAD_ACCESS`.

### Inline image paths must be relative

When inserting an image into post or project markdown content, the path must be relative (`/media/posts/slug/uuid.webp`), not absolute. The base URL is prepended at display time by `resolveMarkdownImageURLs`. Storing absolute URLs breaks when switching environments.

### `AppsRepository` uses `appendingPathComponent` not `appending(path:)`

`AppsRepository` constructs URLs with `appendingPathComponent(_:)` (the older API) rather than `appending(path:)` (iOS 16+). Both work; just be consistent when adding new endpoints.

### Draft fields and schema evolution

`PostDraft` and `ProjectDraft` are `Codable` structs stored as JSON. New optional fields can be added without breaking existing saved drafts — the decoder will set them to `nil`. Non-optional new fields require a default value or a migration strategy.
