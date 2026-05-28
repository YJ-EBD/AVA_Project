import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../config/app_version.dart';
import '../../../shared/ava_dialog.dart';
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

class _AppUpdateGateState extends ConsumerState<AppUpdateGate>
    with WidgetsBindingObserver {
  bool _checked = false;
  bool _checkScheduled = false;
  bool _checkInProgress = false;
  bool _dialogOpen = false;
  bool _postUpdateChecked = false;
  bool _postUpdateCheckInProgress = false;
  bool _retryAfterCurrentCheck = false;

  bool get _updatesSupported => io.Platform.isWindows || io.Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkPostUpdateNotice());
      _scheduleCheck(delay: const Duration(milliseconds: 1200));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_updatesSupported) {
      return;
    }
    if (io.Platform.isAndroid) {
      _checked = false;
      _scheduleCheck(delay: const Duration(milliseconds: 500));
    }
  }

  void _scheduleCheck({Duration delay = Duration.zero}) {
    if (_checkScheduled ||
        _checkInProgress ||
        _checked ||
        _dialogOpen ||
        !_updatesSupported) {
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
    if (_checked ||
        _checkInProgress ||
        _postUpdateCheckInProgress ||
        _dialogOpen ||
        !_updatesSupported) {
      return;
    }
    _checkInProgress = true;
    try {
      await _waitForStartupRoute();
      if (!mounted) {
        return;
      }
      final manifest = await ref
          .read(appUpdateApiProvider)
          .latestForCurrentPlatform();
      _checked = true;
      if (!mounted ||
          manifest == null ||
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
      _checked = false;
      if (io.Platform.isAndroid) {
        _retryAfterCurrentCheck = true;
      }
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

  Future<void> _checkPostUpdateNotice() async {
    if (_postUpdateChecked ||
        _postUpdateCheckInProgress ||
        _dialogOpen ||
        !_updatesSupported) {
      return;
    }
    _postUpdateCheckInProgress = true;
    try {
      await _waitForStartupRoute();
      if (!mounted) {
        return;
      }
      _postUpdateChecked = true;
      final state = await _readUpdateLocalState();
      final marker = await _readAppliedUpdateMarker();
      final markerVersion = marker?['version']?.toString() ?? '';
      final markerNotes = marker?['releaseNotes']?.toString() ?? '';
      final markerPreviousVersion =
          marker?['previousVersion']?.toString() ?? '';

      final currentVersion = AppVersion.name;
      final previousVersion = markerVersion == currentVersion
          ? markerPreviousVersion
          : state.lastLaunchedVersion;
      final shouldShowFromMarker =
          markerVersion == currentVersion &&
          state.lastNotifiedVersion != currentVersion;
      final shouldShowFromState =
          previousVersion.isNotEmpty &&
          _compareVersions(currentVersion, previousVersion) > 0 &&
          state.lastNotifiedVersion != currentVersion;
      final shouldShowFirstKnownRelease =
          previousVersion.isEmpty &&
          state.lastNotifiedVersion != currentVersion;

      if (shouldShowFromMarker ||
          shouldShowFromState ||
          shouldShowFirstKnownRelease) {
        AppUpdateReleaseDto? release;
        try {
          release = await ref.read(appUpdateApiProvider).currentRelease();
        } on Object {
          release = null;
        }
        final releaseNotes = (release?.releaseNotes ?? '').isNotEmpty
            ? release!.releaseNotes
            : markerNotes;
        if (!mounted) {
          return;
        }
        final dialogContext = await _rootNavigatorContext();
        if (dialogContext != null && dialogContext.mounted && mounted) {
          _dialogOpen = true;
          await showDialog<void>(
            context: dialogContext,
            barrierDismissible: true,
            builder: (context) => _AppUpdatedDialog(
              version: currentVersion,
              previousVersion: previousVersion,
              releaseNotes: releaseNotes,
              sizeBytes: release?.sizeBytes ?? 0,
            ),
          );
          _dialogOpen = false;
        }
        await _writeUpdateLocalState(
          _UpdateLocalState(
            lastLaunchedVersion: currentVersion,
            lastNotifiedVersion: currentVersion,
          ),
        );
      } else if (state.lastLaunchedVersion != currentVersion) {
        await _writeUpdateLocalState(
          _UpdateLocalState(
            lastLaunchedVersion: currentVersion,
            lastNotifiedVersion: state.lastNotifiedVersion,
          ),
        );
      }
      if (marker != null) {
        await _deleteAppliedUpdateMarker();
      }
    } on Object {
      // Post-update notice must never block app startup.
    } finally {
      _postUpdateCheckInProgress = false;
      _dialogOpen = false;
      if (mounted) {
        _scheduleCheck(delay: const Duration(milliseconds: 200));
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

  Future<_UpdateLocalState> _readUpdateLocalState() async {
    try {
      final file = await _updateLocalStateFile();
      if (!await file.exists()) {
        return const _UpdateLocalState();
      }
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return _UpdateLocalState.fromJson(data);
    } on Object {
      return const _UpdateLocalState();
    }
  }

  Future<void> _writeUpdateLocalState(_UpdateLocalState state) async {
    final file = await _updateLocalStateFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  Future<Map<String, dynamic>?> _readAppliedUpdateMarker() async {
    try {
      final file = await _appliedUpdateMarkerFile();
      if (!await file.exists()) {
        return null;
      }
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, dynamic>();
    } on Object {
      return null;
    }
  }

  Future<void> _deleteAppliedUpdateMarker() async {
    try {
      final file = await _appliedUpdateMarkerFile();
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Best-effort cleanup only.
    }
  }

  Future<io.File> _updateLocalStateFile() async {
    final directory = await _avaSupportDirectory();
    return io.File(
      '${directory.path}${io.Platform.pathSeparator}update-state.json',
    );
  }

  Future<io.File> _appliedUpdateMarkerFile() async {
    final directory = await _avaSupportDirectory();
    return io.File(
      '${directory.path}${io.Platform.pathSeparator}update-applied.json',
    );
  }

  Future<io.Directory> _avaSupportDirectory() async {
    if (io.Platform.isWindows) {
      final base =
          io.Platform.environment['LOCALAPPDATA'] ??
          io.Platform.environment['APPDATA'] ??
          io.Directory.systemTemp.path;
      return io.Directory('$base${io.Platform.pathSeparator}AVA');
    }
    return io.Directory(
      '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}AVA',
    );
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

class _UpdateLocalState {
  const _UpdateLocalState({
    this.lastLaunchedVersion = '',
    this.lastNotifiedVersion = '',
  });

  factory _UpdateLocalState.fromJson(Map<String, dynamic> json) {
    return _UpdateLocalState(
      lastLaunchedVersion: json['lastLaunchedVersion'] as String? ?? '',
      lastNotifiedVersion: json['lastNotifiedVersion'] as String? ?? '',
    );
  }

  final String lastLaunchedVersion;
  final String lastNotifiedVersion;

  Map<String, dynamic> toJson() {
    return {
      'lastLaunchedVersion': lastLaunchedVersion,
      'lastNotifiedVersion': lastNotifiedVersion,
    };
  }
}

class _AppUpdatedDialog extends StatelessWidget {
  const _AppUpdatedDialog({
    required this.version,
    required this.previousVersion,
    required this.releaseNotes,
    required this.sizeBytes,
  });

  final String version;
  final String previousVersion;
  final String releaseNotes;
  final int sizeBytes;

  @override
  Widget build(BuildContext context) {
    final notes = releaseNotes.trim().isEmpty
        ? '업데이트가 정상적으로 완료되었습니다.'
        : releaseNotes.trim();
    return AvaDialog(
      title: '업데이트 완료',
      subtitle: 'AVA가 새 버전으로 적용되었습니다.',
      icon: const Icon(
        Icons.check_circle_outline_rounded,
        color: Color(0xFF38B75E),
        size: 24,
      ),
      width: 430,
      actions: [
        AvaDialogButton(
          label: '확인',
          filled: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD7E0E6)),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UpdateVersionRow(
                  label: '업데이트 버전',
                  value: version,
                  strong: true,
                ),
                if (previousVersion.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _UpdateVersionRow(label: '이전 버전', value: previousVersion),
                ],
                if (sizeBytes > 0) ...[
                  const SizedBox(height: 8),
                  _UpdateVersionRow(
                    label: '파일 크기',
                    value: _formatUpdateSize(sizeBytes),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          AvaDialogNote(child: _ReleaseNotesText(notes)),
        ],
      ),
    );
  }
}

class _AppUpdateDialog extends ConsumerStatefulWidget {
  const _AppUpdateDialog({required this.manifest});

  final AppUpdateManifestDto manifest;

  @override
  ConsumerState<_AppUpdateDialog> createState() => _AppUpdateDialogState();
}

enum _UpdatePhase { idle, downloading, downloaded, installing, restarting }

class _AppUpdateDialogState extends ConsumerState<_AppUpdateDialog> {
  static const MethodChannel _androidUpdateChannel = MethodChannel(
    'ava/android_update',
  );

  double? _progress;
  String? _error;
  bool _updating = false;
  _UpdatePhase _phase = _UpdatePhase.idle;
  String? _downloadedApkLocation;

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
    final isAndroid = io.Platform.isAndroid;
    final androidDownloadReady =
        isAndroid &&
        phase == _UpdatePhase.downloaded &&
        (_downloadedApkLocation?.isNotEmpty ?? false);
    return AvaDialog(
      title: 'AVA 업데이트',
      subtitle: '새 버전 ${manifest.latestVersion}이 준비되었습니다.',
      icon: const Icon(
        Icons.system_update_alt_rounded,
        color: Color(0xFF4F65C8),
        size: 24,
      ),
      width: 430,
      actions: [
        if (!manifest.required)
          AvaDialogButton(
            label: androidDownloadReady ? '닫기' : '나중에',
            onPressed: _updating ? null : () => Navigator.of(context).pop(),
          ),
        AvaDialogButton(
          label: androidDownloadReady
              ? '확인'
              : isAndroid
              ? 'APK 다운로드'
              : '업데이트',
          filled: true,
          onPressed: _updating
              ? null
              : androidDownloadReady
              ? () => Navigator.of(context).pop()
              : _downloadAndInstall,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UpdateVersionCard(manifest: manifest),
          if (manifest.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            AvaDialogNote(child: _ReleaseNotesText(manifest.releaseNotes)),
          ],
          if (_updating && phase == _UpdatePhase.downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFFD7E6F0),
              color: const Color(0xFF4F65C8),
            ),
            const SizedBox(height: 8),
            Text(
              progress == null
                  ? isAndroid
                        ? 'APK 다운로드를 준비하고 있습니다.'
                        : '업데이트 파일을 준비하고 있습니다.'
                  : '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}% 다운로드중',
              style: const TextStyle(
                color: Color(0xFF5E7182),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (androidDownloadReady) ...[
            const SizedBox(height: 16),
            _AndroidDownloadCompleteStatus(location: _downloadedApkLocation!),
          ],
          if (_updating &&
              phase != _UpdatePhase.downloading &&
              phase != _UpdatePhase.downloaded) ...[
            const SizedBox(height: 16),
            _UpdateBusyStatus(message: _phaseMessage(phase)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFE84D5B),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _updating = true;
      _phase = _UpdatePhase.downloading;
      _progress = null;
      _error = null;
      _downloadedApkLocation = null;
    });

    try {
      final api = ref.read(appUpdateApiProvider);
      final url = api.absoluteDownloadUrl(widget.manifest.downloadUrl);
      final updateDir = await _updateWorkingDirectory();
      final packagePath =
          '${updateDir.path}${io.Platform.pathSeparator}${widget.manifest.fileName}';

      await Dio().download(
        url,
        packagePath,
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
          _progress = 1;
          if (!io.Platform.isAndroid) {
            _phase = _UpdatePhase.installing;
          }
        });
        if (!io.Platform.isAndroid) {
          await _showBusyFrame();
        }
      }

      if (widget.manifest.sha256.isNotEmpty) {
        final actual = io.Platform.isAndroid
            ? await _sha256Dart(packagePath)
            : await _sha256(packagePath);
        if (actual.toLowerCase() != widget.manifest.sha256.toLowerCase()) {
          throw StateError('업데이트 파일 검증에 실패했습니다.');
        }
      }

      if (io.Platform.isAndroid) {
        final visibleLocation = await _saveAndroidApkToDownloads(packagePath);
        if (mounted) {
          setState(() {
            _updating = false;
            _phase = _UpdatePhase.downloaded;
            _progress = 1;
            _downloadedApkLocation = visibleLocation;
          });
        }
        return;
      }

      final scriptPath = await _writeWindowsUpdaterScript(
        updateDir,
        packagePath,
      );
      if (mounted) {
        setState(() {
          _phase = _UpdatePhase.restarting;
        });
        await _showBusyFrame(const Duration(milliseconds: 700));
      }
      await _launchUpdater(updateDir, scriptPath);
      io.exit(0);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _updating = false;
        _phase = _UpdatePhase.idle;
        _error = _updateErrorMessage(error);
      });
    }
  }

  String _updateErrorMessage(Object error) {
    if (error is StateError) {
      return error.message;
    }
    if (error is PlatformException) {
      return error.message ?? 'Android 업데이트 설치 화면을 열지 못했습니다.';
    }
    return authErrorMessage(error);
  }

  Future<void> _showBusyFrame([
    Duration duration = const Duration(milliseconds: 350),
  ]) async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(duration);
  }

  Future<io.Directory> _updateWorkingDirectory() async {
    if (io.Platform.isAndroid) {
      try {
        final basePath = await _androidUpdateChannel.invokeMethod<String>(
          'updateDownloadDirectory',
        );
        if (basePath != null && basePath.trim().isNotEmpty) {
          final directory = io.Directory(
            '${basePath.trim()}${io.Platform.pathSeparator}ava_updates',
          );
          await directory.create(recursive: true);
          return directory;
        }
      } on Object {
        // Fall back to the app temp directory below.
      }
    }
    final directory = io.Directory(
      '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}ava_update_${DateTime.now().millisecondsSinceEpoch}',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _sha256Dart(String path) async {
    final digest = await crypto.sha256.bind(io.File(path).openRead()).first;
    return digest.toString();
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

  Future<String> _saveAndroidApkToDownloads(String packagePath) async {
    try {
      final location = await _androidUpdateChannel.invokeMethod<String>(
        'saveApkToDownloads',
        {'path': packagePath, 'fileName': widget.manifest.fileName},
      );
      final trimmed = location?.trim() ?? '';
      if (trimmed.isEmpty) {
        throw StateError('APK를 다운로드 폴더에 저장하지 못했습니다.');
      }
      return trimmed;
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'APK를 다운로드 폴더에 저장하지 못했습니다.');
    }
  }

  Future<void> _launchUpdater(io.Directory updateDir, String scriptPath) async {
    final commandPath = await _writeWindowsUpdaterCommand(
      updateDir,
      scriptPath,
    );
    final launcher = await io.Process.run(commandPath, [
      io.pid.toString(),
    ], runInShell: true);
    if (launcher.exitCode != 0) {
      throw StateError('업데이트 설치 프로그램을 시작하지 못했습니다.');
    }
  }

  Future<String> _writeWindowsUpdaterScript(
    io.Directory updateDir,
    String zipPath,
  ) async {
    final exePath = io.Platform.resolvedExecutable;
    final installDir = io.File(exePath).parent.path;
    final scriptPath =
        '${updateDir.path}${io.Platform.pathSeparator}apply_update.ps1';
    final markerJson = jsonEncode({
      'version': widget.manifest.latestVersion,
      'previousVersion': AppVersion.name,
      'releaseNotes': widget.manifest.releaseNotes,
      'appliedAt': DateTime.now().toIso8601String(),
    });
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
\$markerPath = Join-Path \$logDir 'update-applied.json'
\$markerJson = ${_psQuote(markerJson)}

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
  New-Item -ItemType Directory -Force -Path \$logDir | Out-Null
  Set-Content -LiteralPath \$markerPath -Encoding UTF8 -Value \$markerJson
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

  Future<String> _writeWindowsUpdaterCommand(
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

class _ReleaseNotesText extends StatelessWidget {
  const _ReleaseNotesText(this.notes);

  final String notes;

  @override
  Widget build(BuildContext context) {
    final lines = _releaseNoteLines(notes);
    return Text(
      lines.map((line) => '- $line').join('\n'),
      style: const TextStyle(
        color: Color(0xFF102040),
        fontSize: 13,
        height: 1.45,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _UpdateVersionCard extends StatelessWidget {
  const _UpdateVersionCard({required this.manifest});

  final AppUpdateManifestDto manifest;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7E0E6)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _UpdateVersionRow(
            label: '업데이트 버전',
            value: manifest.latestVersion,
            strong: true,
          ),
          const SizedBox(height: 8),
          _UpdateVersionRow(label: '현재 버전', value: AppVersion.name),
          if (manifest.sizeBytes > 0) ...[
            const SizedBox(height: 8),
            _UpdateVersionRow(
              label: '파일 크기',
              value: _formatUpdateSize(manifest.sizeBytes),
            ),
          ],
        ],
      ),
    );
  }
}

class _UpdateVersionRow extends StatelessWidget {
  const _UpdateVersionRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF5E7182),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: strong ? const Color(0xFF4F65C8) : const Color(0xFF102040),
              fontSize: strong ? 14 : 12,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatUpdateSize(int bytes) {
  if (bytes <= 0) {
    return '-';
  }
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final digits = value >= 10 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
}

List<String> _releaseNoteLines(String notes) {
  final normalized = notes
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split(RegExp(r'[\n,]'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.replaceFirst(RegExp(r'^[-•]\s*'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (normalized.isEmpty) {
    return const ['업데이트가 정상적으로 완료되었습니다.'];
  }
  return normalized;
}

int _compareVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index += 1) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) {
      return leftValue.compareTo(rightValue);
    }
  }
  return 0;
}

List<int> _versionParts(String version) {
  return version
      .split('+')
      .first
      .split('.')
      .map(
        (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9].*'), '')) ?? 0,
      )
      .toList();
}

class _AndroidDownloadCompleteStatus extends StatelessWidget {
  const _AndroidDownloadCompleteStatus({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF4FFF8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFE8CE)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Color(0xFF38B75E),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '다운로드 완료',
                  style: TextStyle(
                    color: Color(0xFF102040),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$location에 APK 다운로드가 완료되었습니다.\n휴대폰의 다운로드 앱 또는 파일 관리자에서 APK를 열어 설치해주세요. 설치가 끝나면 AVA를 다시 실행해주세요.',
                  style: const TextStyle(
                    color: Color(0xFF3F5068),
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
          child: CircularProgressIndicator(
            strokeWidth: 2.8,
            color: Color(0xFF4F65C8),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF102040),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
