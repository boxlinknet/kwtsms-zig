# GitHub Workflow

## Solo Dev Flow (Trunk-Based)

```
main ──commit──commit──commit── [tag v0.2.0] ──commit──
```

1. Commit directly to `main`
2. When ready to release: go to **Actions > Create Release > Run workflow** > pick bump type (patch/minor/major)
3. Everything else is automated

## Automation Stack

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| **CI** | Push/PR to main, weekly cron | Build + format check + test |
| **Release** | `v*` tag pushed | Build cross-platform binaries, create GitHub Release with artifacts |
| **Create Release** | Manual dispatch | Bump version in `build.zig.zon`, commit, tag (triggers Release) |
| **Dependabot** | Weekly | Update GitHub Actions versions |
| **Auto-merge Dependabot** | Dependabot PR | Auto-approve + squash merge |
| **Label PRs** | PR opened/updated | Auto-label by changed file paths |
| **Stale** | Weekly (Monday) | Mark stale after 60 days, close after 14 more |

## Release Binaries

Each release automatically builds and attaches binaries for:

| Platform | Artifact |
|----------|----------|
| Linux x86_64 | `kwtsms-linux-x86_64` |
| Linux aarch64 | `kwtsms-linux-aarch64` |
| Windows x86_64 | `kwtsms-windows-x86_64.exe` |
| macOS aarch64 (Apple Silicon) | `kwtsms-macos-aarch64` |
| macOS x86_64 (Intel) | `kwtsms-macos-x86_64` |

## Branch Protection (main)

- CI must pass before merge (strict mode)
- Force pushes disabled
- Admin bypass enabled (so you can still push directly as solo dev)

## Required Repo Settings

These must be enabled manually in GitHub repo settings:

- **Allow auto-merge**: Settings > General > Pull Requests > Allow auto-merge
  (required for Dependabot auto-merge workflow to work)

## How to Release

1. Go to **Actions** tab on GitHub
2. Click **Create Release** workflow
3. Click **Run workflow**
4. Pick bump type: `patch` / `minor` / `major` (or enter a custom version)
5. The workflow will:
   - Bump version in `build.zig.zon`
   - Commit the change
   - Create and push a `v*` tag
   - Tag push triggers the **Release** workflow
6. Release workflow builds 5 platform binaries and creates a GitHub Release with auto-generated notes

## Issue Templates

- **Bug Report** — description, repro steps, Zig version, OS
- **Feature Request** — problem, proposed solution, alternatives
- Blank issues disabled — users must pick a template or use Discussions

## PR Template

Auto-populated with summary, changes, and test plan checklist.

## Labels (auto-applied to PRs)

| Label | Files |
|-------|-------|
| `ci` | `.github/**` |
| `documentation` | `*.md`, `LICENSE` |
| `source` | `src/**` |
| `build` | `build.zig`, `build.zig.zon` |
| `examples` | `examples/**` |
| `dependencies` | `build.zig.zon` |

## Exempt from Stale Bot

Add label `pinned` or `keep` to any issue/PR to exempt it from auto-closing.
