package com.ava.backend.avastock.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class AvaStockWebController {

	@GetMapping({"/stock", "/stock/"})
	public String stockDashboard() {
		return "ava-stock/dashboard";
	}

	@GetMapping("/stock/admin")
	public String stockAdmin() {
		return "ava-stock/admin";
	}
}
