class AppVersion {
  const AppVersion._();

  static const name = String.fromEnvironment(
    'AVA_APP_VERSION',
    defaultValue: '0.1.304',
  );
  static const buildNumber = int.fromEnvironment(
    'AVA_BUILD_NUMBER',
    defaultValue: 1304,
  );
  static const display = 'ver. $name';
}
