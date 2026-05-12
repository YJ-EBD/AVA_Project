import 'dart:async';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_version.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_api.dart';
import '../data/app_update_api.dart';

class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate> {
  bool _checked = false;
  bool _checkScheduled = false;
  bool _checkInProgress = false;
  bool _dialogOpen = false;
  bool _retryAfterCurrentCheck = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleCheck();
    });
  }

  void _scheduleCheck({Duration delay = Duration.zero}) {
    if (_checkScheduled ||
        _checkInProgress ||
        _checked ||
        _dialogOpen ||
        !io.Platform.isWindows) {
      return;
    }
    _checkScheduled = true;
    Future<void>.delayed(delay, () async {
      _checkScheduled = false;
      if (mounted) {
        await _checkForUpdate();
      }
    });
  }

  Future<void> _checkForUpdate() async {
    if (_checked || _checkInProgress || _dialogOpen || !io.Platform.isWindows) {
      return;
    }
    _checkInProgress = true;
    try {
      await _waitForStartupRoute();
      if (!mounted) {
        return;
      }
      _checked = true;
      final manifest = await ref.read(appUpdateApiProvider).windowsLatest();
      if (!mounted ||
          !manifest.updateAvailable ||
          manifest.downloadUrl.isEmpty ||
          manifest.fileName.isEmpty) {
        return;
      }
      final dialogContext = await _rootNavigatorContext();
      if (!mounted || dialogContext == null || !dialogContext.mounted) {
        _checked = false;
        _retryAfterCurrentCheck = true;
        return;
      }
      _dialogOpen = true;
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: !manifest.required,
        builder: (context) => _AppUpdateDialog(manifest: manifest),
      );
    } on Object {
      // Update checks must never block normal app startup.
    } finally {
      _checkInProgress = false;
      _dialogOpen = false;
      if (_retryAfterCurrentCheck) {
        _retryAfterCurrentCheck = false;
        if (mounted) {
          _scheduleCheck(delay: const Duration(seconds: 1));
        }
      }
    }
  }

  Future<void> _waitForStartupRoute() async {
    try {
      await ref
          .read(authControllerProvider.future)
          .timeout(const Duration(seconds: 8));
    } on Object {
      // Updating is best-effort; auth startup should not block the app forever.
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<BuildContext?> _rootNavigatorContext() async {
    for (var attempt = 0; attempt < 10; attempt += 1) {
      final navigator = widget.navigatorKey.currentState;
      final navigatorContext = navigator?.context;
      if (navigator != null &&
          navigator.mounted &&
          navigatorContext != null &&
          navigatorContext.mounted) {
        return navigatorContext;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AuthState>>(authControllerProvider, (previous, next) {
      if (!next.isLoading) {
        _scheduleCheck(delay: const Duration(milliseconds: 700));
      }
    });
    return widget.child;
  }
}

class _AppUpdateDialog extends ConsumerStatefulWidget {
  const _AppUpdateDialog({required this.manifest});

  final AppUpdateManifestDto manifest;

  @override
  ConsumerState<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

enum _UpdatePhase { idle, downloading, installing, restarting }

class _AppUpdateDialogState extends ConsumerState<_AppUpdateDialog> {
  double? _progress;
  String? _error;
  bool _updating = false;
  _UpdatePhase _phase = _UpdatePhase.idle;

  String _phaseMessage(_UpdatePhase phase) {
    return switch (phase) {
      _UpdatePhase.installing => '업데이트중. . .',
      _UpdatePhase.restarting => '재시작중. . .',
      _ => '업데이트중. . .',
    };
  }

  @override
  Widget build(BuildContext context) {
    final manifest = widget.manifest;
    final progress = _progress;
    final phase = _phase;
    return AlertDialog(
      title: const Text('AVA 업데이트'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('새 버전 ${manifest.latestVersion}이 준비되었습니다.'),
            const SizedBox(height: 6),
            Text(
              '현재 버전 ${AppVersion.name}',
              style: const TextStyle(color: Color(0xFF6F7782), fontSize: 12),
            ),
            if (manifest.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                manifest.releaseNotes,
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
            ],
            if (_updating && phase == _UpdatePhase.downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                progress == null
                    ? '업데이트 파일을 준비하고 있습니다.'
                    : '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}% 다운로드 중',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (_updating && phase != _UpdatePhase.downloading) ...[
              const SizedBox(height: 16),
              _UpdateBusyStatus(message: _phaseMessage(phase)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFC62828), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!manifest.required)
          TextButton(
            onPressed: _updating ? null : () => Navigator.of(context).pop(),
            child: const Text('나중에'),
          ),
        FilledButton(
          onPressed: _updating ? null : _downloadAndInstall,
          child: const Text('업데이트'),
        ),
      ],
    );
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _updating = true;
      _phase = _UpdatePhase.downloading;
      _progress = null;
      _error = null;
    });

    try {
      final api = ref.read(appUpdateApiProvider);
      final url = api.absoluteDownloadUrl(widget.manifest.downloadUrl);
      final updateDir = await _updateWorkingDirectory();
      final zipPath =
          '${updateDir.path}${io.Platform.pathSeparator}${widget.manifest.fileName}';

      await Dio().download(
        url,
        zipPath,
        onReceiveProgress: (received, total) {
          if (!mounted || total <= 0) {
            return;
          }
          setState(() {
            _progress = received / total;
          });
        },
        options: Options(receiveTimeout: const Duration(minutes: 10)),
      );

      if (mounted) {
        setState(() {
          _phase = _UpdatePhase.installing;
          _progress = 1;
        });
        await _showBusyFrame();
      }

      if (widget.manifest.sha256.isNotEmpty) {
        final actual = await _sha256(zipPath);
        if (actual.toLowerCase() != widget.manifest.sha256.toLowerCase()) {
          throw StateError('업데이트 파일 검증에 실패했습니다.');
        }
      }

      final scriptPath = await _writeUpdaterScript(updateDir, zipPath);
      final commandPath = await _writeUpdaterCommand(updateDir, scriptPath);
      if (mounted) {
        setState(() {
          _phase = _UpdatePhase.restarting;
        });
        await _showBusyFrame(const Duration(milliseconds: 700));
      }
      final launcher = await io.Process.run(commandPath, [
        io.pid.toString(),
      ], runInShell: true);
      if (launcher.exitCode != 0) {
        throw StateError('업데이트 설치 프로그램을 시작하지 못했습니다.');
      }
      io.exit(0);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _updating = false;
        _phase = _UpdatePhase.idle;
        _error = authErrorMessage(error);
      });
    }
  }

  Future<void> _showBusyFrame([
    Duration duration = const Duration(milliseconds: 350),
  ]) async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(duration);
  }

  Future<io.Directory> _updateWorkingDirectory() async {
    final directory = io.Directory(
      '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}ava_update_${DateTime.now().millisecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _sha256(String path) async {
    final result = await io.Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      "(Get-FileHash -Algorithm SHA256 -LiteralPath ${_psQuote(path)}).Hash.ToLowerInvariant()",
    ]);
    if (result.exitCode != 0) {
      throw StateError('업데이트 파일 해시를 확인할 수 없습니다.');
    }
    return result.stdout.toString().trim();
  }

  Future<String> _writeUpdaterScript(
    io.Directory updateDir,
    String zipPath,
  ) async {
    final exePath = io.Platform.resolvedExecutable;
    final installDir = io.File(exePath).parent.path;
    final scriptPath =
        '${updateDir.path}${io.Platform.pathSeparator}apply_update.ps1';
    final script =
        '''
param([int]\$LauncherPid = 0)
\$ErrorActionPreference = 'Stop'
\$zipPath = ${_psQuote(zipPath)}
\$installDir = ${_psQuote(installDir)}
\$exePath = ${_psQuote(exePath)}
\$workDir = ${_psQuote(updateDir.path)}
\$extractDir = Join-Path \$workDir 'extracted'
\$backupDir = Join-Path \$workDir 'backup'
\$processName = [System.IO.Path]::GetFileNameWithoutExtension(\$exePath)
\$logDir = Join-Path \$env:LOCALAPPDATA 'AVA'
\$logPath = Join-Path \$logDir 'update.log'

function Write-UpdateLog {
  param([string]\$Message)
  New-Item -ItemType Directory -Force -Path \$logDir | Out-Null
  \$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
  Add-Content -LiteralPath \$logPath -Encoding UTF8 -Value "[\$timestamp] \$Message"
}

function Stop-AvaProcesses {
  param([int]\$ExpectedPid)
  if (\$ExpectedPid -gt 0) {
    \$expected = Get-Process -Id \$ExpectedPid -ErrorAction SilentlyContinue
    if (\$null -ne \$expected) {
      Write-UpdateLog "Waiting for AVA process \$ExpectedPid to exit."
      Wait-Process -Id \$ExpectedPid -Timeout 15 -ErrorAction SilentlyContinue
    }
  }
  \$remaining = Get-Process -Name \$processName -ErrorAction SilentlyContinue
  foreach (\$process in \$remaining) {
    Write-UpdateLog "Stopping remaining AVA process \$([string]\$process.Id)."
    Stop-Process -Id \$process.Id -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Milliseconds 700
}

try {
  Write-UpdateLog "Starting update. InstallDir=\$installDir Zip=\$zipPath LauncherPid=\$LauncherPid"
  Stop-AvaProcesses -ExpectedPid \$LauncherPid

  Remove-Item -LiteralPath \$extractDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath \$backupDir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path \$extractDir | Out-Null
  Expand-Archive -LiteralPath \$zipPath -DestinationPath \$extractDir -Force

  \$newExe = Get-ChildItem -LiteralPath \$extractDir -Recurse -Filter 'ava_flutter.exe' | Select-Object -First 1
  if (\$null -eq \$newExe) {
    throw 'ava_flutter.exe was not found in update package.'
  }
  \$sourceDir = \$newExe.Directory.FullName
  \$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath \$newExe.FullName).Hash.ToLowerInvariant()

  if (Test-Path -LiteralPath \$installDir) {
    New-Item -ItemType Directory -Force -Path \$backupDir | Out-Null
    Copy-Item -Path (Join-Path \$installDir '*') -Destination \$backupDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  New-Item -ItemType Directory -Force -Path \$installDir | Out-Null
  Copy-Item -Path (Join-Path \$sourceDir '*') -Destination \$installDir -Recurse -Force

  \$installedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath \$exePath).Hash.ToLowerInvariant()
  if (\$installedHash -ne \$sourceHash) {
    throw "Installed exe hash mismatch. expected=\$sourceHash actual=\$installedHash"
  }

  Write-UpdateLog "Update copied successfully. Restarting AVA."
  Start-Process -FilePath \$exePath -WorkingDirectory \$installDir
  Start-Sleep -Seconds 2
  Write-UpdateLog "Update finished."
  Remove-Item -LiteralPath \$workDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  Write-UpdateLog ("Update failed: " + \$_.Exception.Message)
  try {
    if ((Test-Path -LiteralPath \$backupDir) -and (Test-Path -LiteralPath \$installDir)) {
      Copy-Item -Path (Join-Path \$backupDir '*') -Destination \$installDir -Recurse -Force -ErrorAction SilentlyContinue
      Write-UpdateLog "Rollback attempted."
    }
    if (Test-Path -LiteralPath \$exePath) {
      Start-Process -FilePath \$exePath -WorkingDirectory \$installDir
    }
  } catch {
    Write-UpdateLog ("Rollback/restart failed: " + \$_.Exception.Message)
  }
}
''';
    await io.File(scriptPath).writeAsString(script);
    return scriptPath;
  }

  Future<String> _writeUpdaterCommand(
    io.Directory updateDir,
    String scriptPath,
  ) async {
    final commandPath =
        '${updateDir.path}${io.Platform.pathSeparator}launch_update.cmd';
    final command =
        '''
@echo off
setlocal
set "LAUNCHER_PID=%~1"
if "%LAUNCHER_PID%"=="" set "LAUNCHER_PID=0"
set "LOGDIR=%LOCALAPPDATA%\\AVA"
if not exist "%LOGDIR%" mkdir "%LOGDIR%" >nul 2>nul
>> "%LOGDIR%\\update-launch.log" echo [%date% %time%] Launching updater pid=%LAUNCHER_PID% script=$scriptPath
start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$scriptPath" -LauncherPid %LAUNCHER_PID%
exit /b %ERRORLEVEL%
''';
    await io.File(commandPath).writeAsString(command);
    return commandPath;
  }

  String _psQuote(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }
}

class _UpdateBusyStatus extends StatelessWidget {
  const _UpdateBusyStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.8),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            message,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
