package com.ava.backend.update.service;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Locale;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import com.ava.backend.update.dto.AppUpdateManifestResponse;
import com.ava.backend.update.dto.AppUpdateReleaseResponse;
import com.ava.backend.update.entity.AppUpdateReleaseEntity;
import com.ava.backend.update.repository.AppUpdateReleaseRepository;

@Service
public class AppUpdateService {

	private static final String WINDOWS_PLATFORM = "windows";
	private static final String ANDROID_PLATFORM = "android";
	private static final String MACOS_PLATFORM = "macos";
	private static final String IOS_PLATFORM = "ios";

	private final Path updateDirectory;
	private final PlatformUpdateConfig windowsConfig;
	private final PlatformUpdateConfig androidConfig;
	private final PlatformUpdateConfig macosConfig;
	private final PlatformUpdateConfig iosConfig;
	private final AppUpdateReleaseRepository releaseRepository;

	public AppUpdateService(
		AppUpdateReleaseRepository releaseRepository,
		@Value("${ava.app-update.directory:AppUpdates}") String updateDirectory,
		@Value("${ava.app-update.windows.latest-version:0.1.0}") String latestWindowsVersion,
		@Value("${ava.app-update.windows.file-name:ava-windows-${ava.app-update.windows.latest-version:0.1.0}.zip}") String windowsFileName,
		@Value("${ava.app-update.windows.required:false}") boolean windowsRequired,
		@Value("${ava.app-update.windows.release-notes:AVA desktop update}") String windowsReleaseNotes,
		@Value("${ava.app-update.android.latest-version:0.1.0}") String latestAndroidVersion,
		@Value("${ava.app-update.android.file-name:ava-android-${ava.app-update.android.latest-version:0.1.0}.apk}") String androidFileName,
		@Value("${ava.app-update.android.required:false}") boolean androidRequired,
		@Value("${ava.app-update.android.release-notes:AVA Android update}") String androidReleaseNotes,
		@Value("${ava.app-update.macos.latest-version:0.1.0}") String latestMacosVersion,
		@Value("${ava.app-update.macos.file-name:ava-macos-${ava.app-update.macos.latest-version:0.1.0}.dmg}") String macosFileName,
		@Value("${ava.app-update.macos.required:false}") boolean macosRequired,
		@Value("${ava.app-update.macos.release-notes:AVA macOS update}") String macosReleaseNotes,
		@Value("${ava.app-update.ios.latest-version:0.1.0}") String latestIosVersion,
		@Value("${ava.app-update.ios.file-name:ava-ios-${ava.app-update.ios.latest-version:0.1.0}.ipa}") String iosFileName,
		@Value("${ava.app-update.ios.required:false}") boolean iosRequired,
		@Value("${ava.app-update.ios.release-notes:AVA iOS update}") String iosReleaseNotes
	) {
		this.releaseRepository = releaseRepository;
		this.updateDirectory = Path.of(updateDirectory).toAbsolutePath().normalize();
		this.windowsConfig = buildConfig(
			WINDOWS_PLATFORM,
			latestWindowsVersion,
			windowsFileName,
			windowsRequired,
			windowsReleaseNotes,
			".zip"
		);
		this.androidConfig = buildConfig(
			ANDROID_PLATFORM,
			latestAndroidVersion,
			androidFileName,
			androidRequired,
			androidReleaseNotes,
			".apk"
		);
		this.macosConfig = buildConfig(
			MACOS_PLATFORM,
			latestMacosVersion,
			macosFileName,
			macosRequired,
			macosReleaseNotes,
			".dmg"
		);
		this.iosConfig = buildConfig(
			IOS_PLATFORM,
			latestIosVersion,
			iosFileName,
			iosRequired,
			iosReleaseNotes,
			".ipa"
		);
	}

	public AppUpdateManifestResponse windowsManifest(String currentVersion) {
		return manifest(WINDOWS_PLATFORM, currentVersion);
	}

	public AppUpdateManifestResponse androidManifest(String currentVersion) {
		return manifest(ANDROID_PLATFORM, currentVersion);
	}

