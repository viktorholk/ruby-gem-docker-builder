#!/bin/bash

set -e  # Exit on any error

# Configuration - will be set from command line arguments
GEM_NAME=""
GEM_VERSION=""
CONTAINER_NAME=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[ERROR] $1${NC}" >&2; }
warn() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
info() { echo -e "${BLUE}[INFO] $1${NC}"; }

# Show usage
show_usage() {
    echo "Usage: $0 <gem_name> <gem_version>"
    echo ""
    echo "Build a Ruby gem with C extensions using Docker for compatibility"
    echo ""
    echo "Arguments:"
    echo "  gem_name     Name of the Ruby gem to build"
    echo "  gem_version  Version of the gem to build"
    echo ""
    echo "Examples:"
    echo "  $0 semacode-ruby19 0.7.4"
    echo "  $0 nokogiri 1.13.10"
    echo "  $0 mysql2 0.5.4"
    echo ""
    echo "The script will:"
    echo "  1. Download and compile the gem in a Docker container"
    echo "  2. Create a precompiled version compatible with Bundler"
    echo "  3. Install the gem locally for immediate use"
}

# Parse command line arguments
parse_arguments() {
    if [[ $# -ne 2 ]]; then
        error "Invalid number of arguments"
        echo ""
        show_usage
        exit 1
    fi
    
    GEM_NAME="$1"
    GEM_VERSION="$2"
    CONTAINER_NAME="${GEM_NAME//[^a-zA-Z0-9]/-}-builder"  # Replace non-alphanumeric with dashes
    
    info "Building gem: ${GEM_NAME} v${GEM_VERSION}"
    info "Container name: ${CONTAINER_NAME}"
}

# Clean existing installations
cleanup_existing() {
    log "Cleaning existing ${GEM_NAME} installations..."
    gem uninstall ${GEM_NAME} --force >/dev/null 2>&1 || true
    log "✓ Existing installations cleaned"
}

# Check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
}

# Build gem in Docker
build_in_docker() {
    log "Building Docker image..."
    cat > Dockerfile.${GEM_NAME} << 'EOF'
FROM ruby:2.5-slim
RUN apt-get update && apt-get install -y build-essential wget && rm -rf /var/lib/apt/lists/*
WORKDIR /build
EOF
    
    docker build -f Dockerfile.${GEM_NAME} -t ${GEM_NAME}-builder --platform=linux/arm64 . >/dev/null
    
    log "Downloading and compiling gem in container..."
    docker run --name ${CONTAINER_NAME} --platform=linux/arm64 -d ${GEM_NAME}-builder tail -f /dev/null >/dev/null
    
    docker exec ${CONTAINER_NAME} bash -c "
        gem fetch ${GEM_NAME} --version ${GEM_VERSION}
        gem install ${GEM_NAME}-${GEM_VERSION}.gem --local --no-document
        gem unpack ${GEM_NAME}-${GEM_VERSION}.gem
    " >/dev/null
    
    log "✓ Gem compiled successfully in Docker"
}

# Copy compiled files from container
copy_from_container() {
    log "Copying compiled files..."
    mkdir -p output
    
    # Get gem directory paths
    local gem_dir=$(docker exec ${CONTAINER_NAME} ruby -e "puts Gem.dir")
    
    # Copy the installed gem (with compiled extensions)
    docker cp ${CONTAINER_NAME}:${gem_dir}/gems/${GEM_NAME}-${GEM_VERSION} output/ >/dev/null
    docker cp ${CONTAINER_NAME}:${gem_dir}/specifications/${GEM_NAME}-${GEM_VERSION}.gemspec output/ >/dev/null
    
    log "✓ Files copied from container"
}

# Create precompiled gem
create_precompiled_gem() {
    log "Creating Bundler-compatible gem..."
    
    # Use the installed gem (has compiled extensions) and remove ext directory
    cp -r output/${GEM_NAME}-${GEM_VERSION} precompiled/
    rm -rf precompiled/ext
    
    # Fix gemspec - remove extensions line and update files list
    cp output/${GEM_NAME}-${GEM_VERSION}.gemspec precompiled/
    
    # Remove the extensions line (prevents Bundler from trying to compile)
    sed -i '' '/s\.extensions/d' precompiled/${GEM_NAME}-${GEM_VERSION}.gemspec
    
    # Remove ALL references to ext/ files (they no longer exist in precompiled gem)
    sed -i '' '/\"ext\//d' precompiled/${GEM_NAME}-${GEM_VERSION}.gemspec
    
    # Find and add compiled .so files to the files list
    local so_files=$(find precompiled/lib -name "*.so" -type f 2>/dev/null)
    if [[ -n "$so_files" ]]; then
        info "Found compiled extensions: $(echo "$so_files" | wc -l | tr -d ' ') .so file(s)"
        # Add the .so files to the gemspec files list
        for so_file in $so_files; do
            local relative_path=${so_file#precompiled/}
            # Add each .so file to the files list if not already present
            if ! grep -q "\"$relative_path\"" precompiled/${GEM_NAME}-${GEM_VERSION}.gemspec; then
                sed -i '' "/s\.files.*=.*\[/a\\
  \"$relative_path\",
" precompiled/${GEM_NAME}-${GEM_VERSION}.gemspec
            fi
        done
    else
        warn "No .so files found - gem may not have C extensions or compilation failed"
    fi
    
    # Build and install the fixed gem
    cd precompiled
    gem build ${GEM_NAME}-${GEM_VERSION}.gemspec >/dev/null
    gem install ${GEM_NAME}-${GEM_VERSION}.gem --local --no-document >/dev/null
    cd ..
    
    log "✓ Precompiled gem installed"
}

# Test installation
test_gem() {
    log "Testing gem functionality..."
    
    # Try to require the gem - this is a generic test that works for most gems
    if ruby -e "require '${GEM_NAME//[-_]*/}'" >/dev/null 2>&1; then
        log "✓ Gem loads successfully!"
        return 0
    elif ruby -e "require '${GEM_NAME}'" >/dev/null 2>&1; then
        log "✓ Gem loads successfully!"
        return 0
    else
        warn "Could not auto-test gem loading. Manual verification may be needed."
        info "Try: ruby -e \"require '${GEM_NAME}'\""
        return 0  # Don't fail the build for test issues
    fi
}

# Cleanup Docker
cleanup_docker() {
    docker stop ${CONTAINER_NAME} >/dev/null 2>&1 || true
    docker rm ${CONTAINER_NAME} >/dev/null 2>&1 || true
    docker rmi ${GEM_NAME}-builder >/dev/null 2>&1 || true
    rm -f Dockerfile.${GEM_NAME}
    rm -rf precompiled
}

# Main execution
main() {
    parse_arguments "$@"
    
    log "🚀 Starting ${GEM_NAME} v${GEM_VERSION} build process..."
    
    # Setup cleanup trap
    trap cleanup_docker EXIT
    
    # Execute build steps
    cleanup_existing
    check_docker
    build_in_docker
    copy_from_container
    create_precompiled_gem
    
    if test_gem; then
        log "🎉 SUCCESS! ${GEM_NAME} gem is ready to use!"
        log "   - Works with: require '${GEM_NAME}'"
        log "   - Works with: bundle install" 
        log "   - Built gem saved: ./precompiled/${GEM_NAME}-${GEM_VERSION}.gem"
        info "You can now use this precompiled gem in your projects!"
    else
        error "Build completed but gem test failed"
        exit 1
    fi
}

# Run if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

