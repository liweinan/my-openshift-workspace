#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "${SCRIPT_DIR}")"
BACKUP_DIR="${WORKSPACE_ROOT}/backup-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to create backup and remove files/directories
backup_and_remove() {
    local target="$1"
    local description="$2"
    local backup_subdir="$3"
    
    if [ -e "${target}" ]; then
        # Create backup directory
        local backup_path="${BACKUP_DIR}/${backup_subdir}"
        mkdir -p "${backup_path}"
        
        if [ -d "${target}" ]; then
            echo "  Backing up and removing directory: ${target}"
            cp -r "${target}" "${backup_path}/"
            rm -rf "${target}"
        else
            echo "  Backing up and removing file: ${target}"
            cp "${target}" "${backup_path}/"
            rm -f "${target}"
        fi
        print_success "${description} (backed up to ${backup_path})"
    else
        echo "  Not found: ${target}"
    fi
}

# Function to find, backup and remove files by pattern
backup_and_remove_by_pattern() {
    local pattern="$1"
    local description="$2"
    local backup_subdir="$3"
    local found_files=()
    
    # Find files matching pattern
    while IFS= read -r -d '' file; do
        found_files+=("$file")
    done < <(find "${WORKSPACE_ROOT}" -name "${pattern}" -type f -print0 2>/dev/null)
    
    if [ ${#found_files[@]} -gt 0 ]; then
        # Create backup directory
        local backup_path="${BACKUP_DIR}/${backup_subdir}"
        mkdir -p "${backup_path}"
        
        echo "  Found ${#found_files[@]} file(s) matching '${pattern}':"
        for file in "${found_files[@]}"; do
            echo "    - ${file}"
            # Create relative path in backup
            local rel_path="${file#${WORKSPACE_ROOT}/}"
            local backup_file_path="${backup_path}/${rel_path}"
            mkdir -p "$(dirname "${backup_file_path}")"
            cp "${file}" "${backup_file_path}"
            rm -f "${file}"
        done
        print_success "${description} (backed up to ${backup_path})"
    else
        echo "  No files found matching '${pattern}'"
    fi
}

# Function to find, backup and remove directories by pattern
backup_and_remove_dirs_by_pattern() {
    local pattern="$1"
    local description="$2"
    local backup_subdir="$3"
    local found_dirs=()
    
    # Find directories matching pattern
    while IFS= read -r -d '' dir; do
        found_dirs+=("$dir")
    done < <(find "${WORKSPACE_ROOT}" -name "${pattern}" -type d -print0 2>/dev/null)
    
    if [ ${#found_dirs[@]} -gt 0 ]; then
        # Create backup directory
        local backup_path="${BACKUP_DIR}/${backup_subdir}"
        mkdir -p "${backup_path}"
        
        echo "  Found ${#found_dirs[@]} directory(ies) matching '${pattern}':"
        for dir in "${found_dirs[@]}"; do
            echo "    - ${dir}"
            # Create relative path in backup
            local rel_path="${dir#${WORKSPACE_ROOT}/}"
            local backup_dir_path="${backup_path}/${rel_path}"
            mkdir -p "$(dirname "${backup_dir_path}")"
            cp -r "${dir}" "${backup_dir_path}"
            rm -rf "${dir}"
        done
        print_success "${description} (backed up to ${backup_path})"
    else
        echo "  No directories found matching '${pattern}'"
    fi
}

# --- Main Script ---
print_header "OpenShift Installation Files Cleanup with Backup"
echo "Workspace root: ${WORKSPACE_ROOT}"
echo "Backup directory: ${BACKUP_DIR}"
echo ""

# Check if running in dry-run mode
DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=true
    print_warning "Running in DRY-RUN mode - no files will be deleted"
    echo ""
fi

# Confirmation prompt
if [ "${DRY_RUN}" = false ]; then
    print_warning "This script will backup and delete OpenShift installation files in the workspace."
    print_warning "Files will be backed up to: ${BACKUP_DIR}"
    print_warning "This includes:"
    echo "  - All work*/ directories"
    echo "  - All .openshift_install* files"
    echo "  - All .clusterapi_output/ directories"
    echo "  - All auth/ directories"
    echo "  - All tls/ directories"
    echo "  - All metadata.json files"
    echo "  - All terraform files"
    echo "  - All log files"
    echo "  - All temporary files"
    echo "  - OpenShift installer binaries and packages"
    echo "  - Release and checksum files"
    echo "  - Pull secret files"
    echo ""
    print_info "OCP project directories will be preserved (contain useful scripts)"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_info "Cleanup cancelled by user."
        exit 0
    fi
    echo ""
    
    # Create backup directory
    mkdir -p "${BACKUP_DIR}"
    print_success "Created backup directory: ${BACKUP_DIR}"
    echo ""
fi

# Override functions for dry-run
if [ "${DRY_RUN}" = true ]; then
    backup_and_remove() {
        echo "  [DRY-RUN] Would backup and remove: $1"
    }
    backup_and_remove_by_pattern() {
        echo "  [DRY-RUN] Would backup and remove files matching: $1"
    }
    backup_and_remove_dirs_by_pattern() {
        echo "  [DRY-RUN] Would backup and remove directories matching: $1"
    }
fi

# --- Cleanup Operations ---

print_header "1. Cleaning OpenShift Installation Directories"
# Remove work directories
backup_and_remove_dirs_by_pattern "work*" "Removed work directories" "work-directories"

print_header "2. Cleaning OpenShift Installer State Files"
# Remove .openshift_install files
backup_and_remove_by_pattern ".openshift_install*" "Removed OpenShift installer state files" "installer-state"

print_header "3. Cleaning Cluster API Output Directories"
# Remove .clusterapi_output directories
backup_and_remove_dirs_by_pattern ".clusterapi_output" "Removed Cluster API output directories" "cluster-api-output"

print_header "4. Cleaning Authentication Files"
# Remove auth directories
backup_and_remove_dirs_by_pattern "auth" "Removed authentication directories" "auth-files"

print_header "5. Cleaning TLS Certificates"
# Remove tls directories
backup_and_remove_dirs_by_pattern "tls" "Removed TLS certificate directories" "tls-certificates"

print_header "6. Cleaning Metadata Files"
# Remove metadata.json files
backup_and_remove_by_pattern "metadata.json" "Removed metadata files" "metadata"

print_header "7. Cleaning Terraform Files"
# Remove terraform files
backup_and_remove_by_pattern "terraform.tfstate*" "Removed Terraform state files" "terraform-state"
backup_and_remove_by_pattern "terraform.platform.auto.tfvars.json" "Removed Terraform auto tfvars files" "terraform-config"
backup_and_remove_by_pattern "terraform.tfvars.json" "Removed Terraform tfvars files" "terraform-config"

print_header "8. Cleaning Log Files"
# Remove log files
backup_and_remove_by_pattern "*.log" "Removed log files" "log-files"

print_header "9. Cleaning Temporary Files"
# Remove temporary files
backup_and_remove_by_pattern "*.tmp" "Removed temporary files" "temp-files"
backup_and_remove_by_pattern "*.bak" "Removed backup files" "backup-files"
backup_and_remove_by_pattern "*.swp" "Removed swap files" "swap-files"
backup_and_remove_by_pattern "*~" "Removed tilde backup files" "tilde-backups"

print_header "10. Cleaning Installation Artifacts"
# Remove specific installation artifacts
backup_and_remove_by_pattern "log-bundle-*.tar.gz" "Removed log bundle files" "log-bundles"
backup_and_remove_by_pattern "*.pem" "Removed PEM key files"

print_header "11. Cleaning OpenShift Installer Binaries and Packages"
# Remove OpenShift installer binaries
backup_and_remove_by_pattern "openshift-install" "Removed OpenShift installer binary" "installer-binaries"
backup_and_remove_by_pattern "openshift-install-*.tar.gz" "Removed OpenShift installer packages" "installer-packages"
backup_and_remove_by_pattern "openshift-client-*.tar.gz" "Removed OpenShift client packages" "client-packages"

print_header "12. Cleaning Release and Checksum Files"
# Remove release and checksum files
backup_and_remove_by_pattern "release.txt" "Removed release.txt files" "release-files"
backup_and_remove_by_pattern "sha256sum.txt" "Removed sha256sum.txt files" "checksum-files"
backup_and_remove_by_pattern "pull-secret.json" "Removed pull-secret.json files" "pull-secrets"
backup_and_remove_by_pattern "pull-secret.txt" "Removed pull-secret.txt files" "pull-secrets"

print_header "13. Preserving OCP Project Directories"
echo "  OCP project directories contain useful scripts and are preserved:"
OCP_DIRS=()
while IFS= read -r -d '' dir; do
    OCP_DIRS+=("$dir")
done < <(find "${WORKSPACE_ROOT}" -maxdepth 1 -name "OCP-*" -type d -print0 2>/dev/null)

if [ ${#OCP_DIRS[@]} -gt 0 ]; then
    for dir in "${OCP_DIRS[@]}"; do
        echo "    - $(basename "${dir}") (preserved)"
    done
    print_info "OCP project directories preserved (contain useful scripts)"
else
    echo "  No OCP project directories found"
fi

# --- Summary ---
print_header "Cleanup Summary"
if [ "${DRY_RUN}" = true ]; then
    print_info "Dry-run completed. No files were actually deleted."
    echo ""
    print_info "To perform actual cleanup with backup, run:"
    echo "  $0"
else
    print_success "OpenShift installation files cleanup completed!"
    echo ""
    print_info "Backup location: ${BACKUP_DIR}"
    print_info "Backup size: $(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "Unknown")"
    echo ""
    print_warning "To restore files from backup:"
    echo "  cp -r ${BACKUP_DIR}/* ${WORKSPACE_ROOT}/"
    echo ""
    print_warning "To remove backup after verification:"
    echo "  rm -rf ${BACKUP_DIR}"
fi

echo ""
print_info "Remaining files in workspace:"
echo "  - tools/ directory (utility scripts)"
echo "  - generate-metadata/ directory (metadata generation tools)"
echo "  - README files and documentation"
echo "  - Configuration templates and samples"

echo ""
print_info "If you need to clean up AWS resources as well, use:"
echo "  ./check-cluster-destroy-status.sh <installer-directory>"
echo "  ./delete-stacks-by-name.sh <stack-name-pattern>"
