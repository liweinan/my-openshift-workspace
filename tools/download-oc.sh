#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# --- Configuration ---
DEFAULT_VERSION="4.19.0"
DEFAULT_DIR="./"
DEFAULT_ARCH="x86_64"

# --- Usage ---
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Download OpenShift CLI (oc) for Linux

OPTIONS:
    -v, --version VERSION     OpenShift version (default: $DEFAULT_VERSION)
    -d, --dir DIRECTORY       Download directory (default: $DEFAULT_DIR)
    -a, --arch ARCHITECTURE   Architecture: x86_64, aarch64 (default: $DEFAULT_ARCH)
    -h, --help                Show this help message

EXAMPLES:
    # Download to current directory
    $0

    # Download specific version
    $0 --version 4.18.0

    # Download to custom directory
    $0 --dir ~/downloads

    # Download for ARM64 architecture
    $0 --arch aarch64

ENVIRONMENT VARIABLES:
    OC_VERSION               Override default version
    OC_DOWNLOAD_DIR          Override default download directory
    OC_ARCH                  Override default architecture

EOF
}

# --- Default values ---
OC_VERSION="${OC_VERSION:-$DEFAULT_VERSION}"
OC_DOWNLOAD_DIR="${OC_DOWNLOAD_DIR:-$DEFAULT_DIR}"
OC_ARCH="${OC_ARCH:-$DEFAULT_ARCH}"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            OC_VERSION="$2"
            shift 2
            ;;
        -d|--dir)
            OC_DOWNLOAD_DIR="$2"
            shift 2
            ;;
        -a|--arch)
            OC_ARCH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# --- Validation ---
if [[ ! "$OC_ARCH" =~ ^(x86_64|aarch64)$ ]]; then
    echo "Error: Unsupported architecture '$OC_ARCH'. Supported: x86_64, aarch64"
    exit 1
fi

# --- Functions ---
log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[SUCCESS] $*"
}

check_dependencies() {
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        log_error "Missing required dependencies: wget or curl"
        log_error "Please install wget or curl and try again"
        exit 1
    fi
}

download_file() {
    local url="$1"
    local output="$2"
    
    if command -v wget >/dev/null 2>&1; then
        log_info "Downloading with wget..."
        if ! wget -q --show-progress -O "$output" "$url"; then
            log_error "Failed to download with wget"
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        log_info "Downloading with curl..."
        if ! curl -L --progress-bar -o "$output" "$url"; then
            log_error "Failed to download with curl"
            return 1
        fi
    fi
    
    return 0
}

# --- Main execution ---
main() {
    log_info "OpenShift CLI Downloader"
    log_info "Version: $OC_VERSION"
    log_info "Architecture: $OC_ARCH"
    log_info "Download Directory: $OC_DOWNLOAD_DIR"
    echo
    
    check_dependencies
    
    # Create download directory if it doesn't exist
    if [[ ! -d "$OC_DOWNLOAD_DIR" ]]; then
        log_info "Creating download directory: $OC_DOWNLOAD_DIR"
        mkdir -p "$OC_DOWNLOAD_DIR"
    fi
    
    # Download URL
    local download_url
    download_url="https://mirror.openshift.com/pub/openshift-v4/$OC_ARCH/clients/ocp/$OC_VERSION/openshift-client-linux.tar.gz"
    
    local filename
    filename="openshift-client-linux-${OC_VERSION}-${OC_ARCH}.tar.gz"
    local output_file
    output_file="$OC_DOWNLOAD_DIR/$filename"
    
    log_info "Download URL: $download_url"
    log_info "Output file: $output_file"
    
    # Download the archive
    if ! download_file "$download_url" "$output_file"; then
        log_error "Failed to download OpenShift CLI"
        exit 1
    fi
    
    log_success "OpenShift CLI downloaded successfully"
    log_info "File saved as: $output_file"
    
    echo
    echo "To extract and use:"
    echo "  cd $OC_DOWNLOAD_DIR"
    echo "  tar -xzf $filename"
    echo "  chmod +x oc kubectl"
    echo
    echo "To use directly:"
    echo "  ./oc version --client"
    echo "  ./kubectl version --client"
}

# --- Run main function ---
main "$@"