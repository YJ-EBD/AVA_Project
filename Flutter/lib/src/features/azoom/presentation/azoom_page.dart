// ignore_for_file: unused_element, unused_element_parameter, unused_field

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../config/app_config.dart';
import '../../../platform/azoom_voice_platform.dart';
import '../../../platform/window_control.dart';
import '../../auth/application/auth_controller.dart';
import '../../messenger/application/notification_center_controller.dart';
import '../../messenger/domain/messenger_models.dart';
import '../../messenger/presentation/widgets/profile_avatar.dart';
import '../../../shared/ava_toast.dart';
import '../data/azoom_api.dart';
import 'azoom_screen_share_dialog.dart';

const _serverRailWidth = 72.0;
const _channelSidebarWidth = 290.0;
const _channelHeaderHeight = 48.0;

const _avaAccent = Color(0xFF2387F2);
const _avaAccentDeep = Color(0xFF155E9E);
const _chatBackground = Color(0xFFF4F9FE);
const _borderColor = Color(0xFFC8DDEA);
const _stageBackground = Color(0xFFF2F8FD);
const _stageTile = Color(0xFFE3F0FA);
const _stagePanel = Color(0xFFFFFFFF);
const _stageControl = Color(0xFFE6F1FA);
const _stageBorder = Color(0xFFC5D9E8);
const _stageText = Color(0xFF173247);
const _stageMutedText = Color(0xFF62788A);
const _stageMenu = Color(0xFFFFFFFF);
const _stageMenuHover = Color(0xFFEAF5FF);
const _stageMenuBorder = Color(0xFFD2E2F0);
const _discordActivityTop = Color(0xFFD5EAFF);
const _discordActivityBottom = Color(0xFFF7FBFF);
const _discordDanger = Color(0xFFDA373C);
const _discordSidebarBackground = Color(0xFFF6FAFE);
const _discordSidebarPanel = Color(0xFFEAF3FB);
const _discordSidebarSelected = Color(0xFFDDEEFF);
const _discordSidebarHover = Color(0xFFEFF7FE);
const _discordSidebarBorder = Color(0xFFC9DDEA);
const _discordSidebarText = Color(0xFF17212A);
const _discordSidebarMuted = Color(0xFF63788A);
const _discordSidebarSubtle = Color(0xFF8798A7);
const _discordSidebarGreen = Color(0xFF20A66A);
const _stageControlsBottomInset = 18.0;
const _stageControlsOverlayHeight = 96.0;
const _mobileAzoomBreakpoint = 720.0;
const _mobileAzoomRailWidth = 64.0;
const _mobileAzoomRailColor = Color(0xFFE8F3FC);
const _mobileAzoomBottomNavHeight = 58.0;
const _mobileAzoomBottomSheetHeight = 236.0;
const _azoomLiveKitProbeTimeout = Duration(seconds: 2);
const _azoomLiveKitConnectTimeout = Duration(seconds: 25);
const _azoomMicrophoneEnableTimeout = Duration(seconds: 12);
const _azoomLiveKitRetryDelay = Duration(seconds: 4);
const _azoomVoiceStatusTimeout = Duration(seconds: 6);
const _azoomFireworkDuration = Duration(milliseconds: 2150);
const _notivaRealtimeChunkDuration = Duration(seconds: 6);
const _notivaRecordSampleRate = 16000;
const _notivaRecordChannels = 1;
const _notivaMinAudioFileBytes = 1024;
const _notivaMinSpeechRms = 0.006;
const _notivaMinSpeechPeak = 0.030;
const _notivaMinSpeechActiveRatio = 0.003;
const _notivaRealtimeUploadTimeout = Duration(minutes: 10);
const _azoomVoiceHeartbeatInterval = Duration(seconds: 3);
const _discordSpeaking = Color(0xFF23A55A);
const _voiceRoomBackground = Color(0xFFF2F8FD);
const _voiceRoomHeader = Color(0xFFE3F1FF);
const _voiceRoomBottom = Color(0xFFE8F4FF);
const _voiceRoomPanel = Color(0xFFFFFFFF);
const _voiceRoomTile = Color(0xFFE4F1FB);
const _voiceRoomControl = Color(0xFFEAF5FF);
const _voiceRoomBorder = Color(0xFFC5D9E8);
const _voiceRoomText = Color(0xFF123047);
const _voiceRoomMutedText = Color(0xFF62788A);
const _primaryText = Color(0xFF213640);
const _secondaryText = Color(0xFF4D6370);

Future<List<String>> _orderedLiveKitConnectUrls(
  String rawUrl, {
  String? apiBaseUrl,
}) async {
  final candidates = _liveKitConnectUrlCandidates(
    rawUrl,
    apiBaseUrl: apiBaseUrl,
  );
  if (candidates.length < 2) {
    return candidates;
  }

  final checks = await Future.wait(
    candidates.map(_canReachLiveKitSignalUrl),
    eagerError: false,
  );
  final reachable = <String>[];
  final fallback = <String>[];
  for (var i = 0; i < candidates.length; i += 1) {
    if (checks[i]) {
      reachable.add(candidates[i]);
    } else {
      fallback.add(candidates[i]);
    }
  }
  return reachable.isEmpty ? candidates : [...reachable, ...fallback];
}

List<String> _liveKitConnectUrlCandidates(String rawUrl, {String? apiBaseUrl}) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) {
    return const <String>[];
  }

  final candidates = <String>[trimmed];
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.scheme == 'ws' || uri.scheme == 'wss')) {
    if (_isLoopbackLiveKitHost(uri.host) && Platform.isAndroid) {
      candidates.add(uri.replace(host: '10.0.2.2').toString());
    } else if (!_isLoopbackLiveKitHost(uri.host)) {
      candidates.add(uri.replace(host: '127.0.0.1').toString());
    }
  }
  final proxyUrl = _liveKitProxyUrlFromApiBase(apiBaseUrl);
  if (proxyUrl != null) {
    candidates.add(proxyUrl);
  }
  return <String>{...candidates}.toList(growable: false);
}

@visibleForTesting
List<String> liveKitConnectUrlCandidatesForTest(
  String rawUrl, {
  String? apiBaseUrl,
}) {
  return _liveKitConnectUrlCandidates(rawUrl, apiBaseUrl: apiBaseUrl);
}

String? _liveKitProxyUrlFromApiBase(String? apiBaseUrl) {
  final raw = apiBaseUrl?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(raw);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  final host = Platform.isAndroid && _isLoopbackLiveKitHost(uri.host)
      ? '10.0.2.2'
      : uri.host;
  return uri
      .replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        host: host,
        path: '',
        query: null,
      )
      .toString();
}

Future<bool> _canReachLiveKitSignalUrl(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || (uri.scheme != 'ws' && uri.scheme != 'wss')) {
    return true;
  }
  final port = uri.hasPort ? uri.port : (uri.scheme == 'wss' ? 443 : 80);
  Socket? socket;
  try {
    socket = await Socket.connect(
      uri.host,
      port,
      timeout: _azoomLiveKitProbeTimeout,
    );
    return true;
  } on Object {
    return false;
  } finally {
    socket?.destroy();
  }
}

bool _isLoopbackLiveKitHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1' ||
      normalized == '[::1]';
}

