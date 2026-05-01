#!/bin/bash
##############################################################################
# ZZCOLLAB UNINSTALL SCRIPT
##############################################################################
# 
# PURPOSE: Safely removes files and directories created by zzcollab setup
#          - Reads manifest file to determine what to remove
#          - Provides interactive confirmation for safety
#          - Handles Docker image cleanup
#          - Preserves user-created content
#
# USAGE:   ./zzcollab-uninstall.sh [OPTIONS]
#
# AUTHOR:  Companion to zzcollab.sh
##############################################################################

set -euo pipefail

#=============================================================================
# CONFIGURATION
#=============================================================================

readonly MANIFEST_FILE=".zzcollab_manifest.json"
readonly MANIFEST_TXT=".zzcollab_manifest.txt"
readonly SCRIPT_NAME="$(basename "$0")"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

confirm() {
    local message="$1"
    local response
    
    # Ensure we're reading from the terminal, not stdin
    if [[ -t 0 ]]; then
        echo -e "${YELLOW}$message [y/N]: ${NC}"
        read -r response
    else
        echo -e "${YELLOW}$message [y/N]: ${NC}"
        read -r response </dev/tty
    fi
    [[ "$response" =~ ^[Yy]$ ]]
}

#=============================================================================
# MANIFEST READING FUNCTIONS
#=============================================================================

read_manifest_json() {
    if [[ ! -f "$MANIFEST_FILE" ]]; then
        return 1
    fi
    
    if ! command_exists jq; then
        log_error "jq is required to read JSON manifest but not installed"
        return 1
    fi
    
    # Validate JSON format
    if ! jq empty "$MANIFEST_FILE" 2>/dev/null; then
        log_error "Invalid JSON in manifest file"
        return 1
    fi
    
    return 0
}

read_manifest_txt() {
    if [[ ! -f "$MANIFEST_TXT" ]]; then
        return 1
    fi
    return 0
}

get_created_items() {
    local type="$1"
    
    if read_manifest_json; then
        case "$type" in
            directories) jq -r '.directories[]' "$MANIFEST_FILE" 2>/dev/null || true ;;
            files) jq -r '.files[]' "$MANIFEST_FILE" 2>/dev/null || true ;;
            symlinks) jq -r '.symlinks[].link' "$MANIFEST_FILE" 2>/dev/null || true ;;
            docker_image) jq -r '.docker_image // empty' "$MANIFEST_FILE" 2>/dev/null || true ;;
        esac
    elif read_manifest_txt; then
        case "$type" in
            directories) grep "^directory:" "$MANIFEST_TXT" | cut -d: -f2- || true ;;
            files) grep "^file:" "$MANIFEST_TXT" | cut -d: -f2- || true ;;
            symlinks) grep "^symlink:" "$MANIFEST_TXT" | cut -d: -f2- || true ;;
            docker_image) grep "^docker_image:" "$MANIFEST_TXT" | cut -d: -f2- || true ;;
        esac
    fi
}

#=============================================================================
# REMOVAL FUNCTIONS
#=============================================================================

remove_symlinks() {
    log_info "Checking for symbolic links to remove..."
    
    local symlinks
    symlinks=$(get_created_items "symlinks")
    
    if [[ -z "$symlinks" ]]; then
        log_info "No symbolic links found in manifest"
        return 0
    fi
    
    local count=0
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        
        if [[ -L "$link" ]]; then
            log_info "Removing symlink: $link"
            unlink "$link"
            ((count++))
        else
            log_warning "Symlink not found or not a link: $link"
        fi
    done <<< "$symlinks"
    
    log_success "Removed $count symbolic links"
}

