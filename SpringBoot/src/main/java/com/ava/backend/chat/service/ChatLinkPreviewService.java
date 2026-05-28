package com.ava.backend.chat.service;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.springframework.stereotype.Service;

import com.ava.backend.chat.dto.ChatLinkPreviewResponse;

@Service
public class ChatLinkPreviewService {

	private final HttpClient httpClient = HttpClient.newBuilder()
		.connectTimeout(Duration.ofSeconds(5))
		.followRedirects(HttpClient.Redirect.NORMAL)
		.build();

	public ChatLinkPreviewResponse preview(String rawUrl) {
		URI uri = normalizeUrl(rawUrl);
		if (uri == null) {
			throw new IllegalArgumentException("Invalid URL.");
		}
		try {
			HttpRequest request = HttpRequest.newBuilder(uri)
				.timeout(Duration.ofSeconds(8))
				.header("User-Agent", "AVA-LinkPreview/1.0")
				.header("Accept", "text/html,application/xhtml+xml")
				.GET()
				.build();
			HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
			if (response.statusCode() < 200 || response.statusCode() >= 400) {
				return fallback(uri);
			}
			Document document = Jsoup.parse(response.body(), uri.toString());
			String title = meta(document, "meta[property=og:title]", "meta[name=twitter:title]");
			if (title.isBlank()) {
				title = text(document.selectFirst("title"));
			}
			String description = meta(
				document,
				"meta[property=og:description]",
				"meta[name=description]",
				"meta[name=twitter:description]"
			);
			String image = normalizeImageUrl(
				uri,
				meta(document, "meta[property=og:image]", "meta[name=twitter:image]", "meta[property=twitter:image]")
			);
			String siteName = meta(document, "meta[property=og:site_name]");
			if (siteName.isBlank()) {
				siteName = uri.getHost() == null ? uri.toString() : uri.getHost();
			}
			return new ChatLinkPreviewResponse(
				uri.toString(),
				blankToDefault(title, siteName),
				description,
				image,
				siteName
			);
		} catch (IOException exception) {
			return fallback(uri);
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			return fallback(uri);
		}
	}

	private URI normalizeUrl(String rawUrl) {
		if (rawUrl == null || rawUrl.isBlank()) {
			return null;
		}
		try {
			URI uri = URI.create(rawUrl.strip());
			String scheme = uri.getScheme();
			if (!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme)) {
				return null;
			}
			if (uri.getHost() == null || uri.getHost().isBlank()) {
				return null;
			}
			return uri;
		} catch (IllegalArgumentException exception) {
			return null;
		}
	}

	private ChatLinkPreviewResponse fallback(URI uri) {
		String host = uri.getHost() == null ? uri.toString() : uri.getHost();
		return new ChatLinkPreviewResponse(uri.toString(), host, "", "", host);
	}

	private String meta(Document document, String... selectors) {
		for (String selector : selectors) {
			Element element = document.selectFirst(selector);
			if (element == null) {
				continue;
			}
			String value = element.attr("content");
			if (!value.isBlank()) {
				return value.strip();
			}
		}
		return "";
	}

	private String text(Element element) {
		return element == null ? "" : element.text().strip();
	}

	private String normalizeImageUrl(URI baseUri, String value) {
		if (value == null || value.isBlank()) {
			return "";
		}
		String normalized = value.strip();
		if (normalized.startsWith("//")) {
			return "https:" + normalized;
		}
		if (normalized.startsWith("http://") || normalized.startsWith("https://")) {
			return normalized;
		}
		try {
			return baseUri.resolve(normalized).toString();
		} catch (IllegalArgumentException exception) {
			return "";
		}
	}

	private String blankToDefault(String value, String fallback) {
		return value == null || value.isBlank() ? fallback : value.strip();
	}
}
