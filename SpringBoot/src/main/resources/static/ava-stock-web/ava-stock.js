(function () {
	"use strict";

	const tokenKey = "avaStockAccessToken";
	const page = document.body.dataset.page;
	const state = {
		token: localStorage.getItem(tokenKey) || "",
		models: [],
		parts: [],
		bomVersions: [],
		selectedModelId: "",
		selectedBomVersionId: ""
	};

	function $(selector, root = document) {
		return root.querySelector(selector);
	}

	function $all(selector, root = document) {
		return Array.from(root.querySelectorAll(selector));
	}

	function setText(selector, value) {
		const el = $(selector);
		if (el) el.textContent = value == null ? "" : String(value);
	}

	function escapeHtml(value) {
		return String(value == null ? "" : value)
			.replace(/&/g, "&amp;")
			.replace(/</g, "&lt;")
			.replace(/>/g, "&gt;")
			.replace(/"/g, "&quot;")
			.replace(/'/g, "&#039;");
	}

	function number(value) {
		return Number(value || 0).toLocaleString("ko-KR");
	}

	function apiHeaders(extra = {}) {
		const headers = { "Content-Type": "application/json", ...extra };
		if (state.token) headers.Authorization = `Bearer ${state.token}`;
		return headers;
	}

	async function api(path, options = {}) {
		const response = await fetch(path, {
			...options,
			headers: apiHeaders(options.headers || {})
		});
		if (!response.ok) {
			let message = `${response.status} ${response.statusText}`;
			try {
				const body = await response.json();
				message = body.message || message;
			} catch (_) {
				// Keep HTTP fallback message.
			}
			throw new Error(message);
		}
		if (response.status === 204) return null;
		return response.json();
	}

	function setupAuth() {
		const button = $("[data-auth-login]");
		if (!button) return;
		const label = $("[data-auth-state]");
		if (state.token && label) label.textContent = "로그인 토큰이 저장되어 있습니다.";
		button.addEventListener("click", async () => {
			const email = $("[data-auth-email]")?.value.trim();
			const password = $("[data-auth-password]")?.value || "";
			if (!email || !password) {
				if (label) label.textContent = "이메일과 비밀번호를 입력하세요.";
				return;
			}
			button.disabled = true;
			if (label) label.textContent = "로그인 중...";
			try {
				const body = await api("/api/auth/login", {
					method: "POST",
					body: JSON.stringify({ email, password, rememberMe: true, autoLogin: false, forceLogin: true }),
					headers: {}
				});
				state.token = body.accessToken;
				localStorage.setItem(tokenKey, state.token);
				if (label) label.textContent = `${body.user?.displayName || email} 로그인 완료`;
				await bootPage();
			} catch (error) {
				if (label) label.textContent = error.message;
			} finally {
				button.disabled = false;
			}
		});
	}

	async function loadDashboard() {
		if (!state.token) return;
		const [summary, stock, shipments, parts, partUsage, shipmentHistory] = await Promise.all([
			api("/api/ava-stock/dashboard/summary"),
			api("/api/ava-stock/dashboard/stock"),
			api("/api/ava-stock/dashboard/recent-shipments"),
			api("/api/ava-stock/parts/inventory"),
			api("/api/ava-stock/dashboard/part-usage"),
			api("/api/ava-stock/dashboard/shipment-history")
		]);
		renderDashboard(summary, stock, shipments, parts, partUsage, shipmentHistory);
	}

	function renderDashboard(summary, stock, shipments, parts, partUsage, shipmentHistory) {
		setText('[data-summary="totalStock"]', number(summary.totalStock));
		setText('[data-summary="shippable"]', number(summary.shippable));
		setText('[data-summary="shipping"]', number(summary.shipping));
		setText('[data-summary="inspectionRepair"]', number(summary.inspectionRepair));

		const max = Math.max(1, ...stock.map((row) => Number(row.totalRegisteredProducts || 0)));
		const bars = $("[data-stock-bars]");
		if (bars) {
			bars.innerHTML = stock.length
				? stock.map((row) => `
					<div class="stock-bar">
						<div class="stock-bar-meta"><strong>${escapeHtml(row.modelName)}</strong><span>${number(row.totalRegisteredProducts)}대</span></div>
						<div class="stock-bar-track"><div class="stock-bar-fill" style="width:${Math.max(4, (Number(row.totalRegisteredProducts || 0) / max) * 100)}%"></div></div>
					</div>
				`).join("")
				: '<div class="stock-list-item">등록된 제품이 없습니다.</div>';
		}

		const stockTable = $("[data-stock-table]");
		if (stockTable) {
			stockTable.innerHTML = stock.length
				? stock.map((row) => `
					<tr>
						<td>${escapeHtml(row.modelName)}<br><small>${escapeHtml(row.modelCode)}</small></td>
						<td>${number(row.semiStockQty)}</td>
						<td>${number(row.asInProgressQty)}</td>
						<td>${number(row.shippableQty)}</td>
						<td>${number(row.shippingQty)}</td>
						<td>${number(row.shippedQty)}</td>
					</tr>
				`).join("")
				: '<tr><td colspan="6">등록된 제품이 없습니다.</td></tr>';
		}

		const shipmentTable = $("[data-shipment-table]");
		if (shipmentTable) {
			shipmentTable.innerHTML = shipments.length
				? shipments.map((row) => `
					<tr>
						<td>${escapeHtml(row.shippingDate)}</td>
						<td>${escapeHtml(row.destinationName)}</td>
						<td>${escapeHtml(row.shippingMethod)}</td>
						<td>${escapeHtml(row.shipmentStatus)}</td>
					</tr>
				`).join("")
				: '<tr><td colspan="4">최근 출고가 없습니다.</td></tr>';
		}

		const partList = $("[data-part-inventory]");
		if (partList) {
			partList.innerHTML = parts.length
				? parts.slice(0, 12).map((part) => `
					<div class="stock-list-item">
						<strong><span class="stock-part-name">${escapeHtml(part.partName)}</span> <small class="stock-part-code">${escapeHtml(part.partCode)}</small></strong>
						<span>${number(part.currentQty)} ${escapeHtml(part.unit || "EA")}</span>
					</div>
				`).join("")
				: '<div class="stock-list-item">등록된 부품이 없습니다.</div>';
		}

		const usageList = $("[data-part-usage]");
		if (usageList) {
			usageList.innerHTML = partUsage.length
				? partUsage.slice(0, 10).map((usage) => `
					<div class="stock-list-item">
						<strong>${escapeHtml(usage.partName)} <small>${escapeHtml(usage.movementType)}</small></strong>
						<span>${escapeHtml(usage.modelName)} · ${escapeHtml(usage.serialNo)} · ${number(Math.abs(Number(usage.qtyDelta || 0)))}개</span>
						<span>${escapeHtml(usage.destinationName || "납품 전")} ${usage.shippingDate ? "· " + escapeHtml(usage.shippingDate) : ""}</span>
					</div>
				`).join("")
				: '<div class="stock-list-item">부품 사용 이력이 없습니다.</div>';
		}

		const sevenDayList = $("[data-seven-day-changes]");
		if (sevenDayList) {
			const changes = aggregateSevenDayChanges(shipmentHistory || []);
			sevenDayList.innerHTML = changes.length
				? changes.map((row) => `
					<div class="stock-list-item">
						<strong>${escapeHtml(row.date)}</strong>
						<span>출고 ${number(row.count)}건</span>
					</div>
				`).join("")
				: '<div class="stock-list-item">최근 7일 출고 변동이 없습니다.</div>';
		}
	}

	function aggregateSevenDayChanges(rows) {
		const today = new Date();
		const keys = new Map();
		for (let offset = 6; offset >= 0; offset -= 1) {
			const date = new Date(today);
			date.setDate(today.getDate() - offset);
			const key = date.toISOString().slice(0, 10);
			keys.set(key, 0);
		}
		for (const row of rows) {
			const key = String(row.shippingDate || "").slice(0, 10);
			if (keys.has(key)) keys.set(key, keys.get(key) + 1);
		}
		return Array.from(keys, ([date, count]) => ({ date, count }));
	}

	async function loadAdmin() {
		if (!state.token) return;
		const [models, parts] = await Promise.all([
			api("/api/ava-stock/admin/product-models"),
			api("/api/ava-stock/admin/parts")
		]);
		state.models = models;
		state.parts = parts;
		renderModelLists();
		renderPartLists();
		if (!state.selectedModelId && models[0]) {
			state.selectedModelId = String(models[0].modelId);
		}
		await loadBomVersions();
	}

	function renderModelLists() {
		const modelList = $("[data-model-list]");
		if (modelList) {
			modelList.innerHTML = state.models.length
				? state.models.map((model) => `
					<div class="stock-list-item">
						<strong>${escapeHtml(model.modelName)}</strong>
						<span>${escapeHtml(model.modelCode)} · ${model.active ? "활성" : "비활성"}</span>
						<div class="stock-master-actions">
							<button type="button" class="primary" data-select-model="${model.modelId}">BOM 관리</button>
							<button type="button" data-edit-model="${model.modelId}">수정</button>
						</div>
					</div>
				`).join("")
				: '<div class="stock-list-item">제품 모델을 등록하세요.</div>';
		}
		const selects = $all("[data-model-select]");
		selects.forEach((select) => {
			select.innerHTML = '<option value="">제품 모델 선택</option>' + state.models.map((model) =>
				`<option value="${model.modelId}" ${String(model.modelId) === state.selectedModelId ? "selected" : ""}>${escapeHtml(model.modelCode)} · ${escapeHtml(model.modelName)}</option>`
			).join("");
		});
	}

	function renderPartLists() {
		const partList = $("[data-part-list]");
		if (partList) {
			partList.innerHTML = state.parts.length
				? state.parts.map((part) => `
					<div class="stock-list-item">
						<strong>${escapeHtml(part.partName)}</strong>
						<span>${escapeHtml(part.partCode)} · ${number(part.currentQty)} ${escapeHtml(part.unit || "EA")} · ${part.active ? "활성" : "비활성"}</span>
						<div class="stock-master-actions">
							<button type="button" data-edit-part="${part.partId}">수정</button>
							<button type="button" data-show-part-qr="${part.partId}">QR ${part.qrCodes?.length || 0}</button>
						</div>
					</div>
				`).join("")
				: '<div class="stock-list-item">부품을 등록하세요.</div>';
		}
		$all("[data-part-select], [data-part-qr-select]").forEach((select) => {
			select.innerHTML = '<option value="">부품 선택</option>' + state.parts.map((part) =>
				`<option value="${part.partId}">${escapeHtml(part.partCode)} · ${escapeHtml(part.partName)}</option>`
			).join("");
		});
	}

	async function loadBomVersions() {
		if (!state.selectedModelId) {
			state.bomVersions = [];
			renderBomVersions();
			return;
		}
		state.bomVersions = await api(`/api/ava-stock/admin/product-models/${state.selectedModelId}/bom-versions`);
		if (!state.selectedBomVersionId && state.bomVersions[0]) {
			state.selectedBomVersionId = String(state.bomVersions[0].bomVersionId);
		}
		renderBomVersions();
		await loadBomItems();
	}

	function renderBomVersions() {
		const list = $("[data-bom-version-list]");
		if (list) {
			list.innerHTML = state.bomVersions.length
				? state.bomVersions.map((version) => `
					<div class="stock-list-item">
						<strong>v${version.versionNo} ${escapeHtml(version.versionName || "")}</strong>
						<span>${version.currentVersion ? "현재 BOM" : "보관 BOM"} · ${version.active ? "활성" : "비활성"}</span>
						<div class="stock-master-actions">
							<button type="button" class="primary" data-select-bom="${version.bomVersionId}">항목 관리</button>
							<button type="button" data-current-bom="${version.bomVersionId}">현재 지정</button>
						</div>
					</div>
				`).join("")
				: '<div class="stock-list-item">BOM 버전을 등록하세요.</div>';
		}
		const select = $("[data-bom-select]");
		if (select) {
			select.innerHTML = '<option value="">BOM 버전 선택</option>' + state.bomVersions.map((version) =>
				`<option value="${version.bomVersionId}" ${String(version.bomVersionId) === state.selectedBomVersionId ? "selected" : ""}>v${version.versionNo} ${escapeHtml(version.versionName || "")}</option>`
			).join("");
		}
	}

	async function loadBomItems() {
		const list = $("[data-bom-item-list]");
		if (!list || !state.selectedBomVersionId) {
			if (list) list.innerHTML = '<div class="stock-list-item">BOM 버전을 선택하세요.</div>';
			return;
		}
		const items = await api(`/api/ava-stock/admin/bom-versions/${state.selectedBomVersionId}/items`);
		list.innerHTML = items.length
			? items.map((item) => `
				<div class="stock-list-item">
					<strong>${escapeHtml(item.itemLabel || item.partName)}</strong>
					<span>${escapeHtml(item.partCode)} · ${number(item.defaultQty)}개 · 정렬 ${number(item.sortOrder)} · ${item.active ? "활성" : "비활성"}</span>
					<div class="stock-master-actions">
						<button type="button" data-deactivate-bom-item="${item.bomItemId}">비활성화</button>
					</div>
				</div>
			`).join("")
			: '<div class="stock-list-item">BOM 항목을 등록하세요.</div>';
	}

	function formData(form) {
		const data = Object.fromEntries(new FormData(form).entries());
		$all('input[type="checkbox"]', form).forEach((checkbox) => {
			data[checkbox.name] = checkbox.checked;
		});
		return data;
	}

	function setupAdminForms() {
		const modelForm = $("[data-model-form]");
		modelForm?.addEventListener("submit", async (event) => {
			event.preventDefault();
			await api("/api/ava-stock/admin/product-models", {
				method: "POST",
				body: JSON.stringify(formData(modelForm))
			});
			modelForm.reset();
			await loadAdmin();
			toast("제품 모델이 저장되었습니다.");
		});

		const partForm = $("[data-part-form]");
		partForm?.addEventListener("submit", async (event) => {
			event.preventDefault();
			await api("/api/ava-stock/admin/parts", {
				method: "POST",
				body: JSON.stringify(formData(partForm))
			});
			partForm.reset();
			partForm.unit.value = "EA";
			await loadAdmin();
			toast("부품이 저장되었습니다.");
		});

		const bomVersionForm = $("[data-bom-version-form]");
		bomVersionForm?.addEventListener("submit", async (event) => {
			event.preventDefault();
			const data = formData(bomVersionForm);
			if (!data.modelId) return toast("제품 모델을 선택하세요.");
			await api(`/api/ava-stock/admin/product-models/${data.modelId}/bom-versions`, {
				method: "POST",
				body: JSON.stringify({
					versionNo: Number(data.versionNo || 1),
					versionName: data.versionName,
					currentVersion: Boolean(data.currentVersion),
					active: true
				})
			});
			state.selectedModelId = String(data.modelId);
			bomVersionForm.reset();
			await loadBomVersions();
			toast("BOM 버전이 저장되었습니다.");
		});

		const bomItemForm = $("[data-bom-item-form]");
		bomItemForm?.addEventListener("submit", async (event) => {
			event.preventDefault();
			const data = formData(bomItemForm);
			if (!data.bomVersionId || !data.partId) return toast("BOM 버전과 부품을 선택하세요.");
			await api(`/api/ava-stock/admin/bom-versions/${data.bomVersionId}/items`, {
				method: "POST",
				body: JSON.stringify({
					partId: Number(data.partId),
					itemLabel: data.itemLabel,
					defaultQty: Number(data.defaultQty || 1),
					sortOrder: Number(data.sortOrder || 1),
					requiredFlag: Boolean(data.requiredFlag),
					active: true
				})
			});
			state.selectedBomVersionId = String(data.bomVersionId);
			bomItemForm.reset();
			await loadBomItems();
			toast("BOM 항목이 저장되었습니다.");
		});

		const partQrForm = $("[data-part-qr-form]");
		partQrForm?.addEventListener("submit", async (event) => {
			event.preventDefault();
			const data = formData(partQrForm);
			if (!data.partId || !data.qrValue) return toast("부품과 QR 값을 입력하세요.");
			await api(`/api/ava-stock/admin/parts/${data.partId}/qr-codes`, {
				method: "POST",
				body: JSON.stringify({
					qrValue: data.qrValue,
					label: data.label,
					locationCode: data.locationCode
				})
			});
			partQrForm.reset();
			await loadAdmin();
			toast("부품 QR이 등록되었습니다.");
		});

		document.addEventListener("click", async (event) => {
			const modelId = event.target.dataset.selectModel;
			if (modelId) {
				state.selectedModelId = String(modelId);
				state.selectedBomVersionId = "";
				renderModelLists();
				await loadBomVersions();
			}
			const bomVersionId = event.target.dataset.selectBom;
			if (bomVersionId) {
				state.selectedBomVersionId = String(bomVersionId);
				renderBomVersions();
				await loadBomItems();
			}
			const currentBomId = event.target.dataset.currentBom;
			if (currentBomId) {
				const version = state.bomVersions.find((item) => String(item.bomVersionId) === String(currentBomId));
				await api(`/api/ava-stock/admin/bom-versions/${currentBomId}`, {
					method: "PUT",
					body: JSON.stringify({
						versionNo: version.versionNo,
						versionName: version.versionName,
						currentVersion: true,
						active: version.active
					})
				});
				await loadBomVersions();
				toast("현재 BOM으로 지정했습니다.");
			}
			const bomItemId = event.target.dataset.deactivateBomItem;
			if (bomItemId && confirm("BOM 항목을 비활성화할까요?")) {
				await api(`/api/ava-stock/admin/bom-items/${bomItemId}`, { method: "DELETE" });
				await loadBomItems();
				toast("BOM 항목을 비활성화했습니다.");
			}
			const editModelId = event.target.dataset.editModel;
			if (editModelId) {
				const model = state.models.find((item) => String(item.modelId) === String(editModelId));
				const nextName = prompt("제품 모델명", model.modelName);
				if (nextName) {
					await api(`/api/ava-stock/admin/product-models/${editModelId}`, {
						method: "PUT",
						body: JSON.stringify({
							modelCode: model.modelCode,
							modelName: nextName,
							description: model.description,
							imageUrl: model.imageUrl,
							active: model.active
						})
					});
					await loadAdmin();
					toast("제품 모델을 수정했습니다.");
				}
			}
			const editPartId = event.target.dataset.editPart;
			if (editPartId) {
				const part = state.parts.find((item) => String(item.partId) === String(editPartId));
				const nextName = prompt("부품명", part.partName);
				if (nextName) {
					await api(`/api/ava-stock/admin/parts/${editPartId}`, {
						method: "PUT",
						body: JSON.stringify({
							partCode: part.partCode,
							partName: nextName,
							unit: part.unit,
							imageUrl: part.imageUrl,
							description: part.description,
							active: part.active
						})
					});
					await loadAdmin();
					toast("부품을 수정했습니다.");
				}
			}
			const showQrId = event.target.dataset.showPartQr;
			if (showQrId) {
				const part = state.parts.find((item) => String(item.partId) === String(showQrId));
				const rows = (part.qrCodes || []).map((qr) => `${qr.qrValue}${qr.label ? ` (${qr.label})` : ""}`).join("\n");
				alert(rows || "등록된 QR이 없습니다.");
			}
		});
	}

	function toast(message) {
		const target = $("[data-admin-state]") || $("[data-auth-state]");
		if (target) target.textContent = message;
	}

	async function bootPage() {
		try {
			if (page === "dashboard") {
				await loadDashboard();
			} else if (page === "admin") {
				await loadAdmin();
			}
		} catch (error) {
			toast(error.message);
		}
	}

	setupAuth();
	if (page === "dashboard") {
		$("[data-refresh-dashboard]")?.addEventListener("click", loadDashboard);
	}
	if (page === "admin") {
		setupAdminForms();
		$("[data-model-select]")?.addEventListener("change", async (event) => {
			state.selectedModelId = event.target.value;
			state.selectedBomVersionId = "";
			await loadBomVersions();
		});
		$("[data-bom-select]")?.addEventListener("change", async (event) => {
			state.selectedBomVersionId = event.target.value;
			await loadBomItems();
		});
	}
	bootPage();
})();
