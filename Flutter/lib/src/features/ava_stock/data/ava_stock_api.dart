import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/company_scope.dart';
import '../../auth/data/auth_api.dart';

final avaStockApiProvider = Provider<AvaStockApi>((ref) {
  return AvaStockApi(ref.watch(dioProvider), ref.watch(activeCompanyProvider));
});

class AvaStockApi {
  const AvaStockApi(this._dio, this._activeCompany);

  final Dio _dio;
  final String? _activeCompany;

  Future<AvaStockHomeDto> home(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/ava-stock/home',
      options: _authOptions(accessToken),
    );
    return AvaStockHomeDto.fromJson(response.data ?? const {});
  }

  Future<AvaStockQrLookupDto> lookupQr({
    required String accessToken,
    required String qrValue,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ava-stock/qr/lookup',
      data: {'qrValue': qrValue},
      options: _authOptions(accessToken),
    );
    return AvaStockQrLookupDto.fromJson(response.data ?? const {});
  }

  Future<Map<String, dynamic>> productByQr({
    required String accessToken,
    required String qrValue,
  }) async {
    final encodedQrValue = Uri.encodeComponent(qrValue);
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/ava-stock/products/by-qr/$encodedQrValue',
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> product({
    required String accessToken,
    required int productUnitId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/ava-stock/products/$productUnitId',
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> partByQr({
    required String accessToken,
    required String qrValue,
  }) async {
    final encodedQrValue = Uri.encodeComponent(qrValue);
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/ava-stock/parts/by-qr/$encodedQrValue',
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> part({
    required String accessToken,
    required int partId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/ava-stock/parts/$partId',
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> manufacturingChecklist({
    required String accessToken,
    required int productUnitId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/ava-stock/products/$productUnitId/manufacturing/checklist',
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> saveManufacturing({
    required String accessToken,
    required int productUnitId,
    required List<Map<String, dynamic>> items,
    bool complete = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ava-stock/products/$productUnitId/manufacturing/${complete ? 'complete' : 'save'}',
      data: {'items': items},
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> startService({
    required String accessToken,
    required int productUnitId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ava-stock/products/$productUnitId/service/start',
      data: const {},
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> saveService({
    required String accessToken,
    required int serviceCaseId,
    required List<Map<String, dynamic>> items,
    bool complete = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ava-stock/service-cases/$serviceCaseId/${complete ? 'complete' : 'save'}',
      data: {'items': items},
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> createShipment({
    required String accessToken,
    required String destinationName,
    required String imei,
    required String shippingMethod,
    required DateTime shippingDate,
    required List<int> productUnitIds,
    String shipmentStatus = 'DELIVERED',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ava-stock/shipments',
      data: {
        'destinationName': destinationName,
        'imei': imei,
        'shippingMethod': shippingMethod,
        'shippingDate':
            '${shippingDate.year.toString().padLeft(4, '0')}-${shippingDate.month.toString().padLeft(2, '0')}-${shippingDate.day.toString().padLeft(2, '0')}',
        'shipmentStatus': shipmentStatus,
        'productUnitIds': productUnitIds,
      },
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> purchasePart({
    required String accessToken,
    required int partId,
    required int quantity,
    String memo = '',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/ava-stock/parts/$partId/purchase',
      data: {'quantity': quantity, if (memo.isNotEmpty) 'memo': memo},
      options: _authOptions(accessToken),
    );
    return response.data ?? const {};
  }

  Future<AvaStockHomeDto> refreshHome(String accessToken) => home(accessToken);

  Options _authOptions(String accessToken) {
    return Options(
      headers: {
        'Authorization': 'Bearer $accessToken',
        if (_activeCompany != null && _activeCompany.isNotEmpty)
          avaCompanyHeader: _activeCompany,
      },
      receiveTimeout: const Duration(seconds: 30),
    );
  }
}

class AvaStockHomeDto {
  const AvaStockHomeDto({
    required this.summary,
    required this.recentShipments,
    required this.inventory,
  });

  factory AvaStockHomeDto.fromJson(Map<String, dynamic> json) {
    return AvaStockHomeDto(
      summary: (json['summary'] as Map? ?? const {}).cast<String, dynamic>(),
      recentShipments: [
        for (final item in json['recentShipments'] as List? ?? const [])
          (item as Map).cast<String, dynamic>(),
      ],
      inventory: [
        for (final item in json['inventory'] as List? ?? const [])
          (item as Map).cast<String, dynamic>(),
      ],
    );
  }

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> recentShipments;
  final List<Map<String, dynamic>> inventory;
}

class AvaStockQrLookupDto {
  const AvaStockQrLookupDto({
    required this.qrType,
    required this.qrValue,
    this.productUnitId,
    this.partId,
    this.modelName,
    this.partName,
    this.serialNo,
    this.currentStatus,
  });

  factory AvaStockQrLookupDto.fromJson(Map<String, dynamic> json) {
    return AvaStockQrLookupDto(
      qrType: json['qrType'] as String? ?? 'UNKNOWN',
      qrValue: json['qrValue'] as String? ?? '',
      productUnitId: _asInt(json['productUnitId']),
      partId: _asInt(json['partId']),
      modelName: json['modelName'] as String?,
      partName: json['partName'] as String?,
      serialNo: json['serialNo'] as String?,
      currentStatus: json['currentStatus'] as String?,
    );
  }

  final String qrType;
  final String qrValue;
  final int? productUnitId;
  final int? partId;
  final String? modelName;
  final String? partName;
  final String? serialNo;
  final String? currentStatus;
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
