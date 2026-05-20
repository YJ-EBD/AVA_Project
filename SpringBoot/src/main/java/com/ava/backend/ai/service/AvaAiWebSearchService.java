package com.ava.backend.ai.service;

import java.io.IOException;
import java.net.URI;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class AvaAiWebSearchService {

	private static final String GOOGLE_CUSTOM_SEARCH_URL = "https://www.googleapis.com/customsearch/v1";
	private static final String GOOGLE_SEARCH_URL = "https://www.google.com/search?hl=ko&num=10&q=";
	private static final String GOOGLE_IMAGE_SEARCH_URL = "https://www.google.com/search?tbm=isch&hl=ko&q=";
	private static final String DUCK_DUCK_GO_HTML_URL = "https://duckduckgo.com/html/?q=";

	private final ObjectMapper objectMapper;
	private final HttpClient httpClient;
	private final boolean enabled;
	private final int maxResults;
	private final int fallbackMinimumResults;
	private final Duration timeout;
	private final String googleApiKey;
	private final String googleSearchEngineId;

	public AvaAiWebSearchService(
		ObjectMapper objectMapper,
		@Value("${ava.ai.web-search-enabled:true}") boolean enabled,
		@Value("${ava.ai.web-search-max-results:5}") int maxResults,
		@Value("${ava.ai.web-search-fallback-min-results:3}") int fallbackMinimumResults,
		@Value("${ava.ai.web-search-timeout-seconds:12}") long timeoutSeconds,
		@Value("${ava.ai.google-search-api-key:}") String googleApiKey,
		@Value("${ava.ai.google-search-engine-id:}") String googleSearchEngineId
	) {
		this.objectMapper = objectMapper;
		this.enabled = enabled;
		this.maxResults = Math.max(1, maxResults);
		this.fallbackMinimumResults = Math.max(1, Math.min(fallbackMinimumResults, this.maxResults));
		this.timeout = Duration.ofSeconds(Math.max(3, timeoutSeconds));
		this.googleApiKey = googleApiKey == null ? "" : googleApiKey.strip();
		this.googleSearchEngineId = googleSearchEngineId == null ? "" : googleSearchEngineId.strip();
		this.httpClient = HttpClient.newBuilder()
			.connectTimeout(Duration.ofSeconds(Math.min(Math.max(3, timeoutSeconds), 10)))
			.followRedirects(HttpClient.Redirect.NORMAL)
			.build();
	}

	public List<WebSearchResult> searchIfNeeded(String query) {
		if (!enabled || !hasWebIntent(query)) {
			return List.of();
		}
		return search(query);
	}

	public List<WebSearchResult> search(String query) {
		String normalized = query == null ? "" : query.strip();
		if (normalized.isBlank()) {
			return List.of();
		}
		List<WebSearchResult> googleResults = searchGoogle(normalized);
		if (isGoodEnough(googleResults)) {
			return withPreviewImages(googleResults, normalized);
		}
		return withPreviewImages(mergeResults(googleResults, searchDuckDuckGo(normalized)), normalized);
	}

	private List<WebSearchResult> searchGoogle(String query) {
		List<WebSearchResult> customSearchResults = searchGoogleCustomSearch(query);
		if (!customSearchResults.isEmpty()) {
			return customSearchResults;
		}
		return searchGoogleHtml(query);
	}

	private List<WebSearchResult> searchGoogleCustomSearch(String query) {
		if (googleApiKey.isBlank() || googleSearchEngineId.isBlank()) {
			return List.of();
		}
		try {
			String uri = GOOGLE_CUSTOM_SEARCH_URL +
				"?key=" + URLEncoder.encode(googleApiKey, StandardCharsets.UTF_8) +
				"&cx=" + URLEncoder.encode(googleSearchEngineId, StandardCharsets.UTF_8) +
				"&num=" + Math.min(maxResults, 10) +
				"&hl=ko&q=" + URLEncoder.encode(query, StandardCharsets.UTF_8);
			String json = requestJson(URI.create(uri));
			JsonNode items = objectMapper.readTree(json).path("items");
			if (!items.isArray()) {
				return List.of();
			}
			List<WebSearchResult> results = new ArrayList<>();
			for (JsonNode item : items) {
				if (results.size() >= maxResults) {
					break;
				}
				String title = item.path("title").asText("").strip();
				String url = item.path("link").asText("").strip();
				String snippet = item.path("snippet").asText("").strip();
				String imageUrl = item.path("pagemap").path("cse_image").path(0).path("src").asText("").strip();
				if (title.isBlank() || !isSearchResultUrl(url)) {
					continue;
				}
				addUnique(results, new WebSearchResult("Google", title, url, snippet, imageUrl));
			}
			return results;
		} catch (IllegalArgumentException | IOException exception) {
			return List.of();
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			return List.of();
		}
	}

	private List<WebSearchResult> searchGoogleHtml(String query) {
		try {
			URI uri = URI.create(
				GOOGLE_SEARCH_URL + URLEncoder.encode(query, StandardCharsets.UTF_8)
			);
			return parseGoogleResults(requestHtml(uri));
		} catch (IllegalArgumentException | IOException exception) {
			return List.of();
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			return List.of();
		}
	}

	private List<WebSearchResult> searchDuckDuckGo(String query) {
		try {
			URI uri = URI.create(
				DUCK_DUCK_GO_HTML_URL + URLEncoder.encode(query, StandardCharsets.UTF_8)
			);
			return parseDuckDuckGoResults(requestHtml(uri));
		} catch (IllegalArgumentException | IOException exception) {
			return List.of();
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			return List.of();
		}
	}

	private String requestHtml(URI uri) throws IOException, InterruptedException {
		HttpRequest request = HttpRequest.newBuilder(uri)
			.timeout(timeout)
			.header(
				"User-Agent",
				"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AVA-AI-WebSearch/1.0"
			)
			.header("Accept", "text/html,application/xhtml+xml")
			.header("Accept-Language", "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7")
			.GET()
			.build();

		HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
		if (response.statusCode() < 200 || response.statusCode() >= 300) {
			return "";
		}
		return response.body();
	}

	private String requestJson(URI uri) throws IOException, InterruptedException {
		HttpRequest request = HttpRequest.newBuilder(uri)
			.timeout(timeout)
			.header("Accept", "application/json")
			.GET()
			.build();

		HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
		if (response.statusCode() < 200 || response.statusCode() >= 300) {
			return "{}";
		}
		return response.body();
	}

	private List<WebSearchResult> parseGoogleResults(String html) {
		Document document = Jsoup.parse(html, "https://www.google.com/");
		List<WebSearchResult> results = new ArrayList<>();
		for (Element result : document.select("div.g, div.MjjYud, div.SoaBEf")) {
			if (results.size() >= maxResults) {
				break;
			}
			Element titleElement = first(result, "h3");
			Element link = titleElement == null ? first(result, "a[href]") : titleElement.closest("a[href]");
			if (link == null) {
				continue;
			}
			String title = titleElement == null ? link.text().strip() : titleElement.text().strip();
			String url = normalizeGoogleUrl(link.attr("href"));
			String snippet = text(first(result, ".VwiC3b", ".IsZvec", ".GI74Re", ".BNeawe.s3v9rd.AP7Wnd"));
			if (title.isBlank() || !isSearchResultUrl(url)) {
				continue;
			}
			addUnique(results, new WebSearchResult("Google", title, url, snippet));
		}
		return results;
	}

	private List<WebSearchResult> parseDuckDuckGoResults(String html) {
		Document document = Jsoup.parse(html, "https://duckduckgo.com/");
		List<WebSearchResult> results = new ArrayList<>();
		for (Element result : document.select(".result")) {
			if (results.size() >= maxResults) {
				break;
			}
			Element link = first(result, "a.result__a", "a.result-link", "h2 a");
			if (link == null) {
				continue;
			}
			String title = link.text().strip();
			String url = normalizeDuckDuckGoUrl(link.attr("href"));
			String snippet = text(first(result, ".result__snippet", ".result-snippet", ".snippet"));
			if (title.isBlank() || !isSearchResultUrl(url)) {
				continue;
			}
			addUnique(results, new WebSearchResult("DuckDuckGo", title, url, snippet));
		}
		return results;
	}

	private boolean isGoodEnough(List<WebSearchResult> results) {
		if (results.size() >= fallbackMinimumResults) {
			return true;
		}
		return results.size() == maxResults;
	}

	private List<WebSearchResult> mergeResults(
		List<WebSearchResult> primary,
		List<WebSearchResult> fallback
	) {
		List<WebSearchResult> merged = new ArrayList<>();
		for (WebSearchResult result : primary) {
			addUnique(merged, result);
			if (merged.size() >= maxResults) {
				return List.copyOf(merged);
			}
		}
		for (WebSearchResult result : fallback) {
			addUnique(merged, result);
			if (merged.size() >= maxResults) {
				return List.copyOf(merged);
			}
		}
		return List.copyOf(merged);
	}

	private List<WebSearchResult> withPreviewImages(List<WebSearchResult> results, String query) {
		if (results.isEmpty()) {
			return results;
		}
		List<String> imageFallbacks = List.of();
		int imageFallbackIndex = 0;
		List<WebSearchResult> enriched = new ArrayList<>();
		for (WebSearchResult result : results) {
			if (result.imageUrl() != null && !result.imageUrl().isBlank()) {
				enriched.add(result);
				continue;
			}
			String imageUrl = fetchPreviewImage(result.url());
			if (imageUrl.isBlank()) {
				if (imageFallbacks.isEmpty()) {
					imageFallbacks = searchGoogleImages(query);
				}
				if (imageFallbackIndex < imageFallbacks.size()) {
					imageUrl = imageFallbacks.get(imageFallbackIndex++);
				}
			}
			enriched.add(new WebSearchResult(
				result.source(),
				result.title(),
				result.url(),
				result.snippet(),
				imageUrl
			));
		}
		return List.copyOf(enriched);
	}

	private List<String> searchGoogleImages(String query) {
		try {
			URI uri = URI.create(
				GOOGLE_IMAGE_SEARCH_URL + URLEncoder.encode(query, StandardCharsets.UTF_8)
			);
			Document document = Jsoup.parse(requestHtml(uri), "https://www.google.com/");
			List<String> images = new ArrayList<>();
			for (Element image : document.select("img[src], img[data-src]")) {
				if (images.size() >= maxResults) {
					break;
				}
				String value = image.hasAttr("data-src") ? image.attr("data-src") : image.attr("src");
				String normalized = normalizeImageUrl(uri, value);
				if (isPreviewImageUrl(normalized) && images.stream().noneMatch(normalized::equalsIgnoreCase)) {
					images.add(normalized);
				}
			}
			return List.copyOf(images);
		} catch (IllegalArgumentException | IOException exception) {
			return List.of();
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			return List.of();
		}
	}

	private String fetchPreviewImage(String url) {
		if (!isSearchResultUrl(url)) {
			return "";
		}
		try {
			URI uri = URI.create(url);
			String html = requestHtml(uri);
			if (html.isBlank()) {
				return "";
			}
			Document document = Jsoup.parse(html, url);
			Element image = first(
				document,
				"meta[property=og:image]",
				"meta[name=og:image]",
				"meta[name=twitter:image]",
				"meta[property=twitter:image]"
			);
			if (image != null) {
				String value = image.attr("content").strip();
				String normalized = normalizeImageUrl(uri, value);
				if (isPreviewImageUrl(normalized)) {
					return normalized;
				}
			}
			for (Element fallback : document.select("img[src], img[data-src], img[data-original], img[data-lazy-src]")) {
				String candidate = fallback.hasAttr("data-src")
					? fallback.attr("data-src")
					: fallback.hasAttr("data-original")
						? fallback.attr("data-original")
						: fallback.hasAttr("data-lazy-src")
							? fallback.attr("data-lazy-src")
							: fallback.attr("src");
				String normalized = normalizeImageUrl(uri, candidate);
				if (isPreviewImageUrl(normalized)) {
					return normalized;
				}
			}
			return "";
		} catch (IllegalArgumentException | IOException exception) {
			return "";
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			return "";
		}
	}

	private String normalizeImageUrl(URI baseUri, String value) {
		if (value == null || value.isBlank()) {
			return "";
		}
		String normalized = value.strip();
		if (normalized.startsWith("//")) {
			normalized = "https:" + normalized;
		}
		if (normalized.startsWith("http://") || normalized.startsWith("https://")) {
			return normalized;
		}
		try {
			return baseUri.resolve(normalized).toString();
		} catch (IllegalArgumentException ignored) {
			return "";
		}
	}

	private boolean isPreviewImageUrl(String value) {
		if (value == null || value.isBlank()) {
			return false;
		}
		String normalized = value.toLowerCase(Locale.ROOT);
		if (!(normalized.startsWith("http://") || normalized.startsWith("https://"))) {
			return false;
		}
		return !normalized.contains("logo") &&
			!normalized.contains("favicon") &&
			!normalized.contains("spacer") &&
			!normalized.endsWith(".svg");
	}

	private void addUnique(List<WebSearchResult> results, WebSearchResult candidate) {
		for (WebSearchResult result : results) {
			if (result.url().equalsIgnoreCase(candidate.url())) {
				return;
			}
		}
		results.add(candidate);
	}

	private Element first(Element root, String... selectors) {
		for (String selector : selectors) {
			Element element = root.selectFirst(selector);
			if (element != null) {
				return element;
			}
		}
		return null;
	}

	private String text(Element element) {
		return element == null ? "" : element.text().strip();
	}

	private String normalizeGoogleUrl(String value) {
		if (value == null || value.isBlank()) {
			return "";
		}
		String url = value.strip();
		if (url.startsWith("/url?") || url.startsWith("https://www.google.com/url?")) {
			try {
				URI uri = URI.create(url.startsWith("/") ? "https://www.google.com" + url : url);
				String query = uri.getRawQuery();
				if (query != null) {
					for (String part : query.split("&")) {
						int equalsIndex = part.indexOf('=');
						if (equalsIndex <= 0) {
							continue;
						}
						if ("q".equals(part.substring(0, equalsIndex))) {
							return URLDecoder.decode(
								part.substring(equalsIndex + 1),
								StandardCharsets.UTF_8
							);
						}
					}
				}
			} catch (IllegalArgumentException ignored) {
				return "";
			}
		}
		if (url.startsWith("http://") || url.startsWith("https://")) {
			return url;
		}
		return "";
	}

	private String normalizeDuckDuckGoUrl(String value) {
		if (value == null || value.isBlank()) {
			return "";
		}
		String url = value.strip();
		if (url.startsWith("//")) {
			url = "https:" + url;
		}
		if (url.startsWith("/")) {
			url = "https://duckduckgo.com" + url;
		}
		try {
			URI uri = URI.create(url);
			String query = uri.getRawQuery();
			if (query != null) {
				for (String part : query.split("&")) {
					int equalsIndex = part.indexOf('=');
					if (equalsIndex <= 0) {
						continue;
					}
					String key = part.substring(0, equalsIndex);
					if (!"uddg".equals(key)) {
						continue;
					}
					return URLDecoder.decode(
						part.substring(equalsIndex + 1),
						StandardCharsets.UTF_8
					);
				}
			}
		} catch (IllegalArgumentException ignored) {
			return url;
		}
		return url;
	}

	private boolean isSearchResultUrl(String url) {
		if (url == null || url.isBlank()) {
			return false;
		}
		String normalized = url.toLowerCase(Locale.ROOT);
		return (normalized.startsWith("http://") || normalized.startsWith("https://")) &&
			!normalized.contains("google.com/search") &&
			!normalized.contains("google.com/preferences") &&
			!normalized.contains("google.com/support") &&
			!normalized.contains("duckduckgo.com/y.js");
	}

	boolean hasWebIntent(String query) {
		if (query == null || query.isBlank()) {
			return false;
		}
		String value = query.toLowerCase(Locale.ROOT);
		return containsAny(
			value,
			"\uC778\uD130\uB137",
			"\uC6F9",
			"\uAD6C\uAE00",
			"\uB124\uC774\uBC84",
			"\uCFE0\uD321",
			"\uC1FC\uD551",
			"\uC0C1\uD488",
			"\uAD6C\uB9E4",
			"\uAD6C\uC785",
			"\uD310\uB9E4",
			"\uCD5C\uC800\uAC00",
			"\uC624\uD508\uB9C8\uCF13",
			"\uC1FC\uD551\uBAB0",
			"\uB2E4\uB098\uC640",
			"\uC544\uB9C8\uC874",
			"11\uBC88\uAC00",
			"\uC9C0\uB9C8\uCF13",
			"\uC625\uC158",
			"\uCD5C\uC2E0",
			"\uD604\uC7AC",
			"\uC9C0\uAE08",
			"\uC624\uB298",
			"\uC694\uC998",
			"\uB274\uC2A4",
			"\uC2E4\uC2DC\uAC04",
			"\uB0A0\uC528",
			"\uC8FC\uAC00",
			"\uD658\uC728",
			"\uAC00\uACA9",
			"\uBC84\uC804",
			"\uB9B4\uB9AC\uC988",
			"search",
			"internet",
			"web",
			"google",
			"coupang",
			"shopping",
			"shop",
			"product",
			"buy",
			"amazon",
			"latest",
			"current",
			"today",
			"news",
			"weather",
			"price",
			"stock",
			"release"
		);
	}

	private boolean containsAny(String value, String... needles) {
		for (String needle : needles) {
			if (value.contains(needle)) {
				return true;
			}
		}
		return false;
	}

	public record WebSearchResult(String source, String title, String url, String snippet, String imageUrl) {
		public WebSearchResult(String source, String title, String url, String snippet) {
			this(source, title, url, snippet, "");
		}
	}
}
