import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

class AzoomDiscordScreenShareSourceDialog extends StatefulWidget {
  const AzoomDiscordScreenShareSourceDialog({super.key});

  @override
  State<AzoomDiscordScreenShareSourceDialog> createState() =>
      _AzoomDiscordScreenShareSourceDialogState();
}

class _AzoomDiscordScreenShareSourceDialogState
    extends State<AzoomDiscordScreenShareSourceDialog> {
  static final _sourceTypes = [rtc.SourceType.Window, rtc.SourceType.Screen];
  static final _thumbnailSize = rtc.ThumbnailSize(640, 360);

  List<rtc.DesktopCapturerSource> _sources = const [];
  List<rtc.MediaDeviceInfo> _videoDevices = const [];
  final Map<String, Uint8List> _thumbnailCache = {};
  final List<StreamSubscription<rtc.DesktopCapturerSource>>
  _desktopSubscriptions = [];
  rtc.DesktopCapturerSource? _selectedSource;
  _ScreenSharePickerTab _selectedTab = _ScreenSharePickerTab.application;
  Timer? _thumbnailRefreshTimer;
  bool _loading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _desktopSubscriptions.addAll([
      rtc.desktopCapturer.onAdded.stream.listen(_upsertSource),
      rtc.desktopCapturer.onRemoved.stream.listen(_removeSource),
      rtc.desktopCapturer.onNameChanged.stream.listen(_upsertSource),
      rtc.desktopCapturer.onThumbnailChanged.stream.listen(_upsertSource),
    ]);
    unawaited(_loadSources());
  }

  @override
  void dispose() {
    _thumbnailRefreshTimer?.cancel();
    for (final subscription in _desktopSubscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  Future<void> _loadSources() async {
    _thumbnailRefreshTimer?.cancel();
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final sources = await rtc.desktopCapturer.getSources(
        types: _sourceTypes,
        thumbnailSize: _thumbnailSize,
      );
      var videoDevices = <rtc.MediaDeviceInfo>[];
      try {
        final devices = await rtc.navigator.mediaDevices.enumerateDevices();
        videoDevices = devices
            .where((device) => device.kind == 'videoinput')
            .toList();
      } on Object {
        videoDevices = const [];
      }
      if (!mounted) {
        return;
      }
      final windows = _sourcesForTab(
        sources,
        _ScreenSharePickerTab.application,
      );
      final screens = _sourcesForTab(sources, _ScreenSharePickerTab.screen);
      setState(() {
        for (final source in sources) {
          _rememberThumbnail(source);
        }
        _sources = sources;
        _videoDevices = videoDevices;
        _selectedSource = windows.firstOrNull ?? screens.firstOrNull;
        _loading = false;
      });
      _startThumbnailRefreshLoop();
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _sources = const [];
        _videoDevices = const [];
        _selectedSource = null;
        _loading = false;
        _errorText = '공유할 화면 목록을 불러오지 못했습니다.';
      });
    }
  }

  void _startThumbnailRefreshLoop() {
    _thumbnailRefreshTimer?.cancel();
    var ticks = 0;
    unawaited(rtc.desktopCapturer.updateSources(types: _sourceTypes));
    _thumbnailRefreshTimer = Timer.periodic(const Duration(milliseconds: 650), (
      timer,
    ) {
      ticks += 1;
      if (!mounted || ticks > 30) {
        timer.cancel();
        return;
      }
      unawaited(rtc.desktopCapturer.updateSources(types: _sourceTypes));
    });
  }

  void _rememberThumbnail(rtc.DesktopCapturerSource source) {
    final thumbnail = source.thumbnail;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      _thumbnailCache[source.id] = thumbnail;
    }
  }

  void _upsertSource(rtc.DesktopCapturerSource source) {
    if (!mounted) {
      return;
    }
    _rememberThumbnail(source);
    setState(() {
      final nextSources = [..._sources];
      final index = nextSources.indexWhere((item) => item.id == source.id);
      if (index == -1) {
        nextSources.add(source);
      } else {
        nextSources[index] = source;
      }
      _sources = nextSources;
      if (_selectedSource?.id == source.id) {
        _selectedSource = source;
      }
    });
  }

  void _removeSource(rtc.DesktopCapturerSource source) {
    if (!mounted) {
      return;
    }
    setState(() {
      _sources = [
        for (final item in _sources)
          if (item.id != source.id) item,
      ];
      _thumbnailCache.remove(source.id);
      if (_selectedSource?.id == source.id) {
        final tabSources = _sourcesForTab(_sources, _selectedTab);
        _selectedSource = tabSources.firstOrNull;
      }
    });
  }

  List<rtc.DesktopCapturerSource> _currentSources() {
    return _sourcesForTab(_sources, _selectedTab);
  }

  void _selectTab(_ScreenSharePickerTab tab) {
    setState(() {
      _selectedTab = tab;
      final tabSources = _sourcesForTab(_sources, tab);
      if (_selectedSource == null ||
          !tabSources.any((source) => source.id == _selectedSource?.id)) {
        _selectedSource = tabSources.firstOrNull;
      }
    });
  }

  void _selectSource(rtc.DesktopCapturerSource source) {
    setState(() => _selectedSource = source);
  }

  void _shareSource(rtc.DesktopCapturerSource source) {
    Navigator.of(context).pop(source);
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = math.max(320.0, math.min(960.0, viewport.width - 56));
    final dialogHeight = math.max(420.0, math.min(608.0, viewport.height - 48));
    return Dialog(
      key: const ValueKey('azoom-screen-share-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        key: const ValueKey('azoom-screen-share-dialog-frame'),
        width: dialogWidth,
        height: dialogHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF36373F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1F2026)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
              child: _ScreenShareTabBar(
                selectedTab: _selectedTab,
                onSelected: _selectTab,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFE6E8EF),
                        strokeWidth: 2.6,
                      ),
                    )
                  : _errorText != null
                  ? _ScreenShareSourceMessage(
                      message: _errorText!,
                      onRetry: _loadSources,
                    )
                  : _selectedTab == _ScreenSharePickerTab.device
                  ? _ScreenShareDeviceGrid(devices: _videoDevices)
                  : _ScreenShareSourceGrid(
                      sources: _currentSources(),
                      selectedSource: _selectedSource,
                      thumbnailCache: _thumbnailCache,
                      onSelected: _selectSource,
                      onShare: _shareSource,
                    ),
            ),
            _ScreenShareFooter(
              selectedTab: _selectedTab,
              selectedSource: _selectedSource,
              onShare: _selectedSource == null
                  ? null
                  : () => _shareSource(_selectedSource!),
            ),
            const _AvaScreenShareNotice(),
          ],
        ),
      ),
    );
  }
}

