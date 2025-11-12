# Terraform Modules

Each `example.<module>` repo ships with:
- **Terratest** (`test/`) to run `init` and `validate` on PRs.
- **CI workflow** (`.github/workflows/ci.yml`) for fmt, validate, tflint, checkov, terratest.
- **Release workflow** (`.github/workflows/release.yml`) using `release-please` to tag versions.

## Versioning policy
- Conventional commits → automated CHANGELOG + Git tags by release‑please.
- Infra `example.infra.live` pins module versions via Git tag (`?ref=vX.Y.Z`).
