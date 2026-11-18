# Branch workflow

- Before making changes for a new feature, create and switch to a feature branch.
  Use the `codex/` prefix by default.
- Use one branch per feature. Keep refinements, follow-up changes, and validation
  repairs for the same feature on its existing branch, including in future chats.

# Versioning and change records

After each completed app change, update the app version and record the change
inside the app. Treat a coherent change as one release, rather than bumping the
version for every file edit or validation repair.

- Use a patch bump for bug fixes and small improvements, a minor bump for new
  backward-compatible features, and a major bump for breaking changes. For a
  release with several changes, use the highest applicable magnitude.
- Increment the build number in `pubspec.yaml` for every version bump.
- Prepend a dated release entry in `lib/models/app_release.dart`, describing the
  user-visible changes in plain language. Keep existing entries so Settings →
  About → Change history remains a permanent record.
- Add the matching version, build number, date, and changes to `CHANGELOG.md`.
- Keep `pubspec.yaml` and the newest in-app release entry synchronized. Verify
  the release record and run checks appropriate to the implementation.