enum _ScreenSharePickerTab { application, screen, device }

List<rtc.DesktopCapturerSource> _sourcesForTab(
  List<rtc.DesktopCapturerSource> sources,
  _ScreenSharePickerTab tab,
) {
  final sourceType = switch (tab) {
    _ScreenSharePickerTab.application => rtc.SourceType.Window,
    _ScreenSharePickerTab.screen => rtc.SourceType.Screen,
    _ScreenSharePickerTab.device => null,
  };
  if (sourceType == null) {
    return const [];
  }
  return sources.where((source) => source.type == sourceType).toList();
}

class _ScreenShareTabBar extends StatelessWidget {
  const _ScreenShareTabBar({
    required this.selectedTab,
    required this.onSelected,
  });

  final _ScreenSharePickerTab selectedTab;
  final ValueChanged<_ScreenSharePickerTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('azoom-screen-share-tabs'),
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _ScreenShareTabButton(
            tab: _ScreenSharePickerTab.application,
            selected: selectedTab == _ScreenSharePickerTab.application,
            icon: Icons.web_asset,
            label: '애플리케이션',
            onTap: onSelected,
          ),
          _ScreenShareTabButton(
            tab: _ScreenSharePickerTab.screen,
            selected: selectedTab == _ScreenSharePickerTab.screen,
            icon: Icons.desktop_windows,
            label: '전체 화면',
            onTap: onSelected,
          ),
          _ScreenShareTabButton(
            tab: _ScreenSharePickerTab.device,
            selected: selectedTab == _ScreenSharePickerTab.device,
            icon: Icons.videocam,
            label: '기기',
            onTap: onSelected,
          ),
        ],
      ),
    );
  }
}

class _ScreenShareTabButton extends StatelessWidget {
  const _ScreenShareTabButton({
    required this.tab,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final _ScreenSharePickerTab tab;
  final bool selected;
  final IconData icon;
  final String label;
  final ValueChanged<_ScreenSharePickerTab> onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: selected ? const Color(0xFF3E4049) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: () => onTap(tab),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: const Color(0xFFDCDDDE)),
                const SizedBox(width: 9),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFFFFFFFF)
                        : const Color(0xFFDCDDDE),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
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

class _ScreenShareSourceGrid extends StatelessWidget {
  const _ScreenShareSourceGrid({
    required this.sources,
    required this.selectedSource,
    required this.thumbnailCache,
    required this.onSelected,
    required this.onShare,
  });

