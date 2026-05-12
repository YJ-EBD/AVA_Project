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

	@GetMapping("/windows/download/{fileName}")
	public ResponseEntity<Resource> windowsDownload(@PathVariable String fileName) {
		AppUpdateService.UpdatePackage updatePackage = appUpdateService.windowsPackage(fileName);
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
