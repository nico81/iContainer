# Versioning

iContainer uses semantic versioning for the public app version:

- `MAJOR`: large product or compatibility changes.
- `MINOR`: new user-visible features.
- `PATCH`: fixes and small refinements.

Xcode stores the public version in `MARKETING_VERSION` and the build number in
`CURRENT_PROJECT_VERSION`.

## Workflow

During development, add notes under `CHANGELOG.md` > `Unreleased`.

When a version is ready to consolidate:

1. Move the `Unreleased` entries into a dated version section.
2. Update `MARKETING_VERSION`.
3. Increment `CURRENT_PROJECT_VERSION`.
4. Commit the release metadata.
5. Create a Git tag named `vMAJOR.MINOR.PATCH`.

Example tag:

```sh
git tag v1.1.0
```