  final List<rtc.DesktopCapturerSource> sources;
  final rtc.DesktopCapturerSource? selectedSource;
  final Map<String, Uint8List> thumbnailCache;
  final ValueChanged<rtc.DesktopCapturerSource> onSelected;
  final ValueChanged<rtc.DesktopCapturerSource> onShare;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const Center(
        child: Text(
          '공유할 항목이 없습니다.',
          style: TextStyle(
            color: Color(0xFFC7C9D1),
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 760 ? 1 : 2;
        return GridView.builder(
          key: const ValueKey('azoom-screen-share-source-grid'),
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 22,
            crossAxisSpacing: 16,
            childAspectRatio: 1.48,
          ),
          itemCount: sources.length,
          itemBuilder: (context, index) {
            final source = sources[index];
            return _ScreenShareSourceTile(
              key: ValueKey('azoom-screen-share-source-${source.id}'),
              source: source,
              selected: selectedSource?.id == source.id,
              thumbnail: thumbnailCache[source.id],
              onTap: () => onSelected(source),
              onShare: () => onShare(source),
            );
          },
        );
      },
    );
  }
}

class _ScreenShareSourceTile extends StatefulWidget {
  const _ScreenShareSourceTile({
    required this.source,
    required this.selected,
    required this.thumbnail,
    required this.onTap,
    required this.onShare,
    super.key,
  });

  final rtc.DesktopCapturerSource source;
  final bool selected;
  final Uint8List? thumbnail;
  final VoidCallback onTap;
  final VoidCallback onShare;

  @override
  State<_ScreenShareSourceTile> createState() => _ScreenShareSourceTileState();
}

