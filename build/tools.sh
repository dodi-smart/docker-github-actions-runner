#!/usr/bin/env bash
set -euo pipefail

function install_git() {
  ( apt-get install -y --no-install-recommends git \
   || apt-get install -t stable -y --no-install-recommends git )
}

function install_liblttng-ust() {
  if [[ $(apt-cache search -n liblttng-ust0 | awk '{print $1}') == "liblttng-ust0" ]]; then
    apt-get install -y --no-install-recommends liblttng-ust0
  fi

  if [[ $(apt-cache search -n liblttng-ust1 | awk '{print $1}') == "liblttng-ust1" ]]; then
    apt-get install -y --no-install-recommends liblttng-ust1
  fi
}

function install_aws-cli() {
  ( curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip -d /tmp/ \
    && /tmp/aws/install \
    && rm awscliv2.zip \
  ) \
    || pip3 install --no-cache-dir awscli
}

function install_git-lfs() {
  local DPKG_ARCH GIT_LFS_VERSION
  DPKG_ARCH="$(dpkg --print-architecture)"
  GIT_LFS_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/git-lfs/git-lfs/releases/latest \
      | jq -r '.tag_name' | sed 's/^v//g')

  curl -s "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-${DPKG_ARCH}-v${GIT_LFS_VERSION}.tar.gz" -L -o /tmp/lfs.tar.gz
  tar -xzf /tmp/lfs.tar.gz -C /tmp
  "/tmp/git-lfs-${GIT_LFS_VERSION}/install.sh"
  rm -rf /tmp/lfs.tar.gz "/tmp/git-lfs-${GIT_LFS_VERSION}"
}

function install_docker-cli() {
  apt-get install -y docker-ce-cli --no-install-recommends --allow-unauthenticated
}

function install_docker() {
  apt-get install -y docker-ce docker-ce-cli docker-buildx-plugin containerd.io docker-compose-plugin --no-install-recommends --allow-unauthenticated

  echo -e '#!/bin/sh\ndocker compose --compatibility "$@"' > /usr/local/bin/docker-compose
  chmod +x /usr/local/bin/docker-compose

  sed -i 's/ulimit -Hn/# ulimit -Hn/g' /etc/init.d/docker
}

function install_container-tools() {
  ( apt-get install -y --no-install-recommends podman buildah skopeo || : )
}

function install_github-cli() {
  local DPKG_ARCH GH_CLI_VERSION GH_CLI_DOWNLOAD_URL

  DPKG_ARCH="$(dpkg --print-architecture)"

  GH_CLI_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/cli/cli/releases/latest \
      | jq -r '.tag_name' | sed 's/^v//g')

  GH_CLI_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/cli/cli/releases/latest \
      | jq ".assets[] | select(.name == \"gh_${GH_CLI_VERSION}_linux_${DPKG_ARCH}.deb\")" \
      | jq -r '.browser_download_url')

  curl -sSLo /tmp/ghcli.deb "${GH_CLI_DOWNLOAD_URL}"
  apt-get -y install /tmp/ghcli.deb
  rm /tmp/ghcli.deb
}

function install_yq() {
  local DPKG_ARCH YQ_DOWNLOAD_URL

  DPKG_ARCH="$(dpkg --print-architecture)"

  YQ_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/mikefarah/yq/releases/latest \
      | jq ".assets[] | select(.name == \"yq_linux_${DPKG_ARCH}.tar.gz\")" \
      | jq -r '.browser_download_url')

  curl -s "${YQ_DOWNLOAD_URL}" -L -o /tmp/yq.tar.gz
  tar -xzf /tmp/yq.tar.gz -C /tmp
  mv "/tmp/yq_linux_${DPKG_ARCH}" /usr/local/bin/yq
}

