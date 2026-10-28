# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Folio is a native SwiftUI CMS client for the user's portfolio site (a Node.js/Express REST API at jordan-christensen.com). It manages three kinds of content: **Projects** (`/api/projects`), **Posts** (`/api/posts`, markdown blog posts), and **Apps** (`/api/apps/:id/privacy-policy` and `/support`). There's no database access; everything goes through the site's HTTP API with a Bearer token.

One multiplatform target (iOS 26.2, macOS 26.1, and visionOS 26.2 in `SUPPORTED_PLATFORMS`; not Catalyst). The only package dependency is [Textual](https://github.com/gonzalezreal/textual) (`StructuredText(markdown:)` with `.textual.structuredTextStyle(.gitHub)`) for the markdown preview.

`DEVDOC.md` is the detailed developer documentation (architecture, draft system, media, gotchas). Read the relevant section before changing a subsystem, and update it when you change how one works.

## Build settings that matter

- `SWIFT_VERSION = 5.0` (Swift 5 language mode) with `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Everything is `@MainActor` by default; don't add the annotation. Code that must run off the main actor needs an explicit `nonisolated` or `@concurrent`. (DEVDOC.md calls this "Swift 6"; it's the Swift 6 compiler in Swift 5 mode.)
- `PBXFileSystemSynchronizedRootGroup`: new files in `Folio/` join the build automatically. Don't edit `project.pbxproj` to add files.
- The macOS app is sandboxed with outgoing network connections and read-only user-selected files.

## Setup

There's no build-time configuration. Base URLs and API keys are entered at runtime in Settings, per environment (Dev/Prod): URLs in UserDefaults, keys in the Keychain (`KeychainService`), all keys named in `FolioStorageKey`. `Info.plist` only allows plain HTTP to `localhost`. `*.xcconfig` is gitignored. **Never hardcode or commit an API key or base URL.**

**Folio writes to the live portfolio site.** Never run the app, a test, or a `curl` against the Prod environment or jordan-christensen.com in a way that creates, updates, deletes, or uploads anything without asking the user and getting an explicit yes, every time. Read-only `GET`s are fine. Tests must never touch the network (use fakes; see Testing).

## Commands

There's no linter or formatter. Build and test with `xcodebuild` (or Xcode):

```sh
# Build (macOS is fastest)
xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=macOS'

# Build for iOS
xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Unit tests (Swift Testing)
xcodebuild test -project Folio.xcodeproj -scheme Folio -destination 'platform=macOS' -only-testing:FolioTests

# One suite, or one test (Swift Testing functions include their parentheses)
xcodebuild test ... -only-testing:'FolioTests/DraftStoreTests'
xcodebuild test ... -only-testing:'FolioTests/DraftStoreTests/changedLineRanges()'
```

Build both macOS and iOS after touching anything behind `#if os(macOS)` or in `MarkdownEditorView` (it's two separate implementations). SourceKit often reports "Cannot find type X in scope" across files after an edit; trust `xcodebuild`, not the editor diagnostics.

## Git workflow

`main` is the only branch. Commit only when the user asks. When asked, branch off `main` first (`fix/…` or `feature/…`, named after the task) unless the user says to commit to `main`.

The user edits in this checkout too, and often has staged and unstaged work in progress. Commit only your own files, by explicit path (never `git add -A` or `git commit -a`), and leave changes you didn't make alone. If they'd block switching branches, ask instead of stashing or discarding them.

## Architecture

```
Views ──► ViewModels (@Observable) ──► Repositories ──► URLProcessor ──► URLSession
```

Files are flat in `Folio/` (models in `Folio/Models/`, the `@main` app in `Folio/Resources/FolioApp.swift`).

- **Networking.** `URLProcessor.fromSettings()` builds a client from the *active* environment's URL and key on every call, so switching environments in Settings takes effect immediately. Everything in the networking layer uses typed throws: `throws(APIError)`. `GET`s are unauthenticated; `POST`/`PUT`/`DELETE` and uploads send the Bearer token. `APIError.isCancellation` filters out cancelled requests, which are never shown to the user.
- **Repositories** (`ProjectRepository`, `PostRepository`, `MediaRepository`, `AppsRepository`) are stateless and map one method to one endpoint. Edits send partial payloads (`ProjectUpdate`, `PostUpdate`) whose `encode(to:)` uses `encodeIfPresent`, so a `nil` field is left out of the request, not cleared.
- **List → detail.** Each tab (`ContentView`, a `.sidebarAdaptable` `TabView`) owns a `NavigationStack` with `List(selection:)`, a list view model, `selectedID`, and `isCreatingNew`. Edit opens through `.navigationDestination(item:)`, create through `.navigationDestination(isPresented:)`. **Set `selectedID = nil` before `isCreatingNew = true`**, or SwiftUI shows the selected item's editor instead of the create form.
- **Editors** own a fresh view model per push (`@State var vm`), loaded in `.task { await vm.load() }`. They report back through observable `saved` / `deleted` properties that the view forwards to `onSave` / `onDelete` with `.onChange`, so view models never hold SwiftUI closures or `dismiss`. The inspector (`.inspector(isPresented:)`) holds status, dates, and Delete.
- **Drafts.** `DraftStore` writes `PostDraft` / `ProjectDraft` JSON to Application Support (`post-<id>`, `post-new`, …). Form fields call `scheduleAutosave()` in `didSet` (debounced 2 s). Anything that sets fields programmatically (loading, restoring, resetting) wraps the assignments in `isPopulating = true … false`, or it schedules an autosave of half-populated data. In edit mode the draft is layered over the server data; `serverContent` / `serverDescription` keep the server's version as the baseline for **Show Changes** (`computeChangedLineRanges(from:to:)`). Drafts are Codable: add new fields as optionals so existing drafts still decode.
- **Markdown editing.** `MarkdownEditorView` wraps `NSTextView` (macOS) / `UITextView` (iOS). Toolbar buttons send an `EditorAction` through the `pendingAction` binding rather than calling the text view. The coordinator's `isUpdating` flag suppresses the text-changed callback during programmatic edits, and `dismantleNSView` must nil the delegate. Diff highlighting is macOS only (layout manager temporary attributes).
- **Media paths are relative.** The server returns paths like `/media/posts/<id>/<uuid>.webp`. Store them as-is, in model fields and inside markdown, never with a base URL (dev and prod differ). Resolve them only for display: `mediaURL(for:)` for `AsyncImage`, `resolveMarkdownImageURLs(_:)` before `StructuredText`. Hero images are held as a `PendingImage` and uploaded on save; inline and gallery images upload immediately.
- **Apps.** The API has no "list apps" endpoint, so the app slugs live in UserDefaults (`folio.apps`, `AppsViewModel`). Privacy policies store `lastUpdated` as a `yyyy-MM-dd` string, converted with a POSIX, UTC `DateFormatter`.
- **macOS file pickers** use `NSOpenPanel().runModal()`, because `.fileImporter` inside `Form > Section` silently does nothing on macOS. Media reordering uses `.draggable` / `.dropDestination`, since `.onMove` needs a `List`.

## Testing

`FolioTests` (Swift Testing) and `FolioUITests` (XCTest) exist but contain only templates. Build out `FolioTests` as you go:

- **Every bug fix includes a test that fails without the fix and passes with it.** Put it in `FolioTests/<TypeName>Tests.swift` (create it if needed) and mark it with a `/// Regression test: …` doc comment explaining the bug. If the logic lives in a view, move it into the view model or a free function first. Changing copy isn't a bug fix and gets no test.
- Pure helpers are tested directly: `computeChangedLineRanges`, `resolveMarkdownImageURLs`, `mediaURL(for:)`, `ProjectUpdate` / `PostUpdate` encoding, slug generation, `APIError` mapping.
- View models create their repositories directly today (`private let repo = PostRepository()`). To test one, give its initializer a `repo: any PostRepositoryProtocol = PostRepository()` parameter (the protocols already exist) and pass a fake in tests. Do the same for anything that reads UserDefaults, the Keychain, or the file system: inject it, with the real one as the default.
- Tests never hit the network or the real Keychain, and never write drafts into the real Application Support folder.
- Run the affected suite before calling a change done.

## Style guide

These conventions come from TrekPoint. Match them.

### Whitespace and formatting

- Indent with **4 spaces**, never tabs.
- **Blank lines are indented to match the next non-blank line** (this is Xcode's behavior). A blank line between two statements indented 8 spaces contains 8 spaces, not zero. Only blank lines at file scope (between top-level declarations) are truly empty. The Edit tool can strip this whitespace from blank lines in `new_string`, so check `git diff` for added blank lines with no indentation. Never strip the whitespace from lines you didn't change. For example (the blank lines below contain 4 and 8 spaces):

  ```swift
  func save() async {
      isSaving = true
      
      if let pending = pendingHeroImage {
          heroImage = try await upload(pending)
          
          pendingHeroImage = nil
      }
  }
  ```
- One blank (indented) line between members, and between logical groups of statements inside a function.
- Long initializers and calls with many arguments may stay on one line. Break them onto one-argument-per-line when that reads better.

### Comments

- Use `// MARK: - Section` to organize files, and put extensions under `// MARK: - Functions` / `// MARK: - Computed Properties`.
- Use `// TODO: - Description` for known follow-ups and `// NOTE: - Description` for non-obvious explanations. Keep the `: - ` form so they show up in Xcode's jump bar.
- Use `///` doc comments on non-obvious helpers and on anything with a warning (e.g. `/// > Warning:`).

### Swift idioms

- View models are `@Observable class`. (TrekPoint writes `@Observable @MainActor class`; here `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes the annotation redundant, so leave it off.) Dependencies come in through the initializer with the live one as the default (`init(repo: any PostRepositoryProtocol = PostRepository())`) and are stored as `private let`. Properties that views shouldn't observe are `@ObservationIgnored`.
- Views declare an explicit `init` and store their inputs as `private let` properties. Callbacks are named `onX` (`onSave`, `onDelete`, `onSelect`). A view that creates its view model holds it in `@State private var vm`; one that's handed a view model takes it as `@Bindable private var vm`.
- Prefer `if` / `switch` **expressions** and implicit returns (computed properties returning a `switch` directly).
- Use `case let .foo(bar)` for pattern binding, not `case .foo(let bar)`.
- Use `[weak self]` in closures and tasks stored on view models.
- Nested types for scoped helpers, `fileprivate` / `private struct` for view-local subviews.
- Extensions of other types go in `Folio/Helpers/Type+Topic.swift` (e.g. `String+Slug.swift`, `View+ErrorAlert.swift`).
- Platform differences go behind `#if os(macOS)`; iOS-only modifiers (`.keyboardType`, `.textInputAutocapitalization`) behind `#if !os(macOS)`.
- Prefer one shared implementation over copies: posts, projects, and app pages share `MarkdownToolbar`, `HeroImageRow`, `PendingImage` loading, `String.slugified`, and `DraftSession`. Extend those rather than adding another copy.

### Errors and user feedback

- Throw typed errors (`throws(APIError)`, `KeychainService.KeychainError`). View models catch them into `var error: (any LocalizedError)?` (or `APIError?`), and views show it with `.errorAlert($vm.error)`. Cancellations (`APIError.isCancellation`) are never shown.
- Destructive actions go through a `.confirmationDialog`.
- Don't swallow errors the user would want to know about (saving, uploading, deleting) with `try?`, and don't use `print` for error handling.

### Accessibility and input

- Icon-only buttons use `Button("Title", systemImage:)` with `.labelStyle(.iconOnly)`, so they keep an accessibility label.
- Primary actions have keyboard shortcuts (⌘S save/publish, ⌘R refresh, ⌘⌫ delete); keep them when adding actions.

### Previews

Every view file ends with a `#Preview`, using `@Previewable @State` for bindings and the `Test…` fakes (`TestPostRepository`, `TestProjectRepository`, `TestMediaRepository`, …) for view models, so previews never reach a server.

## Gotchas

- Use `url.path(percentEncoded: false)` with `FileManager`, not `url.path()`, which percent-encodes spaces (like in "Application Support") so files never seem to exist.
- Never change `@State` or other observed state from inside `body` or `updateNSView` / `updateUIView` synchronously if you can avoid it; it causes "Modifying state during view update" warnings and update loops. `MarkdownEditorView` currently clears `pendingAction` there, so be careful extending it.
- `FlowLayout` (in `PostEditorView.swift`) must return the proposed width from `sizeThatFits`; returning anything else causes an infinite layout loop on macOS.
- The `createdAt` `didSet` bumps `updatedAt` when the new date is later. It's guarded by `isPopulating`, so set `createdAt` before `updatedAt` only inside a populate block.
