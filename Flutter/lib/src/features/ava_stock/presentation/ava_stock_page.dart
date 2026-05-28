import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../config/app_config.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/data/auth_api.dart';
import '../data/ava_stock_api.dart';

final avaStockImmersiveMobileNavProvider =
    NotifierProvider<AvaStockImmersiveMobileNav, bool>(
      AvaStockImmersiveMobileNav.new,
    );

class AvaStockImmersiveMobileNav extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool value) => state = value;
}

class AvaStockPage extends ConsumerStatefulWidget {
  const AvaStockPage({super.key});

  @override
  ConsumerState<AvaStockPage> createState() => _AvaStockPageState();
}

class _AvaStockPageState extends ConsumerState<AvaStockPage> {
  bool _showSplash = true;
  bool _loading = false;
  String? _errorText;
  AvaStockHomeDto? _home;
  _AvaStockView _view = _AvaStockView.home;
  Map<String, dynamic>? _part;
  Map<String, dynamic>? _product;
  Map<String, dynamic>? _checklist;
  int? _serviceCaseId;
  final Map<int, bool> _checked = {};
  late final AvaStockImmersiveMobileNav _immersiveMobileNav;
  bool _reportedImmersiveMobileNav = false;

  @override
  void initState() {
    super.initState();
    _immersiveMobileNav = ref.read(avaStockImmersiveMobileNavProvider.notifier);
    unawaited(_boot());
  }

  @override
  void dispose() {
    _immersiveMobileNav.setEnabled(false);
    super.dispose();
  }

