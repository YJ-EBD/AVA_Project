package com.ava.backend.avastock.dto;

import java.util.List;

public record AvaStockChecklistSaveRequest(
	List<Item> items,
	String notes
) {
	public record Item(
		Long bomItemId,
		boolean used,
		Integer quantity,
		String memo
	) {
	}
}