remove_files() {
    log_info "Checking for files to remove..."
    
    local files
    files=$(get_created_items "files")
    
    # Add standard zzcollab files that may not be in manifest
    local standard_files="ZZCOLLAB_USER_GUIDE.md Dockerfile docker-compose.yml Dockerfile.teamcore Dockerfile.personal .Rprofile renv.lock Makefile .gitignore zzcollab.yaml config.yaml .Rbuildignore navigation_scripts.sh check_renv_for_commit.R .zshrc_docker dev.sh setup_renv.R LICENSE data/README.md"
    if [[ -n "$files" ]]; then
        files="$(echo -e "${files}\n${standard_files}")"
    else
        files="$standard_files"
    fi
    
    if [[ -z "$files" ]]; then
        log_info "No files found in manifest"
        return 0
    fi
    
    local count=0
    local skipped=0
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        if [[ -f "$file" ]]; then
            # Check if file has been modified by checking if it's different from template
            if should_remove_file "$file"; then
                log_info "Removing file: $file"
                rm "$file"
                ((count++))
            else
                log_warning "Skipping modified file: $file"
                ((skipped++))
            fi
        else
            log_warning "File not found: $file"
        fi
    done <<< "$files"
    
    log_success "Removed $count files"
    [[ $skipped -gt 0 ]] && log_warning "Skipped $skipped modified files"
}

should_remove_file() {
    local file="$1"
    
    # Always confirm removal of certain important files
    case "$file" in
        DESCRIPTION|NAMESPACE|*.Rproj|Makefile|Dockerfile*|docker-compose.yml|ZZCOLLAB_USER_GUIDE.md|.Rprofile|renv.lock|*.yaml)
            confirm "Remove $file (may contain custom changes)?"
            return $?
            ;;
        *)
            return 0
            ;;
    esac
}

remove_directories() {
    log_info "Checking for directories to remove..."
    
    local directories
    directories=$(get_created_items "directories")
    
    if [[ -z "$directories" ]]; then
        log_info "No directories found in manifest"
        return 0
    fi
    
    # Sort directories in reverse order (deepest first)
    local sorted_dirs
    sorted_dirs=$(echo "$directories" | sort -r)
    
    local count=0
    local skipped=0
    
    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        
        if [[ -d "$dir" ]]; then
            if is_directory_empty "$dir"; then
                log_info "Removing empty directory: $dir"
                rmdir "$dir"
                ((count++))
            else
                if confirm "Directory $dir contains files. Remove anyway?"; then
                    log_info "Removing directory and contents: $dir"
                    rm -rf "$dir"
                    ((count++))
                else
                    log_warning "Skipping non-empty directory: $dir"
                    ((skipped++))
                fi
            fi
        else
            log_warning "Directory not found: $dir"
        fi
    done <<< "$sorted_dirs"
    
    log_success "Removed $count directories"
    [[ $skipped -gt 0 ]] && log_warning "Skipped $skipped directories with content"
}

is_directory_empty() {
    local dir="$1"
    [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]
}

remove_renv_directory() {
    log_info "Checking for renv directory..."
    
    if [[ -d "renv" ]]; then
        if confirm "Remove renv directory (contains R package cache)?"; then
            log_info "Removing renv directory and cache..."
            rm -rf renv
            log_success "Removed renv directory"
        else
            log_info "Keeping renv directory"
        fi
    else
        log_info "No renv directory found"
    fi
}

remove_docker_images() {
    log_info "Checking for Docker images to remove..."
    
    # Check manifest first
    local manifest_image
    manifest_image=$(get_created_items "docker_image")
    
    if ! command_exists docker; then
        log_warning "Docker not available, skipping image removal"
        return 0
    fi
    
    # Look for common zzcollab Docker images
    local project_name
    if [[ -f "DESCRIPTION" ]]; then
        project_name=$(grep "^Package:" DESCRIPTION 2>/dev/null | cut -d: -f2 | tr -d ' ')
    fi
    
    local images_to_check=()
    [[ -n "$manifest_image" ]] && images_to_check+=("$manifest_image")
    [[ -n "$project_name" ]] && images_to_check+=("$project_name" "${project_name}:latest")
    
    # Also check for team images if we can determine team name
    if [[ -f "zzcollab.yaml" ]] || [[ -f "config.yaml" ]]; then
        local team_name=$(grep -E "team_name|team-name" *.yaml 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' "'"'" || true)
        if [[ -n "$team_name" && -n "$project_name" ]]; then
            images_to_check+=("${team_name}/${project_name}core-shell:latest")
            images_to_check+=("${team_name}/${project_name}core-rstudio:latest") 
            images_to_check+=("${team_name}/${project_name}core-verse:latest")
        fi
    fi
    
    local removed_count=0
    for image in "${images_to_check[@]}"; do
        [[ -z "$image" ]] && continue
        
        if docker image inspect "$image" >/dev/null 2>&1; then
            if confirm "Remove Docker image '$image'?"; then
                log_info "Removing Docker image: $image"
                if docker rmi "$image" 2>/dev/null; then
                    ((removed_count++))
                else
                    log_warning "Failed to remove Docker image: $image"
                fi
            else
                log_info "Keeping Docker image: $image"
            fi
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        log_success "Removed $removed_count Docker images"
    else
        log_info "No Docker images removed"
    fi
}