function install_powershell() {
  local DPKG_ARCH PWSH_VERSION PWSH_DOWNLOAD_URL

  DPKG_ARCH="$(dpkg --print-architecture)"

  PWSH_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
      | jq -r '.tag_name' \
      | sed 's/^v//g')

  PWSH_DOWNLOAD_URL=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/PowerShell/PowerShell/releases/latest \
      | jq -r ".assets[] | select(.name == \"powershell-${PWSH_VERSION}-linux-${DPKG_ARCH//amd64/x64}.tar.gz\") | .browser_download_url")

  curl -L -o /tmp/powershell.tar.gz "$PWSH_DOWNLOAD_URL"
  mkdir -p /opt/powershell
  tar zxf /tmp/powershell.tar.gz -C /opt/powershell
  chmod +x /opt/powershell/pwsh
  ln -s /opt/powershell/pwsh /usr/bin/pwsh
}

function install_java() {
  local JAVA_VERSION JAVA_PACKAGE

  # Try Java 21 first, fall back to 17 for older Ubuntu versions
  if apt-cache show openjdk-21-jdk-headless &>/dev/null; then
    JAVA_VERSION="21"
  elif apt-cache show openjdk-17-jdk-headless &>/dev/null; then
    JAVA_VERSION="17"
  else
    JAVA_VERSION="11"
  fi

  JAVA_PACKAGE="openjdk-${JAVA_VERSION}-jdk-headless"
  apt-get install -y --no-install-recommends "${JAVA_PACKAGE}"

  echo "export JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-$(dpkg --print-architecture)" >> /etc/profile.d/java.sh
  echo "export PATH=\${PATH}:\${JAVA_HOME}/bin" >> /etc/profile.d/java.sh
  chmod +x /etc/profile.d/java.sh
}

function install_android_sdk() {
  local ANDROID_SDK_ROOT="/opt/android-sdk"
  local CMDLINE_TOOLS_VERSION

  # Get latest command-line tools version (disable pipefail to avoid SIGPIPE)
  set +o pipefail
  CMDLINE_TOOLS_VERSION=$(curl -sL "https://developer.android.com/studio#command-tools" \
    | grep -oP 'commandlinetools-linux-\K[0-9]+' | head -1)
  set -o pipefail

  # Fallback to known stable version if parsing fails
  CMDLINE_TOOLS_VERSION="${CMDLINE_TOOLS_VERSION:-11076708}"

  mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools"

  curl -sSL "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
    -o /tmp/cmdline-tools.zip
  unzip -q /tmp/cmdline-tools.zip -d /tmp/
  mv /tmp/cmdline-tools "${ANDROID_SDK_ROOT}/cmdline-tools/latest"
  rm /tmp/cmdline-tools.zip

  # Accept licenses (disable pipefail temporarily to avoid SIGPIPE exit 141)
  set +o pipefail
  yes | "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" --licenses > /dev/null 2>&1 || true
  set -o pipefail

  # Install essential SDK components
  "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" \
    "platform-tools" \
    "build-tools;36.0.0" \
    "platforms;android-36"

  # Set environment variables
  echo "export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT}" >> /etc/profile.d/android-sdk.sh
  echo "export ANDROID_HOME=${ANDROID_SDK_ROOT}" >> /etc/profile.d/android-sdk.sh
  echo "export PATH=\${PATH}:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools" >> /etc/profile.d/android-sdk.sh
  chmod +x /etc/profile.d/android-sdk.sh
}

