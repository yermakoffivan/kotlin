#!/usr/bin/env bash
# Warm the Kotlin compiler build and verify that its JVM compiler works.
set -euo pipefail
trap 'echo "Kotlin environment setup failed at line $LINENO" >&2' ERR

# Air may execute a materialized copy of this script outside the checkout.
cd "$(git rev-parse --show-toplevel)"
umask 022

setup_dir="$HOME/.local/share/air-kotlin"
mkdir -p "$setup_dir"

# Build helpers require JDK 17 before the toolchain resolver is available.
# Gradle provisions the Java 21 daemon and other toolchains itself.
if [[ ! -x "$setup_dir/jdk-17/bin/javac" ]]; then
    echo 'Installing the Java 17 bootstrap toolchain...'
    case "$(uname -m)" in
        x86_64) jdk_arch=x64 ;;
        aarch64) jdk_arch=aarch64 ;;
        *) echo 'Unsupported JDK architecture' >&2; exit 1 ;;
    esac
    staging_dir=$(mktemp -d "$setup_dir/jdk-17.XXXXXX")
    curl -fsSL -x "${HTTPS_PROXY:?HTTPS_PROXY is required}" \
        "https://api.adoptium.net/v3/binary/latest/17/ga/linux/$jdk_arch/jdk/hotspot/normal/eclipse" \
        -o "$staging_dir/jdk.tar.gz"
    mkdir "$staging_dir/unpacked"
    tar -xzf "$staging_dir/jdk.tar.gz" --strip-components=1 -C "$staging_dir/unpacked"
    "$staging_dir/unpacked/bin/javac" -version
    mv "$staging_dir/unpacked" "$setup_dir/jdk-17"
    rm -rf "$staging_dir"
fi

echo 'Configuring Gradle proxy access and bootstrap toolchain discovery...'
# Java does not honor HTTP(S)_PROXY. Refresh proxy addresses after each boot;
# the snapshot can be restored on a different host. Preserve other settings.
python3 - <<'PY'
import os
import re
from pathlib import Path
from urllib.parse import urlsplit

gradle_home = Path(os.environ.get('GRADLE_USER_HOME', str(Path.home() / '.gradle')))
gradle_home.mkdir(parents=True, exist_ok=True)
properties = gradle_home / 'gradle.properties'
begin, end = '# BEGIN Air Kotlin setup', '# END Air Kotlin setup'
existing = properties.read_text() if properties.exists() else ''
existing = re.sub(re.escape(begin) + r'.*?' + re.escape(end) + r'\n?', '', existing, flags=re.S)
settings = [
    begin,
    'kotlin.build.internal.gradle.setup=false',
    'org.gradle.workers.max=4',
    f'org.gradle.java.installations.paths={Path.home()}/.local/share/air-kotlin/jdk-17',
]
for scheme in ('http', 'https'):
    proxy = urlsplit(os.environ[scheme.upper() + '_PROXY'])
    if not proxy.hostname or not proxy.port:
        raise ValueError(f'{scheme.upper()}_PROXY must specify a host and port')
    settings += [f'systemProp.{scheme}.proxyHost={proxy.hostname}',
                 f'systemProp.{scheme}.proxyPort={proxy.port}',
                 f'systemProp.{scheme}.nonProxyHosts=localhost|127.*|[::1]']
properties.write_text(existing.rstrip() + '\n\n' + '\n'.join(settings + [end]) + '\n')
PY

healthcheck() {
    echo 'Building the compiler distribution and warming Gradle caches...'
    bash ./gradlew --console=plain dist
    echo 'Compiling and running a Kotlin/JVM smoke program...'
    local smoke_dir result
    smoke_dir=$(mktemp -d "$setup_dir/smoke.XXXXXX")
    printf '%s\n' 'fun main() { check(listOf(20, 22).sum() == 42); println("Kotlin environment ready") }' \
        > "$smoke_dir/Smoke.kt"
    bash dist/kotlinc/bin/kotlinc "$smoke_dir/Smoke.kt" -include-runtime -d "$smoke_dir/smoke.jar"
    result=$(java -jar "$smoke_dir/smoke.jar")
    [[ "$result" == 'Kotlin environment ready' ]]
    rm -rf "$smoke_dir"
    echo "$result"
}

if [[ "${AIR_STARTUP_MODE:-}" == warmup ]]; then
    healthcheck
else
    echo 'Kotlin toolchains and caches are ready; skipping the warmup build.'
fi
