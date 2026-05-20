import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

const avaCompanies = ['ABBA-S', 'Cadillac'];
const avaCompanyHeader = 'X-AVA-Company';

final activeCompanyProvider =
    NotifierProvider<ActiveCompanyController, String?>(
      ActiveCompanyController.new,
    );

class ActiveCompanyController extends Notifier<String?> {
  String? _selectedCompany;

  @override
  String? build() {
    final user = ref.watch(authControllerProvider).value?.session?.user;
    if (user == null) {
      _selectedCompany = null;
      return null;
    }
    final ownCompany = _normalizeCompany(user.companyName);
    if (_isSuperuser(user.role)) {
      if (_isKnownCompany(_selectedCompany)) {
        return _selectedCompany;
      }
      return _isKnownCompany(ownCompany) ? ownCompany : avaCompanies.first;
    }
    _selectedCompany = null;
    return ownCompany ?? avaCompanies.first;
  }

  void select(String company) {
    final user = ref.read(authControllerProvider).value?.session?.user;
    if (user == null || !_isSuperuser(user.role)) {
      return;
    }
    final normalized = _normalizeCompany(company);
    if (_isKnownCompany(normalized)) {
      _selectedCompany = normalized;
      state = normalized;
    }
  }

  bool _isSuperuser(String role) => role.toUpperCase() == 'SUPERUSER';

  bool _isKnownCompany(String? company) {
    if (company == null) {
      return false;
    }
    return avaCompanies.any(
      (item) => item.toLowerCase() == company.toLowerCase(),
    );
  }

  String? _normalizeCompany(String? company) {
    final value = company?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.toLowerCase() == 'cadillak') {
      return 'Cadillac';
    }
    for (final item in avaCompanies) {
      if (item.toLowerCase() == value.toLowerCase()) {
        return item;
      }
    }
    return avaCompanies.first;
  }
}