  Future<void> _boot() async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) {
      return;
    }
    setState(() => _showSplash = false);
    await _loadHome();
  }

  String? get _accessToken =>
      ref.read(authControllerProvider).value?.session?.accessToken;

  Future<void> _loadHome() async {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final home = await ref.read(avaStockApiProvider).home(token);
      if (!mounted) {
        return;
      }
      setState(() => _home = home);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorText = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _lookupQr(String value) async {
    final token = _accessToken;
    final qrValue = value.trim();
    if (token == null || token.isEmpty || qrValue.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final api = ref.read(avaStockApiProvider);
      final lookup = await api.lookupQr(accessToken: token, qrValue: qrValue);
      if (lookup.qrType == 'PRODUCT') {
        final product = await api.productByQr(
          accessToken: token,
          qrValue: qrValue,
        );
        final productUnitId = _asInt(product['productUnitId']);
        final currentStatus = product['currentStatus'] as String?;
        Map<String, dynamic>? checklist;
        if (productUnitId != null && _isManufacturingStatus(currentStatus)) {
          checklist = await api.manufacturingChecklist(
            accessToken: token,
            productUnitId: productUnitId,
          );
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _product = product;
          _checklist = checklist;
          _checked
            ..clear()
            ..addAll(_checkedFromChecklist(checklist));
          _view = currentStatus == 'MFG_REVIEW'
              ? _AvaStockView.finishedReview
              : checklist == null
              ? _AvaStockView.finished
              : _AvaStockView.manufacturing;
        });
      } else if (lookup.qrType == 'PART') {
        final part = await api.partByQr(accessToken: token, qrValue: qrValue);
        if (!mounted) {
          return;
        }
        setState(() {
          _part = part;
          _view = _AvaStockView.part;
        });
      } else {
        if (!mounted) {
          return;
        }
        setState(() => _errorText = '????????몄툗 QR????낇돲??');
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorText = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveChecklist({required bool complete}) async {
    final token = _accessToken;
    final productUnitId = _asInt(_product?['productUnitId']);
    if (token == null || token.isEmpty || productUnitId == null) {
      return;
    }
    final items = _checklistItems().map((item) {
      final bomItemId = _asInt(item['bomItemId']) ?? 0;
      final checked = _checked[bomItemId] ?? false;
      return {
        'bomItemId': bomItemId,
        'used': checked,
        'quantity': checked ? (item['defaultQty'] as int? ?? 1) : 0,
      };
    }).toList();
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(avaStockApiProvider)
          .saveManufacturing(
            accessToken: token,
            productUnitId: productUnitId,
            items: items,
            complete: complete,
          );
      if (!mounted) {
        return;
      }
      if (complete) {
        setState(() {
          _product = result;
          _checklist = null;
          _view = _AvaStockView.finishedReview;
        });
      } else {
        setState(() {
          _checklist = result;
          _product = (result['product'] as Map? ?? _product ?? const {})
              .cast<String, dynamic>();
        });
      }
      await _loadHome();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorText = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _startService() async {
    final token = _accessToken;
    final productUnitId = _asInt(_product?['productUnitId']);
    if (token == null || token.isEmpty || productUnitId == null) {
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(avaStockApiProvider)
          .startService(accessToken: token, productUnitId: productUnitId);
      final serviceCase = (result['serviceCase'] as Map? ?? const {})
          .cast<String, dynamic>();
      if (!mounted) {
        return;
      }
      setState(() {
        _serviceCaseId = _asInt(serviceCase['serviceCaseId']);
        _checklist = (result['checklist'] as Map? ?? const {})
            .cast<String, dynamic>();
        _checked
          ..clear()
          ..addAll(_checkedFromChecklist(_checklist));
        _view = _AvaStockView.service;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorText = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _editManufacturing() async {
    final token = _accessToken;
    final productUnitId = _asInt(_product?['productUnitId']);
    if (token == null || token.isEmpty || productUnitId == null) {
      return;
    }
    setState(() => _loading = true);
    try {
      final checklist = await ref
          .read(avaStockApiProvider)
          .manufacturingChecklist(
            accessToken: token,
            productUnitId: productUnitId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _checklist = checklist;
        _product = (checklist['product'] as Map? ?? _product ?? const {})
            .cast<String, dynamic>();
        _checked
          ..clear()
          ..addAll(_checkedFromChecklist(checklist));
        _view = _AvaStockView.manufacturing;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorText = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _finishProductRegistration({
    required String destinationName,
    required String imei,
    required String shippingMethod,
    required DateTime shippingDate,
  }) async {
    final token = _accessToken;
    final productUnitId = _asInt(_product?['productUnitId']);
    if (token == null || token.isEmpty || productUnitId == null) {
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final api = ref.read(avaStockApiProvider);
      await api.createShipment(
        accessToken: token,
        destinationName: destinationName,
        imei: imei,
        shippingMethod: shippingMethod,
        shippingDate: shippingDate,
        productUnitIds: [productUnitId],
        shipmentStatus: 'READY',
      );
      final product = await api.product(
        accessToken: token,
        productUnitId: productUnitId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _product = product;
        _view = _AvaStockView.finished;
      });
      await _loadHome();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorText = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _requestServiceWithAuth() async {
    final verified = await _showPasswordVerificationDialog();
    if (verified == true) {
      await _startService();
    }
  }

  Future<bool?> _showPasswordVerificationDialog() {
    final token = _accessToken;
    final user = ref.read(authControllerProvider).value?.session?.user;
    if (token == null || token.isEmpty || user == null) {
      return Future<bool?>.value(false);
    }
    final controller = TextEditingController();
    String? errorText;
    bool verifying = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Text(
                '怨꾩젙 ?몄쬆',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.email,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '鍮꾨?踰덊샇',
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onSubmitted: (_) async {
                      if (!verifying) {
                        setDialogState(() => verifying = true);
                        try {
                          await ref
                              .read(authApiProvider)
                              .verifyPassword(
                                accessToken: token,
                                password: controller.text,
                              );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        } on Object catch (error) {
                          setDialogState(() {
                            verifying = false;
                            errorText = authErrorMessage(error);
                          });
                        }
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: verifying
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('痍⑥냼'),
                ),
                FilledButton(
                  onPressed: verifying
                      ? null
                      : () async {
                          setDialogState(() => verifying = true);
                          try {
                            await ref
                                .read(authApiProvider)
                                .verifyPassword(
                                  accessToken: token,
                                  password: controller.text,
                                );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } on Object catch (error) {
                            setDialogState(() {
                              verifying = false;
                              errorText = authErrorMessage(error);
                            });
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4663CF),
                  ),
                  child: verifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('?뺤씤'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _saveService({required bool complete}) async {
    final token = _accessToken;
    final serviceCaseId = _serviceCaseId;
    if (token == null || token.isEmpty || serviceCaseId == null) {
      return;
    }
    final items = _checklistItems().map((item) {
      final bomItemId = _asInt(item['bomItemId']) ?? 0;
      final checked = _checked[bomItemId] ?? false;
      return {
        'bomItemId': bomItemId,
        'used': checked,
        'quantity': checked ? (item['defaultQty'] as int? ?? 1) : 0,
      };
    }).toList();
    setState(() => _loading = true);
    try {
      final result = await ref
          .read(avaStockApiProvider)
          .saveService(
            accessToken: token,
            serviceCaseId: serviceCaseId,
            items: items,
            complete: complete,
          );
      if (!mounted) {
        return;
      }
      if (complete) {
        setState(() {
          _product = result;
          _checklist = null;
          _view = _AvaStockView.finished;
        });
      } else {
        setState(
          () => _checklist = result['checklist'] is Map
              ? (result['checklist'] as Map).cast<String, dynamic>()
              : result,
        );
      }
      await _loadHome();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorText = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _purchasePart() async {
    final token = _accessToken;
    final partId = _asInt(_part?['partId']);
    if (token == null || token.isEmpty || partId == null) {
      return;
    }
    final quantity = await _numberDialog(
      '\uCD94\uAC00\uB9E4\uC785 \uC218\uB7C9',
    );
    if (quantity == null || quantity <= 0) {
      return;
    }
    setState(() => _loading = true);
    try {
      final part = await ref
          .read(avaStockApiProvider)
          .purchasePart(accessToken: token, partId: partId, quantity: quantity);
      if (mounted) {
        setState(() => _part = part);
      }
      await _loadHome();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorText = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return const _AvaStockSplash();
    }

    final isQrScan = _view == _AvaStockView.scan;
    final isSpaceDashboard = _view == _AvaStockView.spaceDashboard;
    _reportImmersiveMobileNav(isSpaceDashboard);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: isQrScan ? Colors.transparent : Colors.white,
        statusBarIconBrightness: isQrScan ? Brightness.light : Brightness.dark,
        statusBarBrightness: isQrScan ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: isQrScan
            ? const Color(0xFFF7F8FC)
            : Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: ColoredBox(
        color: Colors.white,
        child: Stack(
          children: [
            SafeArea(
              top: !isQrScan && !isSpaceDashboard,
              bottom: false,
              child: Column(
                children: [
                  if (!isQrScan && !isSpaceDashboard)
                    _Header(
                      title: _titleForView(),
                      subtitle:
                          '\uC0DD\uC0B0 \u00B7 \uC785\uCD9C\uACE0 \u00B7 \uC7AC\uACE0 \uAD00\uB9AC',
                      onBack: _view == _AvaStockView.home
                          ? null
                          : () => setState(() => _view = _AvaStockView.home),
                      onRefresh: _loadHome,
                    ),
                  if (_errorText != null)
                    _ErrorBanner(
                      text: _errorText!,
                      onClose: () => setState(() => _errorText = null),
                    ),
                  Expanded(child: _body()),
                ],
              ),
            ),
            if (_loading)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.08),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFF4663CF)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _reportImmersiveMobileNav(bool enabled) {
    if (_reportedImmersiveMobileNav == enabled) {
      return;
    }
    _reportedImmersiveMobileNav = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _immersiveMobileNav.setEnabled(enabled);
      }
    });
  }

  Widget _body() {
    return switch (_view) {
      _AvaStockView.home => _HomeView(
        home: _home,
        onScan: () => setState(() => _view = _AvaStockView.scan),
        onDashboard: () => setState(() => _view = _AvaStockView.dashboard),
        onSpaceDashboard: () =>
            setState(() => _view = _AvaStockView.spaceDashboard),
      ),
      _AvaStockView.scan => _QrScanView(
        onBack: () => setState(() => _view = _AvaStockView.home),
        onSubmit: _lookupQr,
      ),
      _AvaStockView.part => _PartView(part: _part, onPurchase: _purchasePart),
      _AvaStockView.manufacturing => _ChecklistView(
        title: '\uBC18\uC81C\uD488 \uBD80\uD488 \uCCB4\uD06C',
        product: _product,
        items: _checklistItems(),
        checked: _checked,
        onToggle: (id, value) => setState(() => _checked[id] = value),
        onSave: () => _saveChecklist(complete: false),
        onComplete: () => _saveChecklist(complete: true),
      ),
      _AvaStockView.finishedReview => _FinishedReviewView(
        product: _product,
        onEdit: _editManufacturing,
        onConfirm: () => setState(() => _view = _AvaStockView.finishedRegister),
      ),
      _AvaStockView.finishedRegister => _FinishedRegisterView(
        product: _product,
        onSubmit: _finishProductRegistration,
      ),
      _AvaStockView.finished => _FinishedView(
        product: _product,
        onService: _requestServiceWithAuth,
      ),
      _AvaStockView.service => _ChecklistView(
        title: 'A/S \uBD80\uD488 \uCCB4\uD06C',
        product: _product,
        items: _checklistItems(),
        checked: _checked,
        onToggle: (id, value) => setState(() => _checked[id] = value),
        onSave: () => _saveService(complete: false),
        onComplete: () => _saveService(complete: true),
      ),
      _AvaStockView.dashboard => _DashboardView(home: _home),
      _AvaStockView.spaceDashboard => _SpaceDashboardView(
        onHome: () => setState(() => _view = _AvaStockView.home),
        onScan: () => setState(() => _view = _AvaStockView.scan),
      ),
    };
  }

  String _titleForView() {
    return switch (_view) {
      _AvaStockView.home => 'AVA_stock',
      _AvaStockView.scan => 'QR \uC2A4\uCE94',
      _AvaStockView.part => '\uBD80\uD488 \uC7AC\uACE0',
      _AvaStockView.manufacturing => '\uC81C\uC870 \uCCB4\uD06C',
      _AvaStockView.finishedReview => '\uC644\uC81C\uD488 \uD655\uC778',
      _AvaStockView.finishedRegister => '\uC644\uC81C\uD488',
      _AvaStockView.finished => '\uC644\uC81C\uD488',
      _AvaStockView.service => 'A/S \uCCB4\uD06C',
      _AvaStockView.dashboard => '\uC785\uCD9C\uACE0 \uD604\uD669',
      _AvaStockView.spaceDashboard => '공간 대시보드',
    };
  }

  List<Map<String, dynamic>> _checklistItems() {
    final items = _checklist?['items'];
    if (items is List) {
      return [for (final item in items) (item as Map).cast<String, dynamic>()];
    }
    return const [];
  }

  Map<int, bool> _checkedFromChecklist(Map<String, dynamic>? checklist) {
    final result = <int, bool>{};
    final items = checklist?['items'];
    if (items is List) {
      for (final raw in items) {
        final item = (raw as Map).cast<String, dynamic>();
        final bomItemId = _asInt(item['bomItemId']);
        if (bomItemId != null) {
          result[bomItemId] = item['checkStatus'] == 'USED';
        }
      }
    }
    return result;
  }

  Future<int?> _numberDialog(String title) async {
    final controller = TextEditingController(text: '1');
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '\uC218\uB7C9'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('\uCDE8\uC18C'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(int.tryParse(controller.text)),
              child: const Text('\uD655\uC778'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }
}

enum _AvaStockView {
  home,
  scan,
  part,
  manufacturing,
  finishedReview,
  finishedRegister,
  finished,
  service,
  dashboard,
  spaceDashboard,
}

enum _SpaceStatus { part, semi, finished, process, reserved, defective, empty }

extension _SpaceStatusSpec on _SpaceStatus {
  Color get color {
    return switch (this) {
      _SpaceStatus.part => const Color(0xFF5EA8F2),
      _SpaceStatus.semi => const Color(0xFFFFCE53),
      _SpaceStatus.finished => const Color(0xFF75C86E),
      _SpaceStatus.process => const Color(0xFFFFA64D),
      _SpaceStatus.reserved => const Color(0xFFA787E7),
      _SpaceStatus.defective => const Color(0xFFFF7867),
      _SpaceStatus.empty => const Color(0xFFD9DEE4),
    };
  }

  String get label {
    return switch (this) {
      _SpaceStatus.part => '부품',
      _SpaceStatus.semi => '반제품',
      _SpaceStatus.finished => '완제품',
      _SpaceStatus.process => '공정 진행',
      _SpaceStatus.reserved => '예약/출고예정',
      _SpaceStatus.defective => '불량/확인 필요',
      _SpaceStatus.empty => '비어있음',
    };
  }
}

class _SpaceSlot {
  const _SpaceSlot({
    required this.label,
    required this.status,
    this.displayLabel,
    this.note,
  });

  final String label;
  final _SpaceStatus status;
  final String? displayLabel;
  final String? note;
}

class _SpaceRoom {
  const _SpaceRoom({
    required this.id,
    required this.role,
    required this.icon,
    required this.groups,
  });

  final String id;
  final String role;
  final IconData icon;
  final Map<String, List<_SpaceSlot>> groups;

  List<_SpaceSlot> group(String name) => groups[name] ?? const <_SpaceSlot>[];
}

class _InventoryProduct {
  const _InventoryProduct({
    required this.name,
    required this.quantity,
    required this.status,
    required this.kind,
    this.shortage = false,
  });

  final String name;
  final int quantity;
  final _SpaceStatus status;
  final _InventoryIllustrationKind kind;
  final bool shortage;
}

enum _InventoryIllustrationKind { blueBin, greenBin, yellowBin, motor, module }

final List<_SpaceRoom> _spaceRooms = [
  _SpaceRoom(
    id: '213',
    role: '재고실',
    icon: Icons.layers_rounded,
    groups: {
      'L-B': _slotSeries('L-B', 5, const [
        _SpaceStatus.part,
        _SpaceStatus.semi,
        _SpaceStatus.finished,
        _SpaceStatus.part,
        _SpaceStatus.empty,
      ], displayPrefix: 'B'),
      'L-T': _slotSeries('L-T', 5, const [
        _SpaceStatus.part,
        _SpaceStatus.semi,
        _SpaceStatus.process,
        _SpaceStatus.finished,
        _SpaceStatus.empty,
      ], displayPrefix: 'T'),
      'R-S': [
        _slot('R-S1', _SpaceStatus.finished, displayLabel: 'S1', note: '3층'),
        _slot('R-S2', _SpaceStatus.part, displayLabel: 'S2', note: '3층'),
        _slot('R-S3', _SpaceStatus.process, displayLabel: 'S3', note: '3층'),
        _slot('R-S4', _SpaceStatus.reserved, displayLabel: 'S4'),
        _slot('R-S5', _SpaceStatus.empty, displayLabel: 'S5'),
      ],
      'meeting': [
        _slot(
          'R-회의 테이블',
          _SpaceStatus.semi,
          displayLabel: 'S6',
          note: '회의 테이블',
        ),
      ],
    },
  ),
  _SpaceRoom(
    id: '518',
    role: '공정실',
    icon: Icons.settings_outlined,
    groups: {
      'R-T': _slotSeries('R-T', 3, const [
        _SpaceStatus.part,
        _SpaceStatus.finished,
        _SpaceStatus.process,
      ]),
      'R-B': _slotSeries('R-B', 3, const [
        _SpaceStatus.part,
        _SpaceStatus.semi,
        _SpaceStatus.part,
      ]),
      'L-B': _slotSeries('L-B', 6, const [
        _SpaceStatus.part,
        _SpaceStatus.finished,
        _SpaceStatus.semi,
        _SpaceStatus.process,
        _SpaceStatus.reserved,
        _SpaceStatus.empty,
      ]),
      'L-M': _slotSeries('L-M', 6, const [
        _SpaceStatus.part,
        _SpaceStatus.finished,
        _SpaceStatus.process,
        _SpaceStatus.reserved,
        _SpaceStatus.part,
        _SpaceStatus.empty,
      ]),
      'L-T': _slotSeries('L-T', 6, const [
        _SpaceStatus.part,
        _SpaceStatus.semi,
        _SpaceStatus.finished,
        _SpaceStatus.process,
        _SpaceStatus.reserved,
        _SpaceStatus.empty,
      ]),
    },
  ),
  _SpaceRoom(
    id: '532',
    role: '공정실',
    icon: Icons.settings_outlined,
    groups: {
      'R-B': _slotSeries('R-B', 4, const [
        _SpaceStatus.part,
        _SpaceStatus.finished,
        _SpaceStatus.semi,
        _SpaceStatus.empty,
      ]),
      'R-T': _slotSeries('R-T', 4, const [
        _SpaceStatus.part,
        _SpaceStatus.finished,
        _SpaceStatus.process,
        _SpaceStatus.reserved,
      ]),
      'L-B': _slotSeries('L-B', 4, const [
        _SpaceStatus.part,
        _SpaceStatus.semi,
        _SpaceStatus.finished,
        _SpaceStatus.empty,
      ]),
      'L-T': _slotSeries('L-T', 4, const [
        _SpaceStatus.part,
        _SpaceStatus.finished,
        _SpaceStatus.process,
        _SpaceStatus.reserved,
      ]),
    },
  ),
];

const List<_InventoryProduct> _inventoryProducts = [
  _InventoryProduct(
    name: '부품 A-01',
    quantity: 12,
    status: _SpaceStatus.part,
    kind: _InventoryIllustrationKind.blueBin,
  ),
  _InventoryProduct(
    name: '부품 A-02',
    quantity: 8,
    status: _SpaceStatus.part,
    kind: _InventoryIllustrationKind.blueBin,
  ),
  _InventoryProduct(
    name: '모터 부품',
    quantity: 6,
    status: _SpaceStatus.part,
    kind: _InventoryIllustrationKind.motor,
  ),
  _InventoryProduct(
    name: '센서 모듈',
    quantity: 5,
    status: _SpaceStatus.part,
    kind: _InventoryIllustrationKind.module,
  ),
  _InventoryProduct(
    name: '케이블 세트',
    quantity: 3,
    status: _SpaceStatus.semi,
    kind: _InventoryIllustrationKind.yellowBin,
    shortage: true,
  ),
  _InventoryProduct(
    name: '완제품 B-01',
    quantity: 4,
    status: _SpaceStatus.finished,
    kind: _InventoryIllustrationKind.greenBin,
  ),
];

_SpaceSlot _slot(
  String label,
  _SpaceStatus status, {
  String? displayLabel,
  String? note,
}) {
  return _SpaceSlot(
    label: label,
    status: status,
    displayLabel: displayLabel,
    note: note,
  );
}

List<_SpaceSlot> _slotSeries(
  String prefix,
  int count,
  List<_SpaceStatus> statuses, {
  String? displayPrefix,
}) {
  return List<_SpaceSlot>.generate(count, (index) {
    final number = index + 1;
    return _slot(
      '$prefix$number',
      statuses[index % statuses.length],
      displayLabel: '${displayPrefix ?? prefix}$number',
    );
  });
}

class _SpaceDashboardView extends StatefulWidget {
  const _SpaceDashboardView({required this.onHome, required this.onScan});

  final VoidCallback onHome;
  final VoidCallback onScan;

  @override
  State<_SpaceDashboardView> createState() => _SpaceDashboardViewState();
}

class _SpaceDashboardViewState extends State<_SpaceDashboardView> {
  late final PageController _pageController;
  int _selectedRoomIndex = 1;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    _pageController = PageController(
      initialPage: _selectedRoomIndex,
      viewportFraction: 0.62,
    );
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    _pageController.dispose();
    super.dispose();
  }

  void _showInventory(_SpaceRoom room, _SpaceSlot slot) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.38),
      builder: (context) {
        return _InventoryDetailDialog(room: room, slot: slot);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 768) {
          return _SpaceDashboardDesktop(
            rooms: _spaceRooms,
            onHome: widget.onHome,
            onScan: widget.onScan,
            onSlotTap: _showInventory,
          );
        }
        return _SpaceDashboardMobile(
          rooms: _spaceRooms,
          pageController: _pageController,
          selectedRoomIndex: _selectedRoomIndex,
          onPageChanged: (index) => setState(() => _selectedRoomIndex = index),
          onHome: widget.onHome,
          onScan: widget.onScan,
          onSlotTap: _showInventory,
        );
      },
    );
  }
}

class _SpaceDashboardMobile extends StatelessWidget {
  const _SpaceDashboardMobile({
    required this.rooms,
    required this.pageController,
    required this.selectedRoomIndex,
    required this.onPageChanged,
    required this.onHome,
    required this.onScan,
    required this.onSlotTap,
  });

  final List<_SpaceRoom> rooms;
  final PageController pageController;
  final int selectedRoomIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onHome;
  final VoidCallback onScan;
  final void Function(_SpaceRoom room, _SpaceSlot slot) onSlotTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('ava-stock-space-dashboard-view'),
      color: const Color(0xFFF7F9FC),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(17, 14, 17, 8),
              children: [
                const _SpaceMobileHeader(),
                const SizedBox(height: 15),
                const _ProcessFlowPanel(compact: true),
                const SizedBox(height: 12),
                SizedBox(
                  height: 398,
                  child: PageView.builder(
                    controller: pageController,
                    onPageChanged: onPageChanged,
                    itemCount: rooms.length,
                    clipBehavior: Clip.none,
                    itemBuilder: (context, index) {
                      return AnimatedBuilder(
                        animation: pageController,
                        builder: (context, child) {
                          var page = selectedRoomIndex.toDouble();
                          if (pageController.hasClients &&
                              pageController.position.haveDimensions) {
                            page = pageController.page ?? page;
                          }
                          final delta = (page - index).abs().clamp(0.0, 1.0);
                          final activeProgress = 1 - delta;
                          final scale = 0.94 + activeProgress * 0.06;
                          final y = delta * 18;
                          final opacity = 0.58 + activeProgress * 0.42;
                          return Opacity(
                            opacity: opacity,
                            child: Transform.translate(
                              offset: Offset(0, y),
                              child:
                                  Transform.scale(scale: scale, child: child),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: _RoomPlanCard(
                            room: rooms[index],
                            onSlotTap: onSlotTap,
                            dense: true,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _CarouselDots(count: rooms.length, selected: selectedRoomIndex),
                const SizedBox(height: 12),
                const _RealtimeAlertPanel(compact: true),
                const SizedBox(height: 10),
                const _StatusLegendPanel(compact: true),
              ],
            ),
          ),
          _MobileSpaceNav(onHome: onHome, onScan: onScan),
        ],
      ),
    );
  }
}

class _SpaceDashboardDesktop extends StatelessWidget {
  const _SpaceDashboardDesktop({
    required this.rooms,
    required this.onHome,
    required this.onScan,
    required this.onSlotTap,
  });

  final List<_SpaceRoom> rooms;
  final VoidCallback onHome;
  final VoidCallback onScan;
  final void Function(_SpaceRoom room, _SpaceSlot slot) onSlotTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('ava-stock-space-dashboard-view'),
      color: const Color(0xFFF5F7FA),
      child: Row(
        children: [
          _DesktopSpaceRail(onHome: onHome, onScan: onScan),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 14, 16, 18),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(740, constraints.maxHeight - 32),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const _SpaceDesktopTitle(),
                            const SizedBox(width: 30),
                            const Expanded(child: _ProcessFlowPanel()),
                            const SizedBox(width: 18),
                            SizedBox(
                              width: 452,
                              child: const _StatusLegendPanel(compact: false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 612,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final room in rooms) ...[
                                Expanded(
                                  child: _RoomPlanCard(
                                    room: room,
                                    onSlotTap: onSlotTap,
                                    dense: false,
                                  ),
                                ),
                                if (room != rooms.last)
                                  const SizedBox(width: 18),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(
                              width: 166,
                              height: 174,
                              child: _RealtimeAlertPanel(compact: false),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: SizedBox(
                                height: 174,
                                child: _CommonVerandaPanel(
                                  onTap: () => onSlotTap(
                                    rooms.first,
                                    rooms.first.group('meeting').first,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            const SizedBox(
                              width: 358,
                              height: 174,
                              child: _LegendHelpPanel(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SpaceMobileHeader extends StatelessWidget {
  const _SpaceMobileHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _SpaceTitleBlock(titleSize: 19, subtitleSize: 12)),
        Icon(
          Icons.notifications_none_rounded,
          size: 23,
          color: Color(0xFF111827),
        ),
        SizedBox(width: 18),
        Icon(Icons.menu_rounded, size: 28, color: Color(0xFF111827)),
      ],
    );
  }
}

class _SpaceDesktopTitle extends StatelessWidget {
  const _SpaceDesktopTitle();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 214,
      child: _SpaceTitleBlock(titleSize: 24, subtitleSize: 13),
    );
  }
}

class _SpaceTitleBlock extends StatelessWidget {
  const _SpaceTitleBlock({required this.titleSize, required this.subtitleSize});

  final double titleSize;
  final double subtitleSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '공간 대시보드',
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontSize: titleSize,
            fontWeight: FontWeight.w900,
            height: 1.05,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '공간 기반 재고 ERP',
          style: TextStyle(
            color: const Color(0xFF334155),
            fontSize: subtitleSize,
            fontWeight: FontWeight.w600,
            height: 1.1,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _ProcessFlowPanel extends StatelessWidget {
  const _ProcessFlowPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = compact
        ? FittedBox(
            fit: BoxFit.scaleDown,
            child: _ProcessFlowContent(compact: compact),
          )
        : _ProcessFlowContent(compact: compact);
    return Container(
      height: compact ? 40 : 52,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E6EF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: content,
    );
  }
}

class _ProcessFlowContent extends StatelessWidget {
  const _ProcessFlowContent({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Text(
          compact ? '공정 흐름' : '[공정 흐름]',
          style: TextStyle(
            color: const Color(0xFF111827),
            fontSize: compact ? 12 : 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        SizedBox(width: compact ? 14 : 0),
        if (!compact) const Spacer(),
        _FlowChip(
          text: '518호',
          color: const Color(0xFF2E74DD),
          width: compact ? 56 : 70,
          compact: compact,
        ),
        _FlowArrow(compact: compact),
        _FlowChip(
          text: '532호',
          color: const Color(0xFF3DA25B),
          width: compact ? 56 : 70,
          compact: compact,
        ),
        _FlowArrow(compact: compact),
        _FlowChip(
          text: '518호',
          color: const Color(0xFF2E74DD),
          width: compact ? 56 : 70,
          compact: compact,
        ),
        SizedBox(width: compact ? 14 : 0),
        if (!compact) const Spacer(),
        Text(
          compact ? '(공정 규정)' : '[공정 규정]',
          style: TextStyle(
            color: const Color(0xFF111827),
            fontSize: compact ? 11 : 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _FlowChip extends StatelessWidget {
  const _FlowChip({
    required this.text,
    required this.color,
    required this.width,
    required this.compact,
  });

  final String text;
  final Color color;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: compact ? 27 : 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(compact ? 5 : 6),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.27),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _FlowArrow extends StatelessWidget {
  const _FlowArrow({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 12),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: compact ? 18 : 22,
        color: Colors.black,
      ),
    );
  }
}

class _RoomPlanCard extends StatelessWidget {
  const _RoomPlanCard({
    required this.room,
    required this.onSlotTap,
    required this.dense,
  });

  final _SpaceRoom room;
  final void Function(_SpaceRoom room, _SpaceSlot slot) onSlotTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final titleSize = dense ? 18.0 : 23.0;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(dense ? 10 : 8),
        border: Border.all(color: const Color(0xFFDDE3EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dense ? 0.1 : 0.06),
            blurRadius: dense ? 18 : 10,
            offset: Offset(0, dense ? 7 : 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(dense ? 10 : 10, 9, dense ? 10 : 10, 9),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  room.icon,
                  color: const Color(0xFF45607F),
                  size: dense ? 21 : 26,
                ),
                const SizedBox(width: 8),
                Text(
                  '${room.id}호',
                  style: TextStyle(
                    color: const Color(0xFF111827),
                    fontSize: titleSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '(${room.role})',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF111827),
                      fontSize: dense ? 12 : 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: dense ? 8 : 10),
            Expanded(
              child: _RoomShell(
                dense: dense,
                child: _RoomPlanBody(
                  room: room,
                  dense: dense,
                  onSlotTap: onSlotTap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomShell extends StatelessWidget {
  const _RoomShell({required this.child, required this.dense});

  final Widget child;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RoomOutlinePainter(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          dense ? 10 : 18,
          dense ? 15 : 28,
          dense ? 10 : 18,
          dense ? 11 : 22,
        ),
        child: child,
      ),
    );
  }
}

class _RoomPlanBody extends StatelessWidget {
  const _RoomPlanBody({
    required this.room,
    required this.dense,
    required this.onSlotTap,
  });

  final _SpaceRoom room;
  final bool dense;
  final void Function(_SpaceRoom room, _SpaceSlot slot) onSlotTap;

  @override
  Widget build(BuildContext context) {
    return switch (room.id) {
      '213' => _Room213Layout(room: room, dense: dense, onSlotTap: onSlotTap),
      '518' => _Room518Layout(room: room, dense: dense, onSlotTap: onSlotTap),
      _ => _Room532Layout(room: room, dense: dense, onSlotTap: onSlotTap),
    };
  }
}

class _Room518Layout extends StatelessWidget {
  const _Room518Layout({
    required this.room,
    required this.dense,
    required this.onSlotTap,
  });

  final _SpaceRoom room;
  final bool dense;
  final void Function(_SpaceRoom room, _SpaceSlot slot) onSlotTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: dense ? 45 : 42,
          child: Column(
            children: [
              _SlotGrid(
                room: room,
                slots: room.group('R-T'),
                columns: 3,
                dense: dense,
                onSlotTap: onSlotTap,
              ),
              SizedBox(height: dense ? 8 : 14),
              _SlotGrid(
                room: room,
                slots: room.group('R-B'),
                columns: 3,
                dense: dense,
                onSlotTap: onSlotTap,
              ),
            ],
          ),
        ),
        const _DashedDivider(),
        Expanded(
          flex: dense ? 55 : 58,
          child: Column(
            children: [
              _SlotGrid(
                room: room,
                slots: room.group('L-B'),
                columns: 6,
                dense: dense,
                onSlotTap: onSlotTap,
              ),
              SizedBox(height: dense ? 7 : 13),
              _SlotGrid(
                room: room,
                slots: room.group('L-M'),
                columns: 6,
                dense: dense,
                onSlotTap: onSlotTap,
              ),
              SizedBox(height: dense ? 7 : 13),
              _SlotGrid(
                room: room,
                slots: room.group('L-T'),
                columns: 6,
                dense: dense,
                onSlotTap: onSlotTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Room532Layout extends StatelessWidget {
  const _Room532Layout({
    required this.room,
    required this.dense,
    required this.onSlotTap,
  });

  final _SpaceRoom room;
  final bool dense;
  final void Function(_SpaceRoom room, _SpaceSlot slot) onSlotTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SlotGrid(
          room: room,
          slots: room.group('R-B'),
          columns: 4,
          dense: dense,
          onSlotTap: onSlotTap,
        ),
        SizedBox(height: dense ? 9 : 18),
        _SlotGrid(
          room: room,
          slots: room.group('R-T'),
          columns: 4,
          dense: dense,
          onSlotTap: onSlotTap,
        ),
        const Spacer(),
        const _DashedDivider(),
        const Spacer(),
        _SlotGrid(
          room: room,
          slots: room.group('L-B'),
          columns: 4,
          dense: dense,
          onSlotTap: onSlotTap,
        ),
        SizedBox(height: dense ? 9 : 18),
        _SlotGrid(
          room: room,
          slots: room.group('L-T'),
          columns: 4,
          dense: dense,
          onSlotTap: onSlotTap,
        ),
      ],
    );
  }
}

class _Room213Layout extends StatelessWidget {
  const _Room213Layout({
    required this.room,
    required this.dense,
    required this.onSlotTap,
  });

  final _SpaceRoom room;
  final bool dense;
  final void Function(_SpaceRoom room, _SpaceSlot slot) onSlotTap;

  @override
  Widget build(BuildContext context) {
    final meeting = room.group('meeting').first;
    return Column(
      children: [
        _SlotGrid(
          room: room,
          slots: room.group('L-B'),
          columns: 5,
          dense: dense,
          onSlotTap: onSlotTap,
        ),
        SizedBox(height: dense ? 13 : 28),
        _SlotGrid(
          room: room,
          slots: room.group('L-T'),
          columns: 5,
          dense: dense,
          onSlotTap: onSlotTap,
        ),
        SizedBox(height: dense ? 13 : 28),
        _SlotGrid(
          room: room,
          slots: room.group('R-S'),
          columns: 5,
          dense: dense,
          onSlotTap: onSlotTap,
        ),
        const Spacer(),
        _MeetingTableBlock(
          slot: meeting,
          dense: dense,
          onTap: () => onSlotTap(room, meeting),
        ),
      ],
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.room,
    required this.slots,
    required this.columns,
    required this.dense,
    required this.onSlotTap,
  });

  final _SpaceRoom room;
  final List<_SpaceSlot> slots;
  final int columns;
  final bool dense;
  final void Function(_SpaceRoom room, _SpaceSlot slot) onSlotTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = dense ? 4.0 : 13.0;
        final availableItemWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        final maxDesktopItemWidth = switch (columns) {
          <= 3 => 74.0,
          4 => 68.0,
          5 => 58.0,
          _ => 50.0,
        };
        final itemWidth = dense
            ? availableItemWidth
            : math.min(availableItemWidth, maxDesktopItemWidth);
        final itemHeight = itemWidth *
            (dense ? (columns <= 3 ? 1.04 : 1.09) : 1.18);
        return Wrap(
          alignment: dense ? WrapAlignment.start : WrapAlignment.spaceAround,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final slot in slots)
              SizedBox(
                width: itemWidth,
                height: itemHeight,
                child: _SlotTile(
                  slot: slot,
                  dense: dense,
                  onTap: () => onSlotTap(room, slot),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.slot,
    required this.dense,
    required this.onTap,
  });

  final _SpaceSlot slot;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labelSize = dense ? 8.0 : 14.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(dense ? 1 : 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  slot.displayLabel ?? slot.label,
                  maxLines: 1,
                  style: TextStyle(
                    color: const Color(0xFF111827),
                    fontSize: labelSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    height: 1,
                  ),
                ),
              ),
              if (slot.note != null)
                Text(
                  slot.note!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF111827),
                    fontSize: dense ? 7 : 11,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    letterSpacing: 0,
                  ),
                ),
              SizedBox(height: dense ? 2 : 6),
              Expanded(child: _MiniStockBlock(status: slot.status)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStockBlock extends StatelessWidget {
  const _MiniStockBlock({required this.status});

  final _SpaceStatus status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        border: Border.all(color: const Color(0xFFC6CDD6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: CustomPaint(
          painter: _MiniStockPainter(status),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _MiniStockPainter extends CustomPainter {
  const _MiniStockPainter(this.status);

  final _SpaceStatus status;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = status.color.withValues(
        alpha: status == _SpaceStatus.empty ? 0.62 : 0.9,
      )
      ..style = PaintingStyle.fill;
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final count = status == _SpaceStatus.empty ? 4 : 6;
    final columns = count == 4 ? 2 : 3;
    final rows = count == 4 ? 2 : 2;
    final gap = size.width * 0.04;
    final cellW = (size.width - gap * (columns - 1)) / columns;
    final cellH = (size.height - gap * (rows - 1)) / rows;
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final rect = Rect.fromLTWH(
          column * (cellW + gap),
          row * (cellH + gap),
          cellW,
          cellH,
        );
        canvas.drawRect(rect, fill);
        canvas.drawLine(rect.topLeft, rect.topRight, edge);
        canvas.drawLine(rect.centerLeft, rect.centerRight, edge);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MiniStockPainter oldDelegate) {
    return oldDelegate.status != status;
  }
}

class _MeetingTableBlock extends StatelessWidget {
  const _MeetingTableBlock({
    required this.slot,
    required this.dense,
    required this.onTap,
  });

  final _SpaceSlot slot;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(2),
        onTap: onTap,
        child: SizedBox(
          height: dense ? 73 : 128,
          child: Stack(
            children: [
              Positioned(
                left: dense ? 35 : 58,
                right: dense ? 35 : 58,
                bottom: dense ? 8 : 16,
                top: dense ? 24 : 42,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5B28C),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF9B7756)),
                  ),
                ),
              ),
              for (final offset in const [0.18, 0.34, 0.50, 0.66])
                Positioned(
                  left: dense ? 38 + offset * 100 : 70 + offset * 210,
                  bottom: dense ? 0 : 6,
                  child: _ChairDot(size: dense ? 14 : 21),
                ),
              for (final offset in const [0.18, 0.34, 0.50, 0.66])
                Positioned(
                  left: dense ? 38 + offset * 100 : 70 + offset * 210,
                  top: dense ? 16 : 26,
                  child: _ChairDot(size: dense ? 14 : 21),
                ),
              Positioned(
                left: dense ? 48 : 74,
                top: 0,
                child: Text(
                  '${slot.displayLabel} (${slot.note})',
                  style: TextStyle(
                    color: const Color(0xFF111827),
                    fontSize: dense ? 9 : 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
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

class _ChairDot extends StatelessWidget {
  const _ChairDot({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF9CA3AF),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF6B7280)),
      ),
    );
  }
}

class _RoomOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wall = Paint()
      ..color = const Color(0xFF4B5563)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final thin = Paint()
      ..color = const Color(0xFF4B5563)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromLTWH(6, 8, size.width - 12, size.height - 14);
    canvas.drawRect(rect, wall);
    final topDoorRect = Rect.fromLTWH(size.width - 54, 8, 48, 48);
    canvas.drawArc(topDoorRect, math.pi / 2, math.pi / 2, false, thin);
    canvas.drawLine(
      Offset(size.width - 54, 8),
      Offset(size.width - 54, 46),
      thin,
    );
    final bottomDoorRect = Rect.fromLTWH(6, size.height - 54, 50, 50);
    canvas.drawArc(bottomDoorRect, -math.pi / 2, math.pi / 2, false, thin);
    canvas.drawLine(
      Offset(56, size.height - 8),
      Offset(18, size.height - 8),
      thin,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: CustomPaint(
        painter: _DashedDividerPainter(),
        child: SizedBox(height: 1, width: double.infinity),
      ),
    );
  }
}

class _DashedDividerPainter extends CustomPainter {
  const _DashedDividerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC4CBD4)
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + 6, size.width), 0),
        paint,
      );
      x += 11;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CarouselDots extends StatelessWidget {
  const _CarouselDots({required this.count, required this.selected});

  final int count;
  final int selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: index == selected
                  ? const Color(0xFF3B7DE0)
                  : const Color(0xFFC7CED8),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

class _RealtimeAlertPanel extends StatelessWidget {
  const _RealtimeAlertPanel({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rows = const [
      ('518호 L-B2', '재고가 부족합니다.', '방금 전', _SpaceStatus.part),
      ('532호 R-T3', '공정이 완료되었습니다.', '5분 전', _SpaceStatus.finished),
      ('불량/검수 대기', '2건에 확인 필요합니다.', '10분 전', _SpaceStatus.defective),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 18, 10, compact ? 10 : 14, 8),
      decoration: BoxDecoration(
        color: compact ? Colors.white : const Color(0xFF0E2235),
        borderRadius: BorderRadius.circular(compact ? 8 : 9),
        border: Border.all(
          color: compact ? const Color(0xFFE0E6EE) : const Color(0xFF3B4E63),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: compact ? 0.05 : 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                color: compact ? const Color(0xFF2778E8) : Colors.white,
                size: compact ? 17 : 15,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '실시간 알림',
                  style: TextStyle(
                    color: compact ? const Color(0xFF111827) : Colors.white,
                    fontSize: compact ? 13 : 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (compact)
                const Text(
                  '전체 보기  ›',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 6 : 12),
          for (final row in rows)
            _AlertRow(
              title: row.$1,
              body: row.$2,
              time: row.$3,
              color: row.$4.color,
              compact: compact,
            ),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.title,
    required this.body,
    required this.time,
    required this.color,
    required this.compact,
  });

  final String title;
  final String body;
  final String time;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textColor = compact ? const Color(0xFF111827) : Colors.white;
    final subColor = compact
        ? const Color(0xFF4B5563)
        : const Color(0xFFDCE6F3);
    return Container(
      height: compact ? 30 : 37,
      decoration: compact
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE9EDF4))),
            )
          : null,
      child: Row(
        children: [
          Container(
            width: compact ? 9 : 8,
            height: compact ? 9 : 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: compact ? 112 : 84,
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: compact ? 12 : 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              body,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: subColor,
                fontSize: compact ? 11 : 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          if (compact)
            Text(
              time,
              style: const TextStyle(
                color: Color(0xFF8B95A5),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (compact)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Color(0xFF9AA4B2),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusLegendPanel extends StatelessWidget {
  const _StatusLegendPanel({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final statuses = const [
      _SpaceStatus.part,
      _SpaceStatus.semi,
      _SpaceStatus.finished,
      _SpaceStatus.process,
      _SpaceStatus.reserved,
      _SpaceStatus.defective,
      _SpaceStatus.empty,
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        10,
        compact ? 12 : 14,
        10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 8 : 7),
        border: Border.all(color: const Color(0xFFE0E6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (compact)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                '상태 색상 안내',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          Wrap(
            spacing: compact ? 22 : 22,
            runSpacing: compact ? 7 : 9,
            children: [
              for (final status in statuses)
                _LegendItem(status: status, compact: compact),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.status, required this.compact});

  final _SpaceStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 82 : 88,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 10 : 13,
            height: compact ? 10 : 13,
            decoration: BoxDecoration(
              color: status.color,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              status.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF111827),
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendHelpPanel extends StatelessWidget {
  const _LegendHelpPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E6EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '상태 색상 안내',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _LegendItem(status: _SpaceStatus.part, compact: true),
              _LegendItem(status: _SpaceStatus.semi, compact: true),
              _LegendItem(status: _SpaceStatus.finished, compact: true),
              _LegendItem(status: _SpaceStatus.process, compact: true),
              _LegendItem(status: _SpaceStatus.reserved, compact: true),
              _LegendItem(status: _SpaceStatus.defective, compact: true),
              _LegendItem(status: _SpaceStatus.empty, compact: true),
            ],
          ),
          const Spacer(),
          const Divider(color: Color(0xFFE0E6EF), height: 1),
          const SizedBox(height: 6),
          const Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 28,
                color: Color(0xFF111827),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '박스를 클릭하면 해당 위치의\n상세 재고 정보를 확인할 수 있습니다.',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.22,
                    letterSpacing: 0,
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

class _CommonVerandaPanel extends StatelessWidget {
  const _CommonVerandaPanel({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCE3EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('☘', style: TextStyle(fontSize: 26, height: 1)),
              SizedBox(width: 8),
              Text(
                '공통 (베란다)',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: CustomPaint(
              painter: _RoomOutlinePainter(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 34, 22),
                child: Row(
                  children: [
                    Expanded(
                      child: _VerandaZone(
                        title: '임시 보관',
                        color: _SpaceStatus.part.color,
                        icon: Icons.local_shipping_outlined,
                        onTap: onTap,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _VerandaZone(
                        title: '대기품',
                        color: _SpaceStatus.semi.color,
                        icon: Icons.inventory_2_outlined,
                        onTap: onTap,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _VerandaZone(
                        title: '출고 대기',
                        color: _SpaceStatus.finished.color,
                        icon: Icons.shopping_bag_outlined,
                        onTap: onTap,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _VerandaZone(
                        title: '불량/검수 대기',
                        color: _SpaceStatus.defective.color,
                        icon: Icons.warning_amber_rounded,
                        onTap: onTap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerandaZone extends StatelessWidget {
  const _VerandaZone({
    required this.title,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFFC8D0DA),
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 9),
              Icon(icon, color: color, size: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileSpaceNav extends StatelessWidget {
  const _MobileSpaceNav({required this.onHome, required this.onScan});

  final VoidCallback onHome;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: const Color(0xFFE4E9F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _MobileNavItem(
            icon: Icons.home_outlined,
            label: '대시보드',
            onTap: onHome,
          ),
          const _MobileNavItem(
            icon: Icons.location_on_outlined,
            label: '공간 맵',
            selected: true,
          ),
          _MobileNavItem(
            icon: Icons.qr_code_scanner_rounded,
            label: 'QR 스캔',
            onTap: onScan,
          ),
          const _MobileNavItem(icon: Icons.list_alt_outlined, label: '재고 관리'),
          const _MobileNavItem(icon: Icons.settings_outlined, label: '설정'),
        ],
      ),
    );
  }
}

class _MobileNavItem extends StatelessWidget {
  const _MobileNavItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFF334155);
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: selected ? 21 : 19, color: color),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: 0,
          ),
        ),
      ],
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 49 : 44,
          height: selected ? 51 : 48,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1F73DC) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF1F73DC).withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DesktopSpaceRail extends StatelessWidget {
  const _DesktopSpaceRail({required this.onHome, required this.onScan});

  final VoidCallback onHome;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      color: const Color(0xFF0B1D2D),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            _RailItem(
              icon: Icons.home_work_outlined,
              label: '대시보드',
              onTap: onHome,
            ),
            const SizedBox(height: 14),
            const _RailItem(
              icon: Icons.location_on_outlined,
              label: '공간 맵',
              selected: true,
            ),
            const SizedBox(height: 14),
            _RailItem(
              icon: Icons.qr_code_scanner_rounded,
              label: 'QR 스캔',
              onTap: onScan,
            ),
            const SizedBox(height: 14),
            const _RailItem(icon: Icons.list_alt_outlined, label: '재고 관리'),
            const SizedBox(height: 14),
            const _RailItem(icon: Icons.account_tree_outlined, label: '공정 관리'),
            const SizedBox(height: 14),
            const _RailItem(icon: Icons.manage_search_rounded, label: '이력 조회'),
            const Spacer(),
            const _RailItem(icon: Icons.settings_outlined, label: '설정'),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF58A7FF) : Colors.white;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 70,
          height: 68,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF133F70) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryDetailDialog extends StatelessWidget {
  const _InventoryDetailDialog({required this.room, required this.slot});

  final _SpaceRoom room;
  final _SpaceSlot slot;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final verticalInset = screenSize.height < 720 ? 10.0 : 24.0;

    return Dialog(
      alignment: const Alignment(0, 0.18),
      insetPadding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: verticalInset,
      ),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 330,
          maxHeight: screenSize.height - (verticalInset * 2),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 15, 14, 13),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${room.id}호 / ${slot.label} 상세 재고',
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 28,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
              const Text(
                '해당 구역 내부 재고 현황',
                style: TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _inventoryProducts.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.70,
                ),
                itemBuilder: (context, index) {
                  return _InventoryProductCard(
                    product: _inventoryProducts[index],
                    compact: true,
                  );
                },
              ),
              const SizedBox(height: 12),
              const _InventorySummaryBar(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(39),
                        foregroundColor: const Color(0xFF1264DA),
                        side: const BorderSide(color: Color(0xFF1264DA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      onPressed: () {},
                      child: const Text('상세 보기'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(39),
                        backgroundColor: const Color(0xFF1264DA),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('닫기'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryProductCard extends StatelessWidget {
  const _InventoryProductCard({required this.product, this.compact = false});

  final _InventoryProduct product;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(8, compact ? 8 : 11, 8, compact ? 7 : 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE0E6EF)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: compact ? 9 : 12,
                height: compact ? 9 : 12,
                decoration: BoxDecoration(
                  color: product.status.color,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: compact ? 5 : 7),
              Expanded(
                child: Text(
                  product.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: compact ? 56 : 76,
            height: compact ? 45 : 62,
            child: CustomPaint(
              painter: _InventoryItemPainter(product.kind),
              child: const SizedBox.expand(),
            ),
          ),
          const Spacer(),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 10,
              vertical: compact ? 3 : 5,
            ),
            decoration: BoxDecoration(
              color: product.shortage
                  ? const Color(0xFFFFE8E3)
                  : const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: product.shortage
                    ? const Color(0xFFFFA096)
                    : const Color(0xFFC4DAFF),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (product.shortage) ...[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: Color(0xFFFF402F),
                  ),
                  const SizedBox(width: 3),
                  const Text(
                    '부족',
                    style: TextStyle(
                      color: Color(0xFFFF402F),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  '${product.quantity}개',
                  style: TextStyle(
                    color: product.shortage
                        ? const Color(0xFFFF402F)
                        : const Color(0xFF111827),
                    fontSize: compact ? 13 : 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
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

class _InventorySummaryBar extends StatelessWidget {
  const _InventorySummaryBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE0E6EF)),
      ),
      child: Row(
        children: const [
          _InventorySummaryItem(
            icon: Icons.inventory_2_outlined,
            label: '총 6종',
            color: Color(0xFF2F7DFF),
          ),
          _VerticalSoftDivider(),
          _InventorySummaryItem(
            icon: Icons.all_inbox_outlined,
            label: '재고 38개',
            color: Color(0xFF2F7DFF),
          ),
          _VerticalSoftDivider(),
          _InventorySummaryItem(
            icon: Icons.warning_amber_rounded,
            label: '부족 1건',
            color: Color(0xFFFF402F),
          ),
        ],
      ),
    );
  }
}

class _InventorySummaryItem extends StatelessWidget {
  const _InventorySummaryItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: color == const Color(0xFFFF402F)
                    ? color
                    : const Color(0xFF111827),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalSoftDivider extends StatelessWidget {
  const _VerticalSoftDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 25, color: const Color(0xFFE0E6EF));
  }
}

class _InventoryItemPainter extends CustomPainter {
  const _InventoryItemPainter(this.kind);

  final _InventoryIllustrationKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    switch (kind) {
      case _InventoryIllustrationKind.motor:
        _paintMotor(canvas, size);
      case _InventoryIllustrationKind.module:
        _paintModule(canvas, size);
      case _InventoryIllustrationKind.greenBin:
        _paintBin(
          canvas,
          size,
          const Color(0xFF5DBC68),
          const Color(0xFF2F8D42),
        );
      case _InventoryIllustrationKind.yellowBin:
        _paintBin(
          canvas,
          size,
          const Color(0xFFFFC931),
          const Color(0xFFE0A600),
        );
      case _InventoryIllustrationKind.blueBin:
        _paintBin(
          canvas,
          size,
          const Color(0xFF278DF0),
          const Color(0xFF0D5FC1),
        );
    }
  }

  void _paintBin(Canvas canvas, Size size, Color fill, Color stroke) {
    final shadow = Paint()..color = Colors.black.withValues(alpha: 0.17);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.52, size.height * 0.86),
        width: size.width * 0.72,
        height: size.height * 0.14,
      ),
      shadow,
    );
    final side = Paint()..color = fill;
    final edge = Paint()
      ..color = stroke
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final body = Path()
      ..moveTo(size.width * 0.18, size.height * 0.34)
      ..lineTo(size.width * 0.82, size.height * 0.34)
      ..lineTo(size.width * 0.72, size.height * 0.80)
      ..lineTo(size.width * 0.30, size.height * 0.80)
      ..close();
    canvas.drawPath(body, side);
    canvas.drawPath(body, edge);
    final top = Path()
      ..moveTo(size.width * 0.18, size.height * 0.34)
      ..lineTo(size.width * 0.50, size.height * 0.14)
      ..lineTo(size.width * 0.82, size.height * 0.34)
      ..lineTo(size.width * 0.50, size.height * 0.52)
      ..close();
    canvas.drawPath(top, Paint()..color = fill.withValues(alpha: 0.82));
    canvas.drawPath(top, edge);
    final inner = Path()
      ..moveTo(size.width * 0.30, size.height * 0.35)
      ..lineTo(size.width * 0.50, size.height * 0.24)
      ..lineTo(size.width * 0.70, size.height * 0.35)
      ..lineTo(size.width * 0.50, size.height * 0.46)
      ..close();
    canvas.drawPath(
      inner,
      Paint()..color = const Color(0xFFBFE0FF).withValues(alpha: 0.72),
    );
    canvas.drawPath(
      inner,
      Paint()
        ..color = stroke.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke,
    );
  }

  void _paintMotor(Canvas canvas, Size size) {
    final blue = Paint()..color = const Color(0xFF5EA8F2);
    final dark = Paint()
      ..color = const Color(0xFF1C5F9B)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.28,
        size.height * 0.28,
        size.width * 0.46,
        size.height * 0.38,
      ),
      const Radius.circular(14),
    );
    canvas.drawRRect(body, blue);
    canvas.drawRRect(body, dark);
    for (var i = 0; i < 5; i++) {
      final x = size.width * (0.34 + i * 0.075);
      canvas.drawLine(
        Offset(x, size.height * 0.30),
        Offset(x, size.height * 0.64),
        Paint()
          ..color = const Color(0xFF2E7CC1)
          ..strokeWidth = 1.2,
      );
    }
    canvas.drawCircle(
      Offset(size.width * 0.23, size.height * 0.48),
      size.width * 0.14,
      blue,
    );
    canvas.drawCircle(
      Offset(size.width * 0.23, size.height * 0.48),
      size.width * 0.14,
      dark,
    );
    canvas.drawCircle(
      Offset(size.width * 0.23, size.height * 0.48),
      size.width * 0.07,
      Paint()..color = const Color(0xFFD8EFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.74,
        size.height * 0.42,
        size.width * 0.17,
        size.height * 0.10,
      ),
      Paint()..color = const Color(0xFF74B6F5),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.50,
        size.height * 0.16,
        size.width * 0.16,
        size.height * 0.12,
      ),
      Paint()..color = const Color(0xFF74B6F5),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.50,
        size.height * 0.16,
        size.width * 0.16,
        size.height * 0.12,
      ),
      dark,
    );
  }

  void _paintModule(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.15,
        size.height * 0.22,
        size.width * 0.70,
        size.height * 0.56,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0xFF2F87D7));
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFF07569F)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.25,
          size.height * 0.30,
          size.width * 0.34,
          size.height * 0.30,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFE4EEF7),
    );
    canvas.drawCircle(
      Offset(size.width * 0.70, size.height * 0.52),
      size.width * 0.08,
      Paint()..color = const Color(0xFF104F89),
    );
    canvas.drawCircle(
      Offset(size.width * 0.70, size.height * 0.52),
      size.width * 0.045,
      Paint()..color = const Color(0xFF9ED3FF),
    );
  }

  @override
  bool shouldRepaint(covariant _InventoryItemPainter oldDelegate) {
    return oldDelegate.kind != kind;
  }
}

class _AvaStockSplash extends StatefulWidget {
  const _AvaStockSplash();

  @override
  State<_AvaStockSplash> createState() => _AvaStockSplashState();
}

class _AvaStockSplashState extends State<_AvaStockSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinnerController;

  @override
  void initState() {
    super.initState();
    _spinnerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 960),
    )..repeat();
  }

  @override
  void dispose() {
    _spinnerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.18, -0.2),
            radius: 1.16,
            colors: [Color(0xFFFFFFFF), Color(0xFFF7F8FF)],
            stops: [0.58, 1],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final logoWidth = math.min(width * 0.53, 222.0);
            final allionFontSize = math.min(width * 0.105, 42.0);

            return Stack(
              key: const ValueKey('ava-stock-code-splash'),
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _AvaStockWavePainter()),
                  ),
                ),
                Positioned(
                  top: height * 0.16,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AvaLogoMark(width: logoWidth),
                      const SizedBox(height: 7),
                      _BrandLine(width: logoWidth),
                      SizedBox(height: height * 0.052),
                      Text(
                        'ALLION',
                        style: TextStyle(
                          color: const Color(0xFF06133C),
                          fontSize: allionFontSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '\uC0DD\uC0B0 \u00B7 \uC785\uCD9C\uACE0 \u00B7 \uC7AC\uACE0 \uAD00\uB9AC',
                        style: TextStyle(
                          color: Color(0xFF63646C),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      SizedBox(height: height * 0.078),
                      _AvaStockSpinner(animation: _spinnerController),
                      const SizedBox(height: 24),
                      const Text(
                        '\uCD08\uAE30\uD654 \uC911...',
                        style: TextStyle(
                          color: Color(0xFF6F7077),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AvaLogoMark extends StatelessWidget {
  const _AvaLogoMark({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: width,
            height: width * 0.44,
            child: CustomPaint(painter: _AvaMountainPainter()),
          ),
          SizedBox(height: width * 0.035),
          Text(
            'AVA',
            style: TextStyle(
              color: const Color(0xFF06133C),
              fontSize: width * 0.31,
              fontWeight: FontWeight.w900,
              height: 0.86,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandLine extends StatelessWidget {
  const _BrandLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final fontSize = math.max(12.0, math.min(width * 0.078, 17.0));
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: const Color(0xFF06133C),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          height: 1,
        ),
        children: const [
          TextSpan(text: 'Abbas '),
          TextSpan(
            text: 'Vanguard',
            style: TextStyle(color: Color(0xFF7257FF)),
          ),
          TextSpan(text: ' AI'),
        ],
      ),
    );
  }
}

class _AvaMountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF06133C)
      ..strokeWidth = size.width * 0.035
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.88)
      ..lineTo(size.width * 0.28, size.height * 0.14)
      ..quadraticBezierTo(
        size.width * 0.31,
        size.height * 0.035,
        size.width * 0.36,
        size.height * 0.14,
      )
      ..lineTo(size.width * 0.47, size.height * 0.66)
      ..quadraticBezierTo(
        size.width * 0.50,
        size.height * 0.82,
        size.width * 0.55,
        size.height * 0.66,
      )
      ..lineTo(size.width * 0.66, size.height * 0.14)
      ..quadraticBezierTo(
        size.width * 0.71,
        size.height * 0.035,
        size.width * 0.75,
        size.height * 0.14,
      )
      ..lineTo(size.width * 0.94, size.height * 0.88);
    canvas.drawPath(path, paint);

    final dotPaint = Paint()..style = PaintingStyle.fill;
    dotPaint.color = const Color(0xFF7453FF);
    canvas.drawCircle(
      Offset(size.width * 0.29, size.height * 0.48),
      size.width * 0.022,
      dotPaint,
    );
    dotPaint.color = const Color(0xFF167BFF);
    canvas.drawCircle(
      Offset(size.width * 0.68, size.height * 0.48),
      size.width * 0.022,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AvaMountainPainter oldDelegate) => false;
}

class _AvaStockSpinner extends StatelessWidget {
  const _AvaStockSpinner({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return CustomPaint(painter: _AvaStockSpinnerPainter(animation.value));
        },
      ),
    );
  }
}

class _AvaStockSpinnerPainter extends CustomPainter {
  const _AvaStockSpinnerPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = size.width * 0.068;
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: const [
          Color(0x00FFFFFF),
          Color(0xFFB78DFF),
          Color(0xFF5C6BFF),
          Color(0xFF2F56FF),
        ],
        stops: const [0, 0.42, 0.76, 1],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawArc(
      rect.deflate(strokeWidth),
      -math.pi * 0.93 + progress * math.pi * 2,
      math.pi * 1.62,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AvaStockSpinnerPainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}

class _AvaStockWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final baseY = size.height * 0.80;
    final amplitude = size.height * 0.06;
    final strokeWidth = math.max(0.6, size.width * 0.002);

    for (var index = 0; index < 13; index += 1) {
      final t = index / 12.0;
      final paint = Paint()
        ..color = Color.lerp(
          const Color(0x477759FF),
          const Color(0x313B78FF),
          t,
        )!
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final y = baseY + index * size.height * 0.014;
      final path = Path()
        ..moveTo(-size.width * 0.08, y + amplitude * 0.35)
        ..cubicTo(
          size.width * 0.20,
          y - amplitude * 0.78,
          size.width * 0.42,
          y + amplitude * 0.72,
          size.width * 0.58,
          y + amplitude * 0.20,
        )
        ..cubicTo(
          size.width * 0.80,
          y - amplitude * 0.52,
          size.width * 0.88,
          y - amplitude * 1.42,
          size.width * 1.08,
          y - amplitude * 2.55,
        );
      canvas.drawPath(path, paint);
    }

    final veil = Paint()
      ..shader =
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00FFFFFF), Color(0xCCFFFFFF)],
          ).createShader(
            Rect.fromLTWH(
              0,
              size.height * 0.86,
              size.width,
              size.height * 0.14,
            ),
          );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.86, size.width, size.height * 0.14),
      veil,
    );
  }

  @override
  bool shouldRepaint(covariant _AvaStockWavePainter oldDelegate) => false;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 18, 12),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF4663CF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.white,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF12203B),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF738096),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4663CF)),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({
    required this.home,
    required this.onScan,
    required this.onDashboard,
    required this.onSpaceDashboard,
  });

  final AvaStockHomeDto? home;
  final VoidCallback onScan;
  final VoidCallback onDashboard;
  final VoidCallback onSpaceDashboard;

  @override
  Widget build(BuildContext context) {
    final summary = home?.summary ?? const {};
    final recentShipment = (home?.recentShipments ?? const []).isEmpty
        ? null
        : home!.recentShipments.first;

    return ColoredBox(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 44, 28, 26),
        children: [
          const Center(child: _AvaStockHomeLogo()),
          const SizedBox(height: 56),
          const _HomeSectionLabel('\uBE60\uB978 \uBA54\uB274'),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 3.34,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _QuickCard(
                icon: Icons.qr_code_scanner_rounded,
                iconColor: const Color(0xFF116DFF),
                label: 'QR \uC2A4\uCE94',
                onTap: onScan,
              ),
              _QuickCard(
                icon: Icons.assignment_turned_in_outlined,
                iconColor: const Color(0xFF1CB75B),
                label: '\uC81C\uC870\uC644\uB8CC',
                onTap: onScan,
              ),
              _QuickCard(
                icon: Icons.inventory_2_outlined,
                iconColor: const Color(0xFF116DFF),
                label: '\uC785\uCD9C\uACE0',
                onTap: onDashboard,
              ),
              _QuickCard(
                key: const ValueKey('ava-stock-space-dashboard-card'),
                icon: Icons.map_outlined,
                iconColor: const Color(0xFF2F7D9D),
                label: '공간 대시보드',
                onTap: onSpaceDashboard,
              ),
              _QuickCard(
                icon: Icons.build_rounded,
                iconColor: const Color(0xFF8B6BF4),
                label: 'A/S',
                onTap: onScan,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _HomeSectionLabel('\uC7AC\uACE0 \uC694\uC57D'),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 2.5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              _SummaryCard(
                label: '\uCD1D \uC7AC\uACE0',
                value: summary['totalStock'],
                icon: Icons.inventory_2_outlined,
                iconColor: const Color(0xFF116DFF),
                iconBackground: const Color(0xFFEAF3FF),
              ),
              _SummaryCard(
                label: '\uCD9C\uACE0 \uAC00\uB2A5',
                value: summary['shippable'],
                icon: Icons.check_circle_outline_rounded,
                iconColor: const Color(0xFF34AD54),
                iconBackground: const Color(0xFFEAF9EE),
              ),
              _SummaryCard(
                label: '\uBC30\uC1A1\uC911',
                value: summary['shipping'],
                icon: Icons.local_shipping_outlined,
                iconColor: const Color(0xFFF5A522),
                iconBackground: const Color(0xFFFFF4D8),
              ),
              _SummaryCard(
                label: '\uC0DD\uC0B0\uC911',
                value: summary['inProduction'],
                icon: Icons.precision_manufacturing_outlined,
                iconColor: const Color(0xFF116DFF),
                iconBackground: const Color(0xFFEAF3FF),
              ),
              _SummaryCard(
                label: '\uD655\uC778 \uB300\uAE30',
                value: summary['reviewPending'],
                icon: Icons.fact_check_outlined,
                iconColor: const Color(0xFF4663CF),
                iconBackground: const Color(0xFFEFF3FF),
              ),
              _SummaryCard(
                label: '\uC810\uAC80/\uC218\uB9AC',
                value: summary['inspectionRepair'],
                icon: Icons.build_rounded,
                iconColor: const Color(0xFF8B6BF4),
                iconBackground: const Color(0xFFF1ECFF),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _HomeSectionLabel('\uCD5C\uADFC \uCD9C\uACE0'),
          const SizedBox(height: 8),
          _RecentShipmentCard(shipment: recentShipment),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: FilledButton(
              onPressed: onDashboard,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0677FF),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              child: const Text('\uC785\uCD9C\uACE0 \uD604\uD669 \uBCF4\uAE30'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvaStockHomeLogo extends StatelessWidget {
  const _AvaStockHomeLogo();

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Color(0xFF4663CF), BlendMode.srcIn),
      child: Image.asset(
        'assets/images/abba_ai_login_logo.png',
        width: 212,
        height: 60,
        fit: BoxFit.contain,
      ),
    );
  }
}

class _QrScanView extends StatefulWidget {
  const _QrScanView({required this.onBack, required this.onSubmit});

  final VoidCallback onBack;
  final Future<void> Function(String value) onSubmit;

  @override
  State<_QrScanView> createState() => _QrScanViewState();
}

class _QrScanViewState extends State<_QrScanView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _scannerController = MobileScannerController();
  final _controllerText = TextEditingController();
  bool _handlingScan = false;

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
    _scannerController.dispose();
    _controllerText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canUseCameraScanner = Platform.isAndroid || Platform.isIOS;
    final topInset = MediaQuery.paddingOf(context).top;
    return ColoredBox(
      color: const Color(0xFF0D1014),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (canUseCameraScanner)
            MobileScanner(
              controller: _scannerController,
              fit: BoxFit.cover,
              onDetect: (capture) {
                if (_handlingScan) {
                  return;
                }
                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue?.trim();
                  if (value != null && value.isNotEmpty) {
                    unawaited(_submit(value));
                    break;
                  }
                }
              },
            )
          else
            const Positioned.fill(
              child: CustomPaint(painter: _QrFallbackCameraScene()),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.58),
                    Colors.black.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.28),
                    Colors.black.withValues(alpha: 0.62),
                  ],
                  stops: const [0, 0.30, 0.68, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            top: topInset + 8,
            child: SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: widget.onBack,
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 29,
                      ),
                    ),
                  ),
                  const Text(
                    'QR \uCF54\uB4DC \uC2A4\uCE94',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: topInset + 86,
            child: const Text(
              '\uCF54\uB4DC\uB97C \uC0AC\uAC01\uD615 \uC548\uC5D0 \uB9DE\uCD94\uC138\uC694',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
              ),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const sheetHeight = 143.0;
                final frameWidth = math.min(260.0, constraints.maxWidth * 0.62);
                final frameHeight = frameWidth * 1.34;
                final initialFrameTop = math.max(
                  topInset + 104.0,
                  math.min(
                    topInset + math.max(112.0, constraints.maxHeight * 0.145),
                    constraints.maxHeight - sheetHeight - frameHeight - 116,
                  ),
                );
                final frameLeft = (constraints.maxWidth - frameWidth) / 2;
                final sheetTop = constraints.maxHeight - sheetHeight;
                final initialFrameBottom = initialFrameTop + frameHeight;
                final actionGap = sheetTop - initialFrameBottom;
                final actionTop = math.min(
                  sheetTop - 62,
                  initialFrameBottom +
                      math.max(16.0, (actionGap - 64) / 2) +
                      10,
                );
                final guideBottom = topInset + 106.0;
                final centeredFrameTop =
                    (guideBottom + actionTop - frameHeight) / 2;
                final minFrameTop = topInset + 104.0;
                final maxFrameTop = math.max(
                  minFrameTop,
                  actionTop - frameHeight - 16,
                );
                final safeFrameTop = centeredFrameTop.clamp(
                  minFrameTop,
                  maxFrameTop,
                );
                final scanTravel = math.max(0.0, frameHeight - 84);

                return Stack(
                  children: [
                    Positioned(
                      left: frameLeft,
                      top: safeFrameTop,
                      width: frameWidth,
                      height: frameHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const CustomPaint(painter: _QrScannerFramePainter()),
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              return Positioned(
                                left: -4,
                                right: -4,
                                top: 42 + _controller.value * scanTravel,
                                child: const _QrScanLine(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: actionTop,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _QrScannerAction(
                            icon: Icons.flashlight_on_outlined,
                            label: '\uC190\uC804\uB4F1',
                            onTap: canUseCameraScanner
                                ? () => unawaited(
                                    _scannerController.toggleTorch(),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 84),
                          const _QrScannerAction(
                            icon: Icons.photo_outlined,
                            label:
                                '\uC568\uBC94\uC5D0\uC11C \uAC00\uC838\uC624\uAE30',
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 143,
              decoration: const BoxDecoration(
                color: Color(0xFFFAFBFF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 18,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 31,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8DCE5),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 17),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showManualInput,
                        icon: const Icon(Icons.keyboard_alt_outlined, size: 22),
                        label: const Text('\uC9C1\uC811 \uC785\uB825'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4663CF),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFFE1E6F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          shadowColor: Colors.black.withValues(alpha: 0.08),
                          elevation: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _showManualInput,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF4663CF),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text(
                      '\uCF54\uB4DC\uAC00 \uC548 \uBCF4\uC5EC\uC694?  \u203A',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showManualInput() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('QR \uCF54\uB4DC \uC785\uB825'),
          content: TextField(
            controller: _controllerText,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'QR \uCF54\uB4DC'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('\uCDE8\uC18C'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_controllerText.text),
              child: const Text('\uD655\uC778'),
            ),
          ],
        );
      },
    );
    if (value != null) {
      await _submit(value);
    }
  }

  Future<void> _submit(String rawValue) async {
    final value = rawValue.trim();
    if (value.isEmpty || _handlingScan) {
      return;
    }
    _controllerText.text = value;
    setState(() => _handlingScan = true);
    try {
      await widget.onSubmit(value);
    } finally {
      if (mounted) {
        setState(() => _handlingScan = false);
      }
    }
  }
}

class _QrScanLine extends StatelessWidget {
  const _QrScanLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: const Color(0xFF74A9FF),
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [
          BoxShadow(color: Color(0xCC74A9FF), blurRadius: 12, spreadRadius: 2),
        ],
      ),
    );
  }
}

class _QrScannerAction extends StatelessWidget {
  const _QrScannerAction({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 25),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrScannerFramePainter extends CustomPainter {
  const _QrScannerFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    const radius = 19.0;
    final length = math.min(size.width, size.height) * 0.20;
    final rect = Offset.zero & size;
    final path = Path()
      ..moveTo(rect.left, rect.top + radius + length)
      ..lineTo(rect.left, rect.top + radius)
      ..quadraticBezierTo(rect.left, rect.top, rect.left + radius, rect.top)
      ..lineTo(rect.left + radius + length, rect.top)
      ..moveTo(rect.right - radius - length, rect.top)
      ..lineTo(rect.right - radius, rect.top)
      ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + radius)
      ..lineTo(rect.right, rect.top + radius + length)
      ..moveTo(rect.right, rect.bottom - radius - length)
      ..lineTo(rect.right, rect.bottom - radius)
      ..quadraticBezierTo(
        rect.right,
        rect.bottom,
        rect.right - radius,
        rect.bottom,
      )
      ..lineTo(rect.right - radius - length, rect.bottom)
      ..moveTo(rect.left + radius + length, rect.bottom)
      ..lineTo(rect.left + radius, rect.bottom)
      ..quadraticBezierTo(
        rect.left,
        rect.bottom,
        rect.left,
        rect.bottom - radius,
      )
      ..lineTo(rect.left, rect.bottom - radius - length);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _QrScannerFramePainter oldDelegate) => false;
}

class _QrFallbackCameraScene extends CustomPainter {
  const _QrFallbackCameraScene();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF29323A), Color(0xFF11161A)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final shelfPaint = Paint()..color = const Color(0xFF1D2B35);
    for (var i = 0; i < 4; i++) {
      final y = size.height * (0.08 + i * 0.16);
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, size.height * 0.035),
        shelfPaint,
      );
      final binPaint = Paint()
        ..color = i.isEven ? const Color(0xFF163D67) : const Color(0xFF2B3740);
      for (var x = 16.0; x < size.width; x += 82) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y + 10, 58, 32),
            const Radius.circular(4),
          ),
          binPaint,
        );
      }
    }

    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.58, size.width, size.height * 0.42),
      Paint()..color = const Color(0xFF26312F),
    );
    final boxRect = Rect.fromCenter(
      center: Offset(size.width * 0.52, size.height * 0.48),
      width: size.width * 0.60,
      height: size.height * 0.27,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(boxRect, const Radius.circular(5)),
      Paint()..color = const Color(0xFFB48755),
    );
    final labelRect = Rect.fromLTWH(
      boxRect.left + boxRect.width * 0.16,
      boxRect.top + boxRect.height * 0.29,
      boxRect.width * 0.62,
      boxRect.height * 0.48,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(3)),
      Paint()..color = const Color(0xFFECE8DE),
    );
    final qrPaint = Paint()..color = const Color(0xFF161719);
    final cell = labelRect.width * 0.055;
    for (var row = 0; row < 11; row++) {
      for (var col = 0; col < 11; col++) {
        if ((row * 3 + col * 5) % 4 == 0 ||
            (row < 2 && col < 2) ||
            (row > 8 && col < 2) ||
            (row < 2 && col > 8)) {
          canvas.drawRect(
            Rect.fromLTWH(
              labelRect.left + labelRect.width * 0.48 + col * cell,
              labelRect.top + labelRect.height * 0.18 + row * cell,
              cell * 0.82,
              cell * 0.82,
            ),
            qrPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrFallbackCameraScene oldDelegate) => false;
}

class _PartView extends StatelessWidget {
  const _PartView({required this.part, required this.onPurchase});

  final Map<String, dynamic>? part;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    if (part == null) {
      return const _EmptyCard(
        text:
            '\uBD80\uD488 \uC815\uBCF4\uB97C \uBD88\uB7EC\uC62C \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ImageCard(
          title: part!['partName']?.toString() ?? '\uBD80\uD488',
          subtitle: part!['partCode']?.toString() ?? '',
          icon: Icons.precision_manufacturing_outlined,
          imageUrl: part!['imageUrl']?.toString(),
        ),
        const SizedBox(height: 18),
        _BigNumberCard(
          label: '\uD604\uC7AC \uC7AC\uACE0',
          value: '${part!['currentQty'] ?? 0} ${part!['unit'] ?? 'EA'}',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onPurchase,
          icon: const Icon(Icons.add_shopping_cart_outlined),
          label: const Text(
            '\uCD94\uAC00\uB9E4\uC785 \uC218\uB7C9 \uC785\uB825',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4663CF),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.history),
          label: const Text('\uC7AC\uACE0 \uC774\uB825 \uBCF4\uAE30'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _ChecklistView extends StatelessWidget {
  const _ChecklistView({
    required this.title,
    required this.product,
    required this.items,
    required this.checked,
    required this.onToggle,
    required this.onSave,
    required this.onComplete,
  });

  final String title;
  final Map<String, dynamic>? product;
  final List<Map<String, dynamic>> items;
  final Map<int, bool> checked;
  final void Function(int bomItemId, bool value) onToggle;
  final VoidCallback onSave;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final progress = (product?['progress'] as Map? ?? const {})
        .cast<String, dynamic>();
    final pct = _asDouble(progress['decisionProgressPct']);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ImageCard(
          title: product?['modelName']?.toString() ?? title,
          subtitle:
              'IMEI / \uACE0\uC720\uBC88\uD638 : ${product?['serialNo'] ?? '-'}',
          icon: Icons.memory_outlined,
          imageUrl: product?['modelImageUrl']?.toString(),
          imageFit: BoxFit.contain,
          imageSize: 104,
        ),
        const SizedBox(height: 16),
        _ProgressCard(value: pct / 100),
        const SizedBox(height: 16),
        for (final item in items)
          _ChecklistRow(
            item: item,
            checked: checked[_asInt(item['bomItemId']) ?? -1] ?? false,
            onChanged: (value) {
              final id = _asInt(item['bomItemId']);
              if (id != null) {
                onToggle(id, value);
              }
            },
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onSave,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF111827),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  '\uC800\uC7A5',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onComplete,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4663CF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  '\uC81C\uC870\uC644\uB8CC',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FinishedReviewView extends StatelessWidget {
  const _FinishedReviewView({
    required this.product,
    required this.onEdit,
    required this.onConfirm,
  });

  final Map<String, dynamic>? product;
  final VoidCallback onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    if (product == null) {
      return const _EmptyCard(text: '?쒗뭹 ?뺣낫瑜?遺덈윭?????놁뒿?덈떎.');
    }
    final usedParts = product!['usedParts'] as List? ?? const [];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ImageCard(
          title: product!['modelName']?.toString() ?? '?꾩젣???뺤씤',
          subtitle: 'IMEI / 怨좎쑀踰덊샇 : ${product!['serialNo'] ?? '-'}',
          icon: Icons.inventory_2_outlined,
          imageUrl: product!['modelImageUrl']?.toString(),
          imageFit: BoxFit.contain,
          imageSize: 132,
        ),
        const SizedBox(height: 16),
        const _ListCard(
          title: '?뺤씤 ?④퀎',
          subtitle: '泥댄겕??遺?덇낵 ?쒗뭹 ?뺣낫瑜?留덉?留됱쑝濡??뺤씤?댁＜?몄슂.',
        ),
        const SizedBox(height: 10),
        _SectionTitle('사용 부품 ${usedParts.length}개'),
        const SizedBox(height: 10),
        for (final raw in usedParts)
          _ListCard(
            title: (raw as Map)['partName']?.toString() ?? '부품',
            subtitle: '제조 ${raw['manufacturingQty'] ?? 0}개',
            trailing: '${raw['totalQty'] ?? 0}',
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF111827),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('?섏젙'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: onConfirm,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4663CF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('?쒖“ ?뺤씤'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FinishedRegisterView extends StatefulWidget {
  const _FinishedRegisterView({required this.product, required this.onSubmit});

  final Map<String, dynamic>? product;
  final Future<void> Function({
    required String destinationName,
    required String imei,
    required String shippingMethod,
    required DateTime shippingDate,
  })
  onSubmit;

  @override
  State<_FinishedRegisterView> createState() => _FinishedRegisterViewState();
}

class _FinishedRegisterViewState extends State<_FinishedRegisterView> {
  late final TextEditingController _destinationController;
  late final TextEditingController _imeiController;
  late final TextEditingController _shippingController;
  late DateTime _shippingDate;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final latestShipment = _latestShipment(widget.product);
    _destinationController = TextEditingController(
      text: latestShipment?['destinationName']?.toString() ?? '',
    );
    _imeiController = TextEditingController(
      text: widget.product?['serialNo']?.toString() ?? '',
    );
    _shippingController = TextEditingController(
      text: latestShipment?['shippingMethod']?.toString() ?? '',
    );
    _shippingDate =
        _parseDate(latestShipment?['shippingDate']?.toString()) ??
        DateTime.now();
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _imeiController.dispose();
    _shippingController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _shippingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _shippingDate = picked);
    }
  }

  Future<void> _submit() async {
    final destination = _destinationController.text.trim();
    final imei = _imeiController.text.trim();
    final shipping = _shippingController.text.trim();
    if (destination.isEmpty || imei.isEmpty || shipping.isEmpty) {
      setState(() => _errorText = '?⑺뭹泥? IMEI, 異쒓퀬, 異쒓퀬?쇱쓣 紐⑤몢 ?낅젰?댁＜?몄슂.');
      return;
    }
    setState(() => _errorText = null);
    await widget.onSubmit(
      destinationName: destination,
      imei: imei,
      shippingMethod: shipping,
      shippingDate: _shippingDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    if (product == null) {
      return const _EmptyCard(text: '?쒗뭹 ?뺣낫瑜?遺덈윭?????놁뒿?덈떎.');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 28),
      children: [
        Text(
          product['modelName']?.toString() ?? 'ALLION',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 34,
            height: 1,
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 246,
            height: 286,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _AvaStockCardImage(
              imageUrl: product['modelImageUrl']?.toString(),
              fallbackIcon: Icons.inventory_2_outlined,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'IMEI : ${_imeiController.text.trim().isEmpty ? '-' : _imeiController.text.trim()}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF111827),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.fromLTRB(30, 10, 30, 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              _FinishedInputRow(
                label: '납품처',
                controller: _destinationController,
                hintText: '?⑺뭹泥??낅젰',
              ),
              _FinishedInputRow(
                label: 'IMEI',
                controller: _imeiController,
                hintText: 'IMEI ?낅젰',
                onChanged: (_) => setState(() {}),
              ),
              _FinishedInputRow(
                label: '異쒓퀬',
                controller: _shippingController,
                hintText: '異쒓퀬 二쇱냼 ?낅젰',
              ),
              _FinishedDateRow(date: _shippingDate, onTap: _pickDate),
            ],
          ),
        ),
        if (_errorText != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorText!,
            style: const TextStyle(
              color: Color(0xFFD32F2F),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF087BFF),
            padding: const EdgeInsets.symmetric(vertical: 17),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          child: const Text(
            '?꾨즺',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _FinishedInputRow extends StatelessWidget {
  const _FinishedInputRow({
    required this.label,
    required this.controller,
    required this.hintText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8))),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w700,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              '$label : ',
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FinishedDateRow extends StatelessWidget {
  const _FinishedDateRow({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            const Text(
              '異쒓퀬??: ',
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              _formatDate(date),
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            const Icon(Icons.calendar_month_outlined, color: Color(0xFF111827)),
          ],
        ),
      ),
    );
  }
}

class _FinishedView extends StatelessWidget {
  const _FinishedView({required this.product, required this.onService});

  final Map<String, dynamic>? product;
  final VoidCallback onService;

  @override
  Widget build(BuildContext context) {
    if (product == null) {
      return const _EmptyCard(
        text:
            '\uC81C\uD488 \uC815\uBCF4\uB97C \uBD88\uB7EC\uC62C \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.',
      );
    }
    final usedParts = product!['usedParts'] as List? ?? const [];
    final latestShipment = _latestShipment(product);
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 6, 28, 28),
      children: [
        Text(
          product!['modelName']?.toString() ?? 'ALLION',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 34,
            height: 1,
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 246,
            height: 286,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _AvaStockCardImage(
              imageUrl: product!['modelImageUrl']?.toString(),
              fallbackIcon: Icons.inventory_2_outlined,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'IMEI : ${product!['serialNo'] ?? '-'}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF111827),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 28),
        _FinishedInfoCard(
          destinationName:
              latestShipment?['destinationName']?.toString() ?? '-',
          imei: product!['serialNo']?.toString() ?? '-',
          shippingMethod: latestShipment?['shippingMethod']?.toString() ?? '-',
          shippingDate: latestShipment?['shippingDate']?.toString() ?? '-',
        ),
        const SizedBox(height: 20),
        _SectionTitle('총 사용 부품 ${usedParts.length}개'),
        const SizedBox(height: 10),
        for (final raw in usedParts)
          _ListCard(
            title: (raw as Map)['partName']?.toString() ?? '\uBD80\uD488',
            subtitle:
                '\uC81C\uC870 ${raw['manufacturingQty'] ?? 0} \uAC1C \u00B7 A/S ${raw['asQty'] ?? 0} \uAC1C',
            trailing: '${raw['totalQty'] ?? 0}',
          ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onService,
          icon: const Icon(Icons.build_outlined),
          label: const Text('A/S \uC811\uC218'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF4663CF),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _FinishedInfoCard extends StatelessWidget {
  const _FinishedInfoCard({
    required this.destinationName,
    required this.imei,
    required this.shippingMethod,
    required this.shippingDate,
  });

  final String destinationName;
  final String imei;
  final String shippingMethod;
  final String shippingDate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _FinishedInfoRow(label: '납품처', value: destinationName),
          _FinishedInfoRow(label: 'IMEI', value: imei),
          _FinishedInfoRow(label: '異쒓퀬', value: shippingMethod),
          _FinishedInfoRow(label: '출고일', value: shippingDate),
        ],
      ),
    );
  }
}

class _FinishedInfoRow extends StatelessWidget {
  const _FinishedInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8E8E8))),
      ),
      child: Text(
        '$label : $value',
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 17,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.home});

  final AvaStockHomeDto? home;

  @override
  Widget build(BuildContext context) {
    final inventory = home?.inventory ?? const [];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _SectionTitle('\uBD80\uD488 \uC7AC\uACE0 \uD604\uD669'),
        const SizedBox(height: 10),
        if (inventory.isEmpty)
          const _EmptyCard(
            text:
                '\uC7AC\uACE0 \uB370\uC774\uD130\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
          )
        else
          for (final item in inventory)
            _PartInventoryCard(
              partName: item['partName']?.toString() ?? '\uBD80\uD488',
              partCode: item['partCode']?.toString() ?? '',
              trailing: '${item['currentQty'] ?? 0} ${item['unit'] ?? 'EA'}',
            ),
        const SizedBox(height: 20),
        const _SectionTitle('\uCD5C\uADFC 7\uC77C \uC7AC\uACE0 \uBCC0\uB3D9'),
        const SizedBox(height: 10),
        const _EmptyCard(
          text:
              '\uB300\uC2DC\uBCF4\uB4DC \uADF8\uB798\uD504\uB294 /stock \uC6F9 \uB300\uC2DC\uBCF4\uB4DC\uC5D0\uC11C \uB3D9\uC77C API \uAE30\uC900\uC73C\uB85C \uD655\uC7A5\uD569\uB2C8\uB2E4.',
        ),
      ],
    );
  }
}

class _HomeSectionLabel extends StatelessWidget {
  const _HomeSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF111827),
        fontSize: 15,
        height: 1.1,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.1,
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(9),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 19),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFE8EDF5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.075),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 29),
              const SizedBox(width: 14),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xFF171923),
                      fontSize: 13.5,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
  });

  final String label;
  final Object? value;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      padding: const EdgeInsets.fromLTRB(15, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFE8EDF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.065),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 25),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF697386),
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '${_asDisplayInt(value)}',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const TextSpan(
                        text: ' \uB300',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
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

class _RecentShipmentCard extends StatelessWidget {
  const _RecentShipmentCard({required this.shipment});

  final Map<String, dynamic>? shipment;

  @override
  Widget build(BuildContext context) {
    final destination = _textOrDash(shipment?['destinationName']);
    final imei = _textOrDash(
      shipment?['imei'] ??
          shipment?['serialNo'] ??
          shipment?['productSerialNo'],
    );
    final method = _textOrDash(
      shipment?['shippingMethod'] ?? shipment?['method'],
    );
    final date = _textOrDash(
      shipment?['shippingDate'] ?? shipment?['shippedAt'],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(19, 14, 18, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EDF5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.065),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _RecentInfoRow(
            icon: Icons.apartment_rounded,
            text: '\uB0A9\uD488\uCC98 : $destination',
          ),
          const _RecentDivider(),
          _RecentInfoRow(icon: Icons.barcode_reader, text: 'IMEI : $imei'),
          const _RecentDivider(),
          _RecentInfoRow(
            icon: Icons.flight_rounded,
            text: '\uCD9C\uACE0 : $method',
          ),
          const _RecentDivider(),
          _RecentInfoRow(
            icon: Icons.calendar_month_rounded,
            text: '\uCD9C\uACE0\uC77C : $date',
          ),
        ],
      ),
    );
  }
}

