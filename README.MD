# Ruby Gem Docker Builder

A cross-platform script that builds Ruby gems with C extensions using Docker, creating precompiled versions compatible with modern systems.

## Problem

Many legacy Ruby gems with C extensions fail to compile on modern macOS due to:
- Compiler compatibility issues
- Missing dependencies  
- Architecture mismatches (ARM64 vs x86_64)
- Outdated build tools

## Solution

This script uses Docker with Ruby 2.5 to:
1. Compile gems in a controlled Linux environment
2. Create precompiled versions that bypass compilation
3. Make gems work with both `gem install` and `bundle install`
4. Support any Ruby gem with C extensions

## Requirements

- Docker (with ARM64 support on Apple Silicon)
- Ruby installed locally
- Bash shell

## Usage

```bash
# Make executable
chmod +x build_ruby_gem.sh

# Build any gem with C extensions
./build_ruby_gem.sh <gem_name> <gem_version>
```

## Examples

```bash
# Legacy gems that often fail on modern macOS
./build_ruby_gem.sh semacode-ruby19 0.7.4
./build_ruby_gem.sh nokogiri 1.13.10
./build_ruby_gem.sh nio4r 2.3.1
./build_ruby_gem.sh mysql2 0.5.4
./build_ruby_gem.sh pg 1.4.5
./build_ruby_gem.sh sqlite3 1.6.0
```

## What It Does

1. **Downloads** the gem source in Docker
2. **Compiles** C extensions with compatible toolchain
3. **Removes** extension source files (prevents recompilation)
4. **Packages** precompiled gem with `.so` files
5. **Installs** locally for immediate use

## Output

- Gem installed and ready to `require`
- Works with Bundler (no compilation attempts)
- Precompiled gem saved in `./precompiled/`

## Common Use Cases

- Legacy Rails applications with old gem dependencies
- macOS development with problematic C extensions  
- CI/CD pipelines needing reliable gem builds
- Apple Silicon compatibility for x86_64 gems

---

**Note**: This creates architecture-specific builds. Run on the target platform or use multi-arch Docker builds for cross-platform compatibility. 
