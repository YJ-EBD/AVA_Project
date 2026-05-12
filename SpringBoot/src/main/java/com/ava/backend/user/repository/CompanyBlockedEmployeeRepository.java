package com.ava.backend.user.repository;

import java.util.Collection;
import java.util.Set;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

import com.ava.backend.user.entity.CompanyBlockedEmployee;

public interface CompanyBlockedEmployeeRepository extends JpaRepository<CompanyBlockedEmployee, UUID> {

	boolean existsByCompanyNameIgnoreCaseAndTargetAccountId(String companyName, UUID targetAccountId);

	void deleteByCompanyNameIgnoreCaseAndTargetAccountId(String companyName, UUID targetAccountId);

	Set<CompanyBlockedEmployee> findByCompanyNameIgnoreCaseAndTargetAccountIdIn(
		String companyName,
		Collection<UUID> targetAccountIds
	);
}
