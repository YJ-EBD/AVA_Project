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
import org.springframework.stereotype.Service;

import com.ava.backend.update.dto.AppUpdateManifestResponse;

@Service
public class AppUpdateService {

	private static final String WINDOWS_PLATFORM = "windows";

	private final Path updateDirectory;
	private final String latestWindowsVersion;
	private final String windowsFileName;
	private final boolean windowsRequired;
	private final String windowsReleaseNotes;

	public AppUpdateService(
		@Value("${ava.app-update.directory:AppUpdates}") String updateDirectory,
		@Value("${ava.app-update.windows.latest-version:0.1.0}") String latestWindowsVersion,
		@Value("${ava.app-update.windows.file-name:ava-windows-${ava.app-update.windows.latest-version:0.1.0}.zip}") String windowsFileName,
		@Value("${ava.app-update.windows.required:false}") boolean windowsRequired,
		@Value("${ava.app-update.windows.release-notes:AVA desktop update}") String windowsReleaseNotes
	) {
		this.updateDirectory = Path.of(updateDirectory).toAbsolutePath().normalize();
		this.latestWindowsVersion = normalizeVersion(latestWindowsVersion);
		this.windowsFileName = windowsFileName == null || windowsFileName.isBlank()
			? "ava-windows-" + this.latestWindowsVersion + ".zip"
			: windowsFileName.strip();
		this.windowsRequired = windowsRequired;
		this.windowsReleaseNotes = windowsReleaseNotes == null ? "" : windowsReleaseNotes.strip();
	}

	public AppUpdateManifestResponse windowsManifest(String currentVersion) {
		String normalizedCurrent = normalizeVersion(currentVersion);
		Path packagePath = packagePath();
		boolean packageExists = Files.isRegularFile(packagePath);
		boolean updateAvailable = packageExists && compareVersions(latestWindowsVersion, normalizedCurrent) > 0;
		String encodedFileName = URLEncoder.encode(windowsFileName, StandardCharsets.UTF_8)
			.replace("+", "%20");
		return new AppUpdateManifestResponse(
			WINDOWS_PLATFORM,
			normalizedCurrent,
			latestWindowsVersion,
			updateAvailable,
			updateAvailable && windowsRequired,
			windowsFileName,
			updateAvailable ? "/api/app-updates/windows/download/" + encodedFileName : "",
			packageExists ? sha256(packagePath) : "",
			packageExists ? size(packagePath) : 0,
			windowsReleaseNotes
		);
	}

	public UpdatePackage windowsPackage(String fileName) {
		if (!windowsFileName.equals(fileName)) {
			throw new IllegalArgumentException("Unknown update package.");
		}
		Path path = packagePath();
		if (!Files.isRegularFile(path)) {
			throw new IllegalArgumentException("Update package not found.");
		}
		try {
			return new UpdatePackage(new UrlResource(path.toUri()), windowsFileName, Files.size(path));
		} catch (IOException exception) {
			throw new IllegalStateException("Update package cannot be read.", exception);
		}
	}

	private Path packagePath() {
		return updateDirectory.resolve(windowsFileName).normalize();
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
}