function install_android_ndk() {
  local ANDROID_SDK_ROOT="/opt/android-sdk"
  local NDK_LTS_VERSION="27.3.13750724"
  local NDK_LATEST_VERSION="29.0.14206865"
  local INSTALLED_VERSION

  echo "DEBUG: Starting NDK LTS install..."
  # Install LTS NDK version
  "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" "ndk;${NDK_LTS_VERSION}"
  echo "DEBUG: NDK LTS install done, exit code: $?"

  echo "DEBUG: Starting NDK latest install..."
  # Try to install latest NDK version (may not be available in sdkmanager yet)
  if "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" "ndk;${NDK_LATEST_VERSION}" 2>/dev/null; then
    INSTALLED_VERSION="${NDK_LATEST_VERSION}"
    echo "DEBUG: NDK latest installed successfully"
  else
    echo "NDK ${NDK_LATEST_VERSION} not available in sdkmanager, using LTS version"
    INSTALLED_VERSION="${NDK_LTS_VERSION}"
  fi

  echo "DEBUG: Writing environment variables..."
  # Set environment variables (default to latest installed)
  echo "export ANDROID_NDK_ROOT=${ANDROID_SDK_ROOT}/ndk/${INSTALLED_VERSION}" >> /etc/profile.d/android-ndk.sh
  echo "export ANDROID_NDK_HOME=${ANDROID_SDK_ROOT}/ndk/${INSTALLED_VERSION}" >> /etc/profile.d/android-ndk.sh
  echo "export ANDROID_NDK_LTS=${ANDROID_SDK_ROOT}/ndk/${NDK_LTS_VERSION}" >> /etc/profile.d/android-ndk.sh
  echo "export PATH=\${PATH}:${ANDROID_SDK_ROOT}/ndk/${INSTALLED_VERSION}" >> /etc/profile.d/android-ndk.sh
  chmod +x /etc/profile.d/android-ndk.sh
  echo "DEBUG: install_android_ndk completed"
}

function install_dart() {
  local DPKG_ARCH DART_VERSION DART_ARCH VERSION_JSON

  echo "DEBUG: install_dart starting..."
  DPKG_ARCH="$(dpkg --print-architecture)"
  echo "DEBUG: arch=${DPKG_ARCH}"

  # Map Debian arch to Dart arch naming
  case "${DPKG_ARCH}" in
    amd64) DART_ARCH="x64" ;;
    arm64) DART_ARCH="arm64" ;;
    *) echo "Unsupported architecture: ${DPKG_ARCH}"; return 1 ;;
  esac

  echo "DEBUG: Fetching Dart version..."
  # Get latest stable Dart version
  VERSION_JSON=$(curl -sL "https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION")
  echo "DEBUG: VERSION_JSON=${VERSION_JSON}"
  DART_VERSION=$(echo "${VERSION_JSON}" | jq -r '.version')
  echo "DEBUG: DART_VERSION=${DART_VERSION}"

  curl -sSL "https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-${DART_ARCH}-release.zip" \
    -o /tmp/dart-sdk.zip
  unzip -q /tmp/dart-sdk.zip -d /opt/
  rm /tmp/dart-sdk.zip

  # Set environment variables
  echo "export DART_ROOT=/opt/dart-sdk" >> /etc/profile.d/dart.sh
  echo "export PATH=\${PATH}:/opt/dart-sdk/bin" >> /etc/profile.d/dart.sh
  chmod +x /etc/profile.d/dart.sh
}

function install_flutter() {
  local DPKG_ARCH FLUTTER_DOWNLOAD_URL

  DPKG_ARCH="$(dpkg --print-architecture)"

  # Flutter Linux SDK releases are only available for x64 via the releases API
  if [[ "${DPKG_ARCH}" != "amd64" ]]; then
    echo "Flutter Linux SDK is only available for amd64 architecture via releases API, skipping on ${DPKG_ARCH}"
    return 0
  fi

  # Get latest stable Flutter download URL (disable pipefail to avoid SIGPIPE)
  set +o pipefail
  FLUTTER_DOWNLOAD_URL=$(curl -sL "https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json" \
    | jq -r '[.releases[] | select(.channel == "stable")] | first | .archive')
  set -o pipefail

  if [[ -z "${FLUTTER_DOWNLOAD_URL}" ]]; then
    echo "Failed to get Flutter download URL"
    return 1
  fi

  curl -sSL "https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_DOWNLOAD_URL}" \
    -o /tmp/flutter.tar.xz
  tar xf /tmp/flutter.tar.xz -C /opt/
  rm /tmp/flutter.tar.xz

  # Mark flutter directory as safe for git (required when running as root)
  git config --global --add safe.directory /opt/flutter

  # Set environment variables
  echo "export FLUTTER_ROOT=/opt/flutter" >> /etc/profile.d/flutter.sh
  echo "export PATH=\${PATH}:/opt/flutter/bin" >> /etc/profile.d/flutter.sh
  chmod +x /etc/profile.d/flutter.sh

  # Pre-cache Flutter artifacts
  /opt/flutter/bin/flutter precache
  /opt/flutter/bin/flutter config --no-analytics
}

