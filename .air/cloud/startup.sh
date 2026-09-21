#!/usr/bin/env bash
# The Kotlin Air workspace image supplies the JDKs declared in gradle.properties.
set -euo pipefail

# Air starts this script in the checkout, even when materializing it elsewhere.
cd "$(git rev-parse --show-toplevel)"

healthcheck() {
    echo "Warming Kotlin's Gradle, dependency, toolchain, and compilation caches."
    echo "Building and testing the compiler's language-version settings."
    # This compiles real Kotlin/Java sources (including the JVM standard library)
    # and runs unit tests on JDK 8 using the repository's Java 21 Gradle daemon.
    # Gradle owns synchronous build readiness; failures propagate to startup.
    ./gradlew :core:language.version-settings:test --console=plain
    echo "Kotlin build and test healthcheck passed."
}

if [[ "${AIR_STARTUP_MODE:-}" == warmup ]]; then
    healthcheck
else
    # No service needs restarting: this is a compiler repository. The warmup
    # snapshot already contains the downloaded dependencies and build outputs.
    echo "Kotlin workspace ready; Gradle caches are restored from warmup."
fi
