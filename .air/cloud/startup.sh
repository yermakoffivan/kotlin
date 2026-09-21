#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# Gradle's included build helpers need JDK 17 before toolchain provisioning
# becomes available. Gradle provisions its own JDK 21 and other project JDKs.
case "$(uname -m)" in
    x86_64) jdk_arch=x64 ;;
    aarch64) jdk_arch=aarch64 ;;
    *) echo "Unsupported JDK architecture: $(uname -m)" >&2; exit 1 ;;
esac

export JDK_17_0="$HOME/.jdks/temurin-17"
if [[ ! -x "$JDK_17_0/bin/javac" ]]; then
    echo "Installing Temurin JDK 17 for Kotlin's build helpers..."
    mkdir -p "$HOME/.jdks"
    staging=$(mktemp -d "$HOME/.jdks/.air-jdk-XXXXXX")
    trap 'rm -rf "$staging"' EXIT
    curl --fail --location --show-error --proxy "${HTTPS_PROXY:?HTTPS_PROXY is required}" \
        "https://api.adoptium.net/v3/binary/version/jdk-17.0.20.1%2B1/linux/$jdk_arch/jdk/hotspot/normal/eclipse" \
        --output "$staging/jdk.tar.gz"
    mkdir "$staging/jdk"
    tar -xzf "$staging/jdk.tar.gz" --strip-components=1 -C "$staging/jdk"
    # Remove only an incomplete installation left by an interrupted setup.
    rm -rf "$JDK_17_0"
    mv "$staging/jdk" "$JDK_17_0"
    rm -rf "$staging"
    trap - EXIT
fi

# Java does not automatically use HTTP(S)_PROXY. Persist the settings for
# both the Gradle wrapper and every JVM it launches, including future shells.
mkdir -p "$HOME/.config/air"
python3 - <<'PY' > "$HOME/.config/air/kotlin-env.sh"
import os
import shlex
from urllib.parse import urlsplit

print('export JDK_17_0="$HOME/.jdks/temurin-17"')
options = []
for protocol in ("http", "https"):
    proxy = urlsplit(os.environ.get(protocol.upper() + "_PROXY", ""))
    if proxy.hostname:
        options.extend([
            f"-D{protocol}.proxyHost={proxy.hostname}",
            f"-D{protocol}.proxyPort={proxy.port or 80}",
        ])
if options:
    options.append("-Dhttp.nonProxyHosts=localhost|127.0.0.1")
    print('case "${JAVA_TOOL_OPTIONS:-}" in')
    print('    *-Dhttps.proxyHost=*) ;;')
    print('    *) export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:+$JAVA_TOOL_OPTIONS }"' +
          shlex.quote(" ".join(options)) + ' ;;')
    print('esac')
PY

source_line='[ ! -f "$HOME/.config/air/kotlin-env.sh" ] || . "$HOME/.config/air/kotlin-env.sh" # air-kotlin-env'
profile="$HOME/.profile"
for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    if [[ -f "$candidate" ]]; then
        profile="$candidate"
        break
    fi
done
for shell_file in "$profile" "$HOME/.bashrc"; do
    if ! grep -qF '# air-kotlin-env' "$shell_file" 2>/dev/null; then
        printf '\n%s\n' "$source_line" >> "$shell_file"
    fi
done
source "$HOME/.config/air/kotlin-env.sh"

healthcheck() {
    echo "Warming Gradle, toolchain and dependency caches by compiling the JVM standard library..."
    # The build blocks until completion and propagates failures to startup.
    # Limit parallelism to leave memory for Gradle and Kotlin compiler daemons.
    bash ./gradlew :kotlin-stdlib:compileKotlinJvm --max-workers=2 --console=plain
    echo "Kotlin JVM standard library compilation passed."
}

if [[ "${AIR_STARTUP_MODE:-}" == warmup ]]; then
    healthcheck
fi
echo "Kotlin development environment is ready."
