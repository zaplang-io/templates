# Release readiness and publication checklist

The manifest's development version is `0.1.0`. No package registry publication,
release tag or full Jinja compatibility is implied by merged implementation PRs.
The repository uses Apache License 2.0; retain `LICENSE` in distributions.

Before proposing a release:

- Review `SUPPORT.md` against the final code and fixture counts. Record deliberate
  differences and unsupported syntax rather than claiming full Jinja support.
- Update version metadata and write release notes describing supported APIs,
  compatibility boundaries, resource limits, loader trust and numeric limits.
- Regenerate fixtures with exact `tools/fixtures-requirements.txt` versions and run
  `sh tools/check-fixtures.sh` with `FIXTURE_PYTHON`/`ZAP` configured. The check must
  leave all six JSON/Zap artifacts byte-for-byte unchanged.
- Run `zap fmt --check src tests examples`, `sh tools/run-tests.sh`,
  `sh tools/check-package.sh`, and `sh tools/check-example.sh` with the published,
  pinned codegen-enabled toolchain. Review native CI at the exact proposed commit.
- When changing the toolchain image, update both CI image references together and
  rerun all checks, including regeneration. The current pin is
  `ghcr.io/zaplang-io/zap@sha256:593d82a7938f1fc7f4fb1ead916309089ee17537a1c83ec797bb97a55a82faec`.
- Confirm the external consumer resolves the full package and source submodules;
  inspect `zap publish --dry-run` output and distribution contents.
- Have the user review and explicitly approve that specific PR's merge. Keep
  failing or blocked PRs unmerged. Close the parent `zaplang-io/zap#313` only after
  all four implementation issues are complete and reviewed PRs are merged.
- Publish/tag only when the user explicitly requests it. Registry publication,
  credentials and release tagging are separate from this readiness work.

The release does not remove these application responsibilities: trusted template
sources and filesystem trees, URL/context-specific escaping, JSON-shaped inputs,
explicit cache invalidation, and environment synchronization between workers.
