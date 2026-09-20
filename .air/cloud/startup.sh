#!/usr/bin/env bash
# Warm the Kotlin compiler build and verify that its JVM compiler works.
set -euo pipefail
trap 'echo "Kotlin environment setup failed at line $LINENO" >&2' ERR

# Air may execute a materialized copy of this script outside the checkout.
cd "$(git rev-parse --show-toplevel)"
umask 022

setup_dir="$HOME/.local/share/air-kotlin"
mkdir -p "$setup_dir"

# Keep these distributions and aliases in sync with scripts/kotlin-build-env.dockerfile.
# Install in userspace because cloud tasks cannot write to /usr/lib/jvm.
case "$(uname -m)" in
    x86_64) jdk_platform=linux-x64 ;;
    aarch64) jdk_platform=linux-aarch64 ;;
    *) echo 'Unsupported JDK architecture' >&2; exit 1 ;;
esac
jdks_dir="$setup_dir/jdks"
mkdir -p "$jdks_dir"

install_jdk() (
    local name=$1 url=$2 staging_dir
    [[ ! -x "$jdks_dir/$name/bin/javac" ]] || return 0
    echo "Installing $name..."
    staging_dir=$(mktemp -d "$jdks_dir/.download.XXXXXX")
    trap 'rm -rf "$staging_dir"' EXIT
    curl -fsSL -x "${HTTPS_PROXY:?HTTPS_PROXY is required}" "$url" -o "$staging_dir/jdk.tar.gz"
    mkdir "$staging_dir/unpacked"
    tar -xzf "$staging_dir/jdk.tar.gz" --strip-components=1 -C "$staging_dir/unpacked"
    "$staging_dir/unpacked/bin/javac" -version
    mv "$staging_dir/unpacked" "$jdks_dir/$name"
)

while read -r major version; do
    jdk_name="amazon-corretto-$version-$jdk_platform"
    install_jdk "$jdk_name" "https://corretto.aws/downloads/resources/$version/$jdk_name.tar.gz"
    export "JDK$major=$jdks_dir/$jdk_name"
done <<'JDKS'
8 8.502.07.1
11 11.0.26.4.1
17 17.0.9.8.1
21 21.0.1.12.1
25 25.0.2.10.1
JDKS

install_jdk jdk-27 \
    "https://download.java.net/java/early_access/valhalla/27/1/openjdk-27-jep401ea3+1-1_${jdk_platform}_bin.tar.gz"
install_jdk graalvm-25.2.4+7.1 \
    "https://gds.oracle.com/download/graal/25i2/latest/graalvm-jdk-25i2-25_${jdk_platform}_bin.tar.gz"

export JDK_18="$JDK8" JDK_1_8="$JDK8" JDK_18_x64="$JDK8" JDK_1_8_x64="$JDK8"
export JDK_11_0="$JDK11" JDK_17_0="$JDK17" JDK_21_0="$JDK21" JDK_25_0="$JDK25"
export JDK_VALHALLA="$jdks_dir/jdk-27" JDK_NATIVE_IMAGE="$jdks_dir/graalvm-25.2.4+7.1"
export JAVA_HOME="$JDK_17_0" MAVEN_JAVA_HOME="$JDK_11_0"

# Startup is a child process. Persist the JDK selection for fresh agent shells.
{
    for variable in JDK8 JDK11 JDK17 JDK21 JDK25 \
        JDK_18 JDK_1_8 JDK_18_x64 JDK_1_8_x64 JDK_11_0 JDK_17_0 JDK_21_0 JDK_25_0 \
        JDK_VALHALLA JDK_NATIVE_IMAGE JAVA_HOME MAVEN_JAVA_HOME; do
        printf 'export %s=%q\n' "$variable" "${!variable}"
    done
    cat <<'PROFILE'
case ":$PATH:" in
    ":$JAVA_HOME/bin:"*) ;;
    *) export PATH="$JAVA_HOME/bin:$PATH" ;;
esac
PROFILE
} > "$setup_dir/environment.sh"
profile_line='. "$HOME/.local/share/air-kotlin/environment.sh" # Air Kotlin JDKs'
login_profile="$HOME/.profile"
for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    if [[ -f "$candidate" ]]; then
        login_profile=$candidate
        break
    fi
done
for profile in "$login_profile" "$HOME/.bashrc"; do
    if ! grep -Fqx "$profile_line" "$profile" 2>/dev/null; then
        printf '\n%s\n' "$profile_line" >> "$profile"
    fi
done
source "$setup_dir/environment.sh"

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
    'org.gradle.java.installations.paths=' + ','.join(
        os.environ[key] for key in ('JDK8', 'JDK11', 'JDK17', 'JDK21', 'JDK25', 'JDK_VALHALLA', 'JDK_NATIVE_IMAGE')
    ),
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
    echo 'Checking the build-image JDKs from a fresh login shell...'
    bash -lc '
        set -euo pipefail
        smoke_dir=$(mktemp -d)
        trap '\''rm -rf "$smoke_dir"'\'' EXIT
        printf "%s\n" "class Smoke { public static void main(String[] args) { System.out.println(42); } }" \
            > "$smoke_dir/Smoke.java"
        for key in JDK8 JDK11 JDK17 JDK21 JDK25 JDK_VALHALLA JDK_NATIVE_IMAGE; do
            echo "Checking $key"
            "${!key}/bin/javac" -version
            "${!key}/bin/javac" -d "$smoke_dir" "$smoke_dir/Smoke.java"
            [[ "$("${!key}/bin/java" -cp "$smoke_dir" Smoke)" == 42 ]]
        done
        [[ "$JAVA_HOME" == "$JDK17" && "$MAVEN_JAVA_HOME" == "$JDK11" ]]
        [[ "$(command -v java)" == "$JAVA_HOME/bin/java" ]]
        "$JDK_NATIVE_IMAGE/bin/native-image" --version
    '
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