class _ScreenShareSourceTileState extends State<_ScreenShareSourceTile> {
  final List<StreamSubscription> _subscriptions = [];
  Uint8List? _thumbnail;
  String _name = '';
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _bindSource();
  }

  @override
  void didUpdateWidget(covariant _ScreenShareSourceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.id != widget.source.id) {
      _unbindSource();
      _bindSource();
      return;
    }
    final cachedThumbnail = widget.thumbnail;
    if (cachedThumbnail != null && cachedThumbnail.isNotEmpty) {
      _thumbnail = cachedThumbnail;
    }
    _name = widget.source.name;
  }

  @override
  void dispose() {
    _unbindSource();
    super.dispose();
  }

  void _bindSource() {
    _name = widget.source.name;
    final sourceThumbnail = widget.source.thumbnail;
    final cachedThumbnail = widget.thumbnail;
    _thumbnail = sourceThumbnail != null && sourceThumbnail.isNotEmpty
        ? sourceThumbnail
        : cachedThumbnail != null && cachedThumbnail.isNotEmpty
        ? cachedThumbnail
        : null;
    _subscriptions.addAll([
      widget.source.onThumbnailChanged.stream.listen((thumbnail) {
        if (!mounted || thumbnail.isEmpty) {
          return;
        }
        setState(() {
          _thumbnail = thumbnail;
        });
      }),
      widget.source.onNameChanged.stream.listen((name) {
        if (!mounted) {
          return;
        }
        setState(() {
          _name = name;
        });
      }),
    ]);
  }

  void _unbindSource() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isScreen = widget.source.type == rtc.SourceType.Screen;
    final borderColor = _hovered || widget.selected
        ? const Color(0xFF5E626D)
        : Colors.transparent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                curve: Curves.easeOutCubic,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0xFF111214),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor, width: 2),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ScreenShareThumbnail(bytes: _thumbnail),
                    AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: IgnorePointer(
                        ignoring: !_hovered,
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: 3.5,
                                  sigmaY: 3.5,
                                ),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.34),
                                ),
                              ),
                              Center(
                                child: FilledButton(
                                  key: const ValueKey(
                                    'azoom-screen-share-hover-button',
                                  ),
                                  onPressed: widget.onShare,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF111214),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 25,
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                  child: const Text(
                                    '화면 공유',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(
                  isScreen ? Icons.desktop_windows : Icons.web_asset,
                  color: const Color(0xFFC7C9D1),
                  size: 17,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF2F3F5),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenShareThumbnail extends StatelessWidget {
  const _ScreenShareThumbnail({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final thumbnailBytes = bytes;
    if (thumbnailBytes != null && thumbnailBytes.isNotEmpty) {
      return Image.memory(
        key: const ValueKey('azoom-screen-share-thumbnail-image'),
        thumbnailBytes,
        gaplessPlayback: true,
        fit: BoxFit.cover,
      );
    }
    return Container(
      key: const ValueKey('azoom-screen-share-thumbnail-fallback'),
      color: const Color(0xFF18191C),
      alignment: Alignment.center,
      child: const SizedBox.square(
        dimension: 26,
        child: CircularProgressIndicator(
          color: Color(0xFFAEB1BA),
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}

class _ScreenShareDeviceGrid extends StatelessWidget {
  const _ScreenShareDeviceGrid({required this.devices});

  final List<rtc.MediaDeviceInfo> devices;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return const Center(
        child: Text(
          '연결된 영상 기기를 찾지 못했습니다.',
          style: TextStyle(
            color: Color(0xFFC7C9D1),
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 760 ? 1 : 2;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 22,
            crossAxisSpacing: 16,
            childAspectRatio: 1.48,
          ),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            return _ScreenShareDeviceTile(device: devices[index]);
          },
        );
      },
    );
  }
}

class _ScreenShareDeviceTile extends StatefulWidget {
  const _ScreenShareDeviceTile({required this.device});

  final rtc.MediaDeviceInfo device;

  @override
  State<_ScreenShareDeviceTile> createState() => _ScreenShareDeviceTileState();
}

class _ScreenShareDeviceTileState extends State<_ScreenShareDeviceTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _hovered
                      ? const Color(0xFF5E626D)
                      : Colors.transparent,
                  width: 2,
                ),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF6F93AA),
                    Color(0xFF6B5D70),
                    Color(0xFF6F4F24),
                  ],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.26),
                      ),
                    ),
                  ),
                  Center(
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: FilledButton(
                        onPressed: null,
                        style: FilledButton.styleFrom(
                          disabledBackgroundColor: Colors.white.withValues(
                            alpha: 0.92,
                          ),
                          disabledForegroundColor: const Color(0xFF111214),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 25,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        child: const Text(
                          '기기 선택',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              const Icon(Icons.videocam, color: Color(0xFFC7C9D1), size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.device.label.isEmpty ? '영상 기기' : widget.device.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF2F3F5),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScreenShareFooter extends StatelessWidget {
  const _ScreenShareFooter({
    required this.selectedTab,
    required this.selectedSource,
    required this.onShare,
  });

  final _ScreenSharePickerTab selectedTab;
  final rtc.DesktopCapturerSource? selectedSource;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final deviceMode = selectedTab == _ScreenSharePickerTab.device;
    final sourceName = selectedSource?.name.trim();
    final sourceLabel = sourceName == null || sourceName.isEmpty
        ? 'AVA 최적화'
        : sourceName;
    return Container(
      key: const ValueKey('azoom-screen-share-footer'),
      height: 74,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceMode ? '기기' : '게이밍',
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    deviceMode
                        ? '카메라는 하단 통화 제어에서 켤 수 있습니다.'
                        : '더 부드러운 동영상 · 720p · 30fps · $sourceLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB7BAC4),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _ScreenShareQualityToggle(),
          const SizedBox(width: 10),
          _ScreenShareSettingsButton(onTap: () {}),
          const SizedBox(width: 10),
          SizedBox(
            height: 40,
            child: FilledButton(
              key: const ValueKey('azoom-screen-share-action'),
              onPressed: deviceMode ? null : onShare,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF5865F2),
                disabledBackgroundColor: const Color(
                  0xFF5865F2,
                ).withValues(alpha: 0.44),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white.withValues(alpha: 0.54),
                padding: const EdgeInsets.symmetric(horizontal: 29),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                deviceMode ? '방송' : '공유',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
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

class _ScreenShareQualityToggle extends StatelessWidget {
  const _ScreenShareQualityToggle();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2D31),
        borderRadius: BorderRadius.circular(11),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ScreenShareQualityPill(label: 'SD', selected: true),
          _ScreenShareQualityPill(label: 'HD', selected: false),
        ],
      ),
    );
  }
}

class _ScreenShareQualityPill extends StatelessWidget {
  const _ScreenShareQualityPill({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF3E4049) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : const Color(0xFFFF73DF),
          fontSize: 14,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _ScreenShareSettingsButton extends StatelessWidget {
  const _ScreenShareSettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 40,
      child: IconButton(
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFF42444D),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.settings, color: Colors.white, size: 22),
      ),
    );
  }
}

class _AvaScreenShareNotice extends StatelessWidget {
  const _AvaScreenShareNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF9347DC), Color(0xFFC158A9)],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'AVA 회의 공유는 회사 네트워크 밖에서도 안정적으로 연결되도록 최적화됩니다.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'AVA 공유',
              style: TextStyle(
                color: Color(0xFF9347DC),
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
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
              color: Color(0xFFC7C9D1),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF2F3F5),
              side: const BorderSide(color: Color(0xFF5E626D)),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}
