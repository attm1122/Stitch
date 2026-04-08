# Stitch — Production Setup Guide

Complete checklist for going from the fixed codebase to a live App Store build.

---

## 1. Copy the fixed files into your Xcode project

Replace each file in your project with the version from this `stitch-production-fixes/` directory. The folder structure mirrors your repo exactly.

| Source file | What changed |
|---|---|
| `App/AppServices.swift` | Uses `KeychainStore` instead of `UserDefaults` for auth |
| `App/SettingsView.swift` | Expensify email validation + sign-out confirmation |
| `Features/Auth/AuthView.swift` | Magic link sent state with instructions |
| `Features/Auth/OnboardingView.swift` | **NEW** — first-time user onboarding sheet |
| `Features/Inbox/InboxView.swift` | Error handling, delete, onboarding trigger |
| `Features/Inbox/UploadQueueView.swift` | **NEW** — bottom sheet with upload progress |
| `Features/ReceiptDetail/ReceiptDetailView.swift` | Alerts on save failure instead of silent drop |
| `Models/AuthSession.swift` | Added `extractionError` to `ExtractedReceiptData` |
| `Services/AuthService.swift` | Added `refreshSession()` to protocol + implementation |
| `Services/AppGroupInboxService.swift` | Handles individual import errors gracefully |
| `Services/KeychainStore.swift` | **NEW** — secure token storage |
| `Services/ReceiptExtractionService.swift` | Throws on OCR failure, surfaces errors |
| `Services/ReceiptImportCoordinator.swift` | Propagates save errors, handles extraction failures |
| `Services/SessionStore.swift` | Keychain storage + `validSession()` with auto-refresh |
| `Services/UploadService.swift` | Token refresh before upload, background session, error types |
| `ShareExtension/ShareViewController.swift` | 20 MB size guard with user-facing error |
| `Supabase/functions/batch-upload-expensify/index.ts` | JWT verification, CORS scoping, input validation, localized amounts |
| `Supabase/functions/process-receipt/index.ts` | JWT verification, CORS scoping |
| `Resources/BackendConfig.plist` | **NEW** — required config file (fill in values) |
| `Resources/PrivacyInfo.xcprivacy` | **NEW** — required for App Store submission |

---

## 2. Add new files to your Xcode target

In Xcode, add these **new** files to the Stitch target (drag into the project navigator and check "Add to target: Stitch"):

- `Services/KeychainStore.swift`
- `Features/Auth/OnboardingView.swift`
- `Features/Inbox/UploadQueueView.swift`
- `Resources/BackendConfig.plist` → add to **Stitch** target (not Share Extension)
- `Resources/PrivacyInfo.xcprivacy` → add to **Stitch** target

---

## 3. Configure BackendConfig.plist

Open `Resources/BackendConfig.plist` and fill in:

```
SupabaseURL            → https://<your-project-id>.supabase.co
SupabaseAnonKey        → (from Supabase Dashboard > Settings > API)
SupabaseRedirectURL    → stitch://auth/callback
BatchUploadEndpoint    → https://<your-project-id>.supabase.co/functions/v1/batch-upload-expensify
ExpensifyDestinationEmail → (optional default, users can override)
```

---

## 4. Register the URL scheme for magic links

In Xcode, select the **Stitch** target > Info > URL Types > click **+**:

- Identifier: `com.attm1122.Stitch`
- URL Schemes: `stitch`

This makes `stitch://auth/callback` open your app when a magic link is tapped.

---

## 5. Handle the magic link callback in your app entry point

In your `@main` App struct (or `StitchApp.swift`), add:

```swift
.onOpenURL { url in
    Task {
        await services.sessionStore.handleIncoming(url: url)
    }
}
```

---

## 6. Deploy the Supabase Edge Functions

```bash
# Install Supabase CLI if needed
brew install supabase/tap/supabase

# Log in
supabase login

# Link to your project
supabase link --project-ref <your-project-id>

# Deploy both functions
supabase functions deploy batch-upload-expensify
supabase functions deploy process-receipt
```

---

## 7. Set Edge Function secrets in Supabase

In the Supabase Dashboard > Edge Functions > Manage secrets, add:

| Secret | Value |
|---|---|
| `RESEND_API_KEY` | Your Resend API key (https://resend.com) |
| `STITCH_FROM_EMAIL` | A verified sender email on Resend (e.g. `stitch@yourdomain.com`) |
| `ALLOWED_ORIGINS` | Leave empty for any origin, or set a comma-separated list of allowed iOS app origins |

The `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are automatically injected by Supabase — do not set them manually.

---

## 8. Verify App Group is configured

Both the Stitch app and the Share Extension must share the same App Group:

1. Stitch target > Signing & Capabilities > + Capability > **App Groups**
2. Add group: `group.com.attm1122.Stitch`
3. Repeat for the **ShareExtension** target

---

## 9. Add PrivacyInfo.xcprivacy to the target

Xcode sometimes doesn't pick up the privacy manifest automatically:

1. Select `PrivacyInfo.xcprivacy` in the project navigator
2. In the File Inspector (right panel), ensure "Target Membership" includes **Stitch**
3. Build the app — Xcode will validate the manifest format

---

## 10. Set minimum deployment target

Stitch uses SwiftData and VisionKit features that require iOS 17.0+. Ensure:

- Stitch target > General > Minimum Deployments → **iOS 17.0**
- ShareExtension target → same

---

## 11. Pre-submission checklist

- [ ] `BackendConfig.plist` filled in and added to Stitch target
- [ ] `PrivacyInfo.xcprivacy` added to Stitch target
- [ ] URL scheme `stitch://` registered in Info.plist
- [ ] `onOpenURL` handler added for magic link callback
- [ ] App Group `group.com.attm1122.Stitch` enabled on both targets
- [ ] Edge functions deployed and secrets configured
- [ ] App builds with no warnings for "missing privacy manifest"
- [ ] Tested magic link flow end-to-end on a physical device
- [ ] Tested Share Extension with a PDF from Mail
- [ ] Tested batch upload with at least 3 receipts
- [ ] App Archive completes without errors in Xcode Organizer

---

## Notes on demo mode

If `SupabaseURL` or `SupabaseAnonKey` are empty in `BackendConfig.plist`, the app automatically runs in **demo mode**:
- Auth works locally (no server calls)
- Upload runs a simulated delay and marks receipts as uploaded
- All UI flows are functional for testing

This is intentional and useful for UI testing and TestFlight builds before Supabase is wired up.
