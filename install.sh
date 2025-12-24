#!/usr/bin/env bash
set -euo pipefail

REPO="shaankhosla/repeat"
APP="repeat"

# Allow overriding install dir, otherwise pick a sensible default per OS later.
INSTALL_DIR="${INSTALL_DIR:-}"

cleanup() {
    if [[ -n "${TMPDIR:-}" && -d "${TMPDIR:-}" ]]; then
        rm -rf "$TMPDIR"
    fi
}
trap cleanup EXIT

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "x86_64" ;;
        arm64|aarch64) echo "aarch64" ;;
        *)
            echo "Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
}

detect_os() {
    uname -s | tr '[:upper:]' '[:lower:]'
}

ARCH=$(detect_arch)
OS=$(detect_os)

TARGET=""
ARCHIVE_EXT="tar.gz"
BIN_NAME="$APP"

case "$OS" in
    linux)
        case "$ARCH" in
            x86_64|aarch64) TARGET="${ARCH}-unknown-linux-gnu" ;;
            *)
                echo "Unsupported Linux architecture: $ARCH" >&2
                exit 1
                ;;
        esac
        INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
        ;;
    darwin)
        if [[ "$ARCH" != "aarch64" ]]; then
            echo "Only Apple Silicon (arm64) builds are published for macOS" >&2
            exit 1
        fi
        TARGET="${ARCH}-apple-darwin"
        INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
        ;;
    msys*|mingw*|cygwin*)
        if [[ "$ARCH" != "x86_64" ]]; then
            echo "Only x86_64 builds are published for Windows" >&2
            exit 1
        fi
        TARGET="${ARCH}-pc-windows-msvc"
        ARCHIVE_EXT="zip"
        BIN_NAME="${APP}.exe"
        INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
        ;;
    *)
        echo "Unsupported OS: $OS" >&2
        exit 1
        ;;
esac

# Fetch latest release tag from GitHub API (portable way)
TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
if [[ -z "$TAG" ]]; then
    echo "Could not determine latest release" >&2
    exit 1
fi

# Build URLs
BASENAME="${APP}-${TAG}-${TARGET}"
ARCHIVE="${BASENAME}.${ARCHIVE_EXT}"
CHECKSUM="${ARCHIVE}.sha256"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE}"
CHECKSUM_URL="https://github.com/${REPO}/releases/download/${TAG}/${CHECKSUM}"

# Download files
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

echo "Downloading ${ARCHIVE}..."
curl -fLO "$URL"
curl -fLO "$CHECKSUM_URL"

hash_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        echo "No SHA256 checksum tool found" >&2
        exit 1
    fi
}

echo "Verifying checksum..."
EXPECTED_HASH=$(awk '{print $1}' "$CHECKSUM")
if [[ -z "$EXPECTED_HASH" ]]; then
    echo "Checksum file is empty or malformed" >&2
    exit 1
fi
ACTUAL_HASH=$(hash_file "$ARCHIVE")
if [[ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]]; then
    echo "Checksum mismatch for $ARCHIVE" >&2
    exit 1
fi

# Extract and install
echo "Extracting ${ARCHIVE}..."
case "$ARCHIVE_EXT" in
    tar.gz)
        tar -xzf "$ARCHIVE"
        ;;
    zip)
        if ! command -v unzip >/dev/null 2>&1; then
            echo "unzip is required to extract ${ARCHIVE}" >&2
            exit 1
        fi
        unzip -q "$ARCHIVE"
        ;;
    *)
        echo "Unsupported archive extension: $ARCHIVE_EXT" >&2
        exit 1
        ;;
esac

PAYLOAD_DIR="$BASENAME"
if [[ ! -d "$PAYLOAD_DIR" ]]; then
    echo "Expected payload directory ${PAYLOAD_DIR} not found in archive" >&2
    exit 1
fi

SOURCE_BINARY="${PAYLOAD_DIR}/${BIN_NAME}"
if [[ ! -f "$SOURCE_BINARY" ]]; then
    echo "Binary ${BIN_NAME} not found inside ${PAYLOAD_DIR}" >&2
    exit 1
fi

DEST_PATH="${INSTALL_DIR}/${BIN_NAME}"
DEST_DIR=$(dirname "$DEST_PATH")

ensure_dir() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        return
    fi
    if [[ -w "$(dirname "$dir")" ]]; then
        mkdir -p "$dir"
    elif command -v sudo >/dev/null 2>&1; then
        sudo mkdir -p "$dir"
    else
        echo "Cannot create directory $dir (insufficient permissions and sudo not available)" >&2
        exit 1
    fi
}

install_binary() {
    local src="$1"
    local dest="$2"
    local dir
    dir=$(dirname "$dest")

    ensure_dir "$dir"

    local prefix=()
    if [[ -w "$dir" ]]; then
        prefix=()
    elif command -v sudo >/dev/null 2>&1; then
        prefix=(sudo)
    else
        echo "Cannot write to $dir (insufficient permissions and sudo not available)" >&2
        exit 1
    fi

    if command -v install >/dev/null 2>&1; then
        "${prefix[@]}" install -m 755 "$src" "$dest"
    else
        "${prefix[@]}" cp "$src" "$dest"
        "${prefix[@]}" chmod 755 "$dest"
    fi
}

echo "Installing to ${DEST_PATH}..."
install_binary "$SOURCE_BINARY" "$DEST_PATH"

echo "Installed ${APP} ${TAG} successfully to ${DEST_PATH}"