remove_manifest() {
    local removed=0
    
    if [[ -f "$MANIFEST_FILE" ]]; then
        log_info "Removing manifest file: $MANIFEST_FILE"
        if rm "$MANIFEST_FILE" 2>/dev/null; then
            ((removed++))
        else
            log_warning "Failed to remove manifest file: $MANIFEST_FILE"
        fi
    fi
    
    if [[ -f "$MANIFEST_TXT" ]]; then
        log_info "Removing manifest file: $MANIFEST_TXT"
        if rm "$MANIFEST_TXT" 2>/dev/null; then
            ((removed++))
        else
            log_warning "Failed to remove manifest file: $MANIFEST_TXT"
        fi
    fi
    
    if [[ $removed -gt 0 ]]; then
        log_success "Removed $removed manifest file(s)"
    else
        log_info "No manifest files found to remove"
    fi
}

#=============================================================================
# MAIN FUNCTIONS
#=============================================================================

show_help() {
    cat << EOF
$SCRIPT_NAME - Uninstall zzcollab-created files and directories

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    --dry-run           Show what would be removed without actually removing
    --force             Skip confirmation prompts (dangerous!)
    --keep-docker       Don't remove Docker image
    --keep-files        Only remove empty directories and symlinks
    --help, -h          Show this help message

EXAMPLES:
    $SCRIPT_NAME                    # Interactive uninstall
    $SCRIPT_NAME --dry-run          # See what would be removed
    $SCRIPT_NAME --force            # Uninstall without prompts
    $SCRIPT_NAME --keep-docker      # Keep Docker image

DESCRIPTION:
    This script removes files and directories created by zzcollab. It checks
    both manifest files and common zzcollab-generated files.
    
    It will:
    - Remove symbolic links first
    - Remove zzcollab files (Dockerfile, docker-compose.yml, .Rprofile, renv.lock, etc.)
    - Remove directories (empty ones first, then ask about non-empty)
    - Remove renv directory and package cache
    - Remove Docker images (project and team images)
    - Remove the manifest file itself
    
    Safety features:
    - Confirms before removing non-empty directories
    - Confirms before removing potentially customized files
    - Detects and removes team Docker images automatically
    - Can run in dry-run mode to preview changes

EOF
}

show_summary() {
    log_info "=== ZZCOLLAB UNINSTALL SUMMARY ==="
    
    if ! read_manifest_json && ! read_manifest_txt; then
        log_error "No manifest file found!"
        log_error "Cannot determine what files were created by zzcollab"
        log_error "Manifest files: $MANIFEST_FILE or $MANIFEST_TXT"
        return 1
    fi
    
    local pkg_name
    if read_manifest_json; then
        pkg_name=$(jq -r '.package_name // "unknown"' "$MANIFEST_FILE")
        log_info "Package: $pkg_name"
        log_info "Created: $(jq -r '.created_at // "unknown"' "$MANIFEST_FILE")"
    fi
    
    local dirs files symlinks docker_image
    dirs=$(get_created_items "directories" | wc -l)
    files=$(get_created_items "files" | wc -l)
    symlinks=$(get_created_items "symlinks" | wc -l)
    docker_image=$(get_created_items "docker_image")
    
    log_info "Items to remove:"
    log_info "  - Directories: $dirs"
    log_info "  - Files: $files" 
    log_info "  - Symlinks: $symlinks"
    [[ -n "$docker_image" ]] && log_info "  - Docker image: $docker_image"
    
    echo
}