class _RecentInfoRow extends StatelessWidget {
  const _RecentInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0677FF), size: 17),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF20242D),
                fontSize: 12,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentDivider extends StatelessWidget {
  const _RecentDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 29),
      child: Divider(height: 1, thickness: 1, color: Color(0xFFE9EDF4)),
    );
  }
}

String _textOrDash(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? '-' : text;
}

int _asDisplayInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.imageUrl,
    this.imageFit = BoxFit.cover,
    this.imageSize = 86,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? imageUrl;
  final BoxFit imageFit;
  final double imageSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              color: const Color(0xFFE9F0FF),
              borderRadius: BorderRadius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: _AvaStockCardImage(
              imageUrl: imageUrl,
              fallbackIcon: icon,
              fit: imageFit,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF12203B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF111827),
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

class _AvaStockCardImage extends StatelessWidget {
  const _AvaStockCardImage({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.fit,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = _resolveAvaStockImageUrl(imageUrl);
    if (resolvedUrl == null) {
      return Icon(fallbackIcon, color: const Color(0xFF4663CF), size: 40);
    }
    return Image.network(
      resolvedUrl,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Icon(fallbackIcon, color: const Color(0xFF4663CF), size: 40);
      },
    );
  }
}

String? _resolveAvaStockImageUrl(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return Uri.encodeFull(raw);
  }
  final base = AppConfig.fromEnvironment.apiBaseUrl.endsWith('/')
      ? AppConfig.fromEnvironment.apiBaseUrl.substring(
          0,
          AppConfig.fromEnvironment.apiBaseUrl.length - 1,
        )
      : AppConfig.fromEnvironment.apiBaseUrl;
  final path = raw.startsWith('/') ? raw : '/$raw';
  return Uri.encodeFull('$base$path');
}

