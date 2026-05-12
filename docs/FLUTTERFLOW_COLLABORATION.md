# AVA FlutterFlow Collaboration Guide

## What Is Set Up

- FlutterFlow Desktop is installed at `C:\Program Files\FlutterFlow\flutterflow.exe`.
- GitHub CLI is installed at `C:\Program Files\GitHub CLI\gh.exe`.
- AVA workspace Git ignores now protect local SDKs, build outputs, installers, logs, uploads, app update zips, and LLM model files.
- FlutterFlow review/import scripts live in `tooling/flutterflow`.
- FlutterFlow-derived AVA code has a safe integration boundary at `Flutter/lib/src/flutterflow`.

## Product Limits To Respect

FlutterFlow is not a full two-way visual editor for arbitrary existing Flutter code. Official FlutterFlow Local Run docs state that IDE edits do not sync back into the FlutterFlow project and may be overwritten on hot reload/restart.

For collaboration, use GitHub as the contract:

- `main`: AVA source of truth for production code.
- `develop`: optional shared development branch for developers.
- `flutterflow`: FlutterFlow-managed generated-code branch.

Official FlutterFlow GitHub docs say pushed FlutterFlow code lands in the `flutterflow` branch. FlutterFlow docs also recommend creating a `develop` branch from `flutterflow` when working with GitHub-exported code.

## One-Time GitHub Setup

1. Sign in to GitHub CLI:

   ```powershell
   "C:\Program Files\GitHub CLI\gh.exe" auth login
   ```

2. Create or connect a GitHub repository for this workspace.

   If creating from this local repo:

   ```powershell
   git remote add origin https://github.com/<org-or-user>/<repo>.git
   git push -u origin main
   ```

3. In FlutterFlow:

   - Open the AVA FlutterFlow project.
   - Go to GitHub integration.
   - Connect the same GitHub repository.
   - Configure FlutterFlow to push generated code to the `flutterflow` branch.
   - Add designers/developers through FlutterFlow project/team collaboration.

## Daily Designer Flow

1. Designer edits UI in FlutterFlow.
2. Designer commits inside FlutterFlow.
3. Designer pushes/syncs to GitHub.
4. FlutterFlow updates the `flutterflow` branch.

## Daily Developer Flow

1. Fetch FlutterFlow generated code:

   ```powershell
   .\tooling\flutterflow\pull-flutterflow.ps1
   ```

2. Review generated code under:

   ```text
   .flutterflow-worktree
   ```

3. Import only reviewed files:

   ```powershell
   .\tooling\flutterflow\import-flutterflow-file.ps1 `
     -SourceRelativePath "lib/custom_widgets/example.dart" `
     -DestinationRelativePath "Flutter/lib/src/flutterflow/example.dart"
   ```

4. Adapt imported UI into AVA feature folders as needed.

5. Run checks:

   ```powershell
   .\Flutter\flutter_local.cmd analyze
   .\SpringBoot\gradlew.bat test
   ```

6. Commit to `main` or a feature branch and open a PR.

## Local Code Back To FlutterFlow

Use this only for code that FlutterFlow can understand:

- Custom widgets
- Custom actions
- Theme tokens/assets that FlutterFlow supports

Do not expect arbitrary AVA code, Riverpod providers, Windows native runner code, updater scripts, or Spring Boot code to appear visually in FlutterFlow.

For local code meant for FlutterFlow:

1. Put it into the FlutterFlow project as a custom widget/action in FlutterFlow.
2. Or edit the generated branch carefully and push to `flutterflow`, then verify inside FlutterFlow.
3. Never overwrite AVA `main` with a full FlutterFlow export.

## Useful Commands

Open FlutterFlow:

```powershell
.\tooling\flutterflow\open-flutterflow.ps1
```

Check local setup:

```powershell
.\tooling\flutterflow\check-environment.ps1
```

Pull generated FlutterFlow branch:

```powershell
.\tooling\flutterflow\pull-flutterflow.ps1
```

Push AVA source branch:

```powershell
.\tooling\flutterflow\push-main.ps1
```

## Official References

- FlutterFlow Desktop / Local Run: https://docs.flutterflow.io/testing/local-run
- FlutterFlow GitHub push: https://docs.flutterflow.io/exporting/push-to-github/
- FlutterFlow collaboration: https://docs.flutterflow.io/resources/projects/collaboration
- FlutterFlow branching: https://docs.flutterflow.io/collaboration/branching/
