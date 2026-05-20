package com.ava.backend.update.controller;

import org.springframework.core.io.Resource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.ava.backend.update.dto.AppUpdateManifestResponse;
import com.ava.backend.update.dto.AppUpdateReleaseResponse;
import com.ava.backend.update.service.AppUpdateService;

@RestController
@RequestMapping("/api/app-updates")
public class AppUpdateController {

	private final AppUpdateService appUpdateService;

	public AppUpdateController(AppUpdateService appUpdateService) {
		this.appUpdateService = appUpdateService;
	}

	@GetMapping("/windows/latest")
	public AppUpdateManifestResponse windowsLatest(
		@RequestParam(value = "currentVersion", required = false) String currentVersion
	) {
		return appUpdateService.windowsManifest(currentVersion);
	}

	@GetMapping("/macos/latest")
	public AppUpdateManifestResponse macosLatest(
		@RequestParam(value = "currentVersion", required = false) String currentVersion
	) {
		return appUpdateService.macosManifest(currentVersion);
	}

	@GetMapping("/android/latest")
	public AppUpdateManifestResponse androidLatest(
		@RequestParam(value = "currentVersion", required = false) String currentVersion
	) {
		return appUpdateService.androidManifest(currentVersion);
	}

	@GetMapping("/{platform}/releases/{version}")
	public AppUpdateReleaseResponse release(
		@PathVariable String platform,
		@PathVariable String version
	) {
		return appUpdateService.release(platform, version);
	}

	@GetMapping("/windows/download/{fileName}")
	public ResponseEntity<Resource> windowsDownload(@PathVariable String fileName) {
		AppUpdateService.UpdatePackage updatePackage = appUpdateService.windowsPackage(fileName);
		return updatePackageResponse(updatePackage);
	}

	@GetMapping("/macos/download/{fileName}")
	public ResponseEntity<Resource> macosDownload(@PathVariable String fileName) {
		AppUpdateService.UpdatePackage updatePackage = appUpdateService.macosPackage(fileName);
		return updatePackageResponse(updatePackage);
	}

	@GetMapping("/android/download/{fileName}")
	public ResponseEntity<Resource> androidDownload(@PathVariable String fileName) {
		AppUpdateService.UpdatePackage updatePackage = appUpdateService.androidPackage(fileName);
		return updatePackageResponse(updatePackage);
	}

	private ResponseEntity<Resource> updatePackageResponse(AppUpdateService.UpdatePackage updatePackage) {
		return ResponseEntity.ok()
			.header(
				HttpHeaders.CONTENT_DISPOSITION,
				ContentDisposition.attachment()
					.filename(updatePackage.fileName(), java.nio.charset.StandardCharsets.UTF_8)
					.build()
					.toString()
			)
			.contentType(MediaType.APPLICATION_OCTET_STREAM)
			.contentLength(updatePackage.sizeBytes())
			.body(updatePackage.resource());
	}
}