String _safeFilePart(String value) {
  final safe = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  return safe.isEmpty ? 'notiva' : safe;
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _notivaSpeakerInitial(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first;
}

class _NotivaWavChunk {
  const _NotivaWavChunk({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.data,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final Uint8List data;
}

class _NotivaAudioStats {
  const _NotivaAudioStats({
    required this.rms,
    required this.peak,
    required this.activeRatio,
  });

  final double rms;
  final double peak;
  final double activeRatio;

  bool get hasSpeech =>
      rms >= _notivaMinSpeechRms ||
      (peak >= _notivaMinSpeechPeak &&
          activeRatio >= _notivaMinSpeechActiveRatio);
}

_NotivaWavChunk? _readNotivaWavChunk(Uint8List bytes) {
  if (bytes.length < 44 ||
      !_asciiEquals(bytes, 0, 'RIFF') ||
      !_asciiEquals(bytes, 8, 'WAVE')) {
    return null;
  }

  final view = ByteData.sublistView(bytes);
  var offset = 12;
  var channels = _notivaRecordChannels;
  var sampleRate = _notivaRecordSampleRate;
  var bitsPerSample = 16;
  var dataOffset = -1;
  var dataLength = 0;

  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = view.getUint32(offset + 4, Endian.little);
    final chunkDataOffset = offset + 8;
    if (chunkDataOffset + chunkSize > bytes.length) {
      break;
    }
    if (chunkId == 'fmt ' && chunkSize >= 16) {
      channels = view.getUint16(chunkDataOffset + 2, Endian.little);
      sampleRate = view.getUint32(chunkDataOffset + 4, Endian.little);
      bitsPerSample = view.getUint16(chunkDataOffset + 14, Endian.little);
    } else if (chunkId == 'data') {
      dataOffset = chunkDataOffset;
      dataLength = chunkSize;
      break;
    }
    offset = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (dataOffset < 0 || dataLength <= 0) {
    return null;
  }
  return _NotivaWavChunk(
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bitsPerSample,
    data: Uint8List.sublistView(bytes, dataOffset, dataOffset + dataLength),
  );
}

_NotivaAudioStats _notivaAudioStats(_NotivaWavChunk chunk) {
  if (chunk.bitsPerSample != 16 || chunk.data.length < 2) {
    return const _NotivaAudioStats(rms: 1, peak: 1, activeRatio: 1);
  }
  final view = ByteData.sublistView(chunk.data);
  final sampleCount = chunk.data.length ~/ 2;
  if (sampleCount <= 0) {
    return const _NotivaAudioStats(rms: 0, peak: 0, activeRatio: 0);
  }

  var sumSquares = 0.0;
  var peak = 0.0;
  var active = 0;
  for (var i = 0; i < sampleCount; i += 1) {
    final normalized = view.getInt16(i * 2, Endian.little).abs() / 32768.0;
    sumSquares += normalized * normalized;
    if (normalized > peak) {
      peak = normalized;
    }
    if (normalized >= _notivaMinSpeechPeak) {
      active += 1;
    }
  }

  return _NotivaAudioStats(
    rms: math.sqrt(sumSquares / sampleCount),
    peak: peak,
    activeRatio: active / sampleCount,
  );
}

bool _asciiEquals(Uint8List bytes, int offset, String value) {
  if (offset + value.length > bytes.length) {
    return false;
  }
  for (var i = 0; i < value.length; i += 1) {
    if (bytes[offset + i] != value.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

Uint8List _notivaWavHeader({
  required int dataLength,
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
}) {
  final blockAlign = channels * bitsPerSample ~/ 8;
  final byteRate = sampleRate * blockAlign;
  final bytes = Uint8List(44);
  final view = ByteData.sublistView(bytes);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i += 1) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  view.setUint32(4, 36 + dataLength, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, byteRate, Endian.little);
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, bitsPerSample, Endian.little);
  writeAscii(36, 'data');
  view.setUint32(40, dataLength, Endian.little);
  return bytes;
}

final azoomVoiceStageActiveProvider =
    NotifierProvider<AzoomVoiceStageActive, bool>(AzoomVoiceStageActive.new);

class AzoomVoiceStageActive extends Notifier<bool> {
  @override
  bool build() => false;

  void setActive(bool active) {
    state = active;
  }
}

const _azoomAudioProcessingOptions = lk.AudioCaptureOptions(
  noiseSuppression: true,
  echoCancellation: true,
  autoGainControl: true,
  highPassFilter: true,
  voiceIsolation: true,
  typingNoiseDetection: true,
  stopAudioCaptureOnMute: true,
);
const _azoomAudioOutputOptions = lk.AudioOutputOptions(speakerOn: false);

enum _AzoomNoiseSuppressionMode { krisp, basic, off }

const _azoomScreenShareEncoding = lk.VideoEncoding(
  maxBitrate: 9000 * 1000,
  maxFramerate: 60,
  bitratePriority: lk.Priority.high,
  networkPriority: lk.Priority.high,
);
const _azoomScreenShareParameters = lk.VideoParameters(
  description: 'AZOOM smooth screen share 1080p60',
  dimensions: lk.VideoDimensionsPresets.h1080_169,
  encoding: _azoomScreenShareEncoding,
);
const _azoomScreenShareCaptureOptions = lk.ScreenShareCaptureOptions(
  maxFrameRate: 60,
  params: _azoomScreenShareParameters,
);
const _azoomCameraPublishOptions = lk.VideoPublishOptions(
  degradationPreference: lk.DegradationPreference.maintainFramerate,
);
const _azoomScreenSharePublishOptions = lk.VideoPublishOptions(
  screenShareEncoding: _azoomScreenShareEncoding,
  simulcast: false,
  backupVideoCodec: lk.BackupVideoCodec(enabled: false),
  degradationPreference: lk.DegradationPreference.maintainFramerate,
);

const _fallbackVoiceChannels = [
  AzoomVoiceChannelDto(
    id: 'all-staff',
    name: '전직원 회의',
    roomName: 'azoom-local-voice-all-staff',
    startedAt: null,
    serverNow: null,
    receivedAt: null,
    accessMode: 'ALL',
    allowedDepartments: [],
    canJoin: true,
    participants: [],
  ),
  AzoomVoiceChannelDto(
    id: 'ra',
    name: 'RA 팀',
    roomName: 'azoom-local-voice-ra',
    startedAt: null,
    serverNow: null,
    receivedAt: null,
    accessMode: 'ALL',
    allowedDepartments: [],
    canJoin: true,
    participants: [],
  ),
  AzoomVoiceChannelDto(
    id: 'research',
    name: '연구소',
    roomName: 'azoom-local-voice-research',
    startedAt: null,
    serverNow: null,
    receivedAt: null,
    accessMode: 'ALL',
    allowedDepartments: [],
    canJoin: true,
    participants: [],
  ),
];

class AzoomPage extends ConsumerStatefulWidget {
  const AzoomPage({
    required this.currentUser,
    this.mobileActiveTab = MessengerTab.azoom,
    this.onMobileTabSelected,
    this.bypassAndroidVoicePermissionChecks = false,
    super.key,
  });

  final PersonProfile currentUser;
  final MessengerTab mobileActiveTab;
  final ValueChanged<MessengerTab>? onMobileTabSelected;
  @visibleForTesting
  final bool bypassAndroidVoicePermissionChecks;

  @override
  ConsumerState<AzoomPage> createState() => _AzoomPageState();
}

class _AzoomPageState extends ConsumerState<AzoomPage>
    with WidgetsBindingObserver {
  late final AzoomVoiceStageActive _voiceStageActive;
  late final AzoomApi _disposeAzoomApi;

  AzoomChannelsDto? _channels;
  AzoomVoiceChannelDto? _stageVoiceChannel;
  AzoomVoiceChannelDto? _connectedVoiceChannel;
  AzoomVoiceChannelDto? _mobileVoicePreviewChannel;
  AzoomVoiceRealtimeClient? _voiceRealtimeClient;
  StreamSubscription<AzoomVoiceChannelDto>? _voiceRealtimeSubscription;
  AzoomVoiceEffectRealtimeClient? _voiceEffectRealtimeClient;
  StreamSubscription<AzoomVoiceEffectDto>? _voiceEffectRealtimeSubscription;
  AzoomNotivaRealtimeClient? _notivaRealtimeClient;
  StreamSubscription<AzoomNotivaEventDto>? _notivaRealtimeSubscription;
  Timer? _voiceHeartbeatTimer;
  Timer? _liveKitReconnectTimer;
  AudioRecorder? _notivaRecorder;
  Timer? _notivaChunkTimer;
  Future<void> _notivaRealtimeUploadQueue = Future<void>.value();

  lk.Room? _liveKitRoom;
  lk.EventsListener<lk.RoomEvent>? _liveKitListener;

  bool _loadingChannels = true;
  bool _loadingTranscript = false;
  bool _joiningVoice = false;
  bool _liveKitConnecting = false;
  bool _liveKitConnected = false;
  bool _liveKitReconnectInFlight = false;
  bool _micEnabled = true;
  bool _deafened = false;
  bool _mobilePreviewMicEnabled = true;
  bool _mobilePreviewDeafened = false;
  bool _mobileSpeakerOn = false;
  bool _cameraEnabled = false;
  bool _cameraToggleInFlight = false;
  bool _screenSharing = false;
  bool _screenShareToggleInFlight = false;
  bool _voiceFullscreen = false;
  bool _mobileVoiceRoomVisible = false;
  bool _appInForeground = true;
  bool _mobileMeetingTranscriptsExpanded = false;
  bool _mobileMiniVoiceControlsVisible = false;
  bool _nativeVoiceSessionActive = false;
  String? _nativeVoiceSessionSignature;
  bool _nativeOverlayPermissionPrompted = false;
  bool _nativeNotificationPermissionPrompted = false;
  bool _notivaOpen = false;
  bool _notivaStarting = false;
  bool _notivaAudioCaptureActive = false;
  bool _notivaChunkRotating = false;
  final List<int> _fireworkBurstIds = <int>[];
  int _fireworkBurstSequence = 0;
  _AzoomNoiseSuppressionMode _noiseSuppressionMode =
      _AzoomNoiseSuppressionMode.krisp;
  double _azoomOutputVolume = 0.50;
  Offset? _mobileMiniVoiceOffset;
  String _azoomSearchQuery = '';
  String? _cameraUnavailableReason;
  String? _errorText;
  String? _mediaErrorText;
  String? _notivaErrorText;
  String? _lastAccessToken;
  AzoomMeetingTranscriptDto? _selectedMeetingTranscript;
  AzoomMeetingTranscriptDto? _notivaTranscript;
  List<AzoomMeetingTranscriptSummaryDto> _meetingTranscripts = const [];
  bool _cameraDialogOpen = false;
  String? _notivaCaptureChannelId;
  String? _notivaCurrentChunkPath;
  int _notivaChunkSequence = 0;
  int _liveKitReconnectAttempt = 0;
  final List<String> _notivaBatchChunkPaths = <String>[];
  final List<String> _notivaFullAudioChunkPaths = <String>[];

  bool get _fireworkVisible => _fireworkBurstIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voiceStageActive = ref.read(azoomVoiceStageActiveProvider.notifier);
    _disposeAzoomApi = ref.read(azoomApiProvider);
    _lastAccessToken = ref
        .read(authControllerProvider)
        .value
        ?.session
        ?.accessToken;
    AzoomVoicePlatform.setActionHandler(_handleNativeVoiceAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadChannels());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      Future<void>.microtask(() {
        try {
          _voiceStageActive.setActive(false);
        } on Object {
          // The ProviderScope may already be tearing down in widget tests.
        }
      }),
    );
    if (_voiceFullscreen) {
      unawaited(WindowControl.setAzoomFullscreen(false));
    }
    _stopVoiceRealtime();
    _stopVoiceEffectRealtime();
    _stopNotivaRealtime();
    unawaited(_stopNotivaAudioCapture(uploadBatch: false));
    _stopVoiceHeartbeat();
    _cancelLiveKitReconnect();
    AzoomVoicePlatform.setActionHandler(null);
    final disposeAccessToken = _lastAccessToken;
    unawaited(AzoomVoicePlatform.stopSession());
    unawaited(
      _disconnectLiveKit(
        callServer: true,
        accessTokenOverride: disposeAccessToken,
        apiOverride: _disposeAzoomApi,
      ),
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AzoomPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mobileActiveTab != widget.mobileActiveTab) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_syncNativeVoiceSession());
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    if (_appInForeground == inForeground) {
      return;
    }
    setState(() {
      _appInForeground = inForeground;
    });
    unawaited(_syncNativeVoiceSession());
  }

  String? get _accessToken {
    final token = ref.read(authControllerProvider).value?.session?.accessToken;
    final normalized = token == null || token.isEmpty ? null : token;
    _lastAccessToken = normalized;
    return normalized;
  }

  bool get _isCurrentUserAzoomAdmin {
    final role = widget.currentUser.role?.toUpperCase() ?? '';
    return role == 'ADMIN' || role == 'SUPERUSER';
  }

  Future<void> _handleNativeVoiceAction(String action) async {
    switch (action) {
      case 'open':
      case 'fullscreen':
        widget.onMobileTabSelected?.call(MessengerTab.azoom);
        final channel = _connectedVoiceChannel ?? _stageVoiceChannel;
        if (mounted && channel != null) {
          setState(() {
            _stageVoiceChannel = channel;
            _mobileVoiceRoomVisible = true;
            _mobileMiniVoiceControlsVisible = false;
          });
          unawaited(_syncNativeVoiceSession());
        }
        break;
      case 'toggleMic':
        await _toggleMic();
        break;
      case 'toggleDeafen':
        await _toggleDeafen();
        break;
      case 'leave':
        await _leaveVoice();
        break;
    }
  }

  Future<void> _syncNativeVoiceSession({
    bool requestOverlayPermission = false,
  }) async {
    final channel = _connectedVoiceChannel;
    final token = _accessToken;
    if (channel == null || token == null || token.isEmpty) {
      if (_nativeVoiceSessionActive) {
        _nativeVoiceSessionActive = false;
        _nativeVoiceSessionSignature = null;
        await AzoomVoicePlatform.stopSession();
      }
      return;
    }

    if (Platform.isAndroid) {
      final allowed =
          widget.bypassAndroidVoicePermissionChecks ||
          await _ensureAndroidVoiceSurfacePermissions(requestOverlayPermission);
      if (!allowed) {
        return;
      }
    }

    final featured = _featuredVoiceParticipant(channel);
    final avatarName = featured.displayName.trim().isEmpty
        ? widget.currentUser.name
        : featured.displayName.trim();
    final avatarColor = featured.avatarColor.trim().isEmpty
        ? _colorToHex(widget.currentUser.color)
        : featured.avatarColor.trim();
    final avatarImageUrl = featured.avatarImageUrl.trim().isEmpty
        ? (widget.currentUser.imageUrl ?? '')
        : featured.avatarImageUrl.trim();
    final muted = !_micEnabled || _deafened;
    final voiceRoomVisibleInForeground =
        _mobileVoiceRoomVisible &&
        _appInForeground &&
        widget.mobileActiveTab == MessengerTab.azoom;
    final overlayEnabled = !voiceRoomVisibleInForeground;
    final signature = [
      token,
      channel.id,
      channel.name,
      avatarName,
      avatarColor,
      avatarImageUrl,
      muted,
      _deafened,
      featured.cameraEnabled || _cameraEnabled,
      featured.screenSharing || _screenSharing,
      overlayEnabled,
    ].join('\u001F');
    if (_nativeVoiceSessionActive &&
        _nativeVoiceSessionSignature == signature) {
      return;
    }
    final platformUpdate = _nativeVoiceSessionActive
        ? AzoomVoicePlatform.updateSession(
            channelName: channel.name,
            participantName: avatarName,
            avatarColor: avatarColor,
            avatarImageUrl: avatarImageUrl,
            muted: muted,
            deafened: _deafened,
            cameraEnabled: featured.cameraEnabled || _cameraEnabled,
            screenSharing: featured.screenSharing || _screenSharing,
            overlayEnabled: overlayEnabled,
          )
        : AzoomVoicePlatform.startSession(
            apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
            accessToken: token,
            channelId: channel.id,
            channelName: channel.name,
            participantName: avatarName,
            avatarColor: avatarColor,
            avatarImageUrl: avatarImageUrl,
            muted: muted,
            deafened: _deafened,
            cameraEnabled: featured.cameraEnabled || _cameraEnabled,
            screenSharing: featured.screenSharing || _screenSharing,
            overlayEnabled: overlayEnabled,
          );
    _nativeVoiceSessionActive = true;
    _nativeVoiceSessionSignature = signature;
    await platformUpdate;
  }

  Future<bool> _ensureAndroidVoiceSurfacePermissions(
    bool requestOverlay,
  ) async {
    var notificationsAllowed = true;
    try {
      final notification = await Permission.notification.status;
      if (!notification.isGranted && !notification.isLimited) {
        final requested = await Permission.notification.request();
        notificationsAllowed = requested.isGranted || requested.isLimited;
      }
    } on Object {
      // Older Android versions do not require runtime notification permission.
    }
    try {
      notificationsAllowed =
          notificationsAllowed &&
          await AzoomVoicePlatform.areNotificationsEnabled();
    } on Object {
      // Keep the permission result as the source of truth if the native check fails.
    }
    if (!notificationsAllowed) {
      if (!_nativeNotificationPermissionPrompted) {
        _nativeNotificationPermissionPrompted = true;
        if (mounted) {
          showAvaToast(
            context,
            '\uC54C\uB9BC \uAD8C\uD55C\uC744 \uD5C8\uC6A9\uD574\uC57C AZOOM \uD1B5\uD654 \uC54C\uB9BC\uCE74\uB4DC\uAC00 \uD45C\uC2DC\uB429\uB2C8\uB2E4.',
          );
        }
        await AzoomVoicePlatform.openNotificationSettings();
      }
      return false;
    }

    try {
      final microphone = await Permission.microphone.status;
      if (!_permissionGranted(microphone)) {
        final requested = await Permission.microphone.request();
        if (!_permissionGranted(requested)) {
          if (mounted) {
            showAvaToast(
              context,
              '\uB9C8\uC774\uD06C \uAD8C\uD55C\uC744 \uD5C8\uC6A9\uD574\uC57C AZOOM \uC74C\uC131 \uCC44\uB110\uC5D0 \uC785\uC7A5\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.',
            );
          }
          return false;
        }
      }
    } on Object {
      // Desktop and older platform implementations may not expose this permission.
    }

    var voiceChannelAllowed = true;
    try {
      voiceChannelAllowed =
          await AzoomVoicePlatform.areVoiceNotificationsEnabled();
    } on Object {
      voiceChannelAllowed = true;
    }
    if (!voiceChannelAllowed) {
      if (mounted) {
        showAvaToast(context, 'AZOOM 음성채널 알림 카테고리를 허용해야 실행중 알림카드가 표시됩니다.');
      }
      await AzoomVoicePlatform.openVoiceNotificationSettings();
      return false;
    }

    if (!requestOverlay || _nativeOverlayPermissionPrompted) {
      return true;
    }
    _nativeOverlayPermissionPrompted = true;
    try {
      final overlay = await Permission.systemAlertWindow.status;
      if (!overlay.isGranted) {
        await AzoomVoicePlatform.requestOverlayPermission();
      }
    } on Object {
      await AzoomVoicePlatform.requestOverlayPermission();
    }
    return true;
  }

  AzoomVoiceParticipantDto _featuredVoiceParticipant(
    AzoomVoiceChannelDto channel,
  ) {
    final participants = _voiceRowParticipants(
      channel.participants,
      currentUser: widget.currentUser,
      includeLocal: true,
      micEnabled: _micEnabled,
      deafened: _deafened,
      cameraEnabled: _cameraEnabled,
      screenSharing: _screenSharing,
    );
    if (participants.isEmpty) {
      return _participantFromProfile(widget.currentUser);
    }
    for (final participant in participants) {
      if (participant.screenSharing) {
        return participant;
      }
    }
    for (final participant in participants) {
      if (participant.cameraEnabled) {
        return participant;
      }
    }
    for (final participant in participants) {
      if (!participant.muted && !participant.deafened) {
        return participant;
      }
    }
    final index = DateTime.now().second % participants.length;
    return participants[index];
  }

  List<AzoomMeetingTranscriptSummaryDto> get _visibleMeetingTranscripts {
    final query = _azoomSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _meetingTranscripts;
    }
    return _meetingTranscripts
        .where((item) => _matchesMeetingTranscriptSearch(item, query))
        .toList();
  }

  Future<void> _loadChannels() async {
    final token = _accessToken;
    if (token == null) {
      _stopVoiceRealtime();
      setState(() {
        _channels = const AzoomChannelsDto(
          companyName: 'ABBA-S',
          liveKitEnabled: false,
          liveKitUrl: '',
          voiceChannels: _fallbackVoiceChannels,
        );
        _meetingTranscripts = const [];
        _selectedMeetingTranscript = null;
        _loadingChannels = false;
        _errorText = null;
      });
      _openPendingVoiceEntryIfReady();
      return;
    }

    setState(() {
      _loadingChannels = true;
      _errorText = null;
    });
    try {
      final channels = await ref.read(azoomApiProvider).channels(token);
      final transcripts = await ref
          .read(azoomApiProvider)
          .meetingTranscripts(accessToken: token);
      if (!mounted) {
        return;
      }
      setState(() {
        _channels = channels;
        _meetingTranscripts = transcripts;
        _loadingChannels = false;
      });
      _openPendingVoiceEntryIfReady();
      _startVoiceRealtime(token, channels.voiceChannels);
    } on Object {
      if (!mounted) {
        return;
      }
      _stopVoiceRealtime();
      setState(() {
        _channels = const AzoomChannelsDto(
          companyName: 'ABBA-S',
          liveKitEnabled: false,
          liveKitUrl: '',
          voiceChannels: _fallbackVoiceChannels,
        );
        _meetingTranscripts = const [];
        _selectedMeetingTranscript = null;
        _loadingChannels = false;
        _errorText = 'AZOOM 서버 연결을 확인하고 있습니다.';
      });
      _openPendingVoiceEntryIfReady();
      return;
    }
  }

  Future<void> _joinVoice(
    AzoomVoiceChannelDto channel, {
    bool keepStageOnMediaFailure = true,
  }) async {
    if (_joiningVoice) {
      return;
    }
    final currentChannel = _connectedVoiceChannel;
    if (currentChannel?.id == channel.id &&
        (_liveKitConnected || _liveKitConnecting)) {
      return;
    }
    if (Platform.isAndroid) {
      final allowed =
          widget.bypassAndroidVoicePermissionChecks ||
          await _ensureAndroidVoiceSurfacePermissions(false);
      if (!allowed) {
        return;
      }
      if (!mounted) {
        return;
      }
    }
    final token = _accessToken;
    setState(() {
      _selectedMeetingTranscript = null;
      _stageVoiceChannel = channel;
      _joiningVoice = true;
      _mediaErrorText = null;
    });

    if (token == null) {
      final localChannel = channel.copyWith(
        participants: [_localVoiceParticipant()],
      );
      setState(() {
        _connectedVoiceChannel = localChannel;
        _stageVoiceChannel = localChannel;
        _joiningVoice = false;
      });
      return;
    }

    try {
      if (currentChannel != null && currentChannel.id != channel.id) {
        await _disconnectLiveKit(
          callServer: true,
          clearVoiceState: true,
          stopRealtime: false,
          resetMediaControls: false,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _stageVoiceChannel = channel;
          _joiningVoice = true;
          _mediaErrorText = null;
        });
      }
      final response = await ref
          .read(azoomApiProvider)
          .joinVoice(accessToken: token, channelId: channel.id);
      if (!mounted) {
        return;
      }
      final channels =
          _channels?.voiceChannels ?? const <AzoomVoiceChannelDto>[];
      if (channels.isEmpty) {
        _startVoiceRealtime(token, [response.channel]);
      }
      setState(() {
        _connectedVoiceChannel = response.channel;
        _stageVoiceChannel = response.channel;
        _replaceVoiceChannel(response.channel);
      });
      unawaited(_syncNativeVoiceSession(requestOverlayPermission: true));
      unawaited(_updateVoiceStatus(muted: !_micEnabled, deafened: _deafened));
      final mediaConnected = await _connectLiveKit(response.liveKit);
      if (!mounted) {
        return;
      }
      if (!mediaConnected) {
        _scheduleLiveKitReconnect();
        if (keepStageOnMediaFailure) {
          _startVoiceHeartbeat();
          setState(() {
            _connectedVoiceChannel = response.channel;
            _stageVoiceChannel = response.channel;
            _joiningVoice = false;
          });
          return;
        }
        await _rollbackFailedVoiceJoin(token, response.channel.id);
        if (!mounted) {
          return;
        }
        setState(() {
          _connectedVoiceChannel = null;
          _stageVoiceChannel = null;
          _joiningVoice = false;
        });
        return;
      }
      _startVoiceHeartbeat();
      _startNotivaRealtime(token, response.channel.roomName);
      unawaited(_resumeNotivaCaptureIfActive(response.channel));
      setState(() {
        _joiningVoice = false;
      });
      unawaited(_syncNativeVoiceSession());
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _joiningVoice = false;
        _mediaErrorText = '음성 채널에 접속하지 못했습니다.';
      });
    }
  }

  Future<void> _rollbackFailedVoiceJoin(String token, String channelId) async {
    _stopVoiceHeartbeat();
    try {
      final state = await ref
          .read(azoomApiProvider)
          .leaveVoice(accessToken: token, channelId: channelId)
          .timeout(_azoomVoiceStatusTimeout);
      if (mounted) {
        _syncVoiceState(state);
      }
    } on Object {
      // A failed media join must not leave the UI stuck in a joining state.
    }
  }

  void _startVoiceRealtime(
    String token,
    List<AzoomVoiceChannelDto> voiceChannels,
  ) {
    final roomNames = [
      for (final channel in voiceChannels)
        if (channel.roomName.trim().isNotEmpty) channel.roomName.trim(),
    ];
    if (roomNames.isEmpty) {
      return;
    }
    _stopVoiceRealtime();
    final client = AzoomVoiceRealtimeClient(
      websocketUrl: ref.read(appConfigProvider).websocketUrl,
      accessToken: token,
      roomNames: roomNames,
    );
    _voiceRealtimeClient = client;
    _voiceRealtimeSubscription = client.states.listen((state) {
      if (!mounted) {
        return;
      }
      _syncVoiceState(state);
    }, onError: (_) {});
    client.connect();
    _startVoiceEffectRealtime(token, voiceChannels);
  }

  void _stopVoiceRealtime() {
    _voiceRealtimeSubscription?.cancel();
    _voiceRealtimeSubscription = null;
    _voiceRealtimeClient?.dispose();
    _voiceRealtimeClient = null;
    _stopVoiceEffectRealtime();
  }

  void _startVoiceEffectRealtime(
    String token,
    List<AzoomVoiceChannelDto> voiceChannels,
  ) {
    final roomNames = [
      for (final channel in voiceChannels)
        if (channel.roomName.trim().isNotEmpty) channel.roomName.trim(),
    ];
    if (roomNames.isEmpty) {
      return;
    }
    _stopVoiceEffectRealtime();
    final client = AzoomVoiceEffectRealtimeClient(
      websocketUrl: ref.read(appConfigProvider).websocketUrl,
      accessToken: token,
      roomNames: roomNames,
    );
    _voiceEffectRealtimeClient = client;
    _voiceEffectRealtimeSubscription = client.events.listen((event) {
      if (!mounted || event.type != 'FIREWORK') {
        return;
      }
      final visible =
          _connectedVoiceChannel?.roomName == event.roomName ||
          _stageVoiceChannel?.roomName == event.roomName;
      if (visible) {
        _playFirework();
      }
    }, onError: (_) {});
    client.connect();
  }

  void _stopVoiceEffectRealtime() {
    _voiceEffectRealtimeSubscription?.cancel();
    _voiceEffectRealtimeSubscription = null;
    _voiceEffectRealtimeClient?.dispose();
    _voiceEffectRealtimeClient = null;
  }

  void _playFirework() {
    final burstId = _fireworkBurstSequence++;
    setState(() {
      _fireworkBurstIds.add(burstId);
    });
    Future<void>.delayed(_azoomFireworkDuration, () {
      if (!mounted || !_fireworkBurstIds.contains(burstId)) {
        return;
      }
      setState(() {
        _fireworkBurstIds.remove(burstId);
      });
    });
  }

  Future<void> _triggerFirework(AzoomVoiceChannelDto channel) async {
    _playFirework();
    final token = _accessToken;
    if (token == null) {
      return;
    }
    try {
      await ref
          .read(azoomApiProvider)
          .triggerFirework(accessToken: token, channelId: channel.id);
    } on Object {
      if (mounted) {
        showAvaToast(context, '폭죽을 보낼 수 없습니다.');
      }
    }
  }

  Future<void> _showAzoomManagerPanel() async {
    if (!_isCurrentUserAzoomAdmin) {
      showAvaToast(context, '권한없음');
      return;
    }
    final token = _accessToken;
    if (token == null) {
      showAvaToast(context, '권한없음');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.54),
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 28,
          ),
          backgroundColor: Colors.transparent,
          child: _AzoomManagerPanel(
            api: ref.read(azoomApiProvider),
            accessToken: token,
            voiceChannels: _channels?.voiceChannels ?? const [],
            onChanged: () {
              unawaited(_loadChannels());
            },
          ),
        );
      },
    );
  }

  Future<void> _showParticipantsPanel(AzoomVoiceChannelDto channel) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.54),
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 34,
          ),
          backgroundColor: Colors.transparent,
          child: _AzoomParticipantsPanel(
            channel: channel,
            onClose: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
  }

  void _startNotivaRealtime(String token, String roomName) {
    if (roomName.trim().isEmpty) {
      return;
    }
    _stopNotivaRealtime();
    final client = AzoomNotivaRealtimeClient(
      websocketUrl: ref.read(appConfigProvider).websocketUrl,
      accessToken: token,
      roomName: roomName.trim(),
    );
    _notivaRealtimeClient = client;
    _notivaRealtimeSubscription = client.events.listen((event) {
      if (!mounted || event.roomName != roomName) {
        return;
      }
      final isRealtimeTranscript = event.transcript.kind == 'REALTIME';
      final connectedChannel = _connectedVoiceChannel;
      if (connectedChannel?.roomName == roomName && isRealtimeTranscript) {
        if (event.type == 'STARTED' && event.transcript.endedAt == null) {
          unawaited(_startNotivaAudioCapture(connectedChannel!));
        } else if (event.type == 'FINISHED') {
          unawaited(_stopNotivaAudioCapture(uploadBatch: true));
        }
      }
      if (isRealtimeTranscript) {
        setState(() {
          _notivaTranscript = event.transcript;
          _selectedMeetingTranscript =
              _selectedMeetingTranscript?.id == event.transcript.id
              ? event.transcript
              : _selectedMeetingTranscript;
        });
      }
      unawaited(_refreshMeetingTranscripts());
    }, onError: (_) {});
    client.connect();
  }

  void _stopNotivaRealtime() {
    _notivaRealtimeSubscription?.cancel();
    _notivaRealtimeSubscription = null;
    _notivaRealtimeClient?.dispose();
    _notivaRealtimeClient = null;
  }

  Future<void> _startNotivaAudioCapture(AzoomVoiceChannelDto channel) async {
    final token = _accessToken;
    if (token == null) {
      return;
    }
    if (_notivaAudioCaptureActive &&
        _notivaCaptureChannelId == channel.id &&
        _notivaRecorder != null) {
      return;
    }

    await _stopNotivaAudioCapture(uploadBatch: false);

    final recorder = AudioRecorder();
    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      await recorder.dispose();
      if (mounted) {
        setState(() {
          _notivaErrorText = '마이크 권한이 없어 Notiva AI가 음성을 수집하지 못했습니다.';
        });
      }
      return;
    }

    _notivaRecorder = recorder;
    _notivaCaptureChannelId = channel.id;
    _notivaAudioCaptureActive = true;
    _notivaChunkRotating = false;
    _notivaChunkSequence = 0;
    _notivaCurrentChunkPath = null;
    _notivaBatchChunkPaths.clear();
    _notivaFullAudioChunkPaths.clear();
    _notivaRealtimeUploadQueue = Future<void>.value();

    try {
      await _beginNextNotivaChunk();
    } on Object {
      _notivaAudioCaptureActive = false;
      _notivaCaptureChannelId = null;
      _notivaRecorder = null;
      await recorder.dispose();
      if (mounted) {
        setState(() {
          _notivaErrorText = 'Notiva AI가 마이크 녹음을 시작하지 못했습니다.';
        });
      }
      return;
    }
    _notivaChunkTimer = Timer.periodic(_notivaRealtimeChunkDuration, (_) {
      unawaited(_rotateNotivaChunk());
    });
  }

  Future<void> _beginNextNotivaChunk() async {
    final recorder = _notivaRecorder;
    final channelId = _notivaCaptureChannelId;
    if (!_notivaAudioCaptureActive ||
        recorder == null ||
        channelId == null ||
        !_micEnabled ||
        _deafened) {
      _notivaCurrentChunkPath = null;
      return;
    }
    if (await recorder.isRecording()) {
      return;
    }

    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}ava_notiva_ai',
    );
    await dir.create(recursive: true);
    _notivaChunkSequence += 1;
    final fileName =
        '${_safeFilePart(channelId)}_${DateTime.now().microsecondsSinceEpoch}_${_notivaChunkSequence.toString().padLeft(4, '0')}.wav';
    final path = '${dir.path}${Platform.pathSeparator}$fileName';
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: _notivaRecordSampleRate,
        numChannels: _notivaRecordChannels,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
      path: path,
    );
    _notivaCurrentChunkPath = path;
  }

  Future<void> _rotateNotivaChunk() async {
    if (_notivaChunkRotating || !_notivaAudioCaptureActive) {
      return;
    }
    _notivaChunkRotating = true;
    try {
      final channelId = _notivaCaptureChannelId;
      final recorder = _notivaRecorder;
      if (channelId == null || recorder == null) {
        return;
      }

      String? stoppedPath;
      try {
        if (await recorder.isRecording()) {
          stoppedPath = await recorder.stop();
        }
      } on Object {
        stoppedPath = _notivaCurrentChunkPath;
      }
      _notivaCurrentChunkPath = null;

      if (_notivaAudioCaptureActive) {
        await _beginNextNotivaChunk();
      }
      if (stoppedPath != null) {
        _queueNotivaRealtimeUpload(channelId, stoppedPath);
      }
    } finally {
      _notivaChunkRotating = false;
    }
  }

  void _queueNotivaRealtimeUpload(String channelId, String filePath) {
    _notivaRealtimeUploadQueue = _notivaRealtimeUploadQueue
        .catchError((_) {})
        .then((_) => _uploadNotivaRealtimeChunk(channelId, filePath));
  }

  Future<void> _uploadNotivaRealtimeChunk(
    String channelId,
    String filePath,
  ) async {
    final token = _accessToken;
    final file = File(filePath);
    if (token == null || !await file.exists()) {
      return;
    }
    if (await file.length() < _notivaMinAudioFileBytes) {
      unawaited(file.delete().then<void>((_) {}).catchError((_) {}));
      return;
    }
    _notivaFullAudioChunkPaths.add(filePath);
    if (!await _notivaFileHasSpeech(file)) {
      return;
    }
    _notivaBatchChunkPaths.add(filePath);
    try {
      final response = await ref
          .read(azoomApiProvider)
          .uploadNotivaRealtimeAudio(
            accessToken: token,
            channelId: channelId,
            filePath: filePath,
            speakerUserId: _blankToNull(widget.currentUser.id),
            speakerName: _notivaSpeakerName(),
            speakerEmail: _blankToNull(widget.currentUser.email),
          )
          .timeout(_notivaRealtimeUploadTimeout);
      if (!mounted) {
        return;
      }
      setState(() {
        _notivaTranscript = response.transcript;
        _selectedMeetingTranscript =
            _selectedMeetingTranscript?.id == response.transcript.id
            ? response.transcript
            : _selectedMeetingTranscript;
        _notivaErrorText = null;
      });
      unawaited(_refreshMeetingTranscripts());
    } on Object {
      if (mounted) {
        setState(() {
          _notivaErrorText = 'Notiva AI 실시간 음성 변환에 실패했습니다.';
        });
      }
    }
  }

  Future<bool> _notivaFileHasSpeech(File file) async {
    try {
      final chunk = _readNotivaWavChunk(await file.readAsBytes());
      if (chunk == null || chunk.data.isEmpty) {
        return false;
      }
      return _notivaAudioStats(chunk).hasSpeech;
    } on Object {
      return true;
    }
  }

  Future<void> _stopNotivaAudioCapture({required bool uploadBatch}) async {
    _notivaChunkTimer?.cancel();
    _notivaChunkTimer = null;
    final channelId = _notivaCaptureChannelId;
    final recorder = _notivaRecorder;

    _notivaAudioCaptureActive = false;
    _notivaCaptureChannelId = null;
    _notivaCurrentChunkPath = null;

    if (recorder != null) {
      try {
        if (await recorder.isRecording()) {
          final stoppedPath = await recorder.stop();
          if (channelId != null && stoppedPath != null) {
            _queueNotivaRealtimeUpload(channelId, stoppedPath);
          }
        }
      } on Object {
        // Capture cleanup must not block leaving the voice channel.
      }
      try {
        await recorder.dispose();
      } on Object {
        // Ignore native cleanup failures.
      }
    }
    _notivaRecorder = null;

    final pendingRealtimeUploads = _notivaRealtimeUploadQueue.catchError(
      (_) {},
    );
    final batchChunkPaths = List<String>.of(_notivaFullAudioChunkPaths);
    _notivaBatchChunkPaths.clear();
    _notivaFullAudioChunkPaths.clear();
    if (uploadBatch && channelId != null) {
      unawaited(
        pendingRealtimeUploads
            .then((_) {
              final liveBatchPaths = List<String>.of(
                _notivaFullAudioChunkPaths,
              );
              _notivaBatchChunkPaths.clear();
              _notivaFullAudioChunkPaths.clear();
              final batchPaths = liveBatchPaths..addAll(batchChunkPaths);
              final uniqueBatchPaths = <String>{...batchPaths}.toList();
              if (uniqueBatchPaths.isEmpty) {
                return Future<void>.value();
              }
              return _uploadNotivaBatchAudio(channelId, uniqueBatchPaths);
            })
            .catchError((_) {}),
      );
    }
  }

  Future<void> _uploadNotivaBatchAudio(
    String channelId,
    List<String> chunkPaths,
  ) async {
    final token = _accessToken;
    if (token == null || chunkPaths.isEmpty) {
      return;
    }
    try {
      final batchPath = await _mergeNotivaWavFiles(channelId, chunkPaths);
      if (batchPath == null) {
        return;
      }
      final response = await ref
          .read(azoomApiProvider)
          .uploadNotivaBatchAudio(
            accessToken: token,
            channelId: channelId,
            filePath: batchPath,
            speakerUserId: _blankToNull(widget.currentUser.id),
            speakerName: _notivaSpeakerName(),
            speakerEmail: _blankToNull(widget.currentUser.email),
          );
      if (mounted) {
        setState(() {
          _selectedMeetingTranscript =
              _selectedMeetingTranscript?.id == response.transcript.id
              ? response.transcript
              : _selectedMeetingTranscript;
        });
      }
      unawaited(_refreshMeetingTranscripts());
      if (response.transcript.status == 'PROCESSING') {
        unawaited(_watchMeetingTranscriptUntilReady(response.transcript.id));
      }
    } on Object {
      if (mounted) {
        setState(() {
          _notivaErrorText = 'Notiva AI 전체 음성 회의록 저장에 실패했습니다.';
        });
      }
    }
  }

  Future<String?> _mergeNotivaWavFiles(
    String channelId,
    List<String> paths,
  ) async {
    final chunks = <_NotivaWavChunk>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists() || await file.length() < 44) {
        continue;
      }
      final chunk = _readNotivaWavChunk(await file.readAsBytes());
      if (chunk != null && chunk.data.isNotEmpty) {
        chunks.add(chunk);
      }
    }
    if (chunks.isEmpty) {
      return null;
    }

    final first = chunks.first;
    final totalDataLength = chunks.fold<int>(
      0,
      (sum, chunk) => sum + chunk.data.length,
    );
    final out = BytesBuilder(copy: false)
      ..add(
        _notivaWavHeader(
          dataLength: totalDataLength,
          sampleRate: first.sampleRate,
          channels: first.channels,
          bitsPerSample: first.bitsPerSample,
        ),
      );
    for (final chunk in chunks) {
      out.add(chunk.data);
    }

    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}ava_notiva_ai',
    );
    await dir.create(recursive: true);
    final path =
        '${dir.path}${Platform.pathSeparator}${_safeFilePart(channelId)}_${DateTime.now().microsecondsSinceEpoch}_batch.wav';
    await File(path).writeAsBytes(out.takeBytes(), flush: true);
    return path;
  }

  String _notivaSpeakerName() {
    final nickname = widget.currentUser.nickname?.trim();
    if (nickname != null && nickname.isNotEmpty) {
      return nickname;
    }
    return widget.currentUser.name.trim().isEmpty
        ? 'Unknown'
        : widget.currentUser.name.trim();
  }

  Future<void> _refreshMeetingTranscripts() async {
    final token = _accessToken;
    if (token == null) {
      return;
    }
    try {
      final transcripts = await ref
          .read(azoomApiProvider)
          .meetingTranscripts(accessToken: token);
      if (mounted) {
        setState(() {
          _meetingTranscripts = transcripts;
        });
      }
    } on Object {
      // Transcript refresh should not interrupt voice or chat usage.
    }
  }

  Future<void> _watchMeetingTranscriptUntilReady(String transcriptId) async {
    final token = _accessToken;
    if (token == null || transcriptId.isEmpty) {
      return;
    }
    for (var attempt = 0; mounted && attempt < 240; attempt += 1) {
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) {
        return;
      }
      try {
        final transcript = await ref
            .read(azoomApiProvider)
            .meetingTranscript(accessToken: token, transcriptId: transcriptId);
        final transcripts = await ref
            .read(azoomApiProvider)
            .meetingTranscripts(accessToken: token);
        if (!mounted) {
          return;
        }
        setState(() {
          _meetingTranscripts = transcripts;
          _selectedMeetingTranscript =
              _selectedMeetingTranscript?.id == transcript.id
              ? transcript
              : _selectedMeetingTranscript;
        });
        if (transcript.status != 'PROCESSING') {
          return;
        }
      } on Object {
        // Polling must not interrupt the meeting UI.
      }
    }
  }

  Future<void> _resumeNotivaCaptureIfActive(
    AzoomVoiceChannelDto channel,
  ) async {
    final token = _accessToken;
    if (token == null || channel.roomName.trim().isEmpty) {
      return;
    }
    try {
      final transcripts = await ref
          .read(azoomApiProvider)
          .meetingTranscripts(accessToken: token);
      final active = transcripts.any(
        (item) =>
            item.roomName == channel.roomName &&
            item.kind == 'REALTIME' &&
            item.endedAt == null,
      );
      if (!mounted || !active) {
        return;
      }
      await _startNotivaAudioCapture(channel);
    } on Object {
      // Voice join should not fail just because Notiva state probing failed.
    }
  }

  Future<void> _selectMeetingTranscript(
    AzoomMeetingTranscriptSummaryDto summary,
  ) async {
    final token = _accessToken;
    if (token == null || summary.id.isEmpty) {
      return;
    }
    setState(() {
      _stageVoiceChannel = null;
      _selectedMeetingTranscript = null;
      _loadingTranscript = true;
      _errorText = null;
    });
    try {
      final transcript = await ref
          .read(azoomApiProvider)
          .meetingTranscript(accessToken: token, transcriptId: summary.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedMeetingTranscript = transcript;
        _loadingTranscript = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingTranscript = false;
        _errorText = '회의록을 불러오지 못했습니다.';
      });
    }
  }

  Future<void> _toggleNotiva(AzoomVoiceChannelDto channel) async {
    final nextOpen = !_notivaOpen;
    setState(() {
      _notivaOpen = nextOpen;
      _notivaErrorText = null;
    });
    if (!nextOpen) {
      await _stopNotivaAudioCapture(uploadBatch: true);
      return;
    }
    await _startNotiva(channel);
  }

  Future<void> _startNotiva(AzoomVoiceChannelDto channel) async {
    final token = _accessToken;
    if (token == null || _notivaStarting) {
      return;
    }
    setState(() {
      _notivaStarting = true;
      _notivaErrorText = null;
    });
    try {
      final session = await ref
          .read(azoomApiProvider)
          .startNotiva(accessToken: token, channelId: channel.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _notivaTranscript = session.realtimeTranscript;
        _notivaStarting = false;
      });
      _startNotivaRealtime(token, session.roomName);
      await _startNotivaAudioCapture(channel);
      await _refreshMeetingTranscripts();
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _notivaStarting = false;
        _notivaErrorText = 'Notiva AI를 시작하지 못했습니다.';
      });
    }
  }

  void _startVoiceHeartbeat() {
    _voiceHeartbeatTimer?.cancel();
    unawaited(_sendVoiceHeartbeat());
    _voiceHeartbeatTimer = Timer.periodic(_azoomVoiceHeartbeatInterval, (_) {
      unawaited(_sendVoiceHeartbeat());
    });
  }

  void _stopVoiceHeartbeat() {
    _voiceHeartbeatTimer?.cancel();
    _voiceHeartbeatTimer = null;
  }

  void _cancelLiveKitReconnect() {
    _liveKitReconnectTimer?.cancel();
    _liveKitReconnectTimer = null;
    _liveKitReconnectAttempt = 0;
  }

  void _scheduleLiveKitReconnect() {
    if (!mounted ||
        _connectedVoiceChannel == null ||
        _accessToken == null ||
        _liveKitConnected ||
        _liveKitConnecting ||
        _liveKitReconnectInFlight ||
        (_liveKitReconnectTimer?.isActive ?? false)) {
      return;
    }
    final delaySeconds = math.min(
      20,
      _azoomLiveKitRetryDelay.inSeconds + (_liveKitReconnectAttempt * 2),
    );
    _liveKitReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      unawaited(_retryLiveKitConnection());
    });
  }

  Future<void> _retryLiveKitConnection() async {
    _liveKitReconnectTimer?.cancel();
    _liveKitReconnectTimer = null;
    if (_liveKitReconnectInFlight || !mounted || _liveKitConnected) {
      return;
    }
    final token = _accessToken;
    final channel = _connectedVoiceChannel;
    if (token == null || channel == null) {
      return;
    }

    _liveKitReconnectInFlight = true;
    _liveKitReconnectAttempt += 1;
    var shouldRetry = false;
    try {
      if (mounted) {
        setState(() {
          _liveKitConnecting = true;
        });
      }
      final liveKit = await ref
          .read(azoomApiProvider)
          .liveKitToken(accessToken: token, channelId: channel.id)
          .timeout(const Duration(seconds: 15));
      if (!mounted || _connectedVoiceChannel?.id != channel.id) {
        return;
      }
      final connected = await _connectLiveKit(liveKit);
      shouldRetry =
          !connected && mounted && _connectedVoiceChannel?.id == channel.id;
    } on Object catch (error) {
      shouldRetry = mounted && _connectedVoiceChannel?.id == channel.id;
      if (mounted) {
        setState(() {
          _liveKitConnecting = false;
          _liveKitConnected = false;
          _mediaErrorText = '미디어 서버 재연결 실패: $error';
        });
      }
    } finally {
      _liveKitReconnectInFlight = false;
      if (shouldRetry) {
        _scheduleLiveKitReconnect();
      }
    }
  }

  Future<void> _sendVoiceHeartbeat() async {
    if (!mounted || _connectedVoiceChannel == null) {
      return;
    }
    await _updateVoiceStatus(
      muted: !_micEnabled,
      deafened: _deafened,
      cameraEnabled: _cameraEnabled,
      screenSharing: _screenSharing,
    );
  }

  void _syncVoiceState(AzoomVoiceChannelDto state) {
    setState(() {
      if (_connectedVoiceChannel?.id == state.id) {
        _connectedVoiceChannel = state;
      }
      if (_stageVoiceChannel?.id == state.id) {
        _stageVoiceChannel = state;
      }
      final channels = _channels;
      if (channels != null) {
        _channels = AzoomChannelsDto(
          companyName: channels.companyName,
          liveKitEnabled: channels.liveKitEnabled,
          liveKitUrl: channels.liveKitUrl,
          voiceChannels: [
            for (final channel in channels.voiceChannels)
              if (channel.id == state.id) state else channel,
          ],
        );
      }
    });
    unawaited(_syncNativeVoiceSession());
  }

  void _replaceVoiceChannel(AzoomVoiceChannelDto state) {
    final channels = _channels;
    if (channels == null) {
      return;
    }
    _channels = AzoomChannelsDto(
      companyName: channels.companyName,
      liveKitEnabled: channels.liveKitEnabled,
      liveKitUrl: channels.liveKitUrl,
      voiceChannels: [
        for (final channel in channels.voiceChannels)
          if (channel.id == state.id) state else channel,
      ],
    );
  }

  Future<bool> _connectLiveKit(AzoomLiveKitTokenDto token) async {
    final requestedDeafened = _deafened;
    final requestedMicEnabled = _micEnabled && !requestedDeafened;
    await _disconnectLiveKit(
      callServer: false,
      clearVoiceState: false,
      stopRealtime: false,
      resetMediaControls: false,
    );
    if (!mounted) {
      return false;
    }
    setState(() {
      _micEnabled = requestedMicEnabled;
      _deafened = requestedDeafened;
    });
    if (!token.enabled || token.url.isEmpty || token.token.isEmpty) {
      setState(() {
        _liveKitConnected = false;
        _micEnabled = requestedMicEnabled;
        _deafened = requestedDeafened;
        _mediaErrorText = token.reason.isEmpty
            ? '미디어 서버 설정이 필요합니다.'
            : token.reason;
      });
      return false;
    }

    var effectiveMicEnabled = requestedMicEnabled;
    if (requestedMicEnabled && !await _ensureAzoomMicrophonePermission()) {
      effectiveMicEnabled = false;
      if (mounted) {
        setState(() {
          _micEnabled = false;
        });
      }
    }

    setState(() {
      _liveKitConnecting = true;
      _mediaErrorText = null;
    });
    final audioCaptureOptions = await _resolveAzoomAudioCaptureOptions();
    final connectUrls = await _orderedLiveKitConnectUrls(
      token.url,
      apiBaseUrl: ref.read(appConfigProvider).apiBaseUrl,
    );
    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: false,
        dynacast: false,
        defaultVideoPublishOptions: _azoomCameraPublishOptions,
        defaultAudioCaptureOptions: audioCaptureOptions,
        defaultAudioOutputOptions: _azoomAudioOutputOptions,
        defaultScreenShareCaptureOptions: _azoomScreenShareCaptureOptions,
      ),
    );
    final listener = room.createListener()
      ..on<lk.RoomDisconnectedEvent>((_) {
        if (mounted) {
          setState(() {
            _liveKitConnected = false;
          });
          _scheduleLiveKitReconnect();
        }
      })
      ..on<lk.ParticipantConnectedEvent>((_) => _onLiveKitRoomChanged())
      ..on<lk.ParticipantDisconnectedEvent>((_) => _onLiveKitRoomChanged())
      ..on<lk.TrackPublishedEvent>((event) {
        unawaited(event.publication.subscribe());
        _onLiveKitRoomChanged();
      })
      ..on<lk.TrackSubscribedEvent>((_) => _onLiveKitRoomChanged())
      ..on<lk.TrackUnsubscribedEvent>((_) => _onLiveKitRoomChanged())
      ..on<lk.TrackMutedEvent>((_) => _onLiveKitRoomChanged())
      ..on<lk.TrackUnmutedEvent>((_) => _onLiveKitRoomChanged())
      ..on<lk.ParticipantEvent>((_) => _onLiveKitRoomChanged())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _onLiveKitRoomChanged())
      ..on<lk.RoomConnectedEvent>((_) => _onLiveKitRoomChanged());
    room.addListener(_onLiveKitRoomChanged);

    try {
      await room
          .connect(
            connectUrls.first,
            token.token,
            connectOptions: const lk.ConnectOptions(autoSubscribe: true),
          )
          .timeout(_azoomLiveKitConnectTimeout);
      try {
        await room.localParticipant
            ?.setMicrophoneEnabled(
              effectiveMicEnabled,
              audioCaptureOptions: audioCaptureOptions,
            )
            .timeout(_azoomMicrophoneEnableTimeout);
      } on Object {
        // Keep the user's requested pre-join state in the UI; LiveKit can catch
        // up on the next reconnect or explicit toggle.
      }
      if (!mounted) {
        await listener.dispose();
        await room.dispose();
        return false;
      }
      _ensureRemoteSubscriptions(room);
      _cancelLiveKitReconnect();
      setState(() {
        _liveKitRoom = room;
        _liveKitListener = listener;
        _liveKitConnecting = false;
        _liveKitConnected = true;
        _micEnabled = effectiveMicEnabled;
        _deafened = requestedDeafened;
        _cameraEnabled = false;
        _cameraToggleInFlight = false;
        _screenSharing = false;
        _screenShareToggleInFlight = false;
        _cameraUnavailableReason = null;
      });
      unawaited(_syncNativeVoiceSession());
      unawaited(_applyAzoomOutputVolume(room, _azoomOutputVolume));
      unawaited(_setMobileSpeakerOn(_mobileSpeakerOn));
      if (requestedDeafened) {
        for (final participant in room.remoteParticipants.values) {
          for (final publication in participant.audioTrackPublications) {
            unawaited(publication.unsubscribe());
          }
        }
      }
      unawaited(
        _updateVoiceStatus(
          muted: !effectiveMicEnabled,
          deafened: requestedDeafened,
        ),
      );
      unawaited(_refreshCameraAvailability());
      return true;
    } on Object catch (error) {
      room.removeListener(_onLiveKitRoomChanged);
      await listener.dispose();
      await room.dispose();
      if (!mounted) {
        return false;
      }
      setState(() {
        _liveKitConnecting = false;
        _liveKitConnected = false;
        _micEnabled = effectiveMicEnabled;
        _deafened = requestedDeafened;
        _mediaErrorText = '미디어 서버 연결 실패: $error';
      });
      return false;
    }
  }

  void _onLiveKitRoomChanged() {
    if (mounted) {
      final room = _liveKitRoom;
      _ensureRemoteSubscriptions(room);
      final actualScreenSharing =
          room?.localParticipant?.isScreenShareEnabled() ?? false;
      final shouldUpdateStatus = _screenSharing != actualScreenSharing;
      setState(() {
        _screenSharing = actualScreenSharing;
      });
      if (shouldUpdateStatus && !_screenShareToggleInFlight) {
        unawaited(_updateVoiceStatus(screenSharing: actualScreenSharing));
      }
      unawaited(_applyAzoomOutputVolume(room, _azoomOutputVolume));
    }
  }

  void _ensureRemoteSubscriptions(lk.Room? room) {
    if (room == null) {
      return;
    }
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        if (!publication.subscribed && publication.subscriptionAllowed) {
          unawaited(publication.subscribe());
        }
      }
      if (_deafened) {
        continue;
      }
      for (final publication in participant.audioTrackPublications) {
        if (!publication.subscribed && publication.subscriptionAllowed) {
          unawaited(publication.subscribe());
        }
      }
    }
  }

  Future<void> _leaveVoice() async {
    if (mounted) {
      setState(() {
        _mobileVoicePreviewChannel = null;
        _mobileVoiceRoomVisible = false;
      });
    } else {
      _mobileVoicePreviewChannel = null;
      _mobileVoiceRoomVisible = false;
    }
    final channel = _connectedVoiceChannel;
    if (channel == null) {
      await _setVoiceFullscreen(false);
      return;
    }
    await _setVoiceFullscreen(false);
    await _disconnectLiveKit(callServer: true, stopRealtime: false);
  }

  Future<void> _disconnectLiveKit({
    required bool callServer,
    bool clearVoiceState = true,
    bool stopRealtime = true,
    bool resetMediaControls = true,
    String? accessTokenOverride,
    AzoomApi? apiOverride,
  }) async {
    if (callServer || clearVoiceState || stopRealtime) {
      _stopVoiceHeartbeat();
    }
    if (callServer || clearVoiceState) {
      _cancelLiveKitReconnect();
    }
    await _stopNotivaAudioCapture(uploadBatch: true);
    final channel = _connectedVoiceChannel;
    final room = _liveKitRoom;
    final listener = _liveKitListener;
    _liveKitRoom = null;
    _liveKitListener = null;
    if (room != null) {
      room.removeListener(_onLiveKitRoomChanged);
      await room.disconnect();
      await room.dispose();
    }
    await listener?.dispose();
    final token = callServer
        ? (accessTokenOverride ?? (mounted ? _accessToken : null))
        : null;
    if (token != null && channel != null) {
      try {
        final api =
            apiOverride ?? (mounted ? ref.read(azoomApiProvider) : null);
        if (api == null) {
          return;
        }
        final state = await api.leaveVoice(
          accessToken: token,
          channelId: channel.id,
        );
        if (mounted) {
          _syncVoiceState(state);
        }
      } on Object {
        // Local disconnect must still complete even if presence cleanup retries later.
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (clearVoiceState) {
        _connectedVoiceChannel = null;
        _stageVoiceChannel = null;
        _mobileVoicePreviewChannel = null;
        _mobileVoiceRoomVisible = false;
      }
      _liveKitConnected = false;
      _liveKitConnecting = false;
      if (resetMediaControls) {
        _micEnabled = true;
        _deafened = false;
      }
      _cameraEnabled = false;
      _cameraToggleInFlight = false;
      _screenSharing = false;
      _screenShareToggleInFlight = false;
      _cameraUnavailableReason = null;
      _mediaErrorText = null;
    });
    if (callServer || clearVoiceState) {
      _nativeVoiceSessionActive = false;
      _nativeVoiceSessionSignature = null;
      unawaited(AzoomVoicePlatform.stopSession());
    } else {
      unawaited(_syncNativeVoiceSession());
    }
    if (stopRealtime) {
      _stopVoiceRealtime();
    }
    if (clearVoiceState) {
      _stopNotivaRealtime();
      if (mounted) {
        setState(() {
          _notivaOpen = false;
          _notivaStarting = false;
          _notivaTranscript = null;
        });
      }
    }
  }

  Future<void> _toggleMic() async {
    if (_deafened) {
      await _setDeafenState(false);
      return;
    }
    final next = !_micEnabled;
    if (next && !await _ensureAzoomMicrophonePermission()) {
      return;
    }
    try {
      final audioCaptureOptions = next
          ? await _resolveAzoomAudioCaptureOptions()
          : _azoomAudioProcessingOptions;
      await _liveKitRoom?.localParticipant?.setMicrophoneEnabled(
        next,
        audioCaptureOptions: audioCaptureOptions,
      );
      setState(() {
        _micEnabled = next;
      });
      unawaited(_syncNativeVoiceSession());
      if (_notivaAudioCaptureActive) {
        if (next) {
          await _beginNextNotivaChunk();
        } else {
          await _rotateNotivaChunk();
        }
      }
      await _updateVoiceStatus(muted: !next);
    } on Object catch (error) {
      setState(() {
        _mediaErrorText = '마이크 상태 변경 실패: $error';
      });
    }
  }

  Future<lk.AudioCaptureOptions> _resolveAzoomAudioCaptureOptions() async {
    final device = await _preferredAzoomAudioInput();
    return _audioCaptureOptionsForNoiseMode(deviceId: device?.deviceId);
  }

  lk.AudioCaptureOptions _audioCaptureOptionsForNoiseMode({String? deviceId}) {
    final enabled = _noiseSuppressionMode != _AzoomNoiseSuppressionMode.off;
    final krisp = _noiseSuppressionMode == _AzoomNoiseSuppressionMode.krisp;
    return lk.AudioCaptureOptions(
      deviceId: deviceId,
      noiseSuppression: enabled,
      echoCancellation: enabled,
      autoGainControl: enabled,
      highPassFilter: enabled,
      voiceIsolation: krisp,
      typingNoiseDetection: krisp,
      stopAudioCaptureOnMute: true,
    );
  }

  Future<lk.MediaDevice?> _preferredAzoomAudioInput() async {
    try {
      final inputs = await lk.Hardware.instance.audioInputs();
      if (inputs.isEmpty) {
        return null;
      }

      final selected = lk.Hardware.instance.selectedAudioInput;
      if (selected != null && !_isLoopbackAudioInput(selected)) {
        return selected;
      }

      lk.MediaDevice? preferred;
      for (final input in inputs) {
        if (!_isLoopbackAudioInput(input)) {
          preferred = input;
          break;
        }
      }
      preferred ??= selected ?? inputs.first;
      if (selected?.deviceId != preferred.deviceId) {
        await lk.Hardware.instance.selectAudioInput(preferred);
      }
      return preferred;
    } on Object {
      return null;
    }
  }

  Future<void> _toggleDeafen() async {
    await _setDeafenState(!_deafened);
  }

  Future<void> _setDeafenState(bool next) async {
    final room = _liveKitRoom;
    final nextMicEnabled = !next;
    try {
      if (nextMicEnabled && !await _ensureAzoomMicrophonePermission()) {
        return;
      }
      if (room != null) {
        if (nextMicEnabled) {
          final audioCaptureOptions = await _resolveAzoomAudioCaptureOptions();
          await room.localParticipant?.setMicrophoneEnabled(
            true,
            audioCaptureOptions: audioCaptureOptions,
          );
        } else {
          await room.localParticipant?.setMicrophoneEnabled(
            false,
            audioCaptureOptions: _azoomAudioProcessingOptions,
          );
        }
        for (final participant in room.remoteParticipants.values) {
          for (final publication in participant.audioTrackPublications) {
            if (next) {
              unawaited(publication.unsubscribe());
            } else {
              unawaited(publication.subscribe());
            }
          }
        }
      }
      setState(() {
        _deafened = next;
        _micEnabled = nextMicEnabled;
      });
      unawaited(_syncNativeVoiceSession());
      if (_notivaAudioCaptureActive) {
        if (nextMicEnabled) {
          await _beginNextNotivaChunk();
        } else {
          await _rotateNotivaChunk();
        }
      }
      await _updateVoiceStatus(muted: !nextMicEnabled, deafened: next);
    } on Object catch (error) {
      setState(() {
        _mediaErrorText = 'Deafen state update failed: $error';
      });
    }
  }

  Future<void> _selectAudioInput(lk.MediaDevice device) async {
    final room = _liveKitRoom;
    if (room == null) {
      await lk.Hardware.instance.selectAudioInput(device);
      return;
    }
    await room.setAudioInputDevice(device);
    if (_micEnabled) {
      final audioCaptureOptions = _audioCaptureOptionsForNoiseMode(
        deviceId: device.deviceId,
      );
      await room.localParticipant?.setMicrophoneEnabled(
        false,
        audioCaptureOptions: audioCaptureOptions,
      );
      await room.localParticipant?.setMicrophoneEnabled(
        true,
        audioCaptureOptions: audioCaptureOptions,
      );
      await _updateVoiceStatus(muted: false);
    }
  }

  Future<void> _selectAudioOutput(lk.MediaDevice device) async {
    final room = _liveKitRoom;
    if (room == null) {
      await lk.Hardware.instance.selectAudioOutput(device);
      return;
    }
    await room.setAudioOutputDevice(device);
    await _applyAzoomOutputVolume(room, _azoomOutputVolume);
  }

  Future<void> _setMobileSpeakerOn(bool speakerOn) async {
    try {
      final room = _liveKitRoom;
      if (room != null) {
        await room.setSpeakerOn(speakerOn);
      } else {
        await lk.Hardware.instance.setSpeakerphoneOn(speakerOn);
      }
      if (mounted) {
        setState(() {
          _mobileSpeakerOn = speakerOn;
        });
      } else {
        _mobileSpeakerOn = speakerOn;
      }
    } on Object {
      if (mounted) {
        showAvaToast(
          context,
          '\uC624\uB514\uC624 \uCD9C\uB825\uC744 \uBCC0\uACBD\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.',
        );
      }
    }
  }

  Future<void> _setNoiseSuppressionMode(_AzoomNoiseSuppressionMode mode) async {
    if (_noiseSuppressionMode == mode) {
      return;
    }
    setState(() {
      _noiseSuppressionMode = mode;
    });
    final room = _liveKitRoom;
    final participant = room?.localParticipant;
    if (room == null || participant == null || !_micEnabled) {
      return;
    }
    try {
      final audioCaptureOptions = await _resolveAzoomAudioCaptureOptions();
      await participant.setMicrophoneEnabled(
        false,
        audioCaptureOptions: audioCaptureOptions,
      );
      await participant.setMicrophoneEnabled(
        true,
        audioCaptureOptions: audioCaptureOptions,
      );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _mediaErrorText = 'Noise suppression update failed: $error';
        });
      }
    }
  }

  Future<void> _selectCameraInput(lk.MediaDevice device) async {
    final room = _liveKitRoom;
    if (room == null) {
      lk.Hardware.instance.selectedVideoInput = device;
      return;
    }
    await room.setVideoInputDevice(device);
    if (!mounted) {
      return;
    }
    setState(() {
      _cameraUnavailableReason = null;
      _mediaErrorText = null;
    });
  }

  void _setAzoomOutputVolume(double value) {
    final next = value.clamp(0.0, 1.0);
    setState(() {
      _azoomOutputVolume = next;
    });
    unawaited(_applyAzoomOutputVolume(_liveKitRoom, next));
  }

  Future<void> _applyAzoomOutputVolume(lk.Room? room, double value) async {
    if (room == null) {
      return;
    }
    final volume = value.clamp(0.0, 1.0);
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.audioTrackPublications) {
        final mediaTrack = publication.track?.mediaStreamTrack;
        if (mediaTrack != null) {
          await rtc.Helper.setVolume(volume, mediaTrack);
        }
      }
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameraToggleInFlight) {
      return;
    }
    final unavailableReason = _cameraUnavailableReason;
    if (unavailableReason != null && !_cameraEnabled) {
      await _showCameraUnavailableDialog(unavailableReason);
      return;
    }
    final room = _liveKitRoom;
    final participant = room?.localParticipant;
    if (!_liveKitConnected || room == null || participant == null) {
      await _showCameraUnavailableDialog('미디어 서버 연결이 완료된 뒤 카메라를 켜주세요.');
      return;
    }

    final next = !_cameraEnabled;
    if (next && !await _ensureAzoomCameraPermission()) {
      return;
    }
    setState(() {
      _cameraToggleInFlight = true;
      _mediaErrorText = null;
    });
    try {
      if (next) {
        final videoInputs = await lk.Hardware.instance.videoInputs();
        if (!mounted) {
          return;
        }
        if (videoInputs.isEmpty) {
          const message = '사용 가능한 카메라를 찾지 못했습니다. 장치를 연결한 뒤 다시 시도해주세요.';
          setState(() {
            _cameraEnabled = false;
            _cameraToggleInFlight = false;
            _cameraUnavailableReason = message;
            _mediaErrorText = null;
          });
          await _updateVoiceStatus(cameraEnabled: false);
          await _showCameraUnavailableDialog(message);
          return;
        }
      }

      await participant.setCameraEnabled(next);
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraEnabled = next;
        _cameraToggleInFlight = false;
        if (next) {
          _cameraUnavailableReason = null;
        }
        _mediaErrorText = null;
      });
      await _updateVoiceStatus(cameraEnabled: next);
    } on Object catch (error) {
      try {
        await participant.setCameraEnabled(false);
      } on Object {
        // Keep the UI consistent even if cleanup also fails.
      }
      if (!mounted) {
        return;
      }
      final message = _cameraFailureMessage(error);
      setState(() {
        _cameraEnabled = false;
        _cameraToggleInFlight = false;
        _cameraUnavailableReason = message;
        _mediaErrorText = null;
      });
      await _updateVoiceStatus(cameraEnabled: false);
      await _showCameraUnavailableDialog(message);
    }
  }

  Future<void> _refreshCameraAvailability() async {
    if (!_liveKitConnected || _liveKitRoom == null) {
      return;
    }
    try {
      final videoInputs = await lk.Hardware.instance.videoInputs();
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraUnavailableReason = videoInputs.isEmpty
            ? '사용 가능한 카메라를 찾지 못했습니다. 장치를 연결한 뒤 다시 시도해주세요.'
            : null;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _cameraUnavailableReason =
            '카메라 장치 목록을 확인할 수 없습니다. Windows 카메라 권한과 장치 상태를 확인해주세요.';
      });
    }
  }

  Future<void> _showCameraUnavailableDialog([String? message]) async {
    if (_cameraDialogOpen || !mounted) {
      return;
    }
    _cameraDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFFE8EEF2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
            contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: const Row(
              children: [
                Icon(Icons.videocam_off, color: Color(0xFFFF5A63), size: 24),
                SizedBox(width: 10),
                Text(
                  '카메라 사용 불가능',
                  style: TextStyle(
                    color: _primaryText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            content: Text(
              message ?? '카메라를 사용할 수 없습니다. 카메라 연결과 권한을 확인해주세요.',
              style: const TextStyle(
                color: _secondaryText,
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  '확인',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      _cameraDialogOpen = false;
    }
  }

  bool get _needsRuntimeMediaPermission => Platform.isAndroid || Platform.isIOS;

  bool _permissionGranted(PermissionStatus status) =>
      status.isGranted || status.isLimited;

  Future<bool> _ensureAzoomMicrophonePermission() async {
    if (!_needsRuntimeMediaPermission) {
      return true;
    }
    final current = await Permission.microphone.status;
    if (_permissionGranted(current)) {
      return true;
    }
    final requested = await Permission.microphone.request();
    if (_permissionGranted(requested)) {
      return true;
    }
    if (mounted) {
      setState(() {
        _liveKitConnecting = false;
        _mediaErrorText = '마이크 권한이 필요합니다.';
      });
    }
    return false;
  }

  Future<bool> _ensureAzoomCameraPermission() async {
    if (!_needsRuntimeMediaPermission) {
      return true;
    }
    final current = await Permission.camera.status;
    if (_permissionGranted(current)) {
      return true;
    }
    final requested = await Permission.camera.request();
    if (_permissionGranted(requested)) {
      return true;
    }
    if (mounted) {
      setState(() {
        _cameraToggleInFlight = false;
        _cameraUnavailableReason = '카메라 권한이 필요합니다.';
        _mediaErrorText = null;
      });
    }
    await _showCameraUnavailableDialog('카메라 권한이 필요합니다.');
    return false;
  }

  String _cameraFailureMessage(Object error) {
    final detail = error.toString().toLowerCase();
    if (detail.contains('notallowed') ||
        detail.contains('permission') ||
        detail.contains('denied')) {
      return '카메라 권한이 차단되었습니다. Windows 설정에서 데스크톱 앱의 카메라 접근을 허용해주세요.';
    }
    if (detail.contains('notfound') ||
        detail.contains('no device') ||
        detail.contains('device not found')) {
      return '사용 가능한 카메라를 찾지 못했습니다. 카메라 연결 상태를 확인해주세요.';
    }
    if (detail.contains('notreadable') ||
        detail.contains('in use') ||
        detail.contains('busy') ||
        detail.contains('could not start')) {
      return '카메라가 다른 앱에서 사용 중이거나 시작할 수 없습니다. 다른 화상 앱을 종료한 뒤 다시 시도해주세요.';
    }
    return '카메라를 켜지 못했습니다. 카메라 연결과 권한을 확인한 뒤 다시 시도해주세요.';
  }

  Future<void> _toggleScreenShare() async {
    if (_screenShareToggleInFlight) {
      return;
    }
    final room = _liveKitRoom;
    final participant = room?.localParticipant;
    if (!_liveKitConnected || room == null || participant == null) {
      await _showScreenShareDialog(
        title: '\uD654\uBA74 \uACF5\uC720 \uBD88\uAC00',
        message:
            '\uBBF8\uB514\uC5B4 \uC11C\uBC84 \uC5F0\uACB0\uC774 \uC644\uB8CC\uB41C \uB4A4 \uD654\uBA74 \uACF5\uC720\uB97C \uC2DC\uC791\uD574\uC8FC\uC138\uC694.',
      );
      return;
    }

    final next = !_screenSharing;
    setState(() {
      _screenShareToggleInFlight = true;
      _mediaErrorText = null;
    });
    try {
      if (next) {
        final started = await _startScreenShare(participant);
        if (!started) {
          if (mounted) {
            setState(() {
              _screenShareToggleInFlight = false;
            });
          }
          return;
        }
      } else {
        await participant.setScreenShareEnabled(false);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _screenSharing = next;
        _screenShareToggleInFlight = false;
      });
      await _updateVoiceStatus(screenSharing: next);
    } on Object catch (error) {
      try {
        await participant.setScreenShareEnabled(false);
      } on Object {
        // Keep local state consistent even if native cleanup fails.
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _screenSharing = false;
        _screenShareToggleInFlight = false;
        _mediaErrorText = null;
      });
      await _updateVoiceStatus(screenSharing: false);
      await _showScreenShareDialog(
        title: '화면 공유 실패',
        message: _screenShareFailureMessage(error),
      );
    }
  }

  Future<bool> _startScreenShare(lk.LocalParticipant participant) async {
    await participant.setScreenShareEnabled(false);
    if (!mounted) {
      return false;
    }
    if (lk.lkPlatformIsDesktop()) {
      final source = await _showScreenShareSourceDialog();
      if (!mounted) {
        return false;
      }
      final sourceId = source?.id;
      if (sourceId == null || sourceId.isEmpty) {
        return false;
      }
      final track = await lk.LocalVideoTrack.createScreenShareTrack(
        _azoomScreenShareCaptureOptions.copyWith(sourceId: sourceId),
      );
      await participant.publishVideoTrack(
        track,
        publishOptions: _azoomScreenSharePublishOptions,
      );
      return true;
    }

    await participant.setScreenShareEnabled(
      true,
      captureScreenAudio: true,
      screenShareCaptureOptions: _azoomScreenShareCaptureOptions,
    );
    return true;
  }

  Future<rtc.DesktopCapturerSource?> _showScreenShareSourceDialog() {
    return showDialog<rtc.DesktopCapturerSource>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => const AzoomDiscordScreenShareSourceDialog(),
    );
  }

  Future<void> _showScreenShareDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFFE8EEF2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Row(
            children: [
              const Icon(Icons.screen_share, color: _avaAccentDeep, size: 24),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: _primaryText,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: _secondaryText,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '확인',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );
  }

  String _screenShareFailureMessage(Object error) {
    final detail = error.toString().toLowerCase();
    if (detail.contains('notallowed') ||
        detail.contains('permission') ||
        detail.contains('denied')) {
      return '화면 공유 권한이 차단되었습니다. Windows 또는 보안 프로그램의 화면 캡처 권한을 확인해주세요.';
    }
    if (detail.contains('notfound') ||
        detail.contains('no source') ||
        detail.contains('source')) {
      return '공유할 화면 또는 창을 찾지 못했습니다. 공유할 창을 열어둔 뒤 다시 시도해주세요.';
    }
    if (detail.contains('busy') ||
        detail.contains('in use') ||
        detail.contains('could not start')) {
      return '화면 공유를 시작할 수 없습니다. 다른 화면 공유를 종료한 뒤 다시 시도해주세요.';
    }
    return '화면 공유를 시작하지 못했습니다. 공유할 화면을 다시 선택해주세요.';
  }

  Future<void> _updateVoiceStatus({
    bool? muted,
    bool? deafened,
    bool? cameraEnabled,
    bool? screenSharing,
  }) async {
    final token = _accessToken;
    final channel = _connectedVoiceChannel;
    if (token == null || channel == null) {
      return;
    }
    try {
      final state = await ref
          .read(azoomApiProvider)
          .updateVoiceStatus(
            accessToken: token,
            channelId: channel.id,
            muted: muted,
            deafened: deafened,
            cameraEnabled: cameraEnabled,
            screenSharing: screenSharing,
          )
          .timeout(_azoomVoiceStatusTimeout);
      if (mounted) {
        _syncVoiceState(state);
      }
    } on Object {
      // Media state is local first; presence catches up through the next action.
    }
  }

  void _syncVoiceStageChrome(bool active) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final controller = ref.read(azoomVoiceStageActiveProvider.notifier);
      if (ref.read(azoomVoiceStageActiveProvider) != active) {
        controller.setActive(active);
      }
    });
  }

  Future<void> _setVoiceFullscreen(bool fullscreen) async {
    if (_voiceFullscreen == fullscreen) {
      return;
    }
    if (mounted) {
      setState(() {
        _voiceFullscreen = fullscreen;
      });
    } else {
      _voiceFullscreen = fullscreen;
    }
    await WindowControl.setAzoomFullscreen(fullscreen);
  }

  void _toggleVoiceFullscreen() {
    unawaited(_setVoiceFullscreen(!_voiceFullscreen));
  }

  void _showMobileVoiceEntry(AzoomVoiceChannelDto channel) {
    final connected = _connectedVoiceChannel;
    if (connected?.id == channel.id) {
      setState(() {
        _mobileVoicePreviewChannel = null;
        _stageVoiceChannel = connected;
        _mobileVoiceRoomVisible = true;
      });
      unawaited(_syncNativeVoiceSession());
      return;
    }
    setState(() {
      _mobileVoicePreviewChannel = channel;
      _mobilePreviewMicEnabled = _micEnabled;
      _mobilePreviewDeafened = _deafened;
    });
  }

  void _toggleMobilePreviewMic() {
    setState(() {
      _mobilePreviewMicEnabled = !_mobilePreviewMicEnabled;
    });
  }

  void _toggleMobilePreviewDeafen() {
    setState(() {
      _mobilePreviewDeafened = !_mobilePreviewDeafened;
    });
  }

  void _openPendingVoiceEntryIfReady() {
    final channelId = ref.read(azoomPendingVoiceEntryProvider);
    if (channelId == null || channelId.isEmpty) {
      return;
    }
    final channels = _channels?.voiceChannels ?? const <AzoomVoiceChannelDto>[];
    AzoomVoiceChannelDto? target;
    for (final channel in channels) {
      if (channel.id == channelId) {
        target = channel;
        break;
      }
    }
    if (target == null) {
      return;
    }
    final width = MediaQuery.maybeSizeOf(context)?.width ?? double.infinity;
    if (width <= _mobileAzoomBreakpoint) {
      _showMobileVoiceEntry(target);
    } else {
      unawaited(_joinVoice(target));
    }
    ref.read(azoomPendingVoiceEntryProvider.notifier).clear();
  }

  void _hideMobileVoiceEntry() {
    if (_mobileVoicePreviewChannel == null) {
      return;
    }
    setState(() {
      _mobileVoicePreviewChannel = null;
    });
  }

  Future<void> _joinMobileVoice(AzoomVoiceChannelDto channel) async {
    setState(() {
      _mobileVoicePreviewChannel = null;
      _mobileVoiceRoomVisible = true;
      _micEnabled = _mobilePreviewMicEnabled && !_mobilePreviewDeafened;
      _deafened = _mobilePreviewDeafened;
    });
    await _joinVoice(channel, keepStageOnMediaFailure: true);
    if (!mounted) {
      return;
    }
    final connected = _connectedVoiceChannel;
    final staged = _stageVoiceChannel;
    final visible =
        connected?.id == channel.id ||
        staged?.id == channel.id ||
        _joiningVoice;
    setState(() {
      _mobileVoiceRoomVisible = visible;
      if (connected?.id == channel.id) {
        _stageVoiceChannel = connected;
      } else if (staged?.id == channel.id) {
        _stageVoiceChannel = staged;
      }
    });
    unawaited(_syncNativeVoiceSession());
  }

  void _dismissMobileVoiceRoom() {
    if (!_mobileVoiceRoomVisible) {
      return;
    }
    setState(() {
      _mobileVoiceRoomVisible = false;
      _stageVoiceChannel = null;
    });
    unawaited(_syncNativeVoiceSession());
  }

  bool _handleMobileBack() {
    if (_mobileVoiceRoomVisible) {
      _dismissMobileVoiceRoom();
      return true;
    }
    if (_mobileVoicePreviewChannel != null) {
      _hideMobileVoiceEntry();
      return true;
    }
    return false;
  }

  Widget _buildMobileAzoomLayout({
    required List<AzoomVoiceChannelDto> voiceChannels,
    required Set<String> liveVoiceUserIds,
  }) {
    AzoomVoiceChannelDto rowVoiceChannel(AzoomVoiceChannelDto channel) {
      if (_connectedVoiceChannel?.id == channel.id) {
        return _connectedVoiceChannel!;
      }
      if (_stageVoiceChannel?.id == channel.id) {
        return _stageVoiceChannel!;
      }
      return channel;
    }

    final visibleVoiceChannel = _mobileVoiceRoomVisible
        ? (_connectedVoiceChannel ?? _stageVoiceChannel)
        : null;
    final mediaPadding = MediaQuery.paddingOf(context);
    final pageSize = MediaQuery.sizeOf(context);
    final miniVoiceChannel = !_mobileVoiceRoomVisible
        ? _connectedVoiceChannel
        : null;
    final miniVoiceExpanded = _mobileMiniVoiceControlsVisible;
    final miniVoiceWidth = miniVoiceExpanded ? 178.0 : 112.0;
    final miniVoiceHeight = miniVoiceExpanded ? 174.0 : 112.0;
    final miniDefaultOffset = Offset(
      pageSize.width - miniVoiceWidth - 14,
      mediaPadding.top + 68,
    );
    final rawMiniOffset = _mobileMiniVoiceOffset ?? miniDefaultOffset;
    final miniVoiceOffset = Offset(
      rawMiniOffset.dx.clamp(8.0, pageSize.width - miniVoiceWidth - 8),
      rawMiniOffset.dy.clamp(
        mediaPadding.top + 8,
        pageSize.height - miniVoiceHeight - mediaPadding.bottom - 8,
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: !_mobileVoiceRoomVisible && _mobileVoicePreviewChannel == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handleMobileBack();
          }
        },
        child: ColoredBox(
          key: const ValueKey('azoom-mobile-page'),
          color: _mobileAzoomRailColor,
          child: Stack(
            children: [
              Row(
                children: [
                  _MobileAzoomRail(
                    currentUser: widget.currentUser,
                    transcriptsActive:
                        _mobileMeetingTranscriptsExpanded ||
                        _selectedMeetingTranscript != null,
                    onTranscriptsTap: () {
                      setState(() {
                        _mobileMeetingTranscriptsExpanded = true;
                      });
                    },
                    onCalendarTap: () {},
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: mediaPadding.top),
                      child: ClipRRect(
                        key: const ValueKey('azoom-mobile-channel-card'),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                        ),
                        child: _MobileAzoomChannelList(
                          voiceChannels: voiceChannels,
                          meetingTranscripts: _visibleMeetingTranscripts,
                          searchQuery: _azoomSearchQuery,
                          meetingTranscriptsExpanded:
                              _mobileMeetingTranscriptsExpanded,
                          selectedMeetingTranscript: _selectedMeetingTranscript,
                          stageVoiceChannel: _stageVoiceChannel,
                          connectedVoiceChannel: _connectedVoiceChannel,
                          liveVoiceUserIds: liveVoiceUserIds,
                          currentUser: widget.currentUser,
                          joiningVoice: _joiningVoice,
                          micEnabled: _micEnabled,
                          deafened: _deafened,
                          cameraEnabled: _cameraEnabled,
                          screenSharing: _screenSharing,
                          onVoiceChannelSelected: _showMobileVoiceEntry,
                          onMeetingTranscriptsToggle: () {
                            setState(() {
                              _mobileMeetingTranscriptsExpanded =
                                  !_mobileMeetingTranscriptsExpanded;
                            });
                          },
                          onMeetingTranscriptSelected: (summary) {
                            _hideMobileVoiceEntry();
                            unawaited(_setVoiceFullscreen(false));
                            setState(() {
                              _stageVoiceChannel = null;
                              _mobileVoiceRoomVisible = false;
                            });
                            unawaited(_syncNativeVoiceSession());
                            unawaited(_selectMeetingTranscript(summary));
                          },
                          onSearchChanged: (value) {
                            setState(() {
                              _azoomSearchQuery = value;
                            });
                          },
                          onInvitePressed: () =>
                              unawaited(_showAzoomManagerPanel()),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_mobileVoicePreviewChannel != null)
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('azoom-mobile-join-dismiss-layer'),
                    behavior: HitTestBehavior.translucent,
                    onTap: _hideMobileVoiceEntry,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _MobileBottomSheetSwitcher(
                  child: _mobileVoicePreviewChannel == null
                      ? const SizedBox.shrink(
                          key: ValueKey('azoom-mobile-no-join-sheet'),
                        )
                      : _MobileVoiceJoinSheet(
                          key: ValueKey(
                            'azoom-mobile-join-${_mobileVoicePreviewChannel!.id}',
                          ),
                          channel: rowVoiceChannel(_mobileVoicePreviewChannel!),
                          joining: _joiningVoice,
                          micEnabled: _mobilePreviewMicEnabled,
                          deafened: _mobilePreviewDeafened,
                          onCollapse: _hideMobileVoiceEntry,
                          onToggleMic: _toggleMobilePreviewMic,
                          onToggleDeafen: _toggleMobilePreviewDeafen,
                          onJoin: () => unawaited(
                            _joinMobileVoice(_mobileVoicePreviewChannel!),
                          ),
                        ),
                ),
              ),
              Positioned.fill(
                child: _MobileBottomSheetSwitcher(
                  child: visibleVoiceChannel == null
                      ? const SizedBox.shrink(
                          key: ValueKey('azoom-mobile-no-voice-room'),
                        )
                      : _MobileAzoomVoiceRoom(
                          key: ValueKey(
                            'azoom-mobile-voice-room-${visibleVoiceChannel.id}',
                          ),
                          channel: visibleVoiceChannel,
                          currentUser: widget.currentUser,
                          liveKitRoom: _liveKitRoom,
                          liveKitConnecting: _liveKitConnecting,
                          liveKitConnected: _liveKitConnected,
                          micEnabled: _micEnabled,
                          deafened: _deafened,
                          cameraEnabled: _cameraEnabled,
                          cameraBusy: _cameraToggleInFlight,
                          cameraUnavailableReason: _cameraUnavailableReason,
                          screenSharing: _screenSharing,
                          screenShareBusy: _screenShareToggleInFlight,
                          mediaErrorText: _mediaErrorText,
                          onCollapse: _dismissMobileVoiceRoom,
                          onToggleMic: () => unawaited(_toggleMic()),
                          onToggleDeafen: () => unawaited(_toggleDeafen()),
                          onToggleCamera: () => unawaited(_toggleCamera()),
                          onCameraUnavailable: () =>
                              unawaited(_showCameraUnavailableDialog()),
                          onSelectAudioInput: (device) =>
                              unawaited(_selectAudioInput(device)),
                          onSelectAudioOutput: (device) =>
                              unawaited(_selectAudioOutput(device)),
                          onSelectCameraInput: (device) =>
                              unawaited(_selectCameraInput(device)),
                          outputVolume: _azoomOutputVolume,
                          onOutputVolumeChanged: _setAzoomOutputVolume,
                          mobileSpeakerOn: _mobileSpeakerOn,
                          onMobileSpeakerChanged: (speakerOn) =>
                              unawaited(_setMobileSpeakerOn(speakerOn)),
                          noiseSuppressionMode: _noiseSuppressionMode,
                          onNoiseSuppressionModeChanged: (mode) =>
                              unawaited(_setNoiseSuppressionMode(mode)),
                          onToggleScreenShare: () =>
                              unawaited(_toggleScreenShare()),
                          onShowParticipants: () => unawaited(
                            _showParticipantsPanel(visibleVoiceChannel),
                          ),
                          onTriggerFirework: () =>
                              unawaited(_triggerFirework(visibleVoiceChannel)),
                          onToggleNotiva: () =>
                              unawaited(_toggleNotiva(visibleVoiceChannel)),
                          onLeave: () => unawaited(_leaveVoice()),
                        ),
                ),
              ),
              if (visibleVoiceChannel != null && _notivaOpen)
                Positioned(
                  key: const ValueKey('azoom-mobile-notiva-overlay'),
                  top: mediaPadding.top + 62,
                  left: 16,
                  right: 16,
                  bottom: mediaPadding.bottom + 116,
                  child: _NotivaAiPanel(
                    starting: _notivaStarting,
                    active: _notivaAudioCaptureActive,
                    errorText: _notivaErrorText,
                    transcript: _notivaTranscript,
                    onClose: () =>
                        unawaited(_toggleNotiva(visibleVoiceChannel)),
                  ),
                ),
              if (miniVoiceChannel != null &&
                  _mobileVoicePreviewChannel == null)
                Positioned(
                  left: miniVoiceOffset.dx,
                  top: miniVoiceOffset.dy,
                  child: _MobileAzoomVoiceMiniOverlay(
                    channel: miniVoiceChannel,
                    participant: _featuredVoiceParticipant(miniVoiceChannel),
                    expanded: miniVoiceExpanded,
                    micEnabled: _micEnabled,
                    deafened: _deafened,
                    onTap: () {
                      setState(() {
                        _mobileMiniVoiceControlsVisible =
                            !_mobileMiniVoiceControlsVisible;
                      });
                    },
                    onDragUpdate: (delta) {
                      setState(() {
                        final current =
                            _mobileMiniVoiceOffset ?? miniVoiceOffset;
                        _mobileMiniVoiceOffset = Offset(
                          (current.dx + delta.dx).clamp(
                            8.0,
                            pageSize.width - miniVoiceWidth - 8,
                          ),
                          (current.dy + delta.dy).clamp(
                            mediaPadding.top + 8,
                            pageSize.height -
                                miniVoiceHeight -
                                mediaPadding.bottom -
                                8,
                          ),
                        );
                      });
                    },
                    onOpen: () {
                      setState(() {
                        _stageVoiceChannel = miniVoiceChannel;
                        _mobileVoiceRoomVisible = true;
                        _mobileMiniVoiceControlsVisible = false;
                      });
                      unawaited(_syncNativeVoiceSession());
                    },
                    onToggleMic: () => unawaited(_toggleMic()),
                    onToggleDeafen: () => unawaited(_toggleDeafen()),
                    onLeave: () => unawaited(_leaveVoice()),
                  ),
                ),
              if (_fireworkVisible)
                Positioned.fill(
                  child: IgnorePointer(
                    child: _AzoomFireworkOverlay(
                      burstIds: List<int>.of(_fireworkBurstIds),
                    ),
                  ),
                ),
              if (visibleVoiceChannel == null &&
                  _selectedMeetingTranscript != null)
                Positioned(
                  key: const ValueKey('azoom-mobile-transcript-overlay'),
                  top: mediaPadding.top + 62,
                  left: 16,
                  right: 16,
                  bottom:
                      mediaPadding.bottom + _mobileAzoomBottomNavHeight + 12,
                  child: _NotivaAiPanel(
                    title: '\uD68C\uC758\uB85D',
                    starting: false,
                    active: true,
                    errorText: null,
                    transcript: _selectedMeetingTranscript,
                    relatedTranscripts: _meetingTranscripts,
                    onTranscriptSelected: (summary) =>
                        unawaited(_selectMeetingTranscript(summary)),
                    onClose: () {
                      setState(() {
                        _selectedMeetingTranscript = null;
                      });
                    },
                  ),
                ),
              if (visibleVoiceChannel == null &&
                  _mobileVoicePreviewChannel == null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _MobileAzoomBottomNav(
                    activeTab: widget.mobileActiveTab,
                    onTabSelected: widget.onMobileTabSelected,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(azoomPendingVoiceEntryProvider, (previous, next) {
      if (next == null || next.isEmpty) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _openPendingVoiceEntryIfReady();
        }
      });
    });
    final channels = _channels;
    final voiceChannels = channels?.voiceChannels ?? _fallbackVoiceChannels;
    final voiceStage = _stageVoiceChannel;
    final liveVoiceUserIds = _liveVoiceUserIds(_liveKitRoom);
    final mobileLayout =
        MediaQuery.sizeOf(context).width <= _mobileAzoomBreakpoint;
    _syncVoiceStageChrome(voiceStage != null && _voiceFullscreen);

    Widget buildVoiceSurface(AzoomVoiceChannelDto channel) {
      return _AzoomVoiceSurface(
        channel: channel,
        currentUser: widget.currentUser,
        liveKitRoom: _liveKitRoom,
        liveKitConnecting: _liveKitConnecting,
        liveKitConnected: _liveKitConnected,
        micEnabled: _micEnabled,
        deafened: _deafened,
        cameraEnabled: _cameraEnabled,
        cameraBusy: _cameraToggleInFlight,
        cameraUnavailableReason: _cameraUnavailableReason,
        screenSharing: _screenSharing,
        screenShareBusy: _screenShareToggleInFlight,
        fullscreen: _voiceFullscreen,
        notivaOpen: _notivaOpen,
        notivaStarting: _notivaStarting,
        notivaAudioCaptureActive: _notivaAudioCaptureActive,
        notivaTranscript: _notivaTranscript,
        notivaErrorText: _notivaErrorText,
        mediaErrorText: _mediaErrorText,
        onToggleMic: () => unawaited(_toggleMic()),
        onToggleDeafen: () => unawaited(_toggleDeafen()),
        onToggleCamera: () => unawaited(_toggleCamera()),
        onCameraUnavailable: () => unawaited(_showCameraUnavailableDialog()),
        onSelectAudioInput: (device) => unawaited(_selectAudioInput(device)),
        onSelectAudioOutput: (device) => unawaited(_selectAudioOutput(device)),
        onSelectCameraInput: (device) => unawaited(_selectCameraInput(device)),
        outputVolume: _azoomOutputVolume,
        onOutputVolumeChanged: _setAzoomOutputVolume,
        onToggleScreenShare: () => unawaited(_toggleScreenShare()),
        onToggleFullscreen: _toggleVoiceFullscreen,
        onToggleNotiva: () => unawaited(_toggleNotiva(channel)),
        onShowParticipants: () => unawaited(_showParticipantsPanel(channel)),
        onTriggerFirework: () => unawaited(_triggerFirework(channel)),
        onLeave: () => unawaited(_leaveVoice()),
      );
    }

    if (voiceStage != null && _voiceFullscreen) {
      return ColoredBox(
        key: const ValueKey('azoom-page'),
        color: _stageBackground,
        child: Stack(
          children: [
            buildVoiceSurface(voiceStage),
            if (_fireworkVisible)
              Positioned.fill(
                child: IgnorePointer(
                  child: _AzoomFireworkOverlay(
                    burstIds: List<int>.of(_fireworkBurstIds),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (mobileLayout) {
      return _buildMobileAzoomLayout(
        voiceChannels: voiceChannels,
        liveVoiceUserIds: liveVoiceUserIds,
      );
    }

    return ColoredBox(
      key: const ValueKey('azoom-page'),
      color: _chatBackground,
      child: Stack(
        children: [
          Row(
            children: [
              const _ServerRail(),
              _ChannelSidebar(
                voiceChannels: voiceChannels,
                meetingTranscripts: _visibleMeetingTranscripts,
                searchQuery: _azoomSearchQuery,
                selectedMeetingTranscript: _selectedMeetingTranscript,
                stageVoiceChannel: voiceStage,
                connectedVoiceChannel: _connectedVoiceChannel,
                liveVoiceUserIds: liveVoiceUserIds,
                currentUser: widget.currentUser,
                joiningVoice: _joiningVoice,
                micEnabled: _micEnabled,
                deafened: _deafened,
                cameraEnabled: _cameraEnabled,
                screenSharing: _screenSharing,
                onVoiceChannelSelected: (channel) =>
                    unawaited(_joinVoice(channel)),
                onMeetingTranscriptSelected: (summary) =>
                    unawaited(_selectMeetingTranscript(summary)),
                onSearchChanged: (value) {
                  setState(() {
                    _azoomSearchQuery = value;
                  });
                },
                onInvitePressed: () => unawaited(_showAzoomManagerPanel()),
              ),
              Expanded(
                child: _selectedMeetingTranscript != null
                    ? _AzoomMeetingTranscriptSurface(
                        transcript: _selectedMeetingTranscript!,
                        relatedTranscripts: _meetingTranscripts,
                        onTranscriptSelected: (summary) =>
                            unawaited(_selectMeetingTranscript(summary)),
                      )
                    : voiceStage == null
                    ? _AzoomVoicePlaceholderSurface(
                        voiceChannels: voiceChannels,
                        loading: _loadingChannels || _loadingTranscript,
                        errorText: _errorText,
                        onVoiceChannelSelected: (channel) =>
                            unawaited(_joinVoice(channel)),
                      )
                    : buildVoiceSurface(voiceStage),
              ),
            ],
          ),
          Positioned(
            left: 6,
            bottom: 6,
            width: _serverRailWidth + _channelSidebarWidth - 12,
            child: _DiscordLeftBottomDock(
              connectedVoiceChannel: _connectedVoiceChannel,
              currentUser: widget.currentUser,
              liveKitRoom: _liveKitRoom,
              liveKitConnected: _liveKitConnected,
              micEnabled: _micEnabled,
              deafened: _deafened,
              cameraEnabled: _cameraEnabled,
              cameraBusy: _cameraToggleInFlight,
              cameraUnavailableReason: _cameraUnavailableReason,
              screenSharing: _screenSharing,
              screenShareBusy: _screenShareToggleInFlight,
              outputVolume: _azoomOutputVolume,
              onLeaveVoice: () => unawaited(_leaveVoice()),
              onToggleMic: () => unawaited(_toggleMic()),
              onToggleDeafen: () => unawaited(_toggleDeafen()),
              onToggleCamera: () => unawaited(_toggleCamera()),
              onCameraUnavailable: () =>
                  unawaited(_showCameraUnavailableDialog()),
              onSelectAudioInput: (device) =>
                  unawaited(_selectAudioInput(device)),
              onSelectAudioOutput: (device) =>
                  unawaited(_selectAudioOutput(device)),
              onOutputVolumeChanged: _setAzoomOutputVolume,
              onToggleScreenShare: () => unawaited(_toggleScreenShare()),
              onTriggerFirework: () {
                final channel = _connectedVoiceChannel ?? _stageVoiceChannel;
                if (channel != null) {
                  unawaited(_triggerFirework(channel));
                }
              },
            ),
          ),
          if (_fireworkVisible)
            Positioned.fill(
              child: IgnorePointer(
                child: _AzoomFireworkOverlay(
                  burstIds: List<int>.of(_fireworkBurstIds),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AzoomScreenShareSourceDialog extends StatefulWidget {
  const _AzoomScreenShareSourceDialog();

  @override
  State<_AzoomScreenShareSourceDialog> createState() =>
      _AzoomScreenShareSourceDialogState();
}

class _AzoomScreenShareSourceDialogState
    extends State<_AzoomScreenShareSourceDialog> {
  List<rtc.DesktopCapturerSource> _sources = const [];
  rtc.DesktopCapturerSource? _selectedSource;
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSources());
  }

  Future<void> _loadSources() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final sources = await rtc.desktopCapturer.getSources(
        types: [rtc.SourceType.Screen, rtc.SourceType.Window],
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sources = sources;
        _selectedSource = sources
            .where((source) => source.type == rtc.SourceType.Screen)
            .cast<rtc.DesktopCapturerSource?>()
            .firstOrNull;
        _selectedSource ??= sources.firstOrNull;
        _loading = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _sources = const [];
        _selectedSource = null;
        _loading = false;
        _errorText = '공유할 화면 목록을 불러오지 못했습니다.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFE8EEF2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 680,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.screen_share,
                    color: _avaAccentDeep,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '공유할 화면 선택',
                    style: TextStyle(
                      color: _primaryText,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: _secondaryText),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorText != null
                  ? _ScreenShareSourceMessage(
                      message: _errorText!,
                      onRetry: _loadSources,
                    )
                  : DefaultTabController(
                      length: 2,
                      child: Column(
                        children: [
                          const TabBar(
                            labelColor: _primaryText,
                            unselectedLabelColor: _secondaryText,
                            indicatorColor: _avaAccentDeep,
                            tabs: [
                              Tab(text: '\uC804\uCCB4 \uD654\uBA74'),
                              Tab(text: '\uCC3D'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _ScreenShareSourceGrid(
                                  sources: _sources
                                      .where(
                                        (source) =>
                                            source.type ==
                                            rtc.SourceType.Screen,
                                      )
                                      .toList(),
                                  selectedSource: _selectedSource,
                                  onSelected: (source) {
                                    setState(() => _selectedSource = source);
                                  },
                                ),
                                _ScreenShareSourceGrid(
                                  sources: _sources
                                      .where(
                                        (source) =>
                                            source.type ==
                                            rtc.SourceType.Window,
                                      )
                                      .toList(),
                                  selectedSource: _selectedSource,
                                  onSelected: (source) {
                                    setState(() => _selectedSource = source);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _selectedSource == null
                        ? null
                        : () => Navigator.of(context).pop(_selectedSource),
                    icon: const Icon(Icons.screen_share, size: 18),
                    label: const Text('공유'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenShareSourceGrid extends StatelessWidget {
  const _ScreenShareSourceGrid({
    required this.sources,
    required this.selectedSource,
    required this.onSelected,
  });

  final List<rtc.DesktopCapturerSource> sources;
  final rtc.DesktopCapturerSource? selectedSource;
  final ValueChanged<rtc.DesktopCapturerSource> onSelected;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const Center(
        child: Text(
          '공유할 항목이 없습니다.',
          style: TextStyle(
            color: _secondaryText,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.34,
      ),
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        return _ScreenShareSourceTile(
          source: source,
          selected: selectedSource?.id == source.id,
          onTap: () => onSelected(source),
        );
      },
    );
  }
}

class _ScreenShareSourceTile extends StatelessWidget {
  const _ScreenShareSourceTile({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final rtc.DesktopCapturerSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbnail = source.thumbnail;
    return Material(
      color: selected ? const Color(0xFFD7E6F0) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? _avaAccentDeep : const Color(0xFFB7C9D5),
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF17212A),
                  alignment: Alignment.center,
                  child: thumbnail != null && thumbnail.isNotEmpty
                      ? Image.memory(
                          thumbnail,
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                        )
                      : const Icon(
                          Icons.desktop_windows,
                          color: Color(0xFFB8C8D3),
                          size: 38,
                        ),
                ),
              ),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                child: Text(
                  source.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryText,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreenShareSourceMessage extends StatelessWidget {
  const _ScreenShareSourceMessage({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: _secondaryText,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

class _ServerRail extends StatelessWidget {
  const _ServerRail();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('azoom-server-rail'),
      width: _serverRailWidth,
      color: _discordSidebarPanel,
      child: Column(
        children: [
          const SizedBox(height: 8),
          _ServerButton(
            selected: true,
            child: Image.asset(
              'assets/images/ava_app_icon.png',
              width: 27,
              height: 27,
              fit: BoxFit.contain,
            ),
          ),
          const _RailDivider(),
          const _ServerButton(label: 'AI', color: _discordSidebarSelected),
          const Spacer(),
          const _RailIconButton(icon: Icons.add, tooltip: '서버 추가'),
          const SizedBox(height: 8),
          const _RailIconButton(icon: Icons.explore, tooltip: '서버 둘러보기'),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _ServerButton extends StatelessWidget {
  const _ServerButton({
    this.selected = false,
    this.child,
    this.label,
    this.color = Colors.white,
  });

  final bool selected;
  final Widget? child;
  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _serverRailWidth,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 120),
            left: 0,
            top: selected ? 11 : 21,
            child: Container(
              width: 4,
              height: selected ? 26 : 6,
              decoration: const BoxDecoration(
                color: _discordSidebarText,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
              ),
            ),
          ),
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? _avaAccentDeep : color,
                borderRadius: BorderRadius.circular(selected ? 16 : 24),
              ),
              alignment: Alignment.center,
              child:
                  child ??
                  Text(
                    label ?? '',
                    style: TextStyle(
                      color: _discordSidebarText,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _discordSidebarHover,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({required this.icon, required this.tooltip});

  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: _discordSidebarSelected,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(icon, color: _discordSidebarGreen, size: 22),
      ),
    );
  }
}

class _ChannelSidebar extends StatefulWidget {
  const _ChannelSidebar({
    required this.voiceChannels,
    required this.meetingTranscripts,
    required this.searchQuery,
    required this.selectedMeetingTranscript,
    required this.stageVoiceChannel,
    required this.connectedVoiceChannel,
    required this.liveVoiceUserIds,
    required this.currentUser,
    required this.joiningVoice,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.screenSharing,
    required this.onVoiceChannelSelected,
    required this.onMeetingTranscriptSelected,
    required this.onSearchChanged,
    required this.onInvitePressed,
  });

  final List<AzoomVoiceChannelDto> voiceChannels;
  final List<AzoomMeetingTranscriptSummaryDto> meetingTranscripts;
  final String searchQuery;
  final AzoomMeetingTranscriptDto? selectedMeetingTranscript;
  final AzoomVoiceChannelDto? stageVoiceChannel;
  final AzoomVoiceChannelDto? connectedVoiceChannel;
  final Set<String> liveVoiceUserIds;
  final PersonProfile currentUser;
  final bool joiningVoice;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool screenSharing;
  final ValueChanged<AzoomVoiceChannelDto> onVoiceChannelSelected;
  final ValueChanged<AzoomMeetingTranscriptSummaryDto>
  onMeetingTranscriptSelected;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onInvitePressed;

  @override
  State<_ChannelSidebar> createState() => _ChannelSidebarState();
}

class _ChannelSidebarState extends State<_ChannelSidebar> {
  bool _meetingTranscriptsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final voiceChannels = widget.voiceChannels;
    final meetingTranscripts = widget.meetingTranscripts;
    final meetingTranscriptGroups = _groupMeetingTranscripts(
      meetingTranscripts,
    );
    final selectedMeetingTranscript = widget.selectedMeetingTranscript;
    final stageVoiceChannel = widget.stageVoiceChannel;
    final connectedVoiceChannel = widget.connectedVoiceChannel;
    final liveVoiceUserIds = widget.liveVoiceUserIds;
    final currentUser = widget.currentUser;
    final joiningVoice = widget.joiningVoice;
    final micEnabled = widget.micEnabled;
    final deafened = widget.deafened;
    final cameraEnabled = widget.cameraEnabled;
    final screenSharing = widget.screenSharing;

    AzoomVoiceChannelDto rowVoiceChannel(AzoomVoiceChannelDto channel) {
      if (connectedVoiceChannel?.id == channel.id) {
        return connectedVoiceChannel!;
      }
      if (stageVoiceChannel?.id == channel.id) {
        return stageVoiceChannel!;
      }
      return channel;
    }

    return Container(
      key: const ValueKey('azoom-channel-sidebar'),
      width: _channelSidebarWidth,
      color: _discordSidebarBackground,
      child: Column(
        children: [
          _AzoomServerHeader(
            searchQuery: widget.searchQuery,
            onSearchChanged: widget.onSearchChanged,
            onInvitePressed: widget.onInvitePressed,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                0,
                10,
                0,
                connectedVoiceChannel == null ? 72 : 164,
              ),
              children: [
                _SectionHeader(
                  title: '\uD68C\uC758\uB85D',
                  expanded: _meetingTranscriptsExpanded,
                  showAdd: false,
                  onTap: () {
                    setState(() {
                      _meetingTranscriptsExpanded =
                          !_meetingTranscriptsExpanded;
                    });
                  },
                ),
                if (_meetingTranscriptsExpanded) ...[
                  if (meetingTranscriptGroups.isEmpty)
                    const _TranscriptEmptyRow()
                  else
                    for (final group in meetingTranscriptGroups.take(12))
                      _TranscriptRow(
                        key: ValueKey('azoom-transcript-group-${group.key}'),
                        group: group,
                        selected: group.contains(selectedMeetingTranscript),
                        onTap: () => widget.onMeetingTranscriptSelected(
                          group.preferredTranscript(selectedMeetingTranscript),
                        ),
                      ),
                ],
                const SizedBox(height: 14),
                const _SectionHeader(title: '\uC74C\uC131 \uCC44\uB110'),
                for (final channel in voiceChannels)
                  _VoiceRow(
                    key: ValueKey('azoom-voice-channel-${channel.name}'),
                    channel: rowVoiceChannel(channel),
                    selected:
                        stageVoiceChannel?.id == channel.id ||
                        connectedVoiceChannel?.id == channel.id,
                    connected: connectedVoiceChannel?.id == channel.id,
                    liveUserIds:
                        stageVoiceChannel?.id == channel.id ||
                            connectedVoiceChannel?.id == channel.id
                        ? liveVoiceUserIds
                        : const <String>{},
                    currentUser: currentUser,
                    micEnabled: micEnabled,
                    deafened: deafened,
                    cameraEnabled: cameraEnabled,
                    screenSharing: screenSharing,
                    joining:
                        joiningVoice && stageVoiceChannel?.id == channel.id,
                    onTap: () => widget.onVoiceChannelSelected(channel),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptEmptyRow extends StatelessWidget {
  const _TranscriptEmptyRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 16, 4),
      child: Text(
        '저장된 회의록 없음',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _discordSidebarMuted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

bool _matchesMeetingTranscriptSearch(
  AzoomMeetingTranscriptSummaryDto item,
  String rawQuery,
) {
  final query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) {
    return true;
  }
  final compactQuery = query.replaceAll(RegExp(r'[^0-9]'), '');
  final haystack = [
    item.channelName,
    item.titleTimestamp,
    item.startedAt?.toIso8601String() ?? '',
    item.endedAt?.toIso8601String() ?? '',
    ...?_dateSearchTerms(item.startedAt),
    ...?_dateSearchTerms(item.endedAt),
  ].join(' ').toLowerCase();
  if (haystack.contains(query)) {
    return true;
  }
  if (compactQuery.isEmpty) {
    return false;
  }
  return haystack.replaceAll(RegExp(r'[^0-9]'), '').contains(compactQuery);
}

List<String>? _dateSearchTerms(DateTime? value) {
  if (value == null) {
    return null;
  }
  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return [
    '$year-$month-$day',
    '$year.$month.$day',
    '$year/$month/$day',
    '$year$month$day',
    '${local.month}/${local.day}',
    '${local.month}.${local.day}',
    '${local.month}\uC6D4 ${local.day}\uC77C',
  ];
}

List<_MeetingTranscriptGroup> _groupMeetingTranscripts(
  List<AzoomMeetingTranscriptSummaryDto> transcripts,
) {
  final groups = <String, List<AzoomMeetingTranscriptSummaryDto>>{};
  final realtimeTranscripts = [
    for (final transcript in transcripts)
      if (transcript.kind == 'REALTIME') transcript,
  ];
  final assignedBatchIds = <String>{};

  String groupKey(AzoomMeetingTranscriptSummaryDto transcript) =>
      '${transcript.channelId}|${transcript.titleTimestamp}';

  AzoomMeetingTranscriptSummaryDto? matchingRealtime(
    AzoomMeetingTranscriptSummaryDto batch,
  ) {
    final exactMatches = realtimeTranscripts.where(
      (item) =>
          item.channelId == batch.channelId &&
          item.titleTimestamp == batch.titleTimestamp,
    );
    if (exactMatches.isNotEmpty) {
      return exactMatches.first;
    }
    final batchStartedAt = batch.startedAt;
    if (batchStartedAt == null) {
      return null;
    }
    AzoomMeetingTranscriptSummaryDto? best;
    for (final candidate in realtimeTranscripts) {
      final candidateStartedAt = candidate.startedAt;
      if (candidate.channelId != batch.channelId ||
          candidateStartedAt == null ||
          candidateStartedAt.isAfter(batchStartedAt)) {
        continue;
      }
      if (best == null ||
          candidateStartedAt.isAfter(best.startedAt ?? DateTime(1970))) {
        best = candidate;
      }
    }
    return best;
  }

  for (final realtime in realtimeTranscripts) {
    final key = groupKey(realtime);
    groups
        .putIfAbsent(key, () => <AzoomMeetingTranscriptSummaryDto>[])
        .add(realtime);
    for (final batch in transcripts) {
      if (batch.kind != 'BATCH_AUDIO' || assignedBatchIds.contains(batch.id)) {
        continue;
      }
      if (matchingRealtime(batch)?.id == realtime.id) {
        groups[key]!.add(batch);
        assignedBatchIds.add(batch.id);
      }
    }
  }
  for (final transcript in transcripts) {
    if (transcript.kind == 'BATCH_AUDIO' &&
        assignedBatchIds.contains(transcript.id)) {
      continue;
    }
    final key = groupKey(transcript);
    groups
        .putIfAbsent(key, () => <AzoomMeetingTranscriptSummaryDto>[])
        .add(transcript);
  }
  return [
    for (final entry in groups.entries)
      _MeetingTranscriptGroup(key: entry.key, transcripts: entry.value),
  ];
}

List<AzoomMeetingTranscriptSummaryDto> _matchingMeetingTranscripts(
  AzoomMeetingTranscriptDto transcript,
  List<AzoomMeetingTranscriptSummaryDto> transcripts,
) {
  for (final group in _groupMeetingTranscripts(transcripts)) {
    if (group.contains(transcript)) {
      return group.transcripts;
    }
  }
  return [
    for (final item in transcripts)
      if (item.channelId == transcript.channelId &&
          item.titleTimestamp == transcript.titleTimestamp)
        item,
  ];
}

List<AzoomMeetingTranscriptSummaryDto> _meetingTranscriptMenuItems(
  AzoomMeetingTranscriptDto current,
  List<AzoomMeetingTranscriptSummaryDto> transcripts,
) {
  AzoomMeetingTranscriptSummaryDto? pick(String kind) {
    final matches = [
      for (final item in transcripts)
        if (item.kind == kind) item,
    ];
    if (matches.isEmpty) {
      return null;
    }
    for (final item in matches) {
      if (item.id == current.id) {
        return item;
      }
    }
    for (final item in matches) {
      if (item.status == 'READY') {
        return item;
      }
    }
    for (final item in matches) {
      if (item.status == 'PROCESSING') {
        return item;
      }
    }
    return matches.first;
  }

  return [?pick('REALTIME'), ?pick('BATCH_AUDIO')];
}

class _MeetingTranscriptGroup {
  const _MeetingTranscriptGroup({required this.key, required this.transcripts});

  final String key;
  final List<AzoomMeetingTranscriptSummaryDto> transcripts;

  AzoomMeetingTranscriptSummaryDto get primary => transcripts.first;

  bool contains(AzoomMeetingTranscriptDto? transcript) {
    if (transcript == null) {
      return false;
    }
    return transcripts.any((item) => item.id == transcript.id);
  }

  AzoomMeetingTranscriptSummaryDto preferredTranscript(
    AzoomMeetingTranscriptDto? current,
  ) {
    if (current != null) {
      for (final item in transcripts) {
        if (item.id == current.id) {
          return item;
        }
      }
    }
    return transcripts.firstWhere(
      (item) => item.kind == 'REALTIME',
      orElse: () => primary,
    );
  }

  String get statusLabel {
    final hasRealtime = transcripts.any((item) => item.kind == 'REALTIME');
    final hasBatch = transcripts.any((item) => item.kind == 'BATCH_AUDIO');
    final hasProcessing = transcripts.any(
      (item) => item.status == 'PROCESSING',
    );
    final hasFailed = transcripts.any((item) => item.status == 'FAILED');
    if (hasProcessing) {
      return hasRealtime
          ? '\uC2E4\uC2DC\uAC04 \u00B7 \uD1B5\uD30C\uC77C \uBCC0\uD658\uC911'
          : '\uD1B5\uD30C\uC77C \uBCC0\uD658\uC911';
    }
    if (hasFailed) {
      return hasRealtime
          ? '\uC2E4\uC2DC\uAC04 \u00B7 \uD1B5\uD30C\uC77C \uC2E4\uD328'
          : '\uD1B5\uD30C\uC77C \uC2E4\uD328';
    }
    if (hasRealtime && hasBatch) {
      return '\uC2E4\uC2DC\uAC04 \u00B7 \uD1B5\uD30C\uC77C';
    }
    if (hasBatch) {
      return '\uD1B5\uD30C\uC77C';
    }
    return '\uC2E4\uC2DC\uAC04';
  }
}

class _TranscriptRow extends StatelessWidget {
  const _TranscriptRow({
    required this.group,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final _MeetingTranscriptGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final transcript = group.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
      child: Material(
        color: selected ? _discordSidebarSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.description,
                  color: _discordSidebarMuted,
                  size: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transcript.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? _discordSidebarText
                              : _discordSidebarMuted,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        transcript.titleTimestamp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _discordSidebarSubtle,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileBottomSheetSwitcher extends StatelessWidget {
  const _MobileBottomSheetSwitcher({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 210),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
      child: child,
    );
  }
}

class _MobileAzoomRail extends StatelessWidget {
  const _MobileAzoomRail({
    required this.currentUser,
    required this.transcriptsActive,
    required this.onTranscriptsTap,
    required this.onCalendarTap,
  });

  final PersonProfile currentUser;
  final bool transcriptsActive;
  final VoidCallback onTranscriptsTap;
  final VoidCallback onCalendarTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('azoom-mobile-rail'),
      width: _mobileAzoomRailWidth,
      color: _mobileAzoomRailColor,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 8),
            const _MobileRailLogo(),
            const _MobileRailDivider(),
            const SizedBox(height: 8),
            _MobileRailButton(
              key: const ValueKey('azoom-mobile-rail-transcripts'),
              icon: Icons.description_rounded,
              active: transcriptsActive,
              onTap: onTranscriptsTap,
            ),
            const SizedBox(height: 14),
            _MobileRailButton(
              key: const ValueKey('azoom-mobile-rail-calendar'),
              icon: Icons.calendar_today_rounded,
              active: false,
              onTap: onCalendarTap,
            ),
            const Spacer(),
            KeyedSubtree(
              key: const ValueKey('azoom-mobile-rail-profile'),
              child: ProfileAvatar(profile: currentUser, size: 42),
            ),
            SizedBox(
              height:
                  _mobileAzoomBottomNavHeight +
                  MediaQuery.paddingOf(context).bottom +
                  12,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileRailLogo extends StatelessWidget {
  const _MobileRailLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _mobileAzoomRailWidth,
      height: 50,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 9,
            child: Container(
              width: 4,
              height: 30,
              decoration: const BoxDecoration(
                color: _discordSidebarText,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF0D62BF),
                borderRadius: BorderRadius.circular(15),
              ),
              alignment: Alignment.center,
              child: Image.asset(
                'assets/images/ava_app_icon.png',
                width: 29,
                height: 29,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileRailDivider extends StatelessWidget {
  const _MobileRailDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 1,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      color: _discordSidebarBorder,
    );
  }
}

class _MobileRailButton extends StatelessWidget {
  const _MobileRailButton({
    required this.icon,
    required this.active,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _mobileAzoomRailWidth,
      height: 46,
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            left: 0,
            top: active ? 9 : 20,
            child: Container(
              width: 4,
              height: active ? 28 : 6,
              decoration: const BoxDecoration(
                color: _discordSidebarText,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
              ),
            ),
          ),
          Center(
            child: IconButton(
              onPressed: onTap,
              style: IconButton.styleFrom(
                backgroundColor: active
                    ? _discordSidebarSelected
                    : _discordSidebarPanel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(active ? 16 : 23),
                ),
                fixedSize: const Size.square(46),
              ),
              icon: Icon(
                icon,
                color: active ? _discordSidebarText : _discordSidebarMuted,
                size: 23,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileAzoomBottomNav extends StatelessWidget {
  const _MobileAzoomBottomNav({
    required this.activeTab,
    required this.onTabSelected,
  });

  final MessengerTab activeTab;
  final ValueChanged<MessengerTab>? onTabSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      key: const ValueKey('azoom-mobile-bottom-nav'),
      height: _mobileAzoomBottomNavHeight + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: _discordSidebarPanel,
        border: Border(top: BorderSide(color: _discordSidebarBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _MobileAzoomBottomNavItem(
            key: const ValueKey('azoom-mobile-bottom-nav-friends'),
            icon: Icons.person,
            label: '친구',
            active: activeTab == MessengerTab.friends,
            onTap: () => onTabSelected?.call(MessengerTab.friends),
          ),
          _MobileAzoomBottomNavItem(
            key: const ValueKey('azoom-mobile-bottom-nav-chats'),
            icon: Icons.chat_bubble,
            label: '채팅',
            active: activeTab == MessengerTab.chats,
            onTap: () => onTabSelected?.call(MessengerTab.chats),
          ),
          _MobileAzoomBottomNavItem(
            key: const ValueKey('azoom-mobile-bottom-nav-notifications'),
            icon: Icons.notifications,
            label: '알림',
            active: activeTab == MessengerTab.notifications,
            onTap: () => onTabSelected?.call(MessengerTab.notifications),
          ),
          _MobileAzoomBottomNavItem(
            key: const ValueKey('azoom-mobile-bottom-nav-azoom'),
            icon: Icons.videocam,
            label: 'AZOOM',
            active: activeTab == MessengerTab.azoom,
            onTap: () => onTabSelected?.call(MessengerTab.azoom),
          ),
          _MobileAzoomBottomNavItem(
            key: const ValueKey('azoom-mobile-bottom-nav-ava-stock'),
            icon: Icons.inventory_2_outlined,
            label: '재고',
            active: activeTab == MessengerTab.avaStock,
            onTap: () => onTabSelected?.call(MessengerTab.avaStock),
          ),
          _MobileAzoomBottomNavItem(
            key: const ValueKey('azoom-mobile-bottom-nav-ai'),
            icon: Icons.auto_awesome,
            label: 'AI',
            active: activeTab == MessengerTab.avaAi,
            onTap: () => onTabSelected?.call(MessengerTab.avaAi),
          ),
          _MobileAzoomBottomNavItem(
            key: const ValueKey('azoom-mobile-bottom-nav-more'),
            icon: Icons.more_horiz,
            label: '\uB354\uBCF4\uAE30',
            active: activeTab == MessengerTab.more,
            onTap: () => onTabSelected?.call(MessengerTab.more),
          ),
        ],
      ),
    );
  }
}

class _MobileAzoomBottomNavItem extends StatelessWidget {
  const _MobileAzoomBottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? _discordSidebarText : _discordSidebarMuted;
    return SizedBox(
      width: 54,
      height: 48,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 21),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileAzoomChannelList extends StatelessWidget {
  const _MobileAzoomChannelList({
    required this.voiceChannels,
    required this.meetingTranscripts,
    required this.searchQuery,
    required this.meetingTranscriptsExpanded,
    required this.selectedMeetingTranscript,
    required this.stageVoiceChannel,
    required this.connectedVoiceChannel,
    required this.liveVoiceUserIds,
    required this.currentUser,
    required this.joiningVoice,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.screenSharing,
    required this.onVoiceChannelSelected,
    required this.onMeetingTranscriptsToggle,
    required this.onMeetingTranscriptSelected,
    required this.onSearchChanged,
    required this.onInvitePressed,
  });

  final List<AzoomVoiceChannelDto> voiceChannels;
  final List<AzoomMeetingTranscriptSummaryDto> meetingTranscripts;
  final String searchQuery;
  final bool meetingTranscriptsExpanded;
  final AzoomMeetingTranscriptDto? selectedMeetingTranscript;
  final AzoomVoiceChannelDto? stageVoiceChannel;
  final AzoomVoiceChannelDto? connectedVoiceChannel;
  final Set<String> liveVoiceUserIds;
  final PersonProfile currentUser;
  final bool joiningVoice;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool screenSharing;
  final ValueChanged<AzoomVoiceChannelDto> onVoiceChannelSelected;
  final VoidCallback onMeetingTranscriptsToggle;
  final ValueChanged<AzoomMeetingTranscriptSummaryDto>
  onMeetingTranscriptSelected;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onInvitePressed;

  @override
  Widget build(BuildContext context) {
    AzoomVoiceChannelDto rowVoiceChannel(AzoomVoiceChannelDto channel) {
      if (connectedVoiceChannel?.id == channel.id) {
        return connectedVoiceChannel!;
      }
      if (stageVoiceChannel?.id == channel.id) {
        return stageVoiceChannel!;
      }
      return channel;
    }

    return Container(
      key: const ValueKey('azoom-mobile-channel-list'),
      color: _discordSidebarBackground,
      child: SafeArea(
        left: false,
        top: false,
        child: Column(
          children: [
            _MobileAzoomHeader(
              searchQuery: searchQuery,
              onSearchChanged: onSearchChanged,
              onInvitePressed: onInvitePressed,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  8,
                  8,
                  8,
                  connectedVoiceChannel == null
                      ? _mobileAzoomBottomNavHeight + 24
                      : 168,
                ),
                children: [
                  _MobileMeetingTranscriptSection(
                    meetingTranscripts: meetingTranscripts,
                    expanded: meetingTranscriptsExpanded,
                    selectedMeetingTranscript: selectedMeetingTranscript,
                    onToggle: onMeetingTranscriptsToggle,
                    onMeetingTranscriptSelected: onMeetingTranscriptSelected,
                  ),
                  const SizedBox(height: 14),
                  const _SectionHeader(title: '\uC74C\uC131 \uCC44\uB110'),
                  for (final channel in voiceChannels)
                    _VoiceRow(
                      key: ValueKey('azoom-mobile-voice-${channel.id}'),
                      channel: rowVoiceChannel(channel),
                      selected:
                          stageVoiceChannel?.id == channel.id ||
                          connectedVoiceChannel?.id == channel.id,
                      connected: connectedVoiceChannel?.id == channel.id,
                      liveUserIds:
                          stageVoiceChannel?.id == channel.id ||
                              connectedVoiceChannel?.id == channel.id
                          ? liveVoiceUserIds
                          : const <String>{},
                      currentUser: currentUser,
                      micEnabled: micEnabled,
                      deafened: deafened,
                      cameraEnabled: cameraEnabled,
                      screenSharing: screenSharing,
                      joining:
                          joiningVoice && stageVoiceChannel?.id == channel.id,
                      onTap: () => onVoiceChannelSelected(channel),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMeetingTranscriptSection extends StatelessWidget {
  const _MobileMeetingTranscriptSection({
    required this.meetingTranscripts,
    required this.expanded,
    required this.selectedMeetingTranscript,
    required this.onToggle,
    required this.onMeetingTranscriptSelected,
  });

  final List<AzoomMeetingTranscriptSummaryDto> meetingTranscripts;
  final bool expanded;
  final AzoomMeetingTranscriptDto? selectedMeetingTranscript;
  final VoidCallback onToggle;
  final ValueChanged<AzoomMeetingTranscriptSummaryDto>
  onMeetingTranscriptSelected;

  @override
  Widget build(BuildContext context) {
    final groups = _groupMeetingTranscripts(meetingTranscripts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          key: const ValueKey('azoom-mobile-transcripts-header'),
          title: '\uD68C\uC758\uB85D',
          expanded: expanded,
          showAdd: false,
          onTap: onToggle,
        ),
        if (expanded) ...[
          if (groups.isEmpty)
            const _TranscriptEmptyRow()
          else
            for (final group in groups.take(12))
              _TranscriptRow(
                key: ValueKey('azoom-mobile-transcript-group-${group.key}'),
                group: group,
                selected: group.contains(selectedMeetingTranscript),
                onTap: () => onMeetingTranscriptSelected(
                  group.preferredTranscript(selectedMeetingTranscript),
                ),
              ),
        ],
      ],
    );
  }
}

class _MobileAzoomHeader extends StatelessWidget {
  const _MobileAzoomHeader({
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onInvitePressed,
  });

  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onInvitePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _discordSidebarBorder)),
      ),
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  'AZOOM >',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _discordSidebarText,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AzoomTranscriptSearchField(
                  query: searchQuery,
                  onChanged: onSearchChanged,
                ),
              ),
              const SizedBox(width: 10),
              _MobileHeaderActionButton(
                key: ValueKey('azoom-mobile-header-invite'),
                icon: Icons.person_add_alt_1,
                onPressed: onInvitePressed,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileHeaderActionButton extends StatelessWidget {
  const _MobileHeaderActionButton({
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: _discordSidebarSelected,
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, color: _discordSidebarMuted, size: 20),
      ),
    );
  }
}

class _MobileAzoomVoiceMiniOverlay extends StatelessWidget {
  const _MobileAzoomVoiceMiniOverlay({
    required this.channel,
    required this.participant,
    required this.expanded,
    required this.micEnabled,
    required this.deafened,
    required this.onTap,
    required this.onDragUpdate,
    required this.onOpen,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onLeave,
  });

  final AzoomVoiceChannelDto channel;
  final AzoomVoiceParticipantDto participant;
  final bool expanded;
  final bool micEnabled;
  final bool deafened;
  final VoidCallback onTap;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onOpen;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final width = expanded ? 178.0 : 112.0;
    final height = expanded ? 174.0 : 112.0;
    final muted = !micEnabled || deafened;
    return GestureDetector(
      onTap: onTap,
      onPanUpdate: (details) => onDragUpdate(details.delta),
      child: AnimatedContainer(
        key: const ValueKey('azoom-mobile-floating-voice-card'),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
        padding: EdgeInsets.all(expanded ? 10 : 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF5FF),
          borderRadius: BorderRadius.circular(expanded ? 22 : 20),
          border: Border.all(color: _stageBorder),
          boxShadow: [
            BoxShadow(
              color: _avaAccentDeep.withValues(alpha: 0.14),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: expanded
            ? Column(
                children: [
                  SizedBox(
                    height: 32,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _stageText,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _MiniVoiceIconButton(
                          icon: Icons.open_in_full,
                          onTap: onOpen,
                          tooltip: '전체화면',
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _miniAvatar()),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MiniVoiceIconButton(
                        icon: muted ? Icons.mic_off : Icons.mic,
                        selected: muted,
                        tooltip: muted
                            ? '\uB9C8\uC774\uD06C \uCF1C\uAE30'
                            : '\uC74C\uC18C\uAC70',
                        onTap: onToggleMic,
                      ),
                      _MiniVoiceIconButton(
                        icon: deafened ? Icons.headset_off : Icons.headphones,
                        selected: deafened,
                        tooltip: deafened
                            ? '\uC18C\uB9AC \uCF1C\uAE30'
                            : '\uD5E4\uB4DC\uC14B \uC74C\uC18C\uAC70',
                        onTap: onToggleDeafen,
                      ),
                      _MiniVoiceIconButton(
                        icon: Icons.call_end,
                        danger: true,
                        onTap: onLeave,
                        tooltip: '연결 끊기',
                      ),
                    ],
                  ),
                ],
              )
            : Center(child: _miniAvatar()),
      ),
    );
  }

  Widget _miniAvatar() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        _AzoomAvatar(
          label: _avatarLabel(participant.displayName),
          color: _colorFromHex(participant.avatarColor),
          imageUrl: participant.avatarImageUrl,
          size: expanded ? 68 : 74,
        ),
        if (participant.screenSharing || participant.cameraEnabled)
          Positioned(
            right: expanded ? 20 : 6,
            bottom: expanded ? 4 : 6,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _discordSidebarGreen,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFEAF5FF), width: 2),
              ),
              child: Icon(
                participant.screenSharing ? Icons.screen_share : Icons.videocam,
                color: Colors.white,
                size: 13,
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniVoiceIconButton extends StatelessWidget {
  const _MiniVoiceIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.selected = false,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? _discordDanger
        : selected
        ? _discordSidebarSelected
        : Colors.white.withValues(alpha: 0.54);
    final foreground = danger
        ? Colors.white
        : selected
        ? _discordSidebarText
        : _discordSidebarText;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: foreground, size: 19),
        ),
      ),
    );
  }
}

class _MobileVoiceJoinSheet extends StatelessWidget {
  const _MobileVoiceJoinSheet({
    required this.channel,
    required this.joining,
    required this.micEnabled,
    required this.deafened,
    required this.onCollapse,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onJoin,
    super.key,
  });

  final AzoomVoiceChannelDto channel;
  final bool joining;
  final bool micEnabled;
  final bool deafened;
  final VoidCallback onCollapse;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('azoom-mobile-voice-join-sheet'),
        height: _mobileAzoomBottomSheetHeight,
        decoration: BoxDecoration(
          color: _stagePanel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: const Border(top: BorderSide(color: _stageBorder)),
          boxShadow: [
            BoxShadow(
              color: _avaAccentDeep.withValues(alpha: 0.14),
              blurRadius: 22,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
                child: Row(
                  children: [
                    _MobileSmallCircleButton(
                      icon: Icons.keyboard_arrow_down,
                      onTap: onCollapse,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _stageBackground,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            channel.name,
                            style: const TextStyle(
                              color: _stageText,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right,
                            color: _stageText,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _MobileSmallCircleButton(
                      icon: Icons.group_add,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                '\uC544\uC9C1 \uC544\uBB34\uB3C4 \uC548 \uC654\uC5B4\uC694!',
                style: TextStyle(
                  color: _stageMutedText,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                '\uB300\uD654\uD560 \uC900\uBE44\uAC00 \uB418\uBA74 \uBC14\uB85C \uC2DC\uC791\uD558\uC138\uC694.',
                style: TextStyle(
                  color: _stageMutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                height: 66,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _stageBackground,
                  borderRadius: BorderRadius.circular(33),
                ),
                child: Row(
                  children: [
                    _MobileLargeCircleButton(
                      icon: micEnabled ? Icons.mic : Icons.mic_off,
                      selected: !micEnabled,
                      onTap: onToggleMic,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          key: const ValueKey('azoom-mobile-voice-join-button'),
                          onPressed: joining ? null : onJoin,
                          style: FilledButton.styleFrom(
                            backgroundColor: _discordSidebarGreen,
                            disabledBackgroundColor: _discordSidebarSelected,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: joining
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '\uC74C\uC131 \uCC44\uB110 \uCC38\uAC00\uD558\uAE30',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _MobileLargeCircleButton(
                      icon: deafened ? Icons.headset_off : Icons.headphones,
                      selected: deafened,
                      onTap: onToggleDeafen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileAzoomVoiceRoom extends StatelessWidget {
  const _MobileAzoomVoiceRoom({
    required this.channel,
    required this.currentUser,
    required this.liveKitRoom,
    required this.liveKitConnecting,
    required this.liveKitConnected,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.cameraUnavailableReason,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.mediaErrorText,
    required this.onCollapse,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onToggleCamera,
    required this.onCameraUnavailable,
    required this.onSelectAudioInput,
    required this.onSelectAudioOutput,
    required this.onSelectCameraInput,
    required this.outputVolume,
    required this.onOutputVolumeChanged,
    required this.mobileSpeakerOn,
    required this.onMobileSpeakerChanged,
    required this.noiseSuppressionMode,
    required this.onNoiseSuppressionModeChanged,
    required this.onToggleScreenShare,
    required this.onShowParticipants,
    required this.onTriggerFirework,
    required this.onToggleNotiva,
    required this.onLeave,
    super.key,
  });

  final AzoomVoiceChannelDto channel;
  final PersonProfile currentUser;
  final lk.Room? liveKitRoom;
  final bool liveKitConnecting;
  final bool liveKitConnected;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool cameraBusy;
  final String? cameraUnavailableReason;
  final bool screenSharing;
  final bool screenShareBusy;
  final String? mediaErrorText;
  final VoidCallback onCollapse;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleCamera;
  final VoidCallback onCameraUnavailable;
  final ValueChanged<lk.MediaDevice> onSelectAudioInput;
  final ValueChanged<lk.MediaDevice> onSelectAudioOutput;
  final ValueChanged<lk.MediaDevice> onSelectCameraInput;
  final double outputVolume;
  final ValueChanged<double> onOutputVolumeChanged;
  final bool mobileSpeakerOn;
  final ValueChanged<bool> onMobileSpeakerChanged;
  final _AzoomNoiseSuppressionMode noiseSuppressionMode;
  final ValueChanged<_AzoomNoiseSuppressionMode> onNoiseSuppressionModeChanged;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onShowParticipants;
  final VoidCallback onTriggerFirework;
  final VoidCallback onToggleNotiva;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final liveParticipants = _liveParticipants(
      liveKitRoom,
      channel.participants,
      currentUser,
    );
    final presences = channel.participants.isEmpty
        ? [_participantFromProfile(currentUser)]
        : channel.participants;
    final count = liveParticipants.isNotEmpty
        ? liveParticipants.length
        : presences.length;
    return Material(
      color: _stageBackground,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  _MobileVoiceRoomHeaderFixed(
                    channelName: channel.name,
                    onCollapse: onCollapse,
                    onShowParticipants: onShowParticipants,
                    onToggleNotiva: onToggleNotiva,
                  ),
                  Expanded(
                    child: _MobileVoiceParticipantStage(
                      liveParticipants: liveParticipants,
                      presenceParticipants: presences,
                      liveKitConnected: liveKitConnected,
                      liveKitConnecting: liveKitConnecting,
                      mediaErrorText: mediaErrorText,
                    ),
                  ),
                  _MobileVoiceInviteRow(count: count),
                  const SizedBox(height: 90),
                ],
              ),
            ),
            Positioned.fill(
              child: _MobileVoiceControlDock(
                micEnabled: micEnabled,
                deafened: deafened,
                cameraEnabled: cameraEnabled,
                cameraBusy: cameraBusy,
                cameraUnavailable: cameraUnavailableReason != null,
                screenSharing: screenSharing,
                screenShareBusy: screenShareBusy,
                liveKitRoom: liveKitRoom,
                mediaControlsEnabled: liveKitConnected,
                onToggleMic: onToggleMic,
                onToggleDeafen: onToggleDeafen,
                onToggleCamera:
                    cameraUnavailableReason != null && !cameraEnabled
                    ? onCameraUnavailable
                    : onToggleCamera,
                onCameraUnavailable: onCameraUnavailable,
                onSelectAudioInput: onSelectAudioInput,
                onSelectAudioOutput: onSelectAudioOutput,
                onSelectCameraInput: onSelectCameraInput,
                outputVolume: outputVolume,
                onOutputVolumeChanged: onOutputVolumeChanged,
                mobileSpeakerOn: mobileSpeakerOn,
                onMobileSpeakerChanged: onMobileSpeakerChanged,
                noiseSuppressionMode: noiseSuppressionMode,
                onNoiseSuppressionModeChanged: onNoiseSuppressionModeChanged,
                onToggleScreenShare: onToggleScreenShare,
                onShowParticipants: onShowParticipants,
                onTriggerFirework: onTriggerFirework,
                onToggleNotiva: onToggleNotiva,
                onLeave: onLeave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileVoiceRoomHeaderFixed extends StatelessWidget {
  const _MobileVoiceRoomHeaderFixed({
    required this.channelName,
    required this.onCollapse,
    required this.onShowParticipants,
    required this.onToggleNotiva,
  });

  final String channelName;
  final VoidCallback onCollapse;
  final VoidCallback onShowParticipants;
  final VoidCallback onToggleNotiva;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('azoom-mobile-voice-collapse'),
            onPressed: onCollapse,
            icon: const Icon(
              Icons.keyboard_arrow_down,
              color: _voiceRoomMutedText,
              size: 26,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _voiceRoomText,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  color: _voiceRoomMutedText,
                  size: 18,
                ),
              ],
            ),
          ),
          _MobileHeaderIcon(
            key: const ValueKey('azoom-mobile-notiva-header-button'),
            tooltip: 'Notiva AI',
            icon: Icons.chat_bubble,
            onTap: onToggleNotiva,
          ),
          const SizedBox(width: 8),
          _MobileHeaderIcon(
            tooltip: '\uCC38\uC5EC\uC790',
            icon: Icons.people,
            onTap: onShowParticipants,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _MobileHeaderIcon extends StatelessWidget {
  const _MobileHeaderIcon({
    required this.tooltip,
    required this.icon,
    this.onTap,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 36,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onTap,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, color: _voiceRoomMutedText, size: 23),
      ),
    );
  }
}

class _MobileVoiceParticipantStage extends StatelessWidget {
  const _MobileVoiceParticipantStage({
    required this.liveParticipants,
    required this.presenceParticipants,
    required this.liveKitConnected,
    required this.liveKitConnecting,
    required this.mediaErrorText,
  });

  final List<_LiveParticipantView> liveParticipants;
  final List<AzoomVoiceParticipantDto> presenceParticipants;
  final bool liveKitConnected;
  final bool liveKitConnecting;
  final String? mediaErrorText;

  @override
  Widget build(BuildContext context) {
    final participants = liveParticipants.isNotEmpty
        ? liveParticipants
        : presenceParticipants;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 66).clamp(240.0, 360.0);
        final height = (width * 1.08).clamp(260.0, 360.0);
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: participants.length <= 1
                ? _MobileSingleParticipantTile(
                    participant: participants.first,
                    connected: liveKitConnected,
                    connecting: liveKitConnecting,
                    mediaErrorText: mediaErrorText,
                  )
                : GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                    itemCount: participants.length.clamp(0, 4),
                    itemBuilder: (context, index) {
                      return _MobileSingleParticipantTile(
                        participant: participants[index],
                        connected: liveKitConnected,
                        connecting: liveKitConnecting,
                        mediaErrorText: mediaErrorText,
                        compact: true,
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _MobileSingleParticipantTile extends StatelessWidget {
  const _MobileSingleParticipantTile({
    required this.participant,
    required this.connected,
    required this.connecting,
    required this.mediaErrorText,
    this.compact = false,
  });

  final Object participant;
  final bool connected;
  final bool connecting;
  final String? mediaErrorText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final view = participant is _LiveParticipantView
        ? participant as _LiveParticipantView
        : null;
    final presence = participant is AzoomVoiceParticipantDto
        ? participant as AzoomVoiceParticipantDto
        : null;
    final name = view != null
        ? _liveParticipantDisplayName(view)
        : presence?.displayName ?? '';
    final trackView = view == null ? null : _videoTrackFor(view.participant);
    final speaking = view?.participant.isSpeaking ?? false;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _voiceRoomTile,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: speaking ? _discordSpeaking : _voiceRoomBorder,
          width: speaking ? 4 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (trackView != null)
            lk.VideoTrackRenderer(
              trackView.track,
              fit: trackView.isScreenShare
                  ? lk.VideoViewFit.contain
                  : lk.VideoViewFit.cover,
            )
          else
            Center(
              child: _AzoomAvatar(
                label: _avatarLabel(name),
                color: view != null
                    ? _liveParticipantColor(view)
                    : _colorFromHex(presence?.avatarColor),
                imageUrl: view != null
                    ? _liveParticipantImageUrl(view)
                    : presence?.avatarImageUrl ?? '',
                size: compact ? 54 : 66,
              ),
            ),
          if (!connected || connecting || mediaErrorText != null)
            Positioned(
              top: 12,
              right: 12,
              child: SizedBox.square(
                dimension: 18,
                child: connecting
                    ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _stageBackground,
                      )
                    : Icon(
                        mediaErrorText != null
                            ? Icons.warning_rounded
                            : Icons.cloud_sync,
                        color: _stageBackground.withValues(alpha: 0.72),
                        size: 18,
                      ),
              ),
            ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileVoiceInviteRow extends StatelessWidget {
  const _MobileVoiceInviteRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 20, 14),
      child: Row(
        children: [
          const Icon(Icons.group_add, color: _voiceRoomMutedText, size: 25),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '$count\uBA85\uC774 \uCC38\uC5EC \uC911\uC785\uB2C8\uB2E4',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _voiceRoomText,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: _voiceRoomMutedText, size: 24),
        ],
      ),
    );
  }
}

class _MobileVoiceControlDock extends StatefulWidget {
  const _MobileVoiceControlDock({
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.cameraUnavailable,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.liveKitRoom,
    required this.mediaControlsEnabled,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onToggleCamera,
    required this.onCameraUnavailable,
    required this.onSelectAudioInput,
    required this.onSelectAudioOutput,
    required this.onSelectCameraInput,
    required this.outputVolume,
    required this.onOutputVolumeChanged,
    required this.mobileSpeakerOn,
    required this.onMobileSpeakerChanged,
    required this.noiseSuppressionMode,
    required this.onNoiseSuppressionModeChanged,
    required this.onToggleScreenShare,
    required this.onShowParticipants,
    required this.onTriggerFirework,
    required this.onToggleNotiva,
    required this.onLeave,
  });

  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool cameraBusy;
  final bool cameraUnavailable;
  final bool screenSharing;
  final bool screenShareBusy;
  final lk.Room? liveKitRoom;
  final bool mediaControlsEnabled;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleCamera;
  final VoidCallback onCameraUnavailable;
  final ValueChanged<lk.MediaDevice> onSelectAudioInput;
  final ValueChanged<lk.MediaDevice> onSelectAudioOutput;
  final ValueChanged<lk.MediaDevice> onSelectCameraInput;
  final double outputVolume;
  final ValueChanged<double> onOutputVolumeChanged;
  final bool mobileSpeakerOn;
  final ValueChanged<bool> onMobileSpeakerChanged;
  final _AzoomNoiseSuppressionMode noiseSuppressionMode;
  final ValueChanged<_AzoomNoiseSuppressionMode> onNoiseSuppressionModeChanged;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onShowParticipants;
  final VoidCallback onTriggerFirework;
  final VoidCallback onToggleNotiva;
  final VoidCallback onLeave;

  @override
  State<_MobileVoiceControlDock> createState() =>
      _MobileVoiceControlDockState();
}

class _MobileVoiceControlDockState extends State<_MobileVoiceControlDock> {
  bool _expanded = false;
  double _dragDelta = 0;
  double _pointerDragDelta = 0;
  bool _pointerDragHandled = false;

  void _setExpanded(bool expanded) {
    if (_expanded == expanded) {
      return;
    }
    setState(() {
      _expanded = expanded;
    });
  }

  void _handleDragStart(DragStartDetails details) {
    _dragDelta = 0;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _dragDelta += details.delta.dy;
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragDelta < -18 || velocity < -420) {
      _setExpanded(true);
      return;
    }
    if (_dragDelta > 18 || velocity > 420) {
      _setExpanded(false);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDragDelta = 0;
    _pointerDragHandled = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerDragHandled) {
      return;
    }
    _pointerDragDelta += event.delta.dy;
    if (_expanded && _pointerDragDelta > 72) {
      _pointerDragHandled = true;
      _setExpanded(false);
    } else if (!_expanded && _pointerDragDelta < -72) {
      _pointerDragHandled = true;
      _setExpanded(true);
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    _pointerDragDelta = 0;
    _pointerDragHandled = false;
  }

  @override
  Widget build(BuildContext context) {
    final cameraUnavailable = widget.cameraUnavailable && !widget.cameraEnabled;
    return LayoutBuilder(
      builder: (context, constraints) {
        final expandedHeight = constraints.maxHeight.clamp(440.0, 900.0);
        return Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            key: const ValueKey('azoom-mobile-voice-dock-drag-target'),
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _handleDragStart,
            onVerticalDragUpdate: _handleDragUpdate,
            onVerticalDragEnd: _handleDragEnd,
            child: Listener(
              onPointerDown: _handlePointerDown,
              onPointerMove: _handlePointerMove,
              onPointerUp: _handlePointerEnd,
              onPointerCancel: _handlePointerEnd,
              child: AnimatedContainer(
                key: const ValueKey('azoom-mobile-voice-control-dock'),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: _expanded ? expandedHeight : 70,
                margin: _expanded
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(12, 0, 12, 10),
                decoration: BoxDecoration(
                  color: _expanded ? _stagePanel : _stageControl,
                  border: Border.all(color: _stageBorder),
                  borderRadius: _expanded
                      ? const BorderRadius.vertical(top: Radius.circular(22))
                      : BorderRadius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: _expanded
                    ? _buildExpandedDock(cameraUnavailable)
                    : _buildCollapsedDock(cameraUnavailable),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapsedDock(bool cameraUnavailable) {
    return Stack(
      children: [
        _MobileVoiceDockHandle(
          expanded: false,
          onTap: () => _setExpanded(true),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MobileVoiceDockCircleButton(
                key: const ValueKey('azoom-mobile-camera-device-control'),
                tooltip: cameraUnavailable
                    ? '카메라 사용 불가'
                    : widget.cameraEnabled
                    ? '카메라 끄기'
                    : '카메라 켜기',
                icon: widget.cameraEnabled
                    ? Icons.videocam
                    : Icons.videocam_off,
                selected: widget.cameraEnabled,
                busy: widget.cameraBusy,
                enabled: widget.mediaControlsEnabled && !widget.cameraBusy,
                onTap: cameraUnavailable
                    ? widget.onCameraUnavailable
                    : widget.onToggleCamera,
              ),
              _MobileVoiceDockCircleButton(
                key: const ValueKey('azoom-mobile-mic-device-control'),
                tooltip: widget.micEnabled ? '마이크 끄기' : '마이크 켜기',
                icon: widget.micEnabled ? Icons.mic : Icons.mic_off,
                selected: !widget.micEnabled,
                enabled: widget.mediaControlsEnabled,
                onTap: widget.onToggleMic,
              ),
              _MobileVoiceDockCircleButton(
                tooltip: 'Notiva AI',
                icon: Icons.chat_bubble,
                onTap: widget.onToggleNotiva,
              ),
              _MobileVoiceDockCircleButton(
                key: const ValueKey('azoom-mobile-firework-button'),
                tooltip: '사운드보드',
                icon: Icons.celebration,
                onTap: widget.onTriggerFirework,
              ),
              _MobileVoiceDockCircleButton(
                tooltip: '연결 끊기',
                icon: Icons.call_end,
                danger: true,
                onTap: widget.onLeave,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedDock(bool cameraUnavailable) {
    return ListView(
      key: const ValueKey('azoom-mobile-voice-expanded-menu'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      children: [
        _MobileVoiceDockHandle(
          expanded: true,
          onTap: () => _setExpanded(false),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MobileVoiceDockCircleButton(
                tooltip: cameraUnavailable
                    ? '카메라 사용 불가'
                    : widget.cameraEnabled
                    ? '카메라 끄기'
                    : '카메라 켜기',
                icon: widget.cameraEnabled
                    ? Icons.videocam
                    : Icons.videocam_off,
                selected: widget.cameraEnabled,
                busy: widget.cameraBusy,
                enabled: widget.mediaControlsEnabled && !widget.cameraBusy,
                onTap: cameraUnavailable
                    ? widget.onCameraUnavailable
                    : widget.onToggleCamera,
              ),
              _MobileVoiceDockCircleButton(
                tooltip: widget.micEnabled ? '마이크 끄기' : '마이크 켜기',
                icon: widget.micEnabled ? Icons.mic : Icons.mic_off,
                selected: !widget.micEnabled,
                enabled: widget.mediaControlsEnabled,
                onTap: widget.onToggleMic,
              ),
              _MobileVoiceDockCircleButton(
                tooltip: 'Notiva AI',
                icon: Icons.chat_bubble,
                onTap: widget.onToggleNotiva,
              ),
              _MobileVoiceDockCircleButton(
                key: const ValueKey('azoom-mobile-firework-expanded-button'),
                tooltip: '사운드보드',
                icon: Icons.celebration,
                onTap: widget.onTriggerFirework,
              ),
              _MobileVoiceDockCircleButton(
                tooltip: '연결 끊기',
                icon: Icons.call_end,
                danger: true,
                onTap: widget.onLeave,
              ),
            ],
          ),
        ),
        _MobileVoiceSheetCard(
          children: [
            _MobileVoiceSheetRow(icon: Icons.apps, title: '활동', onTap: () {}),
            const _MobileVoiceSheetDivider(),
            _MobileVoiceSheetRow(
              icon: Icons.screen_share,
              title: '화면 공유하기',
              onTap: widget.mediaControlsEnabled && !widget.screenShareBusy
                  ? widget.onToggleScreenShare
                  : null,
              trailing: widget.screenShareBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _stageText,
                      ),
                    )
                  : null,
            ),
          ],
        ),
        const _MobileVoiceSheetSectionLabel('음성 설정'),
        _MobileVoiceSheetCard(
          children: [
            _MobileVoiceSheetRow(
              icon: Icons.headset_off,
              title: '헤드셋 음소거',
              subtitle: '모든 소리 끄기',
              onTap: widget.onToggleDeafen,
              trailing: _MobileVoiceSheetToggle(selected: widget.deafened),
            ),
            const _MobileVoiceSheetDivider(),
            _MobileVoiceSheetRow(
              icon: Icons.volume_up,
              title: '오디오 출력 변경',
              onTap: () {},
              trailing: const Icon(
                Icons.chevron_right,
                color: _stageText,
                size: 22,
              ),
            ),
            const _MobileVoiceSheetDivider(),
            _MobileVoiceSheetRow(
              icon: Icons.videocam,
              title: '동영상만 보이기',
              subtitle: '영상 없는 참여자를 숨깁니다',
              onTap: () {},
              trailing: const _MobileVoiceSheetToggle(selected: false),
            ),
            const _MobileVoiceSheetDivider(),
            _MobileVoiceSheetRow(
              icon: Icons.photo_camera,
              title: '내 소유 카메라 표시하기',
              onTap: widget.mediaControlsEnabled ? widget.onToggleCamera : null,
              trailing: _MobileVoiceSheetToggle(selected: widget.cameraEnabled),
            ),
            const _MobileVoiceSheetDivider(),
            _MobileVoiceSheetRow(
              icon: Icons.group_add,
              title: '친구 초대하기',
              onTap: () {},
              trailing: const Icon(
                Icons.chevron_right,
                color: _stageText,
                size: 22,
              ),
            ),
          ],
        ),
        const _MobileVoiceSheetSectionLabel('잡음 제거'),
        const _MobileVoiceSheetCard(
          children: [
            _MobileVoiceRadioRow(title: 'Krisp', selected: true),
            _MobileVoiceSheetDivider(),
            _MobileVoiceRadioRow(title: '기본', selected: false),
            _MobileVoiceSheetDivider(),
            _MobileVoiceRadioRow(title: '없음', selected: false),
          ],
        ),
        const SizedBox(height: 12),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '제공 ABBA-S',
                style: TextStyle(
                  color: _stageMutedText,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '자세히 알아보기',
              style: TextStyle(
                color: Color(0xFF7D8AFF),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MobileVoiceDockHandle extends StatelessWidget {
  const _MobileVoiceDockHandle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('azoom-mobile-voice-dock-handle'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        height: expanded ? 19 : 15,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: expanded ? 9 : 5),
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: _stageMutedText.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileVoiceDockCircleButton extends StatelessWidget {
  const _MobileVoiceDockCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.danger = false,
    this.enabled = true,
    this.busy = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool danger;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? _discordDanger
        : selected
        ? _discordSidebarSelected
        : _stageControl;
    final foreground = enabled
        ? _stageText
        : _stageMutedText.withValues(alpha: 0.52);
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 48,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: enabled ? onTap : null,
          style: IconButton.styleFrom(
            backgroundColor: background,
            disabledBackgroundColor: _stageBorder.withValues(alpha: 0.55),
            shape: const CircleBorder(),
          ),
          icon: busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Icon(icon, color: foreground, size: 23),
        ),
      ),
    );
  }
}

class _MobileVoiceSheetSectionLabel extends StatelessWidget {
  const _MobileVoiceSheetSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Text(
        label,
        style: const TextStyle(
          color: _stageMutedText,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MobileVoiceSheetCard extends StatelessWidget {
  const _MobileVoiceSheetCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _stageMenu,
        border: Border.all(color: _stageMenuBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _MobileVoiceSheetDivider extends StatelessWidget {
  const _MobileVoiceSheetDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      indent: 44,
      endIndent: 12,
      color: _stageMenuBorder,
    );
  }
}

class _MobileVoiceSheetRow extends StatelessWidget {
  const _MobileVoiceSheetRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: _stageText, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _stageText,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _stageMutedText,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );
  }
}

class _MobileVoiceSheetToggle extends StatelessWidget {
  const _MobileVoiceSheetToggle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: 52,
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: selected ? _avaAccent : _stageControl,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _stageBorder),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignment: selected ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFF2F3F5),
            shape: BoxShape.circle,
          ),
          child: Icon(
            selected ? Icons.check : Icons.close,
            color: selected ? _avaAccent : _stageControl,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _MobileVoiceRadioRow extends StatelessWidget {
  const _MobileVoiceRadioRow({
    required this.title,
    required this.selected,
    this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _stageText,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _avaAccent : _stageText,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: _avaAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileAudioOutputSheet extends StatelessWidget {
  const _MobileAudioOutputSheet({
    required this.speakerOn,
    required this.onChanged,
  });

  final bool speakerOn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _stagePanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: _stageMutedText.withValues(alpha: 0.44),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '\uC624\uB514\uC624 \uCD9C\uB825 \uC120\uD0DD',
                style: TextStyle(
                  color: _stageText,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _stageMenu,
                  border: Border.all(color: _stageMenuBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MobileAudioOutputOptionRow(
                      icon: Icons.phone_android,
                      title: '\uD734\uB300\uD3F0',
                      subtitle: 'SM-F966N',
                      selected: !speakerOn,
                      onTap: () => onChanged(false),
                    ),
                    const _MobileVoiceSheetDivider(),
                    _MobileAudioOutputOptionRow(
                      icon: Icons.volume_up,
                      title: '\uC2A4\uD53C\uCEE4',
                      subtitle: 'SM-F966N',
                      selected: speakerOn,
                      onTap: () => onChanged(true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileAudioOutputOptionRow extends StatelessWidget {
  const _MobileAudioOutputOptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: _stageText, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _stageText,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _stageMutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _avaAccent : _stageText,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: _avaAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _AzoomAboutEasterEggPanel extends StatelessWidget {
  const _AzoomAboutEasterEggPanel({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _stageMenu.withValues(alpha: 0.98),
        border: Border.all(color: _stageMenuBorder),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: SizedBox(
        height: 410,
        child: Column(
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.fromLTRB(15, 0, 6, 0),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _stageMenuBorder)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: _avaAccent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'AVA',
                      style: TextStyle(
                        color: _stageText,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(
                      Icons.close,
                      color: _stageMutedText,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const Expanded(child: Center(child: _AvaEasterEggCharacter())),
          ],
        ),
      ),
    );
  }
}

class _AvaEasterEggCharacter extends StatefulWidget {
  const _AvaEasterEggCharacter();

  @override
  State<_AvaEasterEggCharacter> createState() => _AvaEasterEggCharacterState();
}

class _AvaEasterEggCharacterState extends State<_AvaEasterEggCharacter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final bob = math.sin(t * math.pi) * 12;
        final tilt = (t - 0.5) * 0.08;
        return Transform.translate(
          offset: Offset(0, -bob),
          child: Transform.rotate(angle: tilt, child: child),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: _stageControl,
              borderRadius: BorderRadius.circular(38),
              border: Border.all(color: _stageBorder),
              boxShadow: [
                BoxShadow(
                  color: _avaAccent.withValues(alpha: 0.28),
                  blurRadius: 26,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(88, 44),
                  painter: _AvaLogoLinePainter(),
                ),
                Positioned(
                  bottom: 28,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _stagePanel.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _stageBorder),
                    ),
                    child: const Text(
                      'AVA',
                      style: TextStyle(
                        color: _stageText,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 37,
                  left: 46,
                  child: _AvaBlinkDot(color: Color(0xFF806BFF)),
                ),
                const Positioned(
                  top: 37,
                  right: 46,
                  child: _AvaBlinkDot(color: Color(0xFF1D8CFF)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Abbas Vanguard AI',
            style: TextStyle(
              color: _stageText,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '앞선 기술로, 더 나은 미래를 만듭니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _stageMutedText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvaBlinkDot extends StatelessWidget {
  const _AvaBlinkDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _AvaLogoLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 6.5;
    final path = Path()
      ..moveTo(0, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.18,
        size.height * 0.04,
        size.width * 0.36,
        size.height * 0.70,
      )
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 1.08,
        size.width * 0.64,
        size.height * 0.70,
      )
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.04,
        size.width,
        size.height * 0.78,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MobileSmallCircleButton extends StatelessWidget {
  const _MobileSmallCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _avaAccentDeep,
          side: const BorderSide(color: _stageBorder),
          shape: const CircleBorder(),
        ),
        icon: Icon(icon, color: _avaAccentDeep, size: 21),
      ),
    );
  }
}

class _MobileLargeCircleButton extends StatelessWidget {
  const _MobileLargeCircleButton({
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: selected ? _avaAccentDeep : Colors.white,
          disabledBackgroundColor: _stageControl,
          foregroundColor: selected ? Colors.white : _avaAccentDeep,
          side: BorderSide(color: selected ? _avaAccentDeep : _stageBorder),
          shape: const CircleBorder(),
        ),
        icon: Icon(
          icon,
          color: selected ? Colors.white : _avaAccentDeep,
          size: 24,
        ),
      ),
    );
  }
}

class _DiscordLeftBottomDock extends StatelessWidget {
  const _DiscordLeftBottomDock({
    required this.connectedVoiceChannel,
    required this.currentUser,
    required this.liveKitRoom,
    required this.liveKitConnected,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.cameraUnavailableReason,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.outputVolume,
    required this.onLeaveVoice,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onToggleCamera,
    required this.onCameraUnavailable,
    required this.onSelectAudioInput,
    required this.onSelectAudioOutput,
    required this.onOutputVolumeChanged,
    required this.onToggleScreenShare,
    required this.onTriggerFirework,
  });

  final AzoomVoiceChannelDto? connectedVoiceChannel;
  final PersonProfile currentUser;
  final lk.Room? liveKitRoom;
  final bool liveKitConnected;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool cameraBusy;
  final String? cameraUnavailableReason;
  final bool screenSharing;
  final bool screenShareBusy;
  final double outputVolume;
  final VoidCallback onLeaveVoice;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleCamera;
  final VoidCallback onCameraUnavailable;
  final ValueChanged<lk.MediaDevice> onSelectAudioInput;
  final ValueChanged<lk.MediaDevice> onSelectAudioOutput;
  final ValueChanged<double> onOutputVolumeChanged;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onTriggerFirework;

  @override
  Widget build(BuildContext context) {
    final channel = connectedVoiceChannel;
    return DecoratedBox(
      key: const ValueKey('azoom-left-bottom-dock'),
      decoration: BoxDecoration(
        color: _discordSidebarPanel,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.26),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (channel != null)
              _DiscordVoiceConnectionPanel(
                channel: channel,
                micEnabled: micEnabled,
                deafened: deafened,
                cameraEnabled: cameraEnabled,
                cameraBusy: cameraBusy,
                cameraUnavailable: cameraUnavailableReason != null,
                screenSharing: screenSharing,
                screenShareBusy: screenShareBusy,
                mediaControlsEnabled: liveKitConnected,
                onLeave: onLeaveVoice,
                onToggleMic: onToggleMic,
                onToggleDeafen: onToggleDeafen,
                onToggleCamera: onToggleCamera,
                onCameraUnavailable: onCameraUnavailable,
                onToggleScreenShare: onToggleScreenShare,
                onTriggerFirework: onTriggerFirework,
              ),
            _UserPanel(
              profile: currentUser,
              liveKitRoom: liveKitRoom,
              mediaControlsEnabled: liveKitConnected,
              micEnabled: micEnabled,
              deafened: deafened,
              outputVolume: outputVolume,
              onToggleMic: onToggleMic,
              onToggleDeafen: onToggleDeafen,
              onSelectAudioInput: onSelectAudioInput,
              onSelectAudioOutput: onSelectAudioOutput,
              onOutputVolumeChanged: onOutputVolumeChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserPanel extends StatelessWidget {
  const _UserPanel({
    required this.profile,
    required this.liveKitRoom,
    required this.mediaControlsEnabled,
    required this.micEnabled,
    required this.deafened,
    required this.outputVolume,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onSelectAudioInput,
    required this.onSelectAudioOutput,
    required this.onOutputVolumeChanged,
  });

  final PersonProfile profile;
  final lk.Room? liveKitRoom;
  final bool mediaControlsEnabled;
  final bool micEnabled;
  final bool deafened;
  final double outputVolume;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final ValueChanged<lk.MediaDevice> onSelectAudioInput;
  final ValueChanged<lk.MediaDevice> onSelectAudioOutput;
  final ValueChanged<double> onOutputVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final status = profile.status?.trim().isNotEmpty == true
        ? profile.status!.trim()
        : '온라인';

    return Container(
      key: const ValueKey('azoom-user-panel'),
      height: 58,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      decoration: const BoxDecoration(
        color: _discordSidebarPanel,
        border: Border(top: BorderSide(color: _discordSidebarBorder)),
      ),
      child: Row(
        children: [
          _UserPanelAvatar(profile: profile),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  key: const ValueKey('azoom-user-panel-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _discordSidebarText,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mediaControlsEnabled
                      ? '\uC74C\uC131 \uCC44\uB110\uC5D0\uC11C \uC0AC\uC6A9'
                      : status,
                  key: const ValueKey('azoom-user-panel-status'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _discordSidebarMuted,
                    fontSize: 11,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          _VoiceSplitMenuControl(
            key: const ValueKey('azoom-sidebar-mic-device-control'),
            tooltip: micEnabled ? 'Mute microphone' : 'Unmute microphone',
            kind: _VoiceDeviceMenuKind.microphone,
            icon: micEnabled && !deafened ? Icons.mic : Icons.mic_off,
            selected: !micEnabled || deafened,
            enabled: mediaControlsEnabled,
            compact: true,
            chevronKey: 'azoom-sidebar-mic-device-chevron',
            liveKitRoom: liveKitRoom,
            micEnabled: micEnabled,
            deafened: deafened,
            outputVolume: outputVolume,
            onMainTap: onToggleMic,
            onToggleDeafen: onToggleDeafen,
            onSelectAudioInput: onSelectAudioInput,
            onSelectAudioOutput: onSelectAudioOutput,
            onOutputVolumeChanged: onOutputVolumeChanged,
          ),
          const SizedBox(width: 2),
          _VoiceSplitMenuControl(
            key: const ValueKey('azoom-sidebar-deafen-device-control'),
            tooltip: deafened ? 'Undeafen' : 'Deafen',
            kind: _VoiceDeviceMenuKind.microphone,
            icon: deafened ? Icons.headset_off : Icons.headphones,
            selected: deafened,
            enabled: mediaControlsEnabled,
            compact: true,
            chevronKey: 'azoom-sidebar-deafen-device-chevron',
            liveKitRoom: liveKitRoom,
            micEnabled: micEnabled,
            deafened: deafened,
            outputVolume: outputVolume,
            onMainTap: onToggleDeafen,
            onToggleDeafen: onToggleDeafen,
            onSelectAudioInput: onSelectAudioInput,
            onSelectAudioOutput: onSelectAudioOutput,
            onOutputVolumeChanged: onOutputVolumeChanged,
          ),
          const SizedBox(width: 2),
          _SidebarPanelIconButton(
            key: const ValueKey('azoom-sidebar-user-settings-button'),
            tooltip: 'User settings',
            icon: Icons.settings,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

class _SidebarPanelIconButton extends StatelessWidget {
  const _SidebarPanelIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 32,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            hoverColor: _discordSidebarHover,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          icon: Icon(icon, color: _discordSidebarMuted, size: 20),
        ),
      ),
    );
  }
}

class _UserPanelAvatar extends StatelessWidget {
  const _UserPanelAvatar({required this.profile});

  final PersonProfile profile;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      key: const ValueKey('azoom-user-panel-avatar'),
      dimension: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ProfileAvatar(profile: profile, size: 34),
          Positioned(
            right: -1,
            bottom: -1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(color: _discordSidebarPanel, width: 3),
              ),
              child: const SizedBox.square(dimension: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _AzoomServerHeader extends StatelessWidget {
  const _AzoomServerHeader({
    this.searchQuery = '',
    this.onSearchChanged,
    this.onInvitePressed,
  });

  final String searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onInvitePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _channelHeaderHeight,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _discordSidebarBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
      child: const Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    'AZOOM',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _discordSidebarText,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
                SizedBox(width: 3),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: _discordSidebarText,
                  size: 17,
                ),
              ],
            ),
          ),
          Icon(Icons.person_add_alt_1, color: _discordSidebarMuted, size: 19),
        ],
      ),
    );
  }
}

class _SidebarShortcutRow extends StatelessWidget {
  const _SidebarShortcutRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.fromLTRB(17, 0, 16, 0),
      child: Row(
        children: [
          Icon(icon, color: _discordSidebarMuted, size: 19),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              color: _discordSidebarMuted,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.expanded = false,
    this.showAdd = true,
    this.onTap,
    super.key,
  });

  final String title;
  final bool expanded;
  final bool showAdd;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 14, 0),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: _discordSidebarSubtle,
              size: 15,
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _discordSidebarSubtle,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
            if (showAdd)
              const Icon(Icons.add, color: _discordSidebarSubtle, size: 19),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return content;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.label,
    this.selected = false,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32,
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: selected ? _discordSidebarSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Icon(
                Icons.tag,
                color: selected ? _discordSidebarText : _discordSidebarMuted,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? _discordSidebarText
                        : _discordSidebarMuted,
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedChannelTools extends StatelessWidget {
  const _SelectedChannelTools();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.person_add_alt_1, color: _discordSidebarText, size: 17),
        SizedBox(width: 6),
        Icon(Icons.settings, color: _discordSidebarText, size: 17),
      ],
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({
    required this.channel,
    required this.selected,
    required this.connected,
    required this.liveUserIds,
    required this.currentUser,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.screenSharing,
    required this.joining,
    required this.onTap,
    super.key,
  });

  final AzoomVoiceChannelDto channel;
  final bool selected;
  final bool connected;
  final Set<String> liveUserIds;
  final PersonProfile currentUser;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool screenSharing;
  final bool joining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sourceParticipants = liveUserIds.isEmpty
        ? channel.participants
        : channel.participants
              .where((participant) => liveUserIds.contains(participant.userId))
              .toList();
    final participants = _voiceRowParticipants(
      sourceParticipants,
      currentUser: currentUser,
      includeLocal: connected,
      micEnabled: micEnabled,
      deafened: deafened,
      cameraEnabled: cameraEnabled,
      screenSharing: screenSharing,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          padding: const EdgeInsets.fromLTRB(9, 0, 9, 6),
          decoration: BoxDecoration(
            color: selected ? _discordSidebarSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 34,
                child: Row(
                  children: [
                    Icon(
                      selected ? Icons.volume_up : Icons.volume_up_outlined,
                      color: selected
                          ? _discordSidebarGreen
                          : _discordSidebarMuted,
                      size: 21,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? _discordSidebarText
                              : _discordSidebarMuted,
                          fontSize: 16,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          height: 1,
                        ),
                      ),
                    ),
                    if (connected) ...[
                      const SizedBox(width: 8),
                      _VoiceElapsedClock(
                        startedAt: channel.startedAt,
                        serverNow: channel.serverNow,
                        receivedAt: channel.receivedAt,
                      ),
                    ],
                    if (joining)
                      const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _discordSidebarText,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(left: 31, right: 4, bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '\uCC44\uB110 \uC0C1\uD0DC \uC124\uC815',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _discordSidebarMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                      ),
                      Icon(Icons.edit, color: _discordSidebarSubtle, size: 13),
                    ],
                  ),
                ),
              for (final participant in participants)
                _VoiceParticipantInline(participant: participant),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceElapsedClock extends StatefulWidget {
  const _VoiceElapsedClock({
    required this.startedAt,
    required this.serverNow,
    required this.receivedAt,
  });

  final DateTime? startedAt;
  final DateTime? serverNow;
  final DateTime? receivedAt;

  @override
  State<_VoiceElapsedClock> createState() => _VoiceElapsedClockState();
}

class _VoiceElapsedClockState extends State<_VoiceElapsedClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = widget.startedAt;
    final serverNow = widget.serverNow;
    final receivedAt = widget.receivedAt;
    if (startedAt == null || serverNow == null || receivedAt == null) {
      return const Text(
        '00:00',
        maxLines: 1,
        style: TextStyle(
          color: _discordSidebarGreen,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      );
    }
    final serverElapsed = serverNow.difference(startedAt);
    final localElapsedSinceSync = DateTime.now().difference(receivedAt);
    final elapsed = serverElapsed + localElapsedSinceSync;
    return Text(
      _formatVoiceElapsed(elapsed),
      maxLines: 1,
      style: const TextStyle(
        color: _discordSidebarGreen,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    );
  }
}

class _VoiceParticipantInline extends StatelessWidget {
  const _VoiceParticipantInline({required this.participant});

  final AzoomVoiceParticipantDto participant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 28, bottom: 5),
      child: Row(
        children: [
          _AzoomAvatar(
            label: _avatarLabel(participant.displayName),
            color: _colorFromHex(participant.avatarColor),
            imageUrl: participant.avatarImageUrl,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              participant.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _discordSidebarMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (participant.muted || participant.deafened)
            const Icon(
              Icons.mic_off,
              key: ValueKey('azoom-sidebar-participant-muted-icon'),
              color: _discordSidebarSubtle,
              size: 14,
            ),
          if (participant.deafened)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.headset_off,
                key: ValueKey('azoom-sidebar-participant-deafened-icon'),
                color: _discordSidebarSubtle,
                size: 14,
              ),
            ),
          if (participant.cameraEnabled)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.videocam,
                color: _discordSidebarGreen,
                size: 14,
              ),
            ),
          if (participant.screenSharing)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(
                Icons.screen_share,
                color: _discordSidebarGreen,
                size: 14,
              ),
            ),
        ],
      ),
    );
  }
}

class _DiscordVoiceConnectionPanel extends StatelessWidget {
  const _DiscordVoiceConnectionPanel({
    required this.channel,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.cameraUnavailable,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.mediaControlsEnabled,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onToggleCamera,
    required this.onCameraUnavailable,
    required this.onToggleScreenShare,
    required this.onTriggerFirework,
  });

  final AzoomVoiceChannelDto channel;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool cameraBusy;
  final bool cameraUnavailable;
  final bool screenSharing;
  final bool screenShareBusy;
  final bool mediaControlsEnabled;
  final VoidCallback onLeave;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleCamera;
  final VoidCallback onCameraUnavailable;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onTriggerFirework;

  @override
  Widget build(BuildContext context) {
    final muted = !micEnabled || deafened;
    return Container(
      key: const ValueKey('azoom-voice-connection-panel'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: _discordSidebarPanel,
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.wifi_tethering,
                color: _discordSidebarGreen,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '\uC74C\uC131 \uC5F0\uACB0\uB428',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _discordSidebarGreen,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${channel.name} / AZOOM',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _discordSidebarMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              _SidebarPanelIconButton(
                tooltip: muted ? 'Muted' : 'Voice activity',
                icon: muted ? Icons.volume_off : Icons.graphic_eq,
                onTap: () {},
              ),
              _SidebarPanelIconButton(
                tooltip: 'Disconnect',
                icon: Icons.call_end,
                onTap: onLeave,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _VoiceConnectionActionButton(
                  tooltip: cameraUnavailable
                      ? 'Camera unavailable'
                      : cameraEnabled
                      ? 'Turn camera off'
                      : 'Turn camera on',
                  icon: cameraEnabled ? Icons.videocam : Icons.videocam_off,
                  selected: cameraEnabled,
                  unavailable: cameraUnavailable && !cameraEnabled,
                  busy: cameraBusy,
                  enabled: mediaControlsEnabled && !cameraBusy,
                  onTap: cameraUnavailable && !cameraEnabled
                      ? onCameraUnavailable
                      : onToggleCamera,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VoiceConnectionActionButton(
                  tooltip: screenSharing ? 'Stop screen share' : 'Screen share',
                  icon: Icons.screen_share,
                  selected: screenSharing,
                  busy: screenShareBusy,
                  enabled: mediaControlsEnabled && !screenShareBusy,
                  onTap: onToggleScreenShare,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VoiceConnectionActionButton(
                  tooltip: 'Activities',
                  icon: Icons.apps,
                  onTap: () {},
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VoiceConnectionActionButton(
                  key: const ValueKey('azoom-sidebar-firework-button'),
                  tooltip: 'Soundboard',
                  icon: Icons.celebration,
                  onTap: onTriggerFirework,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceConnectionActionButton extends StatelessWidget {
  const _VoiceConnectionActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.unavailable = false,
    this.enabled = true,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool unavailable;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final foreground = unavailable || !enabled
        ? _discordSidebarSubtle
        : selected
        ? Colors.white
        : _discordSidebarText;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 42,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? onTap : null,
          style: IconButton.styleFrom(
            backgroundColor: selected ? _avaAccent : _discordSidebarSelected,
            disabledBackgroundColor: _discordSidebarHover,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          icon: busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Icon(icon, color: foreground, size: 22),
        ),
      ),
    );
  }
}

class _VoiceConnectionPanel extends StatelessWidget {
  const _VoiceConnectionPanel({
    required this.channel,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.cameraUnavailable,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.mediaControlsEnabled,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onToggleCamera,
    required this.onCameraUnavailable,
    required this.onToggleScreenShare,
  });

  final AzoomVoiceChannelDto channel;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool cameraBusy;
  final bool cameraUnavailable;
  final bool screenSharing;
  final bool screenShareBusy;
  final bool mediaControlsEnabled;
  final VoidCallback onLeave;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleCamera;
  final VoidCallback onCameraUnavailable;
  final VoidCallback onToggleScreenShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('azoom-voice-connection-panel'),
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _discordSidebarPanel,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '음성 연결됨',
            style: TextStyle(
              color: _discordSidebarGreen,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            channel.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _discordSidebarMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _MiniControlButton(
                icon: micEnabled && !deafened ? Icons.mic : Icons.mic_off,
                selected: !micEnabled || deafened,
                enabled: mediaControlsEnabled,
                onTap: onToggleMic,
              ),
              const SizedBox(width: 8),
              _MiniControlButton(
                icon: deafened ? Icons.headset_off : Icons.headphones,
                selected: deafened,
                enabled: mediaControlsEnabled,
                onTap: onToggleDeafen,
              ),
              const SizedBox(width: 8),
              _MiniControlButton(
                tooltip: cameraUnavailable
                    ? '카메라 사용 불가능'
                    : cameraEnabled
                    ? '카메라 끄기'
                    : '카메라 켜기',
                icon: cameraEnabled ? Icons.videocam : Icons.videocam_off,
                selected: cameraEnabled,
                busy: cameraBusy,
                enabled: mediaControlsEnabled && !cameraBusy,
                unavailable: cameraUnavailable && !cameraEnabled,
                onTap: cameraUnavailable && !cameraEnabled
                    ? onCameraUnavailable
                    : onToggleCamera,
              ),
              const SizedBox(width: 8),
              _MiniControlButton(
                tooltip: screenSharing ? 'Stop screen share' : 'Screen share',
                icon: Icons.screen_share,
                selected: screenSharing,
                busy: screenShareBusy,
                enabled: mediaControlsEnabled && !screenShareBusy,
                onTap: onToggleScreenShare,
              ),
              const SizedBox(width: 8),
              _MiniControlButton(
                tooltip: 'Activities',
                icon: Icons.apps,
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _MiniControlButton(
                tooltip: 'Soundboard',
                icon: Icons.celebration,
                onTap: () {},
              ),
              const Spacer(),
              _MiniControlButton(
                icon: Icons.call_end,
                danger: true,
                onTap: onLeave,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniControlButton extends StatelessWidget {
  const _MiniControlButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.selected = false,
    this.danger = false,
    this.unavailable = false,
    this.enabled = true,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool selected;
  final bool danger;
  final bool unavailable;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox.square(
      dimension: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: enabled ? onTap : null,
        style: IconButton.styleFrom(
          backgroundColor: danger
              ? const Color(0xFFFF5A63)
              : unavailable
              ? _stageMenuHover
              : selected
              ? _avaAccent
              : _stageMenuHover,
          disabledBackgroundColor: _stageControl,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: busy
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(
                icon,
                size: 17,
                color: !enabled || unavailable
                    ? _discordSidebarSubtle
                    : danger || selected
                    ? Colors.white
                    : _discordSidebarText,
              ),
      ),
    );
    final message = tooltip;
    if (message == null) {
      return button;
    }
    return Tooltip(message: message, child: button);
  }
}

class _AzoomVoicePlaceholderSurface extends StatelessWidget {
  const _AzoomVoicePlaceholderSurface({
    required this.voiceChannels,
    required this.loading,
    required this.errorText,
    required this.onVoiceChannelSelected,
  });

  final List<AzoomVoiceChannelDto> voiceChannels;
  final bool loading;
  final String? errorText;
  final ValueChanged<AzoomVoiceChannelDto> onVoiceChannelSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _stageBackground,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const CircularProgressIndicator(color: _avaAccent)
                else ...[
                  const Icon(
                    Icons.volume_up,
                    color: _discordSidebarMuted,
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    errorText ?? '음성 채널을 선택해주세요.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _discordSidebarText,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (voiceChannels.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      height: math.min(
                        voiceChannels.length * 52.0,
                        math.max(
                          52.0,
                          MediaQuery.sizeOf(context).height * 0.45,
                        ),
                      ),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: voiceChannels.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final channel = voiceChannels[index];
                          return SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: FilledButton.icon(
                              onPressed: () => onVoiceChannelSelected(channel),
                              style: FilledButton.styleFrom(
                                backgroundColor: _stageControl,
                                foregroundColor: _discordSidebarText,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.volume_up, size: 18),
                              label: Text(
                                channel.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AzoomMeetingTranscriptSurface extends StatelessWidget {
  const _AzoomMeetingTranscriptSurface({
    required this.transcript,
    required this.relatedTranscripts,
    required this.onTranscriptSelected,
  });

  final AzoomMeetingTranscriptDto transcript;
  final List<AzoomMeetingTranscriptSummaryDto> relatedTranscripts;
  final ValueChanged<AzoomMeetingTranscriptSummaryDto> onTranscriptSelected;

  @override
  Widget build(BuildContext context) {
    final processing = transcript.status == 'PROCESSING';
    final failed = transcript.status == 'FAILED';
    final matching = _matchingMeetingTranscripts(
      transcript,
      relatedTranscripts,
    );
    final menuItems = _meetingTranscriptMenuItems(transcript, matching);
    return ColoredBox(
      color: _chatBackground,
      child: Column(
        children: [
          Container(
            height: _channelHeaderHeight,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
            child: Row(
              children: [
                const Icon(
                  Icons.description,
                  color: _discordSidebarMuted,
                  size: 23,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${transcript.channelName} · ${transcript.titleTimestamp}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _discordSidebarText,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                for (final item in menuItems)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(
                        item.status == 'PROCESSING'
                            ? '변환중'
                            : item.status == 'FAILED'
                            ? '실패'
                            : item.kind == 'BATCH_AUDIO'
                            ? '통파일'
                            : '실시간',
                      ),
                      selected: item.id == transcript.id,
                      onSelected: item.id == transcript.id
                          ? null
                          : (_) => onTranscriptSelected(item),
                      showCheckmark: false,
                      selectedColor: _discordSidebarSelected,
                      disabledColor: _discordSidebarSelected,
                      backgroundColor: _stageControl,
                      labelStyle: const TextStyle(
                        color: _discordSidebarText,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: processing
                ? const Center(child: _TranscriptStatusMessage(text: '변환중입니다'))
                : failed
                ? const Center(
                    child: _TranscriptStatusMessage(text: '변환에 실패했습니다.'),
                  )
                : transcript.utterances.isEmpty
                ? const Center(
                    child: _TranscriptStatusMessage(text: '저장된 발화가 없습니다.'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
                    itemCount: transcript.utterances.length,
                    itemBuilder: (context, index) {
                      final utterance = transcript.utterances[index];
                      return _TranscriptUtteranceBubble(utterance: utterance);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptUtteranceBubble extends StatelessWidget {
  const _TranscriptUtteranceBubble({required this.utterance});

  final AzoomMeetingUtteranceDto utterance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _avaAccentDeep,
            child: Text(
              _initial(utterance.speakerName),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        utterance.speakerName.isEmpty
                            ? 'Unknown'
                            : utterance.speakerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _discordSidebarText,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTranscriptClock(utterance.startedAt),
                      style: const TextStyle(
                        color: _discordSidebarSubtle,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  utterance.content,
                  style: const TextStyle(
                    color: _discordSidebarText,
                    fontSize: 14,
                    height: 1.36,
                    fontWeight: FontWeight.w600,
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

class _TranscriptStatusMessage extends StatelessWidget {
  const _TranscriptStatusMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _discordSidebarMuted,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _AzoomTranscriptSearchField extends StatefulWidget {
  const _AzoomTranscriptSearchField({
    required this.query,
    required this.onChanged,
  });

  final String query;
  final ValueChanged<String> onChanged;

  @override
  State<_AzoomTranscriptSearchField> createState() =>
      _AzoomTranscriptSearchFieldState();
}

class _AzoomTranscriptSearchFieldState
    extends State<_AzoomTranscriptSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _AzoomTranscriptSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Material(
        color: Colors.transparent,
        child: TextField(
          key: const ValueKey('azoom-transcript-date-search'),
          controller: _controller,
          onChanged: widget.onChanged,
          cursorColor: _discordSidebarText,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
            color: _discordSidebarText,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            hintText: '\uAC80\uC0C9\uD558\uAE30',
            hintStyle: const TextStyle(
              color: _discordSidebarMuted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: _discordSidebarMuted,
              size: 18,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 28,
            ),
            suffixIcon: widget.query.trim().isEmpty
                ? null
                : IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged('');
                    },
                    icon: const Icon(
                      Icons.close,
                      color: _discordSidebarMuted,
                      size: 17,
                    ),
                  ),
            filled: true,
            fillColor: _discordSidebarSelected,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _avaAccent, width: 1),
            ),
          ),
        ),
      ),
    );
  }
}

class _AzoomManagerPanel extends StatefulWidget {
  const _AzoomManagerPanel({
    required this.api,
    required this.accessToken,
    required this.voiceChannels,
    required this.onChanged,
  });

  final AzoomApi api;
  final String accessToken;
  final List<AzoomVoiceChannelDto> voiceChannels;
  final VoidCallback onChanged;

  @override
  State<_AzoomManagerPanel> createState() => _AzoomManagerPanelState();
}

class _AzoomManagerPanelState extends State<_AzoomManagerPanel> {
  bool _loading = true;
  bool _inviting = false;
  String? _savingChannelId;
  String? _errorText;
  List<AzoomInviteCandidateDto> _candidates = const [];
  List<AzoomCompanyUserDto> _companyUsers = const [];
  final Set<String> _selectedCandidateIds = <String>{};
  final Map<String, String> _channelAccessModes = <String, String>{};
  final Map<String, Set<String>> _channelDepartments = <String, Set<String>>{};
  final Map<String, String> _departmentDrafts = <String, String>{};

  @override
  void initState() {
    super.initState();
    _syncChannelAccessState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _AzoomManagerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.voiceChannels != widget.voiceChannels) {
      _syncChannelAccessState();
    }
  }

  void _syncChannelAccessState() {
    for (final channel in widget.voiceChannels) {
      _channelAccessModes.putIfAbsent(
        channel.id,
        () => channel.accessMode.isEmpty ? 'ALL' : channel.accessMode,
      );
      _channelDepartments.putIfAbsent(
        channel.id,
        () => {...channel.allowedDepartments},
      );
    }
  }

  List<String> get _departmentOptions {
    final departments = <String>{};
    for (final user in _companyUsers) {
      final value = user.department.trim();
      if (value.isNotEmpty) {
        departments.add(value);
      }
    }
    for (final candidate in _candidates) {
      final value = candidate.department.trim();
      if (value.isNotEmpty) {
        departments.add(value);
      }
    }
    for (final channel in widget.voiceChannels) {
      departments.addAll(channel.allowedDepartments.map((item) => item.trim()));
    }
    final result = departments.where((item) => item.isNotEmpty).toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final results = await Future.wait<Object>([
        widget.api.inviteCandidates(accessToken: widget.accessToken),
        widget.api.companyUsers(accessToken: widget.accessToken),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _candidates = results[0] as List<AzoomInviteCandidateDto>;
        _companyUsers = results[1] as List<AzoomCompanyUserDto>;
        _selectedCandidateIds.removeWhere(
          (id) => !_candidates.any((candidate) => candidate.accountId == id),
        );
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorText = error.toString();
      });
    }
  }

  Future<void> _inviteSelected() async {
    if (_selectedCandidateIds.isEmpty || _inviting) {
      showAvaToast(
        context,
        '\uCD08\uB300\uD560 \uC720\uC800\uB97C \uC120\uD0DD\uD574\uC8FC\uC138\uC694.',
      );
      return;
    }
    setState(() {
      _inviting = true;
      _errorText = null;
    });
    try {
      await widget.api.inviteMembers(
        accessToken: widget.accessToken,
        accountIds: _selectedCandidateIds.toList(),
      );
      if (!mounted) {
        return;
      }
      showAvaToast(context, '\uCD08\uB300\uD588\uC2B5\uB2C8\uB2E4.');
      setState(() {
        _selectedCandidateIds.clear();
        _inviting = false;
      });
      widget.onChanged();
      await _load();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _inviting = false;
        _errorText = error.toString();
      });
    }
  }

  Future<void> _saveChannelAccess(AzoomVoiceChannelDto channel) async {
    if (_savingChannelId != null) {
      return;
    }
    final mode = _channelAccessModes[channel.id] ?? 'ALL';
    final departments =
        (_channelDepartments[channel.id] ?? <String>{})
            .where((item) => item.trim().isNotEmpty)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    setState(() {
      _savingChannelId = channel.id;
      _errorText = null;
    });
    try {
      await widget.api.updateChannelAccess(
        accessToken: widget.accessToken,
        channelId: channel.id,
        accessMode: mode,
        allowedDepartments: mode == 'DEPARTMENTS' ? departments : const [],
      );
      if (!mounted) {
        return;
      }
      showAvaToast(context, '\uC800\uC7A5\uD588\uC2B5\uB2C8\uB2E4.');
      setState(() {
        _savingChannelId = null;
      });
      widget.onChanged();
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _savingChannelId = null;
        _errorText = error.toString();
      });
    }
  }

  void _toggleCandidate(String accountId, bool selected) {
    setState(() {
      if (selected) {
        _selectedCandidateIds.add(accountId);
      } else {
        _selectedCandidateIds.remove(accountId);
      }
    });
  }

  void _setChannelMode(String channelId, String mode) {
    setState(() {
      _channelAccessModes[channelId] = mode;
    });
  }

  void _toggleDepartment(String channelId, String department, bool selected) {
    setState(() {
      final departments = _channelDepartments.putIfAbsent(
        channelId,
        () => <String>{},
      );
      if (selected) {
        departments.add(department);
      } else {
        departments.remove(department);
      }
    });
  }

  void _addDepartment(AzoomVoiceChannelDto channel) {
    final draft = (_departmentDrafts[channel.id] ?? '').trim();
    if (draft.isEmpty) {
      return;
    }
    setState(() {
      _channelAccessModes[channel.id] = 'DEPARTMENTS';
      _channelDepartments.putIfAbsent(channel.id, () => <String>{}).add(draft);
      _departmentDrafts[channel.id] = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height - 72;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 760,
        maxHeight: maxHeight.clamp(420.0, 720.0).toDouble(),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: _stagePanel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _stageBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 26,
                offset: Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _AzoomPanelHeader(
                icon: Icons.admin_panel_settings,
                title: 'AZOOM \uAD00\uB9AC',
                onClose: () => Navigator.of(context).pop(),
              ),
              if (_errorText != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                  color: _discordDanger.withValues(alpha: 0.16),
                  child: Text(
                    _errorText!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFFB4B4),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: _stageText),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                        children: [
                          _buildInviteSection(),
                          const SizedBox(height: 18),
                          _buildAccessSection(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInviteSection() {
    return _AzoomPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AzoomPanelSectionTitle(
            icon: Icons.person_add_alt_1,
            title: 'AZOOM \uC720\uC800 \uCD08\uB300',
            trailing: FilledButton(
              onPressed: _inviting ? null : _inviteSelected,
              style: FilledButton.styleFrom(
                backgroundColor: _discordSidebarGreen,
                foregroundColor: Colors.white,
              ),
              child: _inviting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '\uCD08\uB300 ${_selectedCandidateIds.length}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          if (_candidates.isEmpty)
            const _AzoomPanelEmptyText(
              text:
                  '\uCD08\uB300\uD560 \uC720\uC800\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
            )
          else
            for (final candidate in _candidates)
              _AzoomInviteCandidateRow(
                candidate: candidate,
                selected: _selectedCandidateIds.contains(candidate.accountId),
                onChanged: (selected) =>
                    _toggleCandidate(candidate.accountId, selected),
              ),
        ],
      ),
    );
  }

  Widget _buildAccessSection() {
    return _AzoomPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AzoomPanelSectionTitle(
            icon: Icons.lock_person,
            title: '\uC74C\uC131 \uCC44\uB110 \uCC38\uAC00 \uAD8C\uD55C',
          ),
          const SizedBox(height: 10),
          for (final channel in widget.voiceChannels) ...[
            _AzoomChannelAccessEditor(
              channel: channel,
              mode: _channelAccessModes[channel.id] ?? 'ALL',
              selectedDepartments:
                  _channelDepartments[channel.id] ?? <String>{},
              departmentOptions: _departmentOptions,
              draft: _departmentDrafts[channel.id] ?? '',
              saving: _savingChannelId == channel.id,
              onModeChanged: (mode) => _setChannelMode(channel.id, mode),
              onDepartmentChanged: (department, selected) =>
                  _toggleDepartment(channel.id, department, selected),
              onDraftChanged: (value) => _departmentDrafts[channel.id] = value,
              onAddDepartment: () => _addDepartment(channel),
              onSave: () => _saveChannelAccess(channel),
            ),
            if (channel != widget.voiceChannels.last)
              const Divider(color: _stageBorder, height: 20),
          ],
        ],
      ),
    );
  }
}

class _AzoomPanelHeader extends StatelessWidget {
  const _AzoomPanelHeader({
    required this.icon,
    required this.title,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(18, 0, 10, 0),
      decoration: const BoxDecoration(
        color: _stageControl,
        border: Border(bottom: BorderSide(color: _stageBorder)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _stageText, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _stageText,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: '\uB2EB\uAE30',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: _stageMutedText, size: 22),
          ),
        ],
      ),
    );
  }
}

class _AzoomPanelCard extends StatelessWidget {
  const _AzoomPanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _stageControl,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _stageBorder),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class _AzoomPanelSectionTitle extends StatelessWidget {
  const _AzoomPanelSectionTitle({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: _stageMutedText, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _stageText,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _AzoomPanelEmptyText extends StatelessWidget {
  const _AzoomPanelEmptyText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: _stageMutedText,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AzoomInviteCandidateRow extends StatelessWidget {
  const _AzoomInviteCandidateRow({
    required this.candidate,
    required this.selected,
    required this.onChanged,
  });

  final AzoomInviteCandidateDto candidate;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final name = candidate.displayName.trim().isEmpty
        ? candidate.email
        : candidate.displayName;
    final subtitle = [
      candidate.department,
      candidate.position,
      candidate.email,
    ].where((item) => item.trim().isNotEmpty).join(' 쨌 ');
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: (value) => onChanged(value ?? false),
              visualDensity: VisualDensity.compact,
              activeColor: _discordSidebarGreen,
            ),
            _AzoomAvatar(
              label: _avatarLabel(name),
              color: _colorFromHex(candidate.avatarColor),
              imageUrl: candidate.avatarImageUrl,
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _stageText,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _stageMutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AzoomChannelAccessEditor extends StatelessWidget {
  const _AzoomChannelAccessEditor({
    required this.channel,
    required this.mode,
    required this.selectedDepartments,
    required this.departmentOptions,
    required this.draft,
    required this.saving,
    required this.onModeChanged,
    required this.onDepartmentChanged,
    required this.onDraftChanged,
    required this.onAddDepartment,
    required this.onSave,
  });

  final AzoomVoiceChannelDto channel;
  final String mode;
  final Set<String> selectedDepartments;
  final List<String> departmentOptions;
  final String draft;
  final bool saving;
  final ValueChanged<String> onModeChanged;
  final void Function(String department, bool selected) onDepartmentChanged;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onAddDepartment;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final effectiveMode = mode == 'DEPARTMENTS' ? 'DEPARTMENTS' : 'ALL';
    final departmentsEnabled = effectiveMode == 'DEPARTMENTS';
    final availableDepartments =
        {
            ...departmentOptions,
            ...selectedDepartments,
          }.where((item) => item.trim().isNotEmpty).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.volume_up, color: _stageMutedText, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _stageText,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _stageMenu,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _stageBorder),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: effectiveMode,
                      dropdownColor: _stageControl,
                      style: const TextStyle(
                        color: _stageText,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                      iconEnabledColor: _stageMutedText,
                      items: const [
                        DropdownMenuItem(
                          value: 'ALL',
                          child: Text('\uC804\uCCB4 \uC785\uC7A5'),
                        ),
                        DropdownMenuItem(
                          value: 'DEPARTMENTS',
                          child: Text('\uBD80\uC11C \uC120\uD0DD'),
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => onModeChanged(value ?? 'ALL'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (availableDepartments.isEmpty)
                const Text(
                  '\uC120\uD0DD\uD560 \uBD80\uC11C\uAC00 \uC544\uC9C1 \uC5C6\uC2B5\uB2C8\uB2E4.',
                  style: TextStyle(
                    color: _stageMutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                for (final department in availableDepartments)
                  FilterChip(
                    label: Text(department),
                    selected:
                        departmentsEnabled &&
                        selectedDepartments.contains(department),
                    showCheckmark: false,
                    onSelected: departmentsEnabled
                        ? (selected) =>
                              onDepartmentChanged(department, selected)
                        : null,
                    selectedColor: _avaAccent.withValues(alpha: 0.34),
                    disabledColor: _stageMenu,
                    backgroundColor: _stageMenu,
                    labelStyle: TextStyle(
                      color: departmentsEnabled
                          ? _stageText
                          : _stageMutedText.withValues(alpha: 0.72),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    side: BorderSide(
                      color:
                          departmentsEnabled &&
                              selectedDepartments.contains(department)
                          ? _avaAccent
                          : _stageBorder,
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    key: ValueKey('azoom-channel-department-${channel.id}'),
                    enabled: !saving,
                    onChanged: onDraftChanged,
                    style: const TextStyle(
                      color: _stageText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      hintText: '\uBD80\uC11C \uCD94\uAC00',
                      hintStyle: const TextStyle(
                        color: _stageMutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      filled: true,
                      fillColor: _stageMenu,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _stageBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _stageBorder),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: saving || draft.trim().isEmpty
                    ? null
                    : onAddDepartment,
                child: const Text('\uCD94\uAC00'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: _avaAccent,
                  foregroundColor: Colors.white,
                ),
                child: saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '\uC800\uC7A5',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AzoomParticipantsPanel extends StatelessWidget {
  const _AzoomParticipantsPanel({required this.channel, required this.onClose});

  final AzoomVoiceChannelDto channel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final participants = channel.participants;
    final maxHeight = MediaQuery.sizeOf(context).height - 90;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: maxHeight.clamp(320.0, 620.0).toDouble(),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: _stagePanel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _stageBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 26,
                offset: Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _AzoomPanelHeader(
                icon: Icons.people,
                title: '\uCC38\uC5EC\uC790',
                onClose: onClose,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.volume_up,
                      color: _stageMutedText,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _stageText,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${participants.length}',
                      style: const TextStyle(
                        color: _stageMutedText,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: participants.isEmpty
                    ? const Center(
                        child: Text(
                          '\uCC38\uC5EC \uC911\uC778 \uC720\uC800\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
                          style: TextStyle(
                            color: _stageMutedText,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                        itemCount: participants.length,
                        separatorBuilder: (_, _) =>
                            const Divider(color: _stageBorder, height: 1),
                        itemBuilder: (context, index) {
                          return _AzoomParticipantDialogRow(
                            participant: participants[index],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AzoomParticipantDialogRow extends StatelessWidget {
  const _AzoomParticipantDialogRow({required this.participant});

  final AzoomVoiceParticipantDto participant;

  @override
  Widget build(BuildContext context) {
    final name = participant.displayName.trim().isEmpty
        ? participant.email
        : participant.displayName;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _AzoomAvatar(
            label: _avatarLabel(name),
            color: _colorFromHex(participant.avatarColor),
            imageUrl: participant.avatarImageUrl,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _stageText,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (participant.email.trim().isNotEmpty)
                  Text(
                    participant.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _stageMutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          if (participant.muted)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.mic_off, color: _stageMutedText, size: 18),
            ),
          if (participant.deafened)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.headset_off, color: _stageMutedText, size: 18),
            ),
        ],
      ),
    );
  }
}

class _AzoomFireworkOverlay extends StatelessWidget {
  const _AzoomFireworkOverlay({required this.burstIds});

  final List<int> burstIds;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: const ValueKey('azoom-firework-overlay'),
      child: Stack(
        children: [
          for (final burstId in burstIds)
            Positioned.fill(
              child: _AzoomFireworkBurst(
                key: ValueKey('azoom-firework-burst-$burstId'),
                seedOffset: burstId,
              ),
            ),
        ],
      ),
    );
  }
}

class _AzoomFireworkBurst extends StatefulWidget {
  const _AzoomFireworkBurst({required this.seedOffset, super.key});

  final int seedOffset;

  @override
  State<_AzoomFireworkBurst> createState() => _AzoomFireworkBurstState();
}

class _AzoomFireworkBurstState extends State<_AzoomFireworkBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _azoomFireworkDuration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _AzoomFireworkPainter(
            _controller.value,
            seedOffset: widget.seedOffset,
          ),
        );
      },
    );
  }
}

class _AzoomFireworkPainter extends CustomPainter {
  const _AzoomFireworkPainter(this.progress, {required this.seedOffset});

  final double progress;
  final int seedOffset;

  static const _colors = [
    Color(0xFFFCE18A),
    Color(0xFFFF726D),
    Color(0xFFF4306D),
    Color(0xFFB48DEF),
    Color(0xFF63E6BE),
    Color(0xFF74C0FC),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final veilOpacity = math.sin(progress * math.pi).clamp(0.0, 1.0).toDouble();
    final veil = Paint()
      ..color = Colors.black.withValues(alpha: 0.07 * veilOpacity);
    canvas.drawRect(Offset.zero & size, veil);

    final maxDistance = size.shortestSide * 0.58;
    _paintKonfettiParty(
      canvas,
      size,
      origin: Offset(size.width * 0.50, size.height * 0.30),
      seed: 3 + seedOffset * 37,
      start: 0.00,
      count: 110,
      maxDistance: maxDistance,
    );
    _paintKonfettiParty(
      canvas,
      size,
      origin: Offset(size.width * 0.18, size.height * 0.25),
      seed: 11 + seedOffset * 37,
      start: 0.08,
      count: 72,
      maxDistance: maxDistance * 0.82,
      wind: size.width * 0.08,
    );
    _paintKonfettiParty(
      canvas,
      size,
      origin: Offset(size.width * 0.82, size.height * 0.24),
      seed: 19 + seedOffset * 37,
      start: 0.12,
      count: 72,
      maxDistance: maxDistance * 0.82,
      wind: -size.width * 0.08,
    );
    _paintKonfettiParty(
      canvas,
      size,
      origin: Offset(size.width * 0.50, size.height * 0.62),
      seed: 29 + seedOffset * 37,
      start: 0.22,
      count: 64,
      maxDistance: maxDistance * 0.54,
      gravity: size.height * 0.09,
    );
  }

  void _paintKonfettiParty(
    Canvas canvas,
    Size size, {
    required Offset origin,
    required int seed,
    required double start,
    required int count,
    required double maxDistance,
    double wind = 0,
    double? gravity,
  }) {
    final local = ((progress - start) / 0.78).clamp(0.0, 1.0).toDouble();
    if (local <= 0) {
      return;
    }

    final travel = Curves.easeOutCubic.transform(local);
    final fadeOut = local < 0.18
        ? local / 0.18
        : ((1 - local) / 0.42).clamp(0.0, 1.0).toDouble();
    final damping = 1 - math.pow(0.9, 18 * travel).toDouble();
    final fall = gravity ?? size.height * 0.14;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i += 1) {
      final angle = (((i * 137.5) + seed * 31) % 360) * math.pi / 180.0;
      final speed = 0.54 + (((i * 17 + seed * 13) % 47) / 100);
      final drag = 0.82 + (((i * 7 + seed) % 19) / 100);
      final distance = maxDistance * speed * damping * drag;
      final xWind = wind * travel * (0.35 + ((i + seed) % 9) / 14);
      final yFall = fall * local * local * (0.56 + ((i * 5 + seed) % 13) / 14);
      final position =
          origin +
          Offset(math.cos(angle), math.sin(angle)) * distance +
          Offset(xWind, yFall);
      if (position.dx < -24 ||
          position.dx > size.width + 24 ||
          position.dy < -24 ||
          position.dy > size.height + 24) {
        continue;
      }

      final opacity = (fadeOut * (0.72 + ((i + seed) % 6) / 20))
          .clamp(0.0, 1.0)
          .toDouble();
      paint.color = _colors[(i + seed) % _colors.length].withValues(
        alpha: opacity,
      );

      final confettiSize = 5.0 + ((i * 11 + seed) % 9);
      final rotation = (progress * 8.0) + i * 0.37 + seed;
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(rotation);
      if ((i + seed) % 5 == 0) {
        canvas.drawCircle(Offset.zero, confettiSize * 0.42, paint);
      } else {
        final rect = Rect.fromCenter(
          center: Offset.zero,
          width: confettiSize * 0.62,
          height: confettiSize * (1.08 + ((i + seed) % 3) * 0.24),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1.6)),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _AzoomFireworkPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.seedOffset != seedOffset;
  }
}

class _AzoomAvatar extends StatelessWidget {
  const _AzoomAvatar({
    required this.label,
    required this.color,
    required this.imageUrl,
    required this.size,
  });

  final String label;
  final Color color;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmedImageUrl = imageUrl.trim();
    if (trimmedImageUrl.isEmpty) {
      return _RoundAvatar(label: label, color: color, size: size);
    }
    return ProfileAvatar(
      profile: PersonProfile(
        name: label,
        color: color,
        imageUrl: trimmedImageUrl,
      ),
      size: size,
    );
  }
}

class _RoundAvatar extends StatelessWidget {
  const _RoundAvatar({
    required this.label,
    required this.color,
    required this.size,
  });

  final String label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color.computeLuminance() > 0.55
                  ? const Color(0xFF172033)
                  : Colors.white,
              fontSize: size * 0.38,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _AzoomVoiceRoomSurface extends StatelessWidget {
  const _AzoomVoiceRoomSurface({
    required this.channel,
    required this.currentUser,
    required this.liveKitRoom,
    required this.liveKitConnecting,
    required this.liveKitConnected,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.cameraUnavailableReason,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.mediaErrorText,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onToggleCamera,
    required this.onCameraUnavailable,
    required this.onSelectAudioInput,
    required this.onSelectAudioOutput,
    required this.onSelectCameraInput,
    required this.outputVolume,
    required this.onOutputVolumeChanged,
    required this.onToggleScreenShare,
    required this.onToggleFullscreen,
    required this.onLeave,
  });

  final AzoomVoiceChannelDto channel;
  final PersonProfile currentUser;
  final lk.Room? liveKitRoom;
  final bool liveKitConnecting;
  final bool liveKitConnected;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool cameraBusy;
  final String? cameraUnavailableReason;
  final bool screenSharing;
  final bool screenShareBusy;
  final String? mediaErrorText;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleCamera;
  final VoidCallback onCameraUnavailable;
  final ValueChanged<lk.MediaDevice> onSelectAudioInput;
  final ValueChanged<lk.MediaDevice> onSelectAudioOutput;
  final ValueChanged<lk.MediaDevice> onSelectCameraInput;
  final double outputVolume;
  final ValueChanged<double> onOutputVolumeChanged;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final liveParticipants = _liveParticipants(
      liveKitRoom,
      channel.participants,
      currentUser,
    );
    final presenceParticipants = channel.participants.isEmpty
        ? [_participantFromProfile(currentUser)]
        : channel.participants;
    final participantCount = liveParticipants.isNotEmpty
        ? liveParticipants.length
        : presenceParticipants.length;

    return ColoredBox(
      key: const ValueKey('azoom-voice-room-surface'),
      color: _voiceRoomBackground,
      child: Column(
        children: [
          _VoiceRoomHeader(
            channelName: channel.name,
            count: participantCount,
            onToggleFullscreen: onToggleFullscreen,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth < 760
                    ? 24.0
                    : 44.0;
                final tileHeight = (constraints.maxHeight * 0.46)
                    .clamp(220.0, 306.0)
                    .toDouble();
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    36,
                    horizontalPadding,
                    24,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: tileHeight,
                        child: _VoiceRoomParticipantGrid(
                          liveParticipants: liveParticipants,
                          presenceParticipants: presenceParticipants,
                          liveKitConnected: liveKitConnected,
                        ),
                      ),
                      const Spacer(),
                      _VoiceRoomStatusPanel(
                        liveKitConnecting: liveKitConnecting,
                        liveKitConnected: liveKitConnected,
                        mediaErrorText: mediaErrorText,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          _VoiceRoomControlDock(
            micEnabled: micEnabled,
            deafened: deafened,
            cameraEnabled: cameraEnabled,
            cameraBusy: cameraBusy,
            liveKitRoom: liveKitRoom,
            mediaControlsEnabled: liveKitConnected,
            cameraUnavailableReason: cameraUnavailableReason,
            screenSharing: screenSharing,
            screenShareBusy: screenShareBusy,
            onToggleMic: onToggleMic,
            onToggleDeafen: onToggleDeafen,
            onToggleCamera: onToggleCamera,
            onCameraUnavailable: onCameraUnavailable,
            onSelectAudioInput: onSelectAudioInput,
            onSelectAudioOutput: onSelectAudioOutput,
            onSelectCameraInput: onSelectCameraInput,
            outputVolume: outputVolume,
            onOutputVolumeChanged: onOutputVolumeChanged,
            onToggleScreenShare: onToggleScreenShare,
            onLeave: onLeave,
          ),
        ],
      ),
    );
  }
}

class _VoiceRoomHeader extends StatelessWidget {
  const _VoiceRoomHeader({
    required this.channelName,
    required this.count,
    required this.onToggleFullscreen,
  });

  final String channelName;
  final int count;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('azoom-voice-room-header'),
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: _voiceRoomHeader,
        border: Border(bottom: BorderSide(color: _voiceRoomBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.volume_up, color: _voiceRoomMutedText, size: 24),
          const SizedBox(width: 12),
          Text(
            channelName,
            key: const ValueKey('azoom-voice-room-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _voiceRoomText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count\uBA85',
            style: const TextStyle(
              color: _voiceRoomMutedText,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          const _VoiceRoomHeaderIcon(icon: Icons.chat_bubble),
          const SizedBox(width: 18),
          const _VoiceRoomHeaderIcon(icon: Icons.people),
          const SizedBox(width: 18),
          _VoiceRoomHeaderIcon(
            icon: Icons.fullscreen,
            onTap: onToggleFullscreen,
          ),
        ],
      ),
    );
  }
}

class _VoiceRoomHeaderIcon extends StatelessWidget {
  const _VoiceRoomHeaderIcon({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: onTap == null ? null : '전체화면',
      onPressed: onTap,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, color: _voiceRoomMutedText, size: 23),
    );
  }
}

class _VoiceRoomParticipantGrid extends StatelessWidget {
  const _VoiceRoomParticipantGrid({
    required this.liveParticipants,
    required this.presenceParticipants,
    required this.liveKitConnected,
  });

  final List<_LiveParticipantView> liveParticipants;
  final List<AzoomVoiceParticipantDto> presenceParticipants;
  final bool liveKitConnected;

  @override
  Widget build(BuildContext context) {
    final hasLiveParticipants = liveParticipants.isNotEmpty;
    final itemCount = hasLiveParticipants
        ? liveParticipants.length
        : presenceParticipants.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 720 ? 1 : 2;
        return GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 16 / 9,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (hasLiveParticipants) {
              return _VoiceRoomLiveParticipantTile(
                view: liveParticipants[index],
              );
            }
            return _VoiceRoomPresenceParticipantTile(
              participant: presenceParticipants[index],
              connected: liveKitConnected,
            );
          },
        );
      },
    );
  }
}

class _VoiceRoomLiveParticipantTile extends StatelessWidget {
  const _VoiceRoomLiveParticipantTile({required this.view});

  final _LiveParticipantView view;

  @override
  Widget build(BuildContext context) {
    final trackView = _videoTrackFor(view.participant);
    final name = _liveParticipantDisplayName(view);
    return _VoiceRoomTileFrame(
      name: view.isLocal ? '$name (나)' : name,
      muted: !view.participant.isMicrophoneEnabled(),
      child: trackView == null
          ? _AzoomAvatar(
              label: _avatarLabel(name),
              color: _liveParticipantColor(view),
              imageUrl: _liveParticipantImageUrl(view),
              size: 96,
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: lk.VideoTrackRenderer(
                trackView.track,
                fit: trackView.isScreenShare
                    ? lk.VideoViewFit.contain
                    : lk.VideoViewFit.cover,
              ),
            ),
    );
  }
}

class _VoiceRoomPresenceParticipantTile extends StatelessWidget {
  const _VoiceRoomPresenceParticipantTile({
    required this.participant,
    required this.connected,
  });

  final AzoomVoiceParticipantDto participant;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return _VoiceRoomTileFrame(
      name: participant.displayName,
      muted: participant.muted,
      connected: connected,
      child: _AzoomAvatar(
        label: _avatarLabel(participant.displayName),
        color: _colorFromHex(participant.avatarColor),
        imageUrl: participant.avatarImageUrl,
        size: 96,
      ),
    );
  }
}

class _VoiceRoomTileFrame extends StatelessWidget {
  const _VoiceRoomTileFrame({
    required this.name,
    required this.child,
    required this.muted,
    this.connected = true,
  });

  final String name;
  final Widget child;
  final bool muted;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Container(
        color: _voiceRoomTile,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(child: child),
            Positioned(
              left: 16,
              bottom: 12,
              child: _VoiceRoomNamePill(
                name: connected ? name : '$name \uC5F0\uACB0 \uB300\uAE30',
                muted: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceRoomNamePill extends StatelessWidget {
  const _VoiceRoomNamePill({required this.name, required this.muted});

  final String name;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (muted) ...const [
            Icon(Icons.mic_off, color: _voiceRoomMutedText, size: 14),
            SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _voiceRoomText,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceRoomStatusPanel extends StatelessWidget {
  const _VoiceRoomStatusPanel({
    required this.liveKitConnecting,
    required this.liveKitConnected,
    required this.mediaErrorText,
  });

  final bool liveKitConnecting;
  final bool liveKitConnected;
  final String? mediaErrorText;

  @override
  Widget build(BuildContext context) {
    final status = mediaErrorText != null
        ? mediaErrorText!
        : liveKitConnecting
        ? '미디어 서버에 연결하는 중입니다.'
        : liveKitConnected
        ? '음성 및 화상 연결이 활성화되었습니다.'
        : '음성 채널에 참가했습니다.';
    return Container(
      key: const ValueKey('azoom-voice-room-status-panel'),
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
      decoration: BoxDecoration(
        color: _voiceRoomPanel,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _voiceRoomBorder),
      ),
      child: Row(
        children: [
          Icon(
            mediaErrorText == null ? Icons.auto_awesome : Icons.error_outline,
            color: mediaErrorText == null
                ? _avaAccent
                : const Color(0xFFFFA5AB),
            size: 36,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _voiceRoomText,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 16),
          const _VoiceRoomActionButton(icon: Icons.group_add, label: '초대하기'),
          const SizedBox(width: 10),
          const _VoiceRoomActionButton(icon: Icons.apps, label: '활동 선택'),
        ],
      ),
    );
  }
}

class _VoiceRoomActionButton extends StatelessWidget {
  const _VoiceRoomActionButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: _voiceRoomText,
          side: const BorderSide(color: _voiceRoomBorder),
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
        ),
        icon: Icon(icon, size: 19),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _VoiceRoomControlDock extends StatelessWidget {
  const _VoiceRoomControlDock({
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.liveKitRoom,
    required this.mediaControlsEnabled,
    required this.cameraUnavailableReason,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onToggleCamera,
    required this.onCameraUnavailable,
    required this.onSelectAudioInput,
    required this.onSelectAudioOutput,
    required this.onSelectCameraInput,
    required this.outputVolume,
    required this.onOutputVolumeChanged,
    required this.onToggleScreenShare,
    required this.onLeave,
  });

  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool cameraBusy;
  final lk.Room? liveKitRoom;
  final bool mediaControlsEnabled;
  final String? cameraUnavailableReason;
  final bool screenSharing;
  final bool screenShareBusy;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleCamera;
  final VoidCallback onCameraUnavailable;
  final ValueChanged<lk.MediaDevice> onSelectAudioInput;
  final ValueChanged<lk.MediaDevice> onSelectAudioOutput;
  final ValueChanged<lk.MediaDevice> onSelectCameraInput;
  final double outputVolume;
  final ValueChanged<double> onOutputVolumeChanged;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final cameraUnavailable = cameraUnavailableReason != null && !cameraEnabled;
    return Container(
      key: const ValueKey('azoom-voice-room-controls'),
      height: 88,
      decoration: const BoxDecoration(
        color: _voiceRoomBottom,
        border: Border(top: BorderSide(color: _voiceRoomBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _VoiceSplitMenuControl(
            key: const ValueKey('azoom-mic-device-control'),
            tooltip: micEnabled ? '마이크 끄기' : '마이크 켜기',
            kind: _VoiceDeviceMenuKind.microphone,
            icon: micEnabled ? Icons.mic : Icons.mic_off,
            selected: !micEnabled,
            enabled: mediaControlsEnabled,
            roomStyle: true,
            liveKitRoom: liveKitRoom,
            micEnabled: micEnabled,
            deafened: deafened,
            outputVolume: outputVolume,
            onMainTap: onToggleMic,
            onToggleDeafen: onToggleDeafen,
            onSelectAudioInput: onSelectAudioInput,
            onSelectAudioOutput: onSelectAudioOutput,
            onOutputVolumeChanged: onOutputVolumeChanged,
          ),
          const SizedBox(width: 12),
          _VoiceControlButton(
            tooltip: deafened ? '소리 듣기' : '소리 끄기',
            icon: deafened ? Icons.headset_off : Icons.headphones,
            selected: deafened,
            enabled: mediaControlsEnabled,
            roomStyle: true,
            onTap: onToggleDeafen,
          ),
          const SizedBox(width: 12),
          _VoiceSplitMenuControl(
            key: const ValueKey('azoom-camera-device-control'),
            tooltip: cameraUnavailable
                ? '카메라 사용 불가'
                : cameraEnabled
                ? '카메라 끄기'
                : '카메라 켜기',
            kind: _VoiceDeviceMenuKind.camera,
            icon: cameraEnabled ? Icons.videocam : Icons.videocam_off,
            selected: cameraEnabled,
            busy: cameraBusy,
            unavailable: cameraUnavailable,
            enabled: mediaControlsEnabled && !cameraBusy,
            roomStyle: true,
            liveKitRoom: liveKitRoom,
            micEnabled: micEnabled,
            deafened: deafened,
            outputVolume: outputVolume,
            cameraUnavailableReason: cameraUnavailableReason,
            onMainTap: cameraUnavailable ? onCameraUnavailable : onToggleCamera,
            onToggleDeafen: onToggleDeafen,
            onSelectAudioInput: onSelectAudioInput,
            onSelectAudioOutput: onSelectAudioOutput,
            onSelectCameraInput: onSelectCameraInput,
            onOutputVolumeChanged: onOutputVolumeChanged,
          ),
          const SizedBox(width: 12),
          _VoiceControlButton(
            tooltip: screenSharing ? '공유 중지' : '화면 공유',
            icon: Icons.screen_share,
            selected: screenSharing,
            busy: screenShareBusy,
            enabled: mediaControlsEnabled && !screenShareBusy,
            roomStyle: true,
            onTap: onToggleScreenShare,
          ),
          const SizedBox(width: 12),
          _VoiceControlButton(
            tooltip: '연결 끊기',
            icon: Icons.call_end,
            danger: true,
            onTap: onLeave,
          ),
        ],
      ),
    );
  }
}

class _AzoomVoiceSurface extends StatefulWidget {
  const _AzoomVoiceSurface({
    required this.channel,
    required this.currentUser,
    required this.liveKitRoom,
    required this.liveKitConnecting,
    required this.liveKitConnected,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.cameraUnavailableReason,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.fullscreen,
    required this.notivaOpen,
    required this.notivaStarting,
    required this.notivaAudioCaptureActive,
    required this.notivaTranscript,
    required this.notivaErrorText,
    required this.mediaErrorText,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onToggleCamera,
    required this.onCameraUnavailable,
    required this.onSelectAudioInput,
    required this.onSelectAudioOutput,
    required this.onSelectCameraInput,
    required this.outputVolume,
    required this.onOutputVolumeChanged,
    required this.onToggleScreenShare,
    required this.onToggleFullscreen,
    required this.onToggleNotiva,
    required this.onShowParticipants,
    required this.onTriggerFirework,
    required this.onLeave,
  });

  final AzoomVoiceChannelDto channel;
  final PersonProfile currentUser;
  final lk.Room? liveKitRoom;
  final bool liveKitConnecting;
  final bool liveKitConnected;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool cameraBusy;
  final String? cameraUnavailableReason;
  final bool screenSharing;
  final bool screenShareBusy;
  final bool fullscreen;
  final bool notivaOpen;
  final bool notivaStarting;
  final bool notivaAudioCaptureActive;
  final AzoomMeetingTranscriptDto? notivaTranscript;
  final String? notivaErrorText;
  final String? mediaErrorText;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleCamera;
  final VoidCallback onCameraUnavailable;
  final ValueChanged<lk.MediaDevice> onSelectAudioInput;
  final ValueChanged<lk.MediaDevice> onSelectAudioOutput;
  final ValueChanged<lk.MediaDevice> onSelectCameraInput;
  final double outputVolume;
  final ValueChanged<double> onOutputVolumeChanged;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleNotiva;
  final VoidCallback onShowParticipants;
  final VoidCallback onTriggerFirework;
  final VoidCallback onLeave;

  @override
  State<_AzoomVoiceSurface> createState() => _AzoomVoiceSurfaceState();
}

class _AzoomVoiceSurfaceState extends State<_AzoomVoiceSurface> {
  bool _controlsVisible = false;
  bool _pointerInsideSurface = false;
  int _openDeviceMenuCount = 0;
  String? _spotlightParticipantKey;
  Timer? _controlsRevealTimer;

  bool get _controlsLocked => _openDeviceMenuCount > 0;

  @override
  void didUpdateWidget(covariant _AzoomVoiceSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _spotlightParticipantKey = null;
    }
    if (!oldWidget.fullscreen && widget.fullscreen) {
      _setControlsVisible(true, autoHide: true);
    }
  }

  @override
  void dispose() {
    _controlsRevealTimer?.cancel();
    super.dispose();
  }

  void _setControlsVisible(bool visible, {bool autoHide = false}) {
    if (!visible && _pointerInsideSurface) {
      _controlsRevealTimer?.cancel();
      return;
    }
    if (!visible && _controlsLocked) {
      _controlsRevealTimer?.cancel();
      if (!_controlsVisible) {
        setState(() {
          _controlsVisible = true;
        });
      }
      return;
    }
    if (visible && _controlsLocked) {
      autoHide = false;
    }
    if (!autoHide) {
      _controlsRevealTimer?.cancel();
    }
    if (_controlsVisible == visible) {
      if (visible && autoHide) {
        _scheduleControlsHide();
      }
      return;
    }
    setState(() {
      _controlsVisible = visible;
    });
    if (visible && autoHide) {
      _scheduleControlsHide();
    }
  }

  void _scheduleControlsHide() {
    _scheduleControlsHideAfter(const Duration(milliseconds: 1800));
  }

  void _scheduleControlsHideAfter(Duration delay) {
    if (_controlsLocked) {
      return;
    }
    _controlsRevealTimer?.cancel();
    _controlsRevealTimer = Timer(delay, () {
      if (mounted && !_pointerInsideSurface && !_controlsLocked) {
        _setControlsVisible(false);
      }
    });
  }

  void _handleDeviceMenuOpenChanged(bool open) {
    _controlsRevealTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _openDeviceMenuCount = (_openDeviceMenuCount + (open ? 1 : -1))
          .clamp(0, 8)
          .toInt();
      if (_openDeviceMenuCount > 0) {
        _controlsVisible = true;
      }
    });
  }

  void _toggleParticipantSpotlight(String participantKey) {
    setState(() {
      _spotlightParticipantKey = _spotlightParticipantKey == participantKey
          ? null
          : participantKey;
    });
  }

  @override
  Widget build(BuildContext context) {
    final liveParticipants = _liveParticipants(
      widget.liveKitRoom,
      widget.channel.participants,
      widget.currentUser,
    );
    final participantCount = liveParticipants.isNotEmpty
        ? liveParticipants.length
        : widget.channel.participants.length.clamp(1, 50);
    return Listener(
      behavior: HitTestBehavior.translucent,
      child: MouseRegion(
        opaque: true,
        onEnter: (_) {
          _pointerInsideSurface = true;
          _setControlsVisible(true);
        },
        onHover: (_) {
          _pointerInsideSurface = true;
          _setControlsVisible(true);
        },
        onExit: (_) {
          _pointerInsideSurface = false;
          _scheduleControlsHideAfter(const Duration(milliseconds: 260));
        },
        child: ColoredBox(
          key: const ValueKey('azoom-voice-surface'),
          color: _stageBackground,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              fit: StackFit.expand,
              children: [
                _VoiceGrid(
                  channel: widget.channel,
                  currentUser: widget.currentUser,
                  liveParticipants: liveParticipants,
                  liveKitConnected: widget.liveKitConnected,
                  liveKitConnecting: widget.liveKitConnecting,
                  mediaErrorText: widget.mediaErrorText,
                  fullscreen: widget.fullscreen,
                  showLabels: _controlsVisible,
                  spotlightParticipantKey: _spotlightParticipantKey,
                  onParticipantSelected: _toggleParticipantSpotlight,
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _channelHeaderHeight,
                  child: _AzoomVoiceHeader(
                    visible: _controlsVisible,
                    channelName: widget.channel.name,
                    count: participantCount,
                    notivaOpen: widget.notivaOpen,
                    onNotivaPressed: widget.onToggleNotiva,
                    onParticipantsPressed: widget.onShowParticipants,
                  ),
                ),
                if (widget.notivaOpen)
                  Positioned(
                    top: _channelHeaderHeight + 12,
                    right: 14,
                    bottom: 112,
                    width: widget.fullscreen ? 360 : 330,
                    child: _NotivaAiPanel(
                      starting: widget.notivaStarting,
                      active: widget.notivaAudioCaptureActive,
                      errorText: widget.notivaErrorText,
                      transcript: widget.notivaTranscript,
                      onClose: widget.onToggleNotiva,
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _VoiceControlsBar(
                    visible: _controlsVisible,
                    micEnabled: widget.micEnabled,
                    deafened: widget.deafened,
                    cameraEnabled: widget.cameraEnabled,
                    cameraBusy: widget.cameraBusy,
                    liveKitRoom: widget.liveKitRoom,
                    mediaControlsEnabled: widget.liveKitConnected,
                    cameraUnavailableReason: widget.cameraUnavailableReason,
                    screenSharing: widget.screenSharing,
                    screenShareBusy: widget.screenShareBusy,
                    fullscreen: widget.fullscreen,
                    onToggleMic: widget.onToggleMic,
                    onToggleDeafen: widget.onToggleDeafen,
                    onToggleCamera: widget.onToggleCamera,
                    onCameraUnavailable: widget.onCameraUnavailable,
                    onSelectAudioInput: widget.onSelectAudioInput,
                    onSelectAudioOutput: widget.onSelectAudioOutput,
                    onSelectCameraInput: widget.onSelectCameraInput,
                    outputVolume: widget.outputVolume,
                    onOutputVolumeChanged: widget.onOutputVolumeChanged,
                    onToggleScreenShare: widget.onToggleScreenShare,
                    onToggleFullscreen: widget.onToggleFullscreen,
                    onTriggerFirework: widget.onTriggerFirework,
                    onLeave: widget.onLeave,
                    onDeviceMenuOpenChanged: _handleDeviceMenuOpenChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AzoomVoiceHeader extends StatelessWidget {
  const _AzoomVoiceHeader({
    required this.visible,
    required this.channelName,
    required this.count,
    required this.notivaOpen,
    required this.onNotivaPressed,
    required this.onParticipantsPressed,
  });

  final bool visible;
  final String channelName;
  final int count;
  final bool notivaOpen;
  final VoidCallback onNotivaPressed;
  final VoidCallback onParticipantsPressed;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ClipRect(
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            key: const ValueKey('azoom-voice-header-slide'),
            duration: const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            offset: visible ? Offset.zero : const Offset(0, -1.15),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: visible ? 1 : 0,
              child: Container(
                height: _channelHeaderHeight,
                decoration: const BoxDecoration(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.volume_up,
                      color: _stageMutedText,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      channelName,
                      key: const ValueKey('azoom-voice-title'),
                      style: const TextStyle(
                        color: _stageText,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$count\uBA85',
                      style: const TextStyle(
                        color: _stageMutedText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _VoiceHeaderIcon(
                      icon: Icons.chat_bubble,
                      selected: notivaOpen,
                      onTap: onNotivaPressed,
                    ),
                    const SizedBox(width: 10),
                    _VoiceHeaderIcon(
                      icon: Icons.people,
                      selected: false,
                      onTap: onParticipantsPressed,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceHeaderIcon extends StatelessWidget {
  const _VoiceHeaderIcon({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Notiva AI',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            color: selected ? _stageText : _stageMutedText,
            size: 22,
          ),
        ),
      ),
    );
  }
}

String _meetingTranscriptMenuLabel(AzoomMeetingTranscriptSummaryDto item) {
  if (item.status == 'PROCESSING') {
    return '\uBCC0\uD658\uC911';
  }
  if (item.status == 'FAILED') {
    return '\uC2E4\uD328';
  }
  if (item.kind == 'BATCH_AUDIO') {
    return '\uD1B5\uD30C\uC77C';
  }
  return '\uC2E4\uC2DC\uAC04';
}

class _NotivaTranscriptMenuButton extends StatelessWidget {
  const _NotivaTranscriptMenuButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: _stageText,
          backgroundColor: selected ? _discordSidebarSelected : _stageControl,
          disabledBackgroundColor: _discordSidebarSelected,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: selected ? _stageMenuBorder : _stageBorder),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: _stageText,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _NotivaAiPanel extends StatelessWidget {
  const _NotivaAiPanel({
    this.title = 'Notiva AI',
    required this.starting,
    required this.active,
    required this.errorText,
    required this.transcript,
    this.relatedTranscripts = const [],
    this.onTranscriptSelected,
    required this.onClose,
  });

  final String title;
  final bool starting;
  final bool active;
  final String? errorText;
  final AzoomMeetingTranscriptDto? transcript;
  final List<AzoomMeetingTranscriptSummaryDto> relatedTranscripts;
  final ValueChanged<AzoomMeetingTranscriptSummaryDto>? onTranscriptSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final utterances =
        transcript?.utterances ?? const <AzoomMeetingUtteranceDto>[];
    final statusColor = errorText != null
        ? _discordDanger
        : starting || !active
        ? const Color(0xFFF0B232)
        : _discordSidebarGreen;
    final transcriptMenuItems =
        transcript != null && onTranscriptSelected != null
        ? _meetingTranscriptMenuItems(
            transcript!,
            _matchingMeetingTranscripts(transcript!, relatedTranscripts),
          )
        : const <AzoomMeetingTranscriptSummaryDto>[];
    return DecoratedBox(
      key: const ValueKey('azoom-notiva-ai-panel'),
      decoration: BoxDecoration(
        color: _stageMenu.withValues(alpha: 0.96),
        border: Border.all(color: _stageMenuBorder),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _stageMenuBorder)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: _avaAccent, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _stageText,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.35),
                              blurRadius: 7,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                for (final item in transcriptMenuItems) ...[
                  const SizedBox(width: 6),
                  _NotivaTranscriptMenuButton(
                    label: _meetingTranscriptMenuLabel(item),
                    selected: item.id == transcript?.id,
                    onTap: item.id == transcript?.id
                        ? null
                        : () => onTranscriptSelected?.call(item),
                  ),
                ],
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: const Icon(
                    Icons.close,
                    color: _stageMutedText,
                    size: 19,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                if (starting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _avaAccent),
                  );
                }
                if (utterances.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        '현재 음성채널의 실시간 텍스트가 여기에 표시됩니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _stageMutedText,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  itemCount: utterances.length,
                  itemBuilder: (context, index) {
                    final utterance = utterances[utterances.length - 1 - index];
                    final speakerName = utterance.speakerName.trim().isEmpty
                        ? 'Unknown'
                        : utterance.speakerName.trim();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: _avaAccentDeep,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              _notivaSpeakerInitial(speakerName),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        speakerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _stageText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatTranscriptClock(
                                        utterance.startedAt,
                                      ),
                                      style: const TextStyle(
                                        color: _stageMutedText,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _stagePanel,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _stageBorder),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      11,
                                      8,
                                      11,
                                      9,
                                    ),
                                    child: Text(
                                      utterance.content,
                                      style: const TextStyle(
                                        color: _stageText,
                                        fontSize: 13,
                                        height: 1.36,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

enum _VoiceTileMode { grid, spotlight, thumbnail }

class _VoiceGridParticipant {
  const _VoiceGridParticipant({required this.key, required this.builder});

  final String key;
  final Widget Function(_VoiceTileMode mode, bool selected) builder;
}

class _VoiceGrid extends StatelessWidget {
  const _VoiceGrid({
    required this.channel,
    required this.currentUser,
    required this.liveParticipants,
    required this.liveKitConnected,
    required this.liveKitConnecting,
    required this.mediaErrorText,
    required this.fullscreen,
    required this.showLabels,
    required this.spotlightParticipantKey,
    required this.onParticipantSelected,
  });

  final AzoomVoiceChannelDto channel;
  final PersonProfile currentUser;
  final List<_LiveParticipantView> liveParticipants;
  final bool liveKitConnected;
  final bool liveKitConnecting;
  final String? mediaErrorText;
  final bool fullscreen;
  final bool showLabels;
  final String? spotlightParticipantKey;
  final ValueChanged<String> onParticipantSelected;

  @override
  Widget build(BuildContext context) {
    final fallbackParticipants = channel.participants.isEmpty
        ? [_participantFromProfile(currentUser)]
        : channel.participants;
    final participantItems = liveParticipants.isNotEmpty
        ? [for (final view in liveParticipants) _liveParticipantItem(view)]
        : [
            for (final participant in fallbackParticipants)
              _presenceParticipantItem(participant),
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final spotlightItem = _spotlightItem(participantItems);
        if (spotlightItem != null) {
          return _buildSpotlightLayout(
            constraints: constraints,
            selectedItem: spotlightItem,
            participants: participantItems,
          );
        }

        final activityTile = _VoiceActivityPanel(
          liveKitConnecting: liveKitConnecting,
          liveKitConnected: liveKitConnected,
          mediaErrorText: mediaErrorText,
        );
        final tiles = <Widget>[
          for (final item in participantItems)
            item.builder(_VoiceTileMode.grid, false),
          activityTile,
        ];

        if (!fullscreen && tiles.length == 2) {
          return _buildStackedPair(
            constraints: constraints,
            first: tiles.first,
            second: tiles.last,
          );
        }

        return _buildTileGrid(
          constraints: constraints,
          tiles: tiles,
          fullscreen: fullscreen,
        );
      },
    );
  }

  _VoiceGridParticipant _liveParticipantItem(_LiveParticipantView view) {
    final participantKey = _liveParticipantKey(view);
    return _VoiceGridParticipant(
      key: participantKey,
      builder: (mode, selected) => _VoiceParticipantInteractionFrame(
        key: ValueKey(
          'azoom-live-participant-frame-$participantKey-${mode.name}',
        ),
        speaking: view.participant.isSpeaking,
        selected: selected,
        compact: mode == _VoiceTileMode.thumbnail,
        onTap: () => onParticipantSelected(participantKey),
        child: _LiveParticipantTile(
          view: view,
          showName: mode == _VoiceTileMode.thumbnail ? false : showLabels,
          avatarSize: _avatarSizeFor(mode),
        ),
      ),
    );
  }

  _VoiceGridParticipant _presenceParticipantItem(
    AzoomVoiceParticipantDto participant,
  ) {
    final participantKey = _presenceParticipantKey(participant);
    return _VoiceGridParticipant(
      key: participantKey,
      builder: (mode, selected) => _VoiceParticipantInteractionFrame(
        key: ValueKey(
          'azoom-presence-participant-frame-$participantKey-${mode.name}',
        ),
        speaking: false,
        selected: selected,
        compact: mode == _VoiceTileMode.thumbnail,
        onTap: () => onParticipantSelected(participantKey),
        child: _VoiceParticipantTile(
          participant: participant,
          connected: liveKitConnected,
          showName: mode == _VoiceTileMode.thumbnail ? false : showLabels,
          avatarSize: _avatarSizeFor(mode),
        ),
      ),
    );
  }

  _VoiceGridParticipant? _spotlightItem(
    List<_VoiceGridParticipant> participants,
  ) {
    final key = spotlightParticipantKey;
    if (key == null) {
      return null;
    }
    for (final participant in participants) {
      if (participant.key == key) {
        return participant;
      }
    }
    return null;
  }

  double _avatarSizeFor(_VoiceTileMode mode) {
    return switch (mode) {
      _VoiceTileMode.spotlight => 78,
      _VoiceTileMode.thumbnail => 56,
      _VoiceTileMode.grid => 58,
    };
  }

  Widget _buildSpotlightLayout({
    required BoxConstraints constraints,
    required _VoiceGridParticipant selectedItem,
    required List<_VoiceGridParticipant> participants,
  }) {
    const stripGap = 10.0;
    final thumbnailHeight = constraints.maxWidth < 620 ? 86.0 : 110.0;
    final horizontalMargin = constraints.maxWidth >= 900 ? 88.0 : 24.0;
    final maxMainWidth = math.max(
      1.0,
      constraints.maxWidth - (horizontalMargin * 2),
    );
    final verticalReserve =
        thumbnailHeight + stripGap + (fullscreen ? 96.0 : 48.0);
    final maxMainHeight = math.max(
      140.0,
      constraints.maxHeight - verticalReserve,
    );
    final mainHeight = math.min(maxMainWidth * 9 / 16, maxMainHeight);
    final mainWidth = mainHeight * 16 / 9;

    return Center(
      key: const ValueKey('azoom-voice-spotlight-layout'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: mainWidth,
            height: mainHeight,
            child: selectedItem.builder(_VoiceTileMode.spotlight, true),
          ),
          const SizedBox(height: stripGap),
          _buildSpotlightStrip(
            constraints: constraints,
            participants: participants,
            selectedKey: selectedItem.key,
            thumbnailHeight: thumbnailHeight,
          ),
        ],
      ),
    );
  }

  Widget _buildSpotlightStrip({
    required BoxConstraints constraints,
    required List<_VoiceGridParticipant> participants,
    required String selectedKey,
    required double thumbnailHeight,
  }) {
    const gap = 8.0;
    final thumbnailWidth = thumbnailHeight * 16 / 9;
    final contentWidth =
        (participants.length * thumbnailWidth) +
        (math.max(0, participants.length - 1) * gap);
    final viewportWidth = math.min(
      math.max(1.0, constraints.maxWidth - 32),
      math.max(1.0, contentWidth),
    );
    return Center(
      key: const ValueKey('azoom-voice-spotlight-strip'),
      child: SizedBox(
        width: viewportWidth,
        height: thumbnailHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: participants.length,
          separatorBuilder: (_, _) => const SizedBox(width: gap),
          itemBuilder: (context, index) {
            final participant = participants[index];
            return SizedBox(
              width: thumbnailWidth,
              height: thumbnailHeight,
              child: participant.builder(
                _VoiceTileMode.thumbnail,
                participant.key == selectedKey,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStackedPair({
    required BoxConstraints constraints,
    required Widget first,
    required Widget second,
  }) {
    final maxTileWidth = (constraints.maxWidth - 32)
        .clamp(280.0, 490.0)
        .toDouble();
    final maxTileHeight = ((constraints.maxHeight - 32) / 2)
        .clamp(160.0, double.infinity)
        .toDouble();
    final tileHeight = (maxTileWidth * 9 / 16)
        .clamp(160.0, maxTileHeight)
        .toDouble();
    final tileWidth = tileHeight * 16 / 9;
    return Center(
      child: SizedBox(
        width: tileWidth,
        height: (tileHeight * 2) + 8,
        child: Column(
          children: [
            Expanded(child: first),
            const SizedBox(height: 8),
            Expanded(child: second),
          ],
        ),
      ),
    );
  }

  Widget _buildTileGrid({
    required BoxConstraints constraints,
    required List<Widget> tiles,
    required bool fullscreen,
  }) {
    const gap = 8.0;
    final columns = _gridColumns(
      tileCount: tiles.length,
      width: constraints.maxWidth,
      fullscreen: fullscreen,
    );
    final rows = (tiles.length / columns).ceil();
    final maxWidth = fullscreen
        ? math.max(1.0, constraints.maxWidth - 24)
        : math.min(math.max(1.0, constraints.maxWidth - 32), 980.0);
    final maxHeight = fullscreen
        ? math.max(1.0, constraints.maxHeight - 128)
        : math.max(1.0, constraints.maxHeight - 32);
    final cellWidthByWidth = math.max(
      1.0,
      (maxWidth - (gap * (columns - 1))) / columns,
    );
    final cellHeightByWidth = cellWidthByWidth * 9 / 16;
    final cellHeightByHeight = math.max(
      1.0,
      (maxHeight - (gap * (rows - 1))) / rows,
    );
    final cellHeight = math.min(cellHeightByWidth, cellHeightByHeight);
    final cellWidth = cellHeight * 16 / 9;
    final gridWidth = (cellWidth * columns) + (gap * (columns - 1));
    final gridHeight = (cellHeight * rows) + (gap * (rows - 1));

    return Center(
      child: SizedBox(
        width: gridWidth,
        height: gridHeight,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            childAspectRatio: 16 / 9,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, index) => tiles[index],
        ),
      ),
    );
  }

  int _gridColumns({
    required int tileCount,
    required double width,
    required bool fullscreen,
  }) {
    if (tileCount <= 1 || width < 620) {
      return 1;
    }
    if (tileCount <= 4) {
      return 2;
    }
    if (fullscreen && width >= 1500) {
      return 3;
    }
    return 2;
  }
}

class _VoiceParticipantInteractionFrame extends StatelessWidget {
  const _VoiceParticipantInteractionFrame({
    super.key,
    required this.child,
    required this.speaking,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final Widget child;
  final bool speaking;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = speaking
        ? _discordSpeaking
        : selected
        ? _stageMutedText.withValues(alpha: 0.64)
        : Colors.transparent;
    final borderWidth = speaking
        ? 4.0
        : selected
        ? 1.5
        : 0.0;
    final radius = BorderRadius.circular(compact ? 5 : 6);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: radius),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LiveParticipantTile extends StatelessWidget {
  const _LiveParticipantTile({
    required this.view,
    required this.showName,
    required this.avatarSize,
  });

  final _LiveParticipantView view;
  final bool showName;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final trackView = _videoTrackFor(view.participant);
    final name = _liveParticipantDisplayName(view);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: _stageTile,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (trackView != null)
              lk.VideoTrackRenderer(
                trackView.track,
                fit: trackView.isScreenShare
                    ? lk.VideoViewFit.contain
                    : lk.VideoViewFit.cover,
              )
            else
              Center(
                child: _AzoomAvatar(
                  label: _avatarLabel(name),
                  color: _liveParticipantColor(view),
                  imageUrl: _liveParticipantImageUrl(view),
                  size: avatarSize,
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              left: 12,
              bottom: showName ? 12 : -40,
              child: _VoiceNamePill(
                name: view.isLocal ? '$name (나)' : name,
                muted: !view.participant.isMicrophoneEnabled(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceParticipantTile extends StatelessWidget {
  const _VoiceParticipantTile({
    required this.participant,
    required this.connected,
    required this.showName,
    this.avatarSize = 58,
  });

  final AzoomVoiceParticipantDto participant;
  final bool connected;
  final bool showName;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final displayName = participant.displayName;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        color: _stageTile,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: _AzoomAvatar(
                label: _avatarLabel(displayName),
                color: _colorFromHex(participant.avatarColor),
                imageUrl: participant.avatarImageUrl,
                size: avatarSize,
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              left: 12,
              bottom: showName ? 12 : -40,
              child: _VoiceNamePill(
                name: displayName,
                muted: participant.muted,
                connected: connected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceNamePill extends StatelessWidget {
  const _VoiceNamePill({
    required this.name,
    required this.muted,
    this.connected = true,
  });

  final String name;
  final bool muted;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (muted) ...const [
            Icon(Icons.mic_off, color: _stageMutedText, size: 14),
            SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              connected ? name : '$name \uC5F0\uACB0 \uB300\uAE30',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _stageText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceActivityPanel extends StatelessWidget {
  const _VoiceActivityPanel({
    required this.liveKitConnecting,
    required this.liveKitConnected,
    required this.mediaErrorText,
  });

  final bool liveKitConnecting;
  final bool liveKitConnected;
  final String? mediaErrorText;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context) != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_discordActivityTop, _discordActivityBottom],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(
                bottom: 72,
                child: Center(
                  child: _AvaDarkActivityArt(
                    key: ValueKey('azoom-ava-dark-activity-art'),
                  ),
                ),
              ),
              if (mediaErrorText != null ||
                  liveKitConnecting ||
                  liveKitConnected)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Icon(
                    mediaErrorText != null
                        ? Icons.error_outline
                        : liveKitConnected
                        ? Icons.check_circle
                        : Icons.sync,
                    color: _stageMutedText.withValues(alpha: 0.72),
                    size: 18,
                  ),
                ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _VoiceActionButton(
                      icon: Icons.group_add,
                      label: '음성으로 초대하기',
                    ),
                    SizedBox(width: 8),
                    _VoiceActionButton(icon: Icons.apps, label: '활동 선택하기'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final status = mediaErrorText != null
        ? mediaErrorText!
        : liveKitConnecting
        ? '미디어 서버에 연결하는 중입니다.'
        : liveKitConnected
        ? '음성 및 화상 연결이 활성화되었습니다.'
        : '음성 채널에 참가했습니다.';
    return Container(
      height: 112,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _stagePanel,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _stageBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Icon(
            mediaErrorText == null ? Icons.auto_awesome : Icons.error_outline,
            color: mediaErrorText == null
                ? _avaAccent
                : const Color(0xFFFFA5AB),
            size: 34,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _stageText,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _VoiceActionButton(icon: Icons.person_add_alt_1, label: '초대하기'),
          const SizedBox(width: 8),
          _VoiceActionButton(icon: Icons.apps, label: '활동 선택'),
        ],
      ),
    );
  }
}

class _AvaDarkActivityArt extends StatelessWidget {
  const _AvaDarkActivityArt({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(1.0, constraints.maxWidth);
        final availableHeight = math.max(1.0, constraints.maxHeight);
        return SizedBox(
          width: math.min(availableWidth, 424),
          height: math.min(availableHeight, 266),
          child: const FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 360,
              height: 226,
              child: _AvaDarkBrandLockup(),
            ),
          ),
        );
      },
    );
  }
}

class _AvaDarkBrandLockup extends StatelessWidget {
  const _AvaDarkBrandLockup();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: RadialGradient(
          center: const Alignment(0.0, -0.20),
          radius: 0.92,
          colors: [
            _avaAccent.withValues(alpha: 0.18),
            _stageBackground.withValues(alpha: 0.88),
            Colors.transparent,
          ],
          stops: const [0, 0.62, 1],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 268,
            height: 82,
            child: CustomPaint(painter: _AvaDarkLogoPainter()),
          ),
          const SizedBox(height: 13),
          ShaderMask(
            shaderCallback: (bounds) {
              return const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFD8DFFF)],
              ).createShader(bounds);
            },
            child: const Text(
              'AVA',
              style: TextStyle(
                color: Colors.white,
                fontSize: 54,
                height: 0.92,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Abbas '),
                TextSpan(
                  text: 'Vanguard',
                  style: TextStyle(color: const Color(0xFF7F65FF)),
                ),
                const TextSpan(text: ' AI'),
              ],
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFE7EBFF),
              fontSize: 16,
              height: 1.05,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '앞선 기술로, 더 나은 미래를 만듭니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFAEB7D6),
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvaDarkLogoPainter extends CustomPainter {
  const _AvaDarkLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 268;
    canvas.save();
    canvas.scale(scale);

    final glow = Paint()
      ..color = const Color(0xFF6B60FF).withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final line = Paint()
      ..color = const Color(0xFFEFF3FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final mark = Path()
      ..moveTo(12, 72)
      ..lineTo(63, 10)
      ..quadraticBezierTo(75, -4, 88, 12)
      ..lineTo(127, 73)
      ..quadraticBezierTo(134, 83, 145, 83)
      ..quadraticBezierTo(156, 83, 163, 73)
      ..lineTo(202, 12)
      ..quadraticBezierTo(215, -4, 227, 10)
      ..lineTo(256, 72);
    canvas.drawPath(mark, glow);
    canvas.drawPath(mark, line);

    final leftDot = Paint()..color = const Color(0xFF7B61FF);
    final rightDot = Paint()..color = const Color(0xFF2387F2);
    canvas.drawCircle(const Offset(91, 41), 6.4, leftDot);
    canvas.drawCircle(const Offset(213, 41), 6.4, rightDot);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _VoiceActionButton extends StatelessWidget {
  const _VoiceActionButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        onPressed: () {},
        style: OutlinedButton.styleFrom(
          foregroundColor: _stageText,
          side: const BorderSide(color: _stageBorder),
          backgroundColor: _stageControl.withValues(alpha: 0.84),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _VoiceControlsBar extends StatelessWidget {
  const _VoiceControlsBar({
    required this.visible,
    required this.micEnabled,
    required this.deafened,
    required this.cameraEnabled,
    required this.cameraBusy,
    required this.liveKitRoom,
    required this.mediaControlsEnabled,
    required this.cameraUnavailableReason,
    required this.screenSharing,
    required this.screenShareBusy,
    required this.fullscreen,
    required this.onToggleMic,
    required this.onToggleDeafen,
    required this.onToggleCamera,
    required this.onCameraUnavailable,
    required this.onSelectAudioInput,
    required this.onSelectAudioOutput,
    required this.onSelectCameraInput,
    required this.outputVolume,
    required this.onOutputVolumeChanged,
    required this.onToggleScreenShare,
    required this.onToggleFullscreen,
    required this.onTriggerFirework,
    required this.onLeave,
    this.onDeviceMenuOpenChanged,
  });

  final bool visible;
  final bool micEnabled;
  final bool deafened;
  final bool cameraEnabled;
  final bool cameraBusy;
  final lk.Room? liveKitRoom;
  final bool mediaControlsEnabled;
  final String? cameraUnavailableReason;
  final bool screenSharing;
  final bool screenShareBusy;
  final bool fullscreen;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleDeafen;
  final VoidCallback onToggleCamera;
  final VoidCallback onCameraUnavailable;
  final ValueChanged<lk.MediaDevice> onSelectAudioInput;
  final ValueChanged<lk.MediaDevice> onSelectAudioOutput;
  final ValueChanged<lk.MediaDevice> onSelectCameraInput;
  final double outputVolume;
  final ValueChanged<double> onOutputVolumeChanged;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onTriggerFirework;
  final VoidCallback onLeave;
  final ValueChanged<bool>? onDeviceMenuOpenChanged;

  @override
  Widget build(BuildContext context) {
    final cameraUnavailable = cameraUnavailableReason != null && !cameraEnabled;
    if (MediaQuery.maybeOf(context) != null) {
      return ExcludeSemantics(
        child: ClipRect(
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              key: const ValueKey('azoom-voice-controls-slide'),
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              offset: visible ? Offset.zero : const Offset(0, 1.15),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                opacity: visible ? 1 : 0,
                child: SizedBox(
                  key: const ValueKey('azoom-voice-controls-shell'),
                  height: _stageControlsOverlayHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 16,
                        bottom: _stageControlsBottomInset,
                        child: _DiscordIconButton(
                          tooltip: '음성으로 초대하기',
                          icon: Icons.group_add,
                          onTap: () {},
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: _stageControlsBottomInset,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DiscordControlGroup(
                                children: [
                                  _VoiceSplitMenuControl(
                                    key: const ValueKey(
                                      'azoom-mic-device-control',
                                    ),
                                    tooltip: micEnabled ? '마이크 끄기' : '마이크 켜기',
                                    kind: _VoiceDeviceMenuKind.microphone,
                                    icon: micEnabled
                                        ? Icons.mic
                                        : Icons.mic_off,
                                    selected: !micEnabled,
                                    enabled: mediaControlsEnabled,
                                    liveKitRoom: liveKitRoom,
                                    micEnabled: micEnabled,
                                    deafened: deafened,
                                    outputVolume: outputVolume,
                                    onMainTap: onToggleMic,
                                    onToggleDeafen: onToggleDeafen,
                                    onSelectAudioInput: onSelectAudioInput,
                                    onSelectAudioOutput: onSelectAudioOutput,
                                    onOutputVolumeChanged:
                                        onOutputVolumeChanged,
                                    onMenuOpenChanged: onDeviceMenuOpenChanged,
                                  ),
                                  const SizedBox(width: 8),
                                  _VoiceSplitMenuControl(
                                    key: const ValueKey(
                                      'azoom-camera-device-control',
                                    ),
                                    tooltip: cameraUnavailable
                                        ? '카메라 사용 불가'
                                        : cameraEnabled
                                        ? '카메라 끄기'
                                        : '카메라 켜기',
                                    kind: _VoiceDeviceMenuKind.camera,
                                    icon: cameraEnabled
                                        ? Icons.videocam
                                        : Icons.videocam_off,
                                    selected: cameraEnabled,
                                    busy: cameraBusy,
                                    unavailable: cameraUnavailable,
                                    enabled:
                                        mediaControlsEnabled && !cameraBusy,
                                    liveKitRoom: liveKitRoom,
                                    micEnabled: micEnabled,
                                    deafened: deafened,
                                    outputVolume: outputVolume,
                                    cameraUnavailableReason:
                                        cameraUnavailableReason,
                                    onMainTap: cameraUnavailable
                                        ? onCameraUnavailable
                                        : onToggleCamera,
                                    onToggleDeafen: onToggleDeafen,
                                    onSelectAudioInput: onSelectAudioInput,
                                    onSelectAudioOutput: onSelectAudioOutput,
                                    onSelectCameraInput: onSelectCameraInput,
                                    onOutputVolumeChanged:
                                        onOutputVolumeChanged,
                                    onMenuOpenChanged: onDeviceMenuOpenChanged,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              _DiscordControlGroup(
                                children: [
                                  _VoiceControlButton(
                                    tooltip: screenSharing ? '공유 중지' : '화면 공유',
                                    icon: Icons.screen_share,
                                    selected: screenSharing,
                                    busy: screenShareBusy,
                                    enabled:
                                        mediaControlsEnabled &&
                                        !screenShareBusy,
                                    onTap: onToggleScreenShare,
                                  ),
                                  const SizedBox(width: 8),
                                  _DiscordIconButton(
                                    tooltip: '활동',
                                    icon: Icons.apps,
                                    onTap: () {},
                                  ),
                                  const SizedBox(width: 8),
                                  _DiscordIconButton(
                                    tooltip: '\uC0AC\uC6B4\uB4DC\uBCF4\uB4DC',
                                    icon: Icons.celebration,
                                    onTap: onTriggerFirework,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              _VoiceControlButton(
                                tooltip: '연결 끊기',
                                icon: Icons.call_end,
                                danger: true,
                                onTap: onLeave,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 16,
                        bottom: _stageControlsBottomInset,
                        child: _DiscordIconButton(
                          tooltip: fullscreen ? '전체화면 종료' : '전체화면',
                          icon: fullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          onTap: onToggleFullscreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: _stagePanel,
        border: Border(top: BorderSide(color: _stageBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _VoiceSplitMenuControl(
            key: const ValueKey('azoom-mic-device-control'),
            tooltip: micEnabled ? '마이크 끄기' : '마이크 켜기',
            kind: _VoiceDeviceMenuKind.microphone,
            icon: micEnabled ? Icons.mic : Icons.mic_off,
            selected: !micEnabled,
            enabled: mediaControlsEnabled,
            liveKitRoom: liveKitRoom,
            micEnabled: micEnabled,
            deafened: deafened,
            outputVolume: outputVolume,
            onMainTap: onToggleMic,
            onToggleDeafen: onToggleDeafen,
            onSelectAudioInput: onSelectAudioInput,
            onSelectAudioOutput: onSelectAudioOutput,
            onOutputVolumeChanged: onOutputVolumeChanged,
            onMenuOpenChanged: onDeviceMenuOpenChanged,
          ),
          const SizedBox(width: 10),
          _VoiceControlButton(
            tooltip: deafened ? '소리 듣기' : '소리 끄기',
            icon: deafened ? Icons.headset_off : Icons.headphones,
            selected: deafened,
            enabled: mediaControlsEnabled,
            onTap: onToggleDeafen,
          ),
          const SizedBox(width: 10),
          _VoiceSplitMenuControl(
            key: const ValueKey('azoom-camera-device-control'),
            tooltip: cameraUnavailable
                ? '카메라 사용 불가능'
                : cameraEnabled
                ? '카메라 끄기'
                : '카메라 켜기',
            kind: _VoiceDeviceMenuKind.camera,
            icon: cameraEnabled ? Icons.videocam : Icons.videocam_off,
            selected: cameraEnabled,
            busy: cameraBusy,
            unavailable: cameraUnavailable,
            enabled: mediaControlsEnabled && !cameraBusy,
            liveKitRoom: liveKitRoom,
            micEnabled: micEnabled,
            deafened: deafened,
            outputVolume: outputVolume,
            cameraUnavailableReason: cameraUnavailableReason,
            onMainTap: cameraUnavailable ? onCameraUnavailable : onToggleCamera,
            onToggleDeafen: onToggleDeafen,
            onSelectAudioInput: onSelectAudioInput,
            onSelectAudioOutput: onSelectAudioOutput,
            onSelectCameraInput: onSelectCameraInput,
            onOutputVolumeChanged: onOutputVolumeChanged,
            onMenuOpenChanged: onDeviceMenuOpenChanged,
          ),
          const SizedBox(width: 10),
          _VoiceControlButton(
            tooltip: screenSharing ? '공유 중지' : '화면 공유',
            icon: Icons.screen_share,
            selected: screenSharing,
            busy: screenShareBusy,
            enabled: mediaControlsEnabled && !screenShareBusy,
            onTap: onToggleScreenShare,
          ),
          const SizedBox(width: 10),
          _VoiceControlButton(
            tooltip: '연결 끊기',
            icon: Icons.call_end,
            danger: true,
            onTap: onLeave,
          ),
        ],
      ),
    );
  }
}

class _DiscordControlGroup extends StatelessWidget {
  const _DiscordControlGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _stageControl,
        border: Border.all(color: _stageBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _DiscordIconButton extends StatelessWidget {
  const _DiscordIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 44,
        child: IconButton(
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: _stageControl,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: Icon(icon, color: _stageText, size: 22),
        ),
      ),
    );
  }
}

enum _VoiceDeviceMenuKind { microphone, camera }

class _VoiceSplitMenuControl extends StatefulWidget {
  const _VoiceSplitMenuControl({
    super.key,
    required this.tooltip,
    required this.kind,
    required this.icon,
    required this.onMainTap,
    required this.onToggleDeafen,
    required this.onSelectAudioInput,
    required this.onSelectAudioOutput,
    required this.onOutputVolumeChanged,
    required this.liveKitRoom,
    required this.micEnabled,
    required this.deafened,
    required this.outputVolume,
    this.onSelectCameraInput,
    this.cameraUnavailableReason,
    this.selected = false,
    this.enabled = true,
    this.busy = false,
    this.unavailable = false,
    this.roomStyle = false,
    this.compact = false,
    this.chevronKey,
    this.onMenuOpenChanged,
  });

  final String tooltip;
  final _VoiceDeviceMenuKind kind;
  final IconData icon;
  final VoidCallback onMainTap;
  final VoidCallback onToggleDeafen;
  final ValueChanged<lk.MediaDevice> onSelectAudioInput;
  final ValueChanged<lk.MediaDevice> onSelectAudioOutput;
  final ValueChanged<lk.MediaDevice>? onSelectCameraInput;
  final ValueChanged<double> onOutputVolumeChanged;
  final lk.Room? liveKitRoom;
  final bool micEnabled;
  final bool deafened;
  final double outputVolume;
  final String? cameraUnavailableReason;
  final bool selected;
  final bool enabled;
  final bool busy;
  final bool unavailable;
  final bool roomStyle;
  final bool compact;
  final String? chevronKey;
  final ValueChanged<bool>? onMenuOpenChanged;

  @override
  State<_VoiceSplitMenuControl> createState() => _VoiceSplitMenuControlState();
}

class _VoiceSplitMenuControlState extends State<_VoiceSplitMenuControl> {
  final MenuController _menuController = MenuController();
  Timer? _meterTimer;
  StreamSubscription<List<lk.MediaDevice>>? _deviceSubscription;
  List<lk.MediaDevice> _audioInputs = const [];
  List<lk.MediaDevice> _audioOutputs = const [];
  List<lk.MediaDevice> _videoInputs = const [];
  bool _menuOpen = false;
  bool _loadingDevices = false;
  double _inputLevel = 0;

  @override
  void initState() {
    super.initState();
    _deviceSubscription = lk.Hardware.instance.onDeviceChange.stream.listen((
      _,
    ) {
      if (_menuOpen) {
        unawaited(_loadDevices());
      }
    });
  }

  @override
  void dispose() {
    _meterTimer?.cancel();
    unawaited(_deviceSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final menuWidth = widget.kind == _VoiceDeviceMenuKind.microphone
        ? 286.0
        : 220.0;
    return MenuAnchor(
      controller: _menuController,
      style: _azoomVoiceMenuStyle(menuWidth),
      crossAxisUnconstrained: false,
      alignmentOffset: Offset(
        widget.kind == _VoiceDeviceMenuKind.microphone ? -106 : -74,
        8,
      ),
      onOpen: _handleOpen,
      onClose: _handleClose,
      menuChildren: widget.kind == _VoiceDeviceMenuKind.microphone
          ? _buildMicrophoneMenu(context)
          : _buildCameraMenu(context),
      builder: (context, controller, child) {
        return Tooltip(
          message: widget.tooltip,
          child: _buildSplitButton(controller),
        );
      },
    );
  }

  Widget _buildSplitButton(MenuController controller) {
    final background = widget.compact
        ? Colors.transparent
        : widget.unavailable
        ? (widget.roomStyle ? _voiceRoomBottom : _stagePanel)
        : widget.selected
        ? _avaAccentDeep
        : widget.roomStyle
        ? _voiceRoomControl
        : _stageControl;
    final borderColor = _menuOpen
        ? _avaAccent
        : widget.compact
        ? Colors.transparent
        : widget.roomStyle
        ? _voiceRoomBorder
        : _stageBorder;
    final iconColor = widget.enabled
        ? widget.unavailable
              ? (widget.roomStyle ? _voiceRoomMutedText : _stageMutedText)
              : widget.selected
              ? Colors.white
              : widget.compact
              ? (widget.selected ? _discordSidebarText : _discordSidebarMuted)
              : widget.roomStyle
              ? _voiceRoomText
              : _stageText
        : (widget.compact
                  ? _discordSidebarSubtle
                  : widget.roomStyle
                  ? _voiceRoomMutedText
                  : _stageMutedText)
              .withValues(alpha: 0.56);
    final height = widget.compact ? 32.0 : 44.0;
    final mainWidth = widget.compact ? 28.0 : 44.0;
    final chevronWidth = widget.compact ? 18.0 : 28.0;
    final iconSize = widget.compact ? 19.0 : 22.0;
    final borderRadius = widget.compact ? 4.0 : 11.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: height,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: widget.enabled ? widget.onMainTap : null,
              child: SizedBox(
                width: mainWidth,
                height: height,
                child: Center(
                  child: widget.busy
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              iconColor,
                            ),
                          ),
                        )
                      : Icon(widget.icon, color: iconColor, size: iconSize),
                ),
              ),
            ),
            Container(
              width: 1,
              height: widget.compact ? 20 : 28,
              color: widget.compact
                  ? _discordSidebarBorder
                  : widget.roomStyle
                  ? _voiceRoomBorder
                  : _stageBorder,
            ),
            InkWell(
              key: ValueKey(
                widget.chevronKey ??
                    (widget.kind == _VoiceDeviceMenuKind.microphone
                        ? 'azoom-mic-device-chevron'
                        : 'azoom-camera-device-chevron'),
              ),
              onTap: widget.enabled ? () => _toggleMenu(controller) : null,
              child: SizedBox(
                width: chevronWidth,
                height: height,
                child: Icon(
                  _menuOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: iconColor,
                  size: widget.compact ? 16 : 19,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMicrophoneMenu(BuildContext context) {
    final audioInput = _selectedDevice(
      _audioInputs,
      widget.liveKitRoom?.selectedAudioInputDeviceId ??
          lk.Hardware.instance.selectedAudioInput?.deviceId,
    );
    final audioOutput = _selectedDevice(
      _audioOutputs,
      widget.liveKitRoom?.selectedAudioOutputDeviceId ??
          lk.Hardware.instance.selectedAudioOutput?.deviceId,
    );
    return [
      _AzoomMenuSubmenuButton(
        title: '녹음 장치',
        subtitle: _deviceLabel(audioInput, 'Windows 기본 설정 (마이크)'),
        menuWidth: 380,
        alignmentOffset: const Offset(-2, 0),
        menuChildren: _deviceMenuItems(
          devices: _audioInputs,
          emptyLabel: _loadingDevices ? '장치 검색 중' : '녹음 장치 없음',
          selectedDeviceId: audioInput?.deviceId,
          onSelected: (device) {
            widget.onSelectAudioInput(device);
            setState(() {});
          },
        ),
      ),
      _AzoomMenuSubmenuButton(
        title: '입력 프로필',
        subtitle: '사용자 지정',
        menuWidth: 178,
        alignmentOffset: const Offset(-2, 0),
        menuChildren: [
          _AzoomMenuActionItem(
            title: '사용자 지정',
            selected: true,
            onPressed: () {},
          ),
        ],
      ),
      _AzoomMenuSubmenuButton(
        title: '출력 장치',
        subtitle: _deviceLabel(audioOutput, 'Windows 기본 설정 (출력)'),
        menuWidth: 430,
        alignmentOffset: const Offset(-2, 0),
        menuChildren: _deviceMenuItems(
          devices: _audioOutputs,
          emptyLabel: _loadingDevices ? '장치 검색 중' : '출력 장치 없음',
          selectedDeviceId: audioOutput?.deviceId,
          onSelected: (device) {
            widget.onSelectAudioOutput(device);
            setState(() {});
          },
        ),
      ),
      const _AzoomMenuDivider(),
      const _AzoomMenuSectionLabel('입력 음량'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: _AzoomInputMeter(level: _inputLevel, enabled: widget.micEnabled),
      ),
      const _AzoomMenuSectionLabel('출력 음량'),
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: _avaAccent,
            inactiveTrackColor: _stageBorder.withValues(alpha: 0.62),
            thumbColor: Colors.white,
            overlayColor: _avaAccent.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: widget.outputVolume.clamp(0.0, 1.0).toDouble(),
            onChanged: widget.enabled ? widget.onOutputVolumeChanged : null,
          ),
        ),
      ),
      _AzoomMenuToggleItem(
        title: '헤드셋 음소거',
        value: widget.deafened,
        onPressed: widget.onToggleDeafen,
      ),
      _AzoomMenuActionItem(
        title: '음성 설정',
        trailing: const Icon(Icons.settings, color: _stageMutedText, size: 22),
        closeOnActivate: false,
        onPressed: () => unawaited(_loadDevices()),
      ),
    ];
  }

  List<Widget> _buildCameraMenu(BuildContext context) {
    final camera = _selectedDevice(
      _videoInputs,
      widget.liveKitRoom?.selectedVideoInputDeviceId ??
          lk.Hardware.instance.selectedVideoInput?.deviceId,
    );
    final hasCamera = _videoInputs.isNotEmpty;
    return [
      _AzoomMenuSubmenuButton(
        title: '카메라',
        subtitle: hasCamera ? _deviceLabel(camera, '영상 장치 선택') : '영상 장치 없음',
        highlighted: _menuOpen,
        menuWidth: 188,
        menuChildren: _deviceMenuItems(
          devices: _videoInputs,
          emptyLabel: _loadingDevices ? '장치 검색 중' : '영상 장치 없음',
          selectedDeviceId: camera?.deviceId,
          onSelected: (device) {
            widget.onSelectCameraInput?.call(device);
            setState(() {});
          },
        ),
      ),
      const _AzoomMenuDivider(),
      _AzoomMenuActionItem(
        title: '영상 설정',
        trailing: const Icon(Icons.settings, color: _stageMutedText, size: 22),
        closeOnActivate: false,
        onPressed: () => unawaited(_loadDevices()),
      ),
    ];
  }

  List<Widget> _deviceMenuItems({
    required List<lk.MediaDevice> devices,
    required String emptyLabel,
    required String? selectedDeviceId,
    required ValueChanged<lk.MediaDevice> onSelected,
  }) {
    if (devices.isEmpty) {
      return [_AzoomMenuActionItem(title: emptyLabel, enabled: false)];
    }
    return [
      for (final device in devices)
        _AzoomMenuActionItem(
          title: _deviceLabel(device, '이름 없는 장치'),
          selected: device.deviceId == selectedDeviceId,
          titleMaxLines: 2,
          minHeight: 54,
          trailing: device.deviceId == selectedDeviceId
              ? const Icon(Icons.circle, color: _avaAccent, size: 12)
              : null,
          onPressed: () => onSelected(device),
        ),
    ];
  }

  void _toggleMenu(MenuController controller) {
    if (controller.isOpen) {
      controller.close();
    } else {
      controller.open();
    }
  }

  void _handleOpen() {
    setState(() {
      _menuOpen = true;
    });
    widget.onMenuOpenChanged?.call(true);
    unawaited(_loadDevices());
    if (widget.kind == _VoiceDeviceMenuKind.microphone) {
      _meterTimer?.cancel();
      _meterTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted) {
          return;
        }
        final rawLevel = widget.liveKitRoom?.localParticipant?.audioLevel ?? 0;
        setState(() {
          _inputLevel = widget.micEnabled
              ? rawLevel.clamp(0.0, 1.0).toDouble()
              : 0;
        });
      });
    }
  }

  void _handleClose() {
    _meterTimer?.cancel();
    _meterTimer = null;
    widget.onMenuOpenChanged?.call(false);
    if (!mounted) {
      return;
    }
    setState(() {
      _menuOpen = false;
      _inputLevel = 0;
    });
  }

  Future<void> _loadDevices() async {
    if (_loadingDevices) {
      return;
    }
    setState(() {
      _loadingDevices = true;
    });
    try {
      final hardware = lk.Hardware.instance;
      final audioInputs = await hardware.audioInputs();
      final audioOutputs = await hardware.audioOutputs();
      final videoInputs = await hardware.videoInputs();
      if (!mounted) {
        return;
      }
      setState(() {
        _audioInputs = audioInputs;
        _audioOutputs = audioOutputs;
        _videoInputs = videoInputs;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _audioInputs = const [];
        _audioOutputs = const [];
        _videoInputs = const [];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDevices = false;
        });
      }
    }
  }
}

class _AzoomMenuSubmenuButton extends StatelessWidget {
  const _AzoomMenuSubmenuButton({
    required this.title,
    required this.subtitle,
    required this.menuChildren,
    this.highlighted = false,
    this.menuWidth = 224,
    this.alignmentOffset = const Offset(0, 0),
  });

  final String title;
  final String subtitle;
  final List<Widget> menuChildren;
  final bool highlighted;
  final double menuWidth;
  final Offset alignmentOffset;

  @override
  Widget build(BuildContext context) {
    return SubmenuButton(
      style: _azoomMenuButtonStyle(highlighted: highlighted),
      menuStyle: _azoomVoiceMenuStyle(menuWidth),
      alignmentOffset: alignmentOffset,
      submenuIcon: const WidgetStatePropertyAll<Widget?>(
        Icon(Icons.chevron_right, color: _stageMutedText, size: 22),
      ),
      menuChildren: menuChildren,
      child: _AzoomMenuText(title: title, subtitle: subtitle),
    );
  }
}

class _AzoomMenuActionItem extends StatelessWidget {
  const _AzoomMenuActionItem({
    required this.title,
    this.trailing,
    this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.closeOnActivate = true,
    this.titleMaxLines = 1,
    this.minHeight = 48,
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final bool selected;
  final bool enabled;
  final bool closeOnActivate;
  final int titleMaxLines;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
      closeOnActivate: closeOnActivate,
      onPressed: enabled ? onPressed : null,
      style: _azoomMenuButtonStyle(highlighted: selected, minHeight: minHeight),
      child: Row(
        children: [
          Expanded(
            child: _AzoomMenuText(title: title, titleMaxLines: titleMaxLines),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class _AzoomMenuToggleItem extends StatelessWidget {
  const _AzoomMenuToggleItem({
    required this.title,
    required this.value,
    required this.onPressed,
  });

  final String title;
  final bool value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MenuItemButton(
      closeOnActivate: false,
      onPressed: onPressed,
      style: _azoomMenuButtonStyle(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _stageText,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: value ? _avaAccent : Colors.transparent,
              border: Border.all(color: value ? _avaAccent : _stageBorder),
              borderRadius: BorderRadius.circular(4),
            ),
            child: value
                ? const Icon(Icons.check, color: Colors.white, size: 15)
                : null,
          ),
        ],
      ),
    );
  }
}

class _AzoomMenuText extends StatelessWidget {
  const _AzoomMenuText({
    required this.title,
    this.subtitle,
    this.titleMaxLines = 1,
  });

  final String title;
  final String? subtitle;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    final height = hasSubtitle
        ? 48.0
        : titleMaxLines > 1
        ? 42.0
        : 36.0;
    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
            softWrap: titleMaxLines > 1,
            style: const TextStyle(
              color: _stageText,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (hasSubtitle)
            Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _stageMutedText,
                fontSize: 12,
                height: 1.12,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _AzoomMenuSectionLabel extends StatelessWidget {
  const _AzoomMenuSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: const TextStyle(
            color: _stageText,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AzoomMenuDivider extends StatelessWidget {
  const _AzoomMenuDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Divider(height: 1, thickness: 1, color: _stageMenuBorder),
    );
  }
}

class _AzoomInputMeter extends StatelessWidget {
  const _AzoomInputMeter({required this.level, required this.enabled});

  final double level;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    const barCount = 26;
    final activeCount = enabled
        ? (level.clamp(0.0, 1.0) * barCount).round()
        : 0;
    return Row(
      children: [
        for (var index = 0; index < barCount; index++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index == barCount - 1 ? 0 : 4),
              child: Container(
                height: 17,
                decoration: BoxDecoration(
                  color: index < activeCount
                      ? Color.lerp(
                          _avaAccent,
                          _avaAccentDeep,
                          index / (barCount - 1),
                        )
                      : _stageBorder.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

MenuStyle _azoomVoiceMenuStyle(double width) {
  return MenuStyle(
    backgroundColor: const WidgetStatePropertyAll(_stageMenu),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.black),
    elevation: const WidgetStatePropertyAll(8),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8)),
    fixedSize: WidgetStatePropertyAll(Size.fromWidth(width)),
    side: const WidgetStatePropertyAll(BorderSide(color: _stageMenuBorder)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
  );
}

ButtonStyle _azoomMenuButtonStyle({
  bool highlighted = false,
  double minHeight = 48,
}) {
  return ButtonStyle(
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    ),
    minimumSize: WidgetStatePropertyAll(Size(0, minHeight)),
    foregroundColor: const WidgetStatePropertyAll(_stageText),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed)) {
        return _stageMenuHover;
      }
      return Colors.transparent;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused) ||
          states.contains(WidgetState.pressed) ||
          highlighted) {
        return _stageMenuHover;
      }
      return Colors.transparent;
    }),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}

lk.MediaDevice? _selectedDevice(
  List<lk.MediaDevice> devices,
  String? selectedDeviceId,
) {
  if (selectedDeviceId == null || selectedDeviceId.isEmpty) {
    return devices.isEmpty ? null : devices.first;
  }
  for (final device in devices) {
    if (device.deviceId == selectedDeviceId) {
      return device;
    }
  }
  return devices.isEmpty ? null : devices.first;
}

String _deviceLabel(lk.MediaDevice? device, String fallback) {
  final label = device?.label.trim() ?? '';
  if (label.isEmpty) {
    return fallback;
  }
  return label;
}

class _VoiceControlButton extends StatelessWidget {
  const _VoiceControlButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.selected = false,
    this.danger = false,
    this.enabled = true,
    this.busy = false,
    this.roomStyle = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;
  final bool danger;
  final bool enabled;
  final bool busy;
  final bool roomStyle;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = danger
        ? _discordDanger
        : selected
        ? _avaAccent
        : roomStyle
        ? _voiceRoomControl
        : _stageControl;
    final foregroundColor = danger || selected
        ? Colors.white
        : roomStyle
        ? _voiceRoomText
        : _stageText;
    final disabledForegroundColor =
        (roomStyle ? _voiceRoomMutedText : _stageMutedText).withValues(
          alpha: 0.56,
        );
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: danger ? 66 : 44,
        height: 44,
        child: IconButton(
          onPressed: enabled ? onTap : null,
          style: IconButton.styleFrom(
            backgroundColor: backgroundColor,
            disabledBackgroundColor: roomStyle ? _voiceRoomBottom : _stagePanel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: busy
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                )
              : Icon(
                  icon,
                  color: enabled ? foregroundColor : disabledForegroundColor,
                  size: 22,
                ),
        ),
      ),
    );
  }
}

AzoomVoiceParticipantDto _localVoiceParticipant() {
  return AzoomVoiceParticipantDto(
    userId: 'local',
    email: '',
    displayName: '나',
    nickname: '',
    status: '온라인',
    avatarColor: '#7AA06A',
    avatarImageUrl: '',
    joinedAt: DateTime.now(),
    muted: false,
    deafened: false,
    cameraEnabled: false,
    screenSharing: false,
  );
}

AzoomVoiceParticipantDto _participantFromProfile(PersonProfile profile) {
  return AzoomVoiceParticipantDto(
    userId: profile.id ?? '',
    email: profile.email ?? '',
    displayName: profile.name,
    nickname: profile.nickname ?? '',
    status: profile.status ?? '온라인',
    avatarColor: _colorToHex(profile.color),
    avatarImageUrl: profile.imageUrl ?? '',
    joinedAt: DateTime.now(),
    muted: false,
    deafened: false,
    cameraEnabled: false,
    screenSharing: false,
  );
}

List<AzoomVoiceParticipantDto> _voiceRowParticipants(
  List<AzoomVoiceParticipantDto> participants, {
  required PersonProfile currentUser,
  required bool includeLocal,
  required bool micEnabled,
  required bool deafened,
  required bool cameraEnabled,
  required bool screenSharing,
}) {
  if (!includeLocal) {
    return participants;
  }
  final local = _participantWithVoiceMedia(
    _participantFromProfile(currentUser),
    muted: !micEnabled || deafened,
    deafened: deafened,
    cameraEnabled: cameraEnabled,
    screenSharing: screenSharing,
  );
  final merged = <AzoomVoiceParticipantDto>[];
  var localWasPresent = false;
  for (final participant in participants) {
    if (_isCurrentVoiceParticipant(participant, currentUser)) {
      merged.add(
        _participantWithVoiceMedia(
          participant,
          muted: !micEnabled || deafened,
          deafened: deafened,
          cameraEnabled: cameraEnabled,
          screenSharing: screenSharing,
        ),
      );
      localWasPresent = true;
    } else {
      merged.add(participant);
    }
  }
  if (!localWasPresent) {
    merged.insert(0, local);
  }
  return merged;
}

bool _isCurrentVoiceParticipant(
  AzoomVoiceParticipantDto participant,
  PersonProfile currentUser,
) {
  final profileId = currentUser.id?.trim();
  if (profileId != null &&
      profileId.isNotEmpty &&
      participant.userId == profileId) {
    return true;
  }
  final email = currentUser.email?.trim().toLowerCase();
  return email != null &&
      email.isNotEmpty &&
      participant.email.trim().toLowerCase() == email;
}

AzoomVoiceParticipantDto _participantWithVoiceMedia(
  AzoomVoiceParticipantDto participant, {
  required bool muted,
  required bool deafened,
  required bool cameraEnabled,
  required bool screenSharing,
}) {
  return AzoomVoiceParticipantDto(
    userId: participant.userId,
    email: participant.email,
    displayName: participant.displayName,
    nickname: participant.nickname,
    status: participant.status,
    avatarColor: participant.avatarColor,
    avatarImageUrl: participant.avatarImageUrl,
    joinedAt: participant.joinedAt,
    muted: muted,
    deafened: deafened,
    cameraEnabled: cameraEnabled,
    screenSharing: screenSharing,
  );
}

String _formatVoiceElapsed(Duration elapsed) {
  final normalized = elapsed.isNegative ? Duration.zero : elapsed;
  final hours = normalized.inHours;
  final minutes = normalized.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = normalized.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

String _formatTranscriptClock(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

String _initial(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.characters.first.toUpperCase();
}

String _avatarLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'A';
  }
  return trimmed.characters.first.toUpperCase();
}

Color _colorFromHex(String? hex) {
  final normalized = (hex ?? '').replaceFirst('#', '');
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) {
    return const Color(0xFF7AA06A);
  }
  return Color(0xFF000000 | value);
}

String _colorToHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class _LiveParticipantView {
  const _LiveParticipantView({
    required this.participant,
    required this.isLocal,
    required this.presence,
    required this.localProfile,
  });

  final lk.Participant participant;
  final bool isLocal;
  final AzoomVoiceParticipantDto? presence;
  final PersonProfile? localProfile;
}

class _LiveVideoTrackView {
  const _LiveVideoTrackView({required this.track, required this.isScreenShare});

  final lk.VideoTrack track;
  final bool isScreenShare;
}

List<_LiveParticipantView> _liveParticipants(
  lk.Room? room,
  List<AzoomVoiceParticipantDto> presences,
  PersonProfile currentUser,
) {
  if (room == null) {
    return const [];
  }
  final participants = <_LiveParticipantView>[];
  final local = room.localParticipant;
  if (local != null) {
    participants.add(
      _LiveParticipantView(
        participant: local,
        isLocal: true,
        presence: _matchingPresence(local, presences),
        localProfile: currentUser,
      ),
    );
  }
  for (final participant in room.remoteParticipants.values) {
    participants.add(
      _LiveParticipantView(
        participant: participant,
        isLocal: false,
        presence: _matchingPresence(participant, presences),
        localProfile: null,
      ),
    );
  }
  participants.sort((a, b) {
    if (a.isLocal != b.isLocal) {
      return a.isLocal ? -1 : 1;
    }
    if (a.participant.isSpeaking != b.participant.isSpeaking) {
      return a.participant.isSpeaking ? -1 : 1;
    }
    return a.participant.identity.compareTo(b.participant.identity);
  });
  return participants;
}

Set<String> _liveVoiceUserIds(lk.Room? room) {
  if (room == null) {
    return const {};
  }
  return {
    if (room.localParticipant case final local?) local.identity,
    for (final participant in room.remoteParticipants.values)
      participant.identity,
  };
}

String _liveParticipantKey(_LiveParticipantView view) {
  final identity = view.participant.identity.trim();
  if (identity.isNotEmpty) {
    return 'live:$identity';
  }
  final sid = view.participant.sid.trim();
  return 'live:${sid.isNotEmpty ? sid : _liveParticipantDisplayName(view)}';
}

String _presenceParticipantKey(AzoomVoiceParticipantDto participant) {
  final userId = participant.userId.trim();
  if (userId.isNotEmpty) {
    return 'presence:$userId';
  }
  final email = participant.email.trim();
  if (email.isNotEmpty) {
    return 'presence:$email';
  }
  return 'presence:${participant.displayName.trim()}';
}

AzoomVoiceParticipantDto? _matchingPresence(
  lk.Participant participant,
  List<AzoomVoiceParticipantDto> presences,
) {
  final identity = participant.identity.trim();
  final metadata = _participantMetadata(participant);
  final metadataUserId = _metadataString(metadata, 'userId');
  for (final presence in presences) {
    if (presence.userId == identity || presence.userId == metadataUserId) {
      return presence;
    }
  }
  final name = participant.name.trim();
  for (final presence in presences) {
    if (presence.displayName == name || presence.nickname == name) {
      return presence;
    }
  }
  return null;
}

String _liveParticipantDisplayName(_LiveParticipantView view) {
  final presenceName = view.presence?.displayName.trim() ?? '';
  if (presenceName.isNotEmpty) {
    return presenceName;
  }
  if (view.isLocal) {
    final localName = view.localProfile?.name.trim() ?? '';
    if (localName.isNotEmpty) {
      return localName;
    }
  }
  final metadataName = _metadataString(
    _participantMetadata(view.participant),
    'displayName',
  );
  if (metadataName.isNotEmpty) {
    return metadataName;
  }
  return view.participant.name.isNotEmpty
      ? view.participant.name
      : view.participant.identity;
}

String _liveParticipantImageUrl(_LiveParticipantView view) {
  final presenceImage = view.presence?.avatarImageUrl.trim() ?? '';
  if (presenceImage.isNotEmpty) {
    return presenceImage;
  }
  if (view.isLocal) {
    final localImage = view.localProfile?.imageUrl?.trim() ?? '';
    if (localImage.isNotEmpty) {
      return localImage;
    }
  }
  return _metadataString(
    _participantMetadata(view.participant),
    'avatarImageUrl',
  );
}

Color _liveParticipantColor(_LiveParticipantView view) {
  final presenceColor = view.presence?.avatarColor.trim() ?? '';
  if (presenceColor.isNotEmpty) {
    return _colorFromHex(presenceColor);
  }
  if (view.isLocal && view.localProfile != null) {
    return view.localProfile!.color;
  }
  final metadataColor = _metadataString(
    _participantMetadata(view.participant),
    'avatarColor',
  );
  if (metadataColor.isNotEmpty) {
    return _colorFromHex(metadataColor);
  }
  return const Color(0xFF7AA06A);
}

Map<String, dynamic> _participantMetadata(lk.Participant participant) {
  final metadata = participant.metadata?.trim();
  if (metadata == null || metadata.isEmpty) {
    return const {};
  }
  try {
    final decoded = jsonDecode(metadata);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
  } on FormatException {
    return const {};
  }
  return const {};
}

String _metadataString(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  return value is String ? value.trim() : '';
}

bool _isLoopbackAudioInput(lk.MediaDevice device) {
  final label = device.label.trim().toLowerCase();
  if (label.isEmpty) {
    return false;
  }
  return label.contains('stereo mix') ||
      label.contains('what u hear') ||
      label.contains('loopback') ||
      label.contains('wave out') ||
      label.contains('system audio') ||
      label.contains('스테레오 믹스') ||
      label.contains('루프백') ||
      label.contains('시스템 오디오');
}

_LiveVideoTrackView? _videoTrackFor(lk.Participant participant) {
  for (final publication in participant.videoTrackPublications) {
    if (publication.isScreenShare && !publication.muted) {
      final track = publication.track;
      return track is lk.VideoTrack
          ? _LiveVideoTrackView(track: track, isScreenShare: true)
          : null;
    }
  }
  for (final publication in participant.videoTrackPublications) {
    if (!publication.isScreenShare && !publication.muted) {
      final track = publication.track;
      return track is lk.VideoTrack
          ? _LiveVideoTrackView(track: track, isScreenShare: false)
          : null;
    }
  }
  return null;
}