main() {
    local dry_run=false
    local force=false
    local keep_docker=false
    local keep_files=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --keep-docker)
                keep_docker=true
                shift
                ;;
            --keep-files)
                keep_files=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_error "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Override confirm function if force mode
    if [[ "$force" == true ]]; then
        confirm() { return 0; }
    fi
    
    # Show summary
    show_summary || exit 1
    
    if [[ "$dry_run" == true ]]; then
        log_info "DRY RUN MODE - No files will be removed"
        log_info "Items that would be removed:"
        
        echo "Symlinks:"
        get_created_items "symlinks" | sed 's/^/  /'
        
        echo "Files:"
        (get_created_items "files"; echo -e "ZZCOLLAB_USER_GUIDE.md\nDockerfile\ndocker-compose.yml\nDockerfile.teamcore\nDockerfile.personal\n.Rprofile\nrenv.lock\nMakefile\n.gitignore\nzzcollab.yaml\nconfig.yaml\n.Rbuildignore\nnavigation_scripts.sh\ncheck_renv_for_commit.R\n.zshrc_docker\ndev.sh\nsetup_renv.R\nLICENSE\ndata/README.md") | sort -u | sed 's/^/  /'
        
        echo "Directories:"
        (get_created_items "directories"; [[ -d "renv" ]] && echo "renv"; [[ -d "analysis" ]] && echo "analysis"; [[ -d "tests" ]] && echo "tests"; [[ -d "scripts" ]] && echo "scripts"; [[ -d "R" ]] && echo "R"; [[ -d "data" ]] && echo "data"; [[ -d "figures" ]] && echo "figures"; [[ -d "output" ]] && echo "output"; [[ -d ".github" ]] && echo ".github"; [[ -d "inst" ]] && echo "inst"; [[ -d "man" ]] && echo "man"; [[ -d "vignettes" ]] && echo "vignettes") | sort -ru | sed 's/^/  /'
        
        echo "Docker images:"
        local project_name team_name
        [[ -f "DESCRIPTION" ]] && project_name=$(grep "^Package:" DESCRIPTION 2>/dev/null | cut -d: -f2 | tr -d ' ')
        if [[ -f "zzcollab.yaml" ]] || [[ -f "config.yaml" ]]; then
            team_name=$(grep -E "team_name|team-name" *.yaml 2>/dev/null | head -1 | cut -d: -f2 | tr -d ' "'"'" || true)
        fi
        
        local docker_image
        docker_image=$(get_created_items "docker_image")
        [[ -n "$docker_image" ]] && echo "  $docker_image"
        [[ -n "$project_name" ]] && echo "  $project_name:latest"
        if [[ -n "$team_name" && -n "$project_name" ]]; then
            echo "  ${team_name}/${project_name}core-shell:latest"
            echo "  ${team_name}/${project_name}core-rstudio:latest"
            echo "  ${team_name}/${project_name}core-verse:latest"
        fi
        
        exit 0
    fi
    
    # Confirm before proceeding
    if ! confirm "Proceed with uninstall?"; then
        log_info "Uninstall cancelled"
        exit 0
    fi
    
    # Perform removal in safe order
    log_info "Starting zzcollab uninstall..."
    
    remove_symlinks
    
    if [[ "$keep_files" == false ]]; then
        remove_files
    fi
    
    remove_directories
    
    # Remove renv directory
    remove_renv_directory
    
    if [[ "$keep_docker" == false ]]; then
        remove_docker_images
    fi
    
    remove_manifest
    
    log_success "Uninstall completed!"
    log_info "Some files may have been preserved if they contained modifications"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi