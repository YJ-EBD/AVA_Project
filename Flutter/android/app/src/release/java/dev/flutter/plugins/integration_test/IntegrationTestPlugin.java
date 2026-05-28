package dev.flutter.plugins.integration_test;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Release-only no-op shim for Flutter's generated plugin registrant.
 *
 * The integration_test package is a dev-only dependency, but recent Flutter
 * tooling can still emit it into GeneratedPluginRegistrant during release APK
 * generation. Keeping this shim in the release source set avoids shipping any
 * test behavior while allowing the generated registrant to compile.
 */
public final class IntegrationTestPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
