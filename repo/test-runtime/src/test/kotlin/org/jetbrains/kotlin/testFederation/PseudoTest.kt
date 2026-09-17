/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the license/LICENSE.txt file.
 */

package org.jetbrains.kotlin.testFederation

import org.junit.jupiter.api.AfterAll
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Test
import kotlin.test.assertTrue

/**
 * Provides tests with different selection annotations for the Test Federation functional tests.
 * The functional tests run this class and check which tests ran.
 */
class PseudoTest {
    companion object {
        @JvmStatic
        @BeforeAll
        fun beforeAll() {
            println("PseudoTest.beforeAll executed")
        }

        @JvmStatic
        @AfterAll
        fun afterAll() {
            println("PseudoTest.afterAll executed")
        }
    }

    @Test
    fun `domain test`() {
        if (autoSmokeTestPercentage == 0) {
            val subsets = testFederationSubsets
            assertTrue(
                subsets == null || TestSubset.AllTests in subsets || TestSubset.PlainTests in subsets,
                "Expected 'AllTests' or 'PlainTests' in requested subsets, but was: $subsets"
            )
        }
    }

    @MustRunAlways
    @Test
    fun `smoke test`() {

    }

    @MustRunOnChangesInJs
    @Test
    fun `js contract test`() {
        val subsets = testFederationSubsets ?: return
        if (TestSubset.AllTests in subsets) return
        if (TestSubset.ContractTestsForJs !in subsets && autoSmokeTestPercentage == 0) {
            error("Expected 'ContractTestsForJs' in requested subsets, but was: $subsets")
        }
    }

    @MustRunOnChangesInWasm
    @Test
    fun `wasm contract test`() {
        val subsets = testFederationSubsets ?: return
        if (TestSubset.AllTests in subsets) return
        if (TestSubset.ContractTestsForWasm !in subsets && autoSmokeTestPercentage == 0) {
            error("Expected 'ContractTestsForWasm' in requested subsets, but was: $subsets")
        }
    }

    @MustRunOnChangesInGradle
    @Test
    fun `gradle contract test`() {
        val subsets = testFederationSubsets ?: return
        if (TestSubset.AllTests in subsets) return
        if (TestSubset.ContractTestsForGradle !in subsets && autoSmokeTestPercentage == 0) {
            error("Expected 'ContractTestsForGradle' in requested subsets, but was: $subsets")
        }
    }

    @NightlyTest
    @Test
    fun `nightly test`() {
        assertTrue(testFederationNightly)
    }
}
