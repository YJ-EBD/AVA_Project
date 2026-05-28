package com.ava.backend.avastock.controller;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.view;

import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class AvaStockWebControllerTest {

	private final MockMvc mvc = MockMvcBuilders
		.standaloneSetup(new AvaStockWebController())
		.build();

	@Test
	void stockDashboardRouteReturnsDashboardTemplate() throws Exception {
		mvc.perform(get("/stock"))
			.andExpect(status().isOk())
			.andExpect(view().name("ava-stock/dashboard"));
	}

	@Test
	void stockAdminRouteReturnsAdminTemplate() throws Exception {
		mvc.perform(get("/stock/admin"))
			.andExpect(status().isOk())
			.andExpect(view().name("ava-stock/admin"));
	}
}