function install_chrome() {
  local DPKG_ARCH
  DPKG_ARCH="$(dpkg --print-architecture)"

  # Chrome is only available for amd64
  if [[ "${DPKG_ARCH}" != "amd64" ]]; then
    echo "Google Chrome is only available for amd64 architecture, skipping on ${DPKG_ARCH}"
    return 0
  fi

  curl -sSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb
  apt-get install -y /tmp/chrome.deb || apt-get install -y -f
  rm /tmp/chrome.deb
}

function install_chromedriver() {
  local CHROME_VERSION CHROMEDRIVER_URL DPKG_ARCH CHROMEDRIVER_PLATFORM

  DPKG_ARCH="$(dpkg --print-architecture)"

  # ChromeDriver is only available for amd64
  if [[ "${DPKG_ARCH}" != "amd64" ]]; then
    echo "ChromeDriver is only available for amd64 architecture, skipping on ${DPKG_ARCH}"
    return 0
  fi

  CHROMEDRIVER_PLATFORM="linux64"

  # Get installed Chrome version
  CHROME_VERSION=$(google-chrome --version | grep -oP '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

  # Get ChromeDriver download URL for matching version
  CHROMEDRIVER_URL=$(curl -sL "https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json" \
    | jq -r ".versions[] | select(.version == \"${CHROME_VERSION}\") | .downloads.chromedriver[] | select(.platform == \"${CHROMEDRIVER_PLATFORM}\") | .url")

  # Fallback to latest stable if exact match not found
  if [[ -z "${CHROMEDRIVER_URL}" ]]; then
    CHROMEDRIVER_URL=$(curl -sL "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json" \
      | jq -r ".channels.Stable.downloads.chromedriver[] | select(.platform == \"${CHROMEDRIVER_PLATFORM}\") | .url")
  fi

  curl -sSL "${CHROMEDRIVER_URL}" -o /tmp/chromedriver.zip
  unzip -q /tmp/chromedriver.zip -d /tmp/
  mv "/tmp/chromedriver-${CHROMEDRIVER_PLATFORM}/chromedriver" /usr/local/bin/chromedriver
  chmod +x /usr/local/bin/chromedriver
  rm -rf /tmp/chromedriver.zip "/tmp/chromedriver-${CHROMEDRIVER_PLATFORM}"
}

function install_nodejs() {
  local DPKG_ARCH NODE_ARCH NODE_VERSION

  DPKG_ARCH="$(dpkg --print-architecture)"

  # Map Debian arch to Node.js arch naming
  case "${DPKG_ARCH}" in
    amd64) NODE_ARCH="x64" ;;
    arm64) NODE_ARCH="arm64" ;;
    *) echo "Unsupported architecture: ${DPKG_ARCH}"; return 1 ;;
  esac

  # Get latest LTS version
  NODE_VERSION=$(curl -sL "https://nodejs.org/dist/index.json" \
    | jq -r '[.[] | select(.lts != false)] | first | .version')

  curl -sSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
    -o /tmp/nodejs.tar.xz
  tar xf /tmp/nodejs.tar.xz -C /usr/local --strip-components=1
  rm /tmp/nodejs.tar.xz

  # Install common global packages
  npm install -g npm@latest
}

