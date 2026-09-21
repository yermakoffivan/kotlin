#!/usr/bin/env bash
# The Kotlin Air workspace image supplies the JDKs declared in gradle.properties.
set -euo pipefail

# Air starts this script in the checkout, even when materializing it elsewhere.
cd "$(git rev-parse --show-toplevel)"

# Java does not read HTTP(S)_PROXY. Persist Gradle's equivalent settings so
# both the wrapper and future builds use Air's proxy, including after restore.
python3 - <<'PY'
import os
import re
from pathlib import Path
from urllib.parse import urlsplit

gradle_home = Path(os.environ.get('GRADLE_USER_HOME', Path.home() / '.gradle'))
gradle_home.mkdir(parents=True, exist_ok=True)
properties = gradle_home / 'gradle.properties'
existing = properties.read_text() if properties.exists() else ''
existing = re.sub(r'(?m)^# BEGIN Air proxy\n.*?^# END Air proxy\n?', '', existing, flags=re.S)
lines = ['# BEGIN Air proxy']
for protocol in ('http', 'https'):
    value = os.environ.get(protocol.upper() + '_PROXY')
    if value:
        proxy = urlsplit(value)
        if not proxy.hostname or not proxy.port:
            raise ValueError(f'{protocol.upper()}_PROXY must include a host and port')
        lines.extend([
            f'systemProp.{protocol}.proxyHost={proxy.hostname}',
            f'systemProp.{protocol}.proxyPort={proxy.port}',
            f'systemProp.{protocol}.nonProxyHosts=localhost|127.*|[::1]',
        ])
lines.append('# END Air proxy')
properties.write_text(existing.rstrip() + '\n' + '\n'.join(lines) + '\n')
PY

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
