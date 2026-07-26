# POWERLINE_V2_HANDOFF.md
Durable handoff so the next session continues without amnesia. Preserve → commit → build.

## CURRENT VERIFIED STATE
- Repository: https://github.com/awwmit-69/Powerline
- Default branch: `main`
- Current commit SHA: `6566db6` (build #14 — AZD re-theme source)
- Build #14 result: GREEN — web + deploy + windows jobs all succeeded (verified via the published release + Pages deploy, both gated on green jobs)
- Windows V2 release tag: `windows-preview-v2` (marked Latest)
- Windows V2 ZIP URL: https://github.com/awwmit-69/Powerline/releases/download/windows-preview-v2/PowerLine-Windows-Preview-V2.zip
- Web V2 URL: https://awwmit-69.github.io/Powerline/  (hard-refresh twice for service worker until versioning is fixed)
- Old release preserved: tag `windows-preview` + asset `PowerLine-Windows-Preview.zip` (untouched)
- Website staging URL (separate repo `awwmit-69/azd-staging`): https://awwmit-69.github.io/azd-staging/
- Stable website folder: `D:\Project Data\AZD Global\Website\AZD-Staging-V2\`
- Website ZIP: `D:\Project Data\AZD Global\Website\AZD-Staging-V2.zip`

## WORK COMPLETED (PowerLine V2)
- AZD palette conversion: done, applied app-wide via `PowerlineColors`.
- Exact color tokens (lib/core/theme/theme.dart):
  - navy `#0B1B2B`, panel `#102A40`, raised `#15202E`, border `#243444`
  - textPrimary(mineral) `#F4F2EC`, textSecondary(silver) `#AEB9C7`
  - cobalt `#2C6BFF`, cobaltDeep `#1E4FCC`, cyan `#38E1D6`, violet `#7C5CFF`
  - stateRinging(amber) `#E0A537`, stateConnected(emerald) `#12B981`, stateHold(cobalt) `#2C6BFF`, stateFailed(red) `#E5675A`, stateVoicemail(violet) `#7C5CFF`
- Crimson removal result: 0 crimson colors/variables in `lib/` (only a comment says "no crimson"). Old `crimson`/`crimsonBright`/`graphite*` variables renamed out.
- Manrope declaration: pubspec.yaml `fonts: family: Manrope -> assets/fonts/Manrope-var.ttf`; ThemeData `fontFamily: 'Manrope'`.
- JetBrains Mono declaration: pubspec.yaml `family: JetBrainsMono -> assets/fonts/JetBrainsMono-var.ttf` (intended for technical labels).
- CI font-bundling step: build.yml downloads the variable TTFs into `assets/fonts/` during BOTH web and windows jobs (Google Fonts via raw.githubusercontent), so fonts are baked into the compiled artifacts.
- Windows V2 release workflow: build.yml zips `PowerLine-Windows-Preview-V2.zip` and publishes release `windows-preview-v2` (plus keeps the original).
- Web deployment: GitHub Pages via deploy-pages (base-href /Powerline/).
- Current test status: backend 11 tests pass (prior). Flutter analyze/test run NON-BLOCKING in CI (logged, `|| true`) — real pass/fail totals NOT yet gated. No golden/integration tests yet.
- Feature-status ledger:
  - FUNCTIONAL WITH SAMPLE DATA: Dashboard, Dialpad, Messages, Calls, Voicemail, Contacts, Campaigns, AI Agents, Analytics, Settings
  - UI COMPLETE, BACKEND PENDING: provider setup, CRM connection
  - PROVIDER TEST PENDING / NOT LIVE: real SIP calling (mock adapter only)
  - NOT IMPLEMENTED: real SIP/WebRTC media, golden screenshots, structural per-screen redesign

## WORK NOT COMPLETED
- Full source-tree normalization (repo still uses opaque `powerline_src.zip` as source-of-truth)
- Pre-V2 backup tag/branch (candidate = commit `ae5cc91`, build #12, pre-re-theme dashboard source; NOT yet tagged — see RISKS)
- Font files committed directly to assets/fonts/ (currently CI-downloaded)
- Font-license files
- Structural redesign of every PowerLine screen (only palette+typography changed so far — NOT a structural redesign)
- Real production SIP adapter (still mock)
- SIP automated tests
- Golden screenshot harness (Method C)
- Twelve screenshot outputs
- Website placeholder replacement (site still shows PowerLine placeholders)
- Website republish after screenshots
- HubSpot audit and implementation (explicitly blocked until above done)

## CURRENT LIMITATIONS
- Real SIP audio NOT verified. Calling layer is a MOCK adapter.
- Provider registration is NOT live. No live inbound/outbound call verification.
- Screens use deterministic sample data.
- Website still contains PowerLine screenshot placeholders.
- V2 ZIP has NOT been independently downloaded+inspected (sandbox is proxy-blocked from GitHub release-asset downloads).

## FILES CHANGED (V2 pass)
- `lib/core/theme/theme.dart` — rewrote PowerlineColors to AZD palette; renamed graphite*/crimson* -> navy/panel/raised/cobalt/cobaltDeep; header comment updated; signal-bar color -> mineral; added `fontFamily: 'Manrope'`.
- `lib/features/agents/agents_screen.dart` — color token references updated (crimson*/graphite* -> new tokens).
- `lib/features/call/active_call_screen.dart` — same (color-only).
- `lib/features/contacts/contacts_screen.dart` — same.
- `lib/features/home/home_screen.dart` — same.
- `lib/features/messages/messages_screen.dart` — same.
- `lib/features/shell/app_shell.dart` — same.
- `lib/features/voicemail/voicemail_screen.dart` — same.
- `pubspec.yaml` — added `fonts:` (Manrope + JetBrainsMono) pointing to assets/fonts/*.ttf; added assets/fonts/.gitkeep.
- `.github/workflows/build.yml` — added "Bundle fonts" curl step (web+windows); added V2 zip + `windows-preview-v2` release (kept original).

## CI WORKFLOW
- Workflow filename: `.github/workflows/build.yml`
- Trigger: `push` to main + `workflow_dispatch`
- Font-download step: curl variable TTFs from `raw.githubusercontent.com/google/fonts` into `flutter_app/assets/fonts/` (web job bash; windows job `shell: bash`)
- Web build job (`web`, ubuntu): checkout -> unzip powerline_src.zip -> reset web/index.html -> flutter-action -> flutter create -> bundle fonts -> pub get -> format/analyze/test (non-blocking) -> `flutter build web --release --base-href /Powerline/` -> upload pages artifact
- Windows build job (`windows`, windows-latest): checkout -> Expand-Archive -> remove stub windows/ -> flutter create -> bundle fonts -> pub get -> `flutter build windows --release` -> zip
- Release-publication step: `softprops/action-gh-release@v2` x2 (tag `windows-preview` kept; tag `windows-preview-v2` new)
- GitHub Pages deployment step: `deploy` job uses `actions/deploy-pages@v4`
- V2 release asset name: `PowerLine-Windows-Preview-V2.zip`

## NEXT EXECUTION ORDER
1. Normalize repository source tree (commit real files, stop using the zip)
2. Create pre-V2 backup tag (`powerline-pre-azd-v2` at `ae5cc91`)
3. Commit actual font assets + licenses; drop CI font-download
4. Build golden screenshot harness (Method C)
5. Generate twelve real Flutter screen captures (1440x960 desktop; 430x932 narrow)
6. Complete structural redesigns (layout/hierarchy/empty/error states per screen)
7. Implement real SIP provider abstraction (WebRTC/SIP; sip_ua/flutter_webrtc)
8. Add provider tests (mock transport)
9. Rebuild Windows + Web
10. Replace website placeholders with real screenshots
11. Republish AZD staging
12. Begin HubSpot work

## KNOWN RISKS
- Repo relies on an opaque `powerline_src.zip` (not a normal versioned tree).
- CI downloads fonts at build time rather than versioning them.
- A theme swap exists WITHOUT a full structural redesign — do not overstate "perfected".
- Mock SIP may look more complete than it is.
- V2 ZIP has not been independently inspected after download.
- Website screenshots are still placeholders.

## PRE-V2 BACKUP CANDIDATE (uncertainty noted)
- Best confirmed pre-V2 source commit: `ae5cc91` (build #12, "Add files via upload", dashboard command-center, pre-crimson-removal).
- Intervening: `a5af38d` (build #13, workflow-only update).
- V2 source: `6566db6` (build #14).
- Recommended backup: tag `powerline-pre-azd-v2` -> `ae5cc91`, and/or branch `backup/pre-azd-v2` from `ae5cc91`.