function install_ffmpeg() {
  # shellcheck source=/dev/null
  source /etc/os-release

  # Try to add FFmpeg PPA for latest versions (may not be available for all Ubuntu versions)
  apt-get install -y --no-install-recommends software-properties-common
  if add-apt-repository -y ppa:ubuntuhandbook1/ffmpeg7 2>/dev/null; then
    apt-get update
  else
    echo "FFmpeg PPA not available for ${VERSION_CODENAME}, using default repository"
  fi

  # Install FFmpeg with development libraries
  apt-get install -y --no-install-recommends \
    ffmpeg \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libavfilter-dev \
    libavdevice-dev \
    libswscale-dev \
    libswresample-dev \
    libpostproc-dev
}

function install_opencv() {
  apt-get install -y --no-install-recommends \
    libopencv-dev \
    python3-opencv
}

function install_ktlint() {
  local KTLINT_VERSION

  KTLINT_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/pinterest/ktlint/releases/latest \
      | jq -r '.tag_name')

  curl -sSL "https://github.com/pinterest/ktlint/releases/download/${KTLINT_VERSION}/ktlint" \
    -o /usr/local/bin/ktlint
  chmod +x /usr/local/bin/ktlint
}

function install_swiftformat() {
  local DPKG_ARCH SWIFTFORMAT_VERSION

  DPKG_ARCH="$(dpkg --print-architecture)"

  # SwiftFormat Linux binary is only available for amd64
  if [[ "${DPKG_ARCH}" != "amd64" ]]; then
    echo "SwiftFormat Linux binary is only available for amd64 architecture, skipping on ${DPKG_ARCH}"
    return 0
  fi

  SWIFTFORMAT_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/nicklockwood/SwiftFormat/releases/latest \
      | jq -r '.tag_name')

  curl -sSL "https://github.com/nicklockwood/SwiftFormat/releases/download/${SWIFTFORMAT_VERSION}/swiftformat_linux.zip" \
    -o /tmp/swiftformat.zip
  unzip -q /tmp/swiftformat.zip -d /tmp/
  mv /tmp/swiftformat_linux /usr/local/bin/swiftformat
  chmod +x /usr/local/bin/swiftformat
  rm -rf /tmp/swiftformat.zip
}

function install_bun() {
  local DPKG_ARCH BUN_VERSION BUN_DOWNLOAD_URL BUN_ARCH

  DPKG_ARCH="$(dpkg --print-architecture)"

  # Map Debian arch to Bun arch naming
  case "${DPKG_ARCH}" in
    amd64) BUN_ARCH="x64" ;;
    arm64) BUN_ARCH="aarch64" ;;
    *) echo "Unsupported architecture: ${DPKG_ARCH}"; return 1 ;;
  esac

  BUN_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/oven-sh/bun/releases/latest \
      | jq -r '.tag_name' | sed 's/^bun-v//g')

  BUN_DOWNLOAD_URL="https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-${BUN_ARCH}.zip"

  curl -sSL "${BUN_DOWNLOAD_URL}" -o /tmp/bun.zip
  unzip -q /tmp/bun.zip -d /tmp/
  mv "/tmp/bun-linux-${BUN_ARCH}/bun" /usr/local/bin/bun
  chmod +x /usr/local/bin/bun
  rm -rf /tmp/bun.zip "/tmp/bun-linux-${BUN_ARCH}"
}

function install_tools() {
  local function_name package
  # shellcheck source=/dev/null
  source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

  # Use process substitution to avoid subshell trap where exit would only exit the subshell
  while read -r package; do
    function_name="install_${package}"
    echo "========== Installing: ${package} =========="
    if declare -f "${function_name}" > /dev/null; then
      "${function_name}"
      echo "========== Finished: ${package} (exit: $?) =========="
    else
      echo "No install script found for package: ${package}"
      exit 1
    fi
  done < <(script_packages)
  echo "========== All packages installed =========="
}