	public AppUpdateManifestResponse macosManifest(String currentVersion) {
		return manifest(MACOS_PLATFORM, currentVersion);
	}

	public AppUpdateManifestResponse iosManifest(String currentVersion) {
		return manifest(IOS_PLATFORM, currentVersion);
	}

	public AppUpdateManifestResponse manifest(String platform, String currentVersion) {
		PlatformUpdateConfig config = configFor(platform);
		String normalizedCurrent = normalizeVersion(currentVersion);
		Path packagePath = packagePath(config.fileName());
		boolean packageExists = Files.isRegularFile(packagePath);
		String packageSha256 = packageExists ? sha256(packagePath) : "";
		long packageSize = packageExists ? size(packagePath) : 0;
		AppUpdateReleaseEntity release = saveConfiguredRelease(
			config,
			packageExists,
			packageSha256,
			packageSize
		);
		boolean updateAvailable = packageExists && compareVersions(config.latestVersion(), normalizedCurrent) > 0;
		String encodedFileName = URLEncoder.encode(config.fileName(), StandardCharsets.UTF_8)
			.replace("+", "%20");
		return new AppUpdateManifestResponse(
			release.getPlatform(),
			normalizedCurrent,
			release.getVersion(),
			updateAvailable,
			updateAvailable && release.isRequired(),
			release.getFileName(),
			updateAvailable ? "/api/app-updates/" + release.getPlatform() + "/download/" + encodedFileName : "",
			release.getSha256(),
			release.getSizeBytes(),
			release.getReleaseNotes()
		);
	}

	public AppUpdateReleaseResponse release(String platform, String version) {
		PlatformUpdateConfig config = configFor(platform);
		if (config.latestVersion().equals(normalizeVersion(version))) {
			Path packagePath = packagePath(config.fileName());
			boolean packageExists = Files.isRegularFile(packagePath);
			saveConfiguredRelease(
				config,
				packageExists,
				packageExists ? sha256(packagePath) : "",
				packageExists ? size(packagePath) : 0
			);
		}
		String normalizedPlatform = platform == null ? "" : platform.strip().toLowerCase(Locale.ROOT);
		String normalizedVersion = normalizeVersion(version);
		AppUpdateReleaseEntity release = releaseRepository
			.findByPlatformAndVersion(normalizedPlatform, normalizedVersion)
			.orElseThrow(() -> new IllegalArgumentException("Update release not found."));
		return toReleaseResponse(release);
	}

	public UpdatePackage windowsPackage(String fileName) {
		return packageFor(WINDOWS_PLATFORM, fileName);
	}

	public UpdatePackage androidPackage(String fileName) {
		return packageFor(ANDROID_PLATFORM, fileName);
	}

	public UpdatePackage macosPackage(String fileName) {
		return packageFor(MACOS_PLATFORM, fileName);
	}

	public UpdatePackage iosPackage(String fileName) {
		return packageFor(IOS_PLATFORM, fileName);
	}

	public UpdatePackage packageFor(String platform, String fileName) {
		PlatformUpdateConfig config = configFor(platform);
		if (!config.fileName().equals(fileName)) {
			throw new IllegalArgumentException("Unknown update package.");
		}
		Path path = packagePath(config.fileName());
		if (!Files.isRegularFile(path)) {
			throw new IllegalArgumentException("Update package not found.");
		}
		try {
			return new UpdatePackage(new UrlResource(path.toUri()), config.fileName(), Files.size(path));
		} catch (IOException exception) {
			throw new IllegalStateException("Update package cannot be read.", exception);
		}
	}

	private PlatformUpdateConfig buildConfig(
		String platform,
		String latestVersion,
		String fileName,
		boolean required,
		String releaseNotes,
		String extension
	) {
		String normalizedLatest = normalizeVersion(latestVersion);
		String resolvedFileName = fileName == null || fileName.isBlank()
			? "ava-" + platform + "-" + normalizedLatest + extension
			: fileName.strip();
		return new PlatformUpdateConfig(
			platform,
			normalizedLatest,
			resolvedFileName,
			required,
			releaseNotes == null ? "" : releaseNotes.strip()
		);
	}