class _BigNumberCard extends StatelessWidget {
  const _BigNumberCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF728096))),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Color(0xFF12203B),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).clamp(0, 100).round();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '\uC9C4\uD589\uB960',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: value.clamp(0.0, 1.0).toDouble(),
            minHeight: 9,
            borderRadius: BorderRadius.circular(99),
            color: const Color(0xFF4663CF),
            backgroundColor: const Color(0xFFE1E7F2),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.item,
    required this.checked,
    required this.onChanged,
  });

  final Map<String, dynamic> item;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE0E6F0)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: checked,
            activeColor: const Color(0xFF4663CF),
            onChanged: (value) => onChanged(value ?? false),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['partName']?.toString() ?? '\uBD80\uD488',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF12203B),
                  ),
                ),
                Text(
                  '${item['partCode'] ?? ''} \u00B7 \uAE30\uBCF8 \uC218\uB7C9 ${item['defaultQty'] ?? 1} EA',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 12,
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

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.title,
    required this.subtitle,
    this.trailing = '',
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E7F2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (trailing.isNotEmpty)
            Text(
              trailing,
              style: const TextStyle(
                color: Color(0xFF4663CF),
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _PartInventoryCard extends StatelessWidget {
  const _PartInventoryCard({
    required this.partName,
    required this.partCode,
    required this.trailing,
  });

  final String partName;
  final String partCode;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E7F2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  partName,
                  style: const TextStyle(
                    color: Color(0xFF4663CF),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  partCode,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFF4663CF),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: Color(0xFF12203B),
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF748197),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text, required this.onClose});

  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFD32F2F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFD32F2F)),
            ),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

bool _isManufacturingStatus(String? status) {
  return status == null ||
      status == 'SEMI_RECEIVED' ||
      status == 'MFG_SAVED' ||
      status == 'HOLD';
}

Map<String, dynamic>? _latestShipment(Map<String, dynamic>? product) {
  final raw = product?['latestShipment'];
  if (raw is Map) {
    return raw.cast<String, dynamic>();
  }
  return null;
}

DateTime? _parseDate(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value.trim());
}

String _formatDate(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double _asDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}
