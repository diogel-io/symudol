# Android Diogel

Android Diogel is the mobile app codebase for Diogel.

A privacy-first Nostr signer and identity-security companion app, with Android as the immediate primary target.

## Product intent

Android Diogel exists to reduce private-key exposure.

The app is being built around a simple trust model:
- keep sensitive signing material on the phone
- make approval flows explicit
- let users manage multiple Nostr identities cleanly
- avoid turning the signer into a vague all-purpose crypto app

The aim is not to build a bloated everything-app.
The aim is to build a serious signer product that does a small number of important things well.

## Current state

This repository is still early.

Right now it contains:
- a real Flutter app scaffold
- early Material 3 theming
- Diogel design tokens
- a prototype UI shell for unlock, accounts, requests, and settings flows
- an initial feature-based structure rather than a single giant `main.dart`

It should be treated as a foundation in progress, not as a production-ready signer yet.

## Project structure

Current high-level app structure:
- `lib/app/` - app entry and root wiring
- `lib/features/unlock/` - unlock flow prototype
- `lib/features/navigation/` - main navigation shell
- `lib/features/accounts/` - account/identity screens
- `lib/features/requests/` - signing request review UI
- `lib/features/settings/` - settings UI
- `lib/theme/` - shared theme and token definitions

## Related planning docs

Product planning and review docs live in the workspace project folder:
- `/root/.openclaw/workspace/projects/android-diogel`

Important documents there currently include:
- `README.md`
- `repo-review-2026-04-27.md`
- `objective.md`
- `mvp-scope.md`
- `user-flows.md`

Those docs are the current source of truth for product direction while the app is still taking shape.

## Immediate development priorities

1. keep the app structure clean and feature-oriented
2. define the session/security model explicitly before deep signer logic lands
3. implement bounded MVP slices instead of vague large rewrites
4. keep trust, provenance, and approval clarity central to the UI

## What this app is not

Android Diogel is not currently trying to be:
- a full social Nostr client
- a generic crypto wallet
- a kitchen-sink privacy dashboard
- a fake-finished prototype padded with marketing language

## Tech stack

- Flutter
- Dart
- Material 3
- `dart_nostr` (Verified: sufficient for key generation, derivation, nsec/npub encoding/decoding, and Schnorr signing)

## Development stance

This codebase should prefer:
- small bounded refactors
- explicit architecture over accidental architecture
- honest security language
- clear approval flows
- meaningful tests that match real app behavior

## Status reminder

Promising start, still early.
The important job now is to keep the architecture sane before real signer/security complexity lands.