	private PlatformUpdateConfig configFor(String platform) {
		String normalized = platform == null ? "" : platform.strip().toLowerCase(Locale.ROOT);
		if (WINDOWS_PLATFORM.equals(normalized)) {
			return windowsConfig;
		}
		if (ANDROID_PLATFORM.equals(normalized)) {
			return androidConfig;
		}
		if (MACOS_PLATFORM.equals(normalized)) {
			return macosConfig;
		}
		if (IOS_PLATFORM.equals(normalized)) {
			return iosConfig;
		}
		throw new IllegalArgumentException("Unsupported update platform.");
	}

	private Path packagePath(String fileName) {
		return updateDirectory.resolve(fileName).normalize();
	}

	private AppUpdateReleaseEntity saveConfiguredRelease(
		PlatformUpdateConfig config,
		boolean packageAvailable,
		String sha256,
		long sizeBytes
	) {
		AppUpdateReleaseEntity release = releaseRepository
			.findByPlatformAndVersion(config.platform(), config.latestVersion())
			.orElseGet(() -> new AppUpdateReleaseEntity(config.platform(), config.latestVersion()));
		release.update(
			config.fileName(),
			config.required(),
			config.releaseNotes(),
			sha256,
			sizeBytes,
			packageAvailable
		);
		try {
			return releaseRepository.saveAndFlush(release);
		} catch (DataIntegrityViolationException exception) {
			AppUpdateReleaseEntity existing = releaseRepository
				.findByPlatformAndVersion(config.platform(), config.latestVersion())
				.orElseThrow(() -> exception);
			existing.update(
				config.fileName(),
				config.required(),
				config.releaseNotes(),
				sha256,
				sizeBytes,
				packageAvailable
			);
			return releaseRepository.save(existing);
		}
	}

	private AppUpdateReleaseResponse toReleaseResponse(AppUpdateReleaseEntity release) {
		return new AppUpdateReleaseResponse(
			release.getPlatform(),
			release.getVersion(),
			release.getFileName(),
			release.isRequired(),
			release.getReleaseNotes(),
			release.getSha256(),
			release.getSizeBytes(),
			release.isPackageAvailable(),
			release.getUpdatedAt()
		);
	}

	private long size(Path path) {
		try {
			return Files.size(path);
		} catch (IOException exception) {
			return 0;
		}
	}

	private String sha256(Path path) {
		try {
			MessageDigest digest = MessageDigest.getInstance("SHA-256");
			try (InputStream input = Files.newInputStream(path);
				 DigestInputStream digestInput = new DigestInputStream(input, digest)) {
				digestInput.transferTo(OutputStream.nullOutputStream());
			}
			return HexFormat.of().formatHex(digest.digest());
		} catch (IOException | NoSuchAlgorithmException exception) {
			return "";
		}
	}

	private String normalizeVersion(String version) {
		if (version == null || version.isBlank()) {
			return "0.0.0";
		}
		return version.strip().split("\\+", 2)[0].toLowerCase(Locale.ROOT);
	}

	private int compareVersions(String left, String right) {
		int[] leftParts = versionParts(left);
		int[] rightParts = versionParts(right);
		for (int index = 0; index < Math.max(leftParts.length, rightParts.length); index++) {
			int leftValue = index < leftParts.length ? leftParts[index] : 0;
			int rightValue = index < rightParts.length ? rightParts[index] : 0;
			if (leftValue != rightValue) {
				return Integer.compare(leftValue, rightValue);
			}
		}
		return 0;
	}

	private int[] versionParts(String version) {
		String[] parts = normalizeVersion(version).split("\\.");
		int[] values = new int[parts.length];
		for (int index = 0; index < parts.length; index++) {
			try {
				values[index] = Integer.parseInt(parts[index].replaceAll("[^0-9].*", ""));
			} catch (NumberFormatException exception) {
				values[index] = 0;
			}
		}
		return values;
	}

	public record UpdatePackage(Resource resource, String fileName, long sizeBytes) {
	}

	private record PlatformUpdateConfig(
		String platform,
		String latestVersion,
		String fileName,
		boolean required,
		String releaseNotes
	) {
	}
}
