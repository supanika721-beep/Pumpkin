# PumpkinMC Android Build Guide

## 🎯 Overview

This guide explains how to automatically build PumpkinMC for Android using GitHub Actions. This workflow:

- ✅ Builds binaries for **ARM64** (64-bit, recommended for most phones)
- ✅ Builds binaries for **ARM32** (32-bit, for older devices)
- ✅ Patches the code for Android/Bionic compatibility
- ✅ Optimizes binaries (strips debug symbols)
- ✅ Uploads artifacts automatically

## 📋 What This Workflow Does

### 1. **Bionic Compatibility Patches**

The workflow automatically applies patches to make PumpkinMC work with Android's Bionic libc:

- Creates an `android` module for Android-specific configuration
- Disables TTY/terminal input (not available on Android)
- Fixes WASI compile errors
- Sets Android-specific file paths

### 2. **Cross-Compilation Setup**

- Installs Android NDK r27b
- Sets up Rust targets for ARM64 and ARM32
- Configures Cargo for cross-compilation

### 3. **Optimized Build**

- Compiles in release mode (optimized)
- Strips debug symbols to reduce binary size
- Generates SHA256 checksums for verification

## 🚀 How to Use

### Step 1: Create the Workflow File

Create a new file in your repository: `.github/workflows/build-android.yml`

Copy the following YAML content:

```yaml
name: Build PumpkinMC for Android

on:
  push:
    branches: [ main, master, dev ]
  pull_request:
    branches: [ main, master, dev ]
  workflow_dispatch:

env:
  CARGO_TERM_COLOR: always
  RUST_BACKTRACE: 1

jobs:
  build-arm64:
    name: Build PumpkinMC Android Binary (ARM64)
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          toolchain: stable
          targets: aarch64-linux-android

      - name: Setup Android NDK
        uses: nttld/setup-ndk@v1
        with:
          ndk-version: r27b
          add-to-path: true

      - name: Configure Cargo for Android
        run: |
          mkdir -p ~/.cargo
          cat >> ~/.cargo/config.toml << 'EOF'
          [target.aarch64-linux-android]
          linker = "${{ env.ANDROID_NDK }}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android-clang"
          ar = "${{ env.ANDROID_NDK }}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android-ar"
          
          [build]
          target-dir = "target"
          EOF

      - name: Create Android module
        run: |
          mkdir -p pumpkin/src/android
          cat > pumpkin/src/android/mod.rs << 'EOF'
          //! Android-specific configuration and utilities
          
          #[cfg(target_os = "android")]
          pub const FORCE_DISABLE_TTY: bool = true;
          
          pub fn get_config_dir() -> std::path::PathBuf {
              std::env::var("PUMPKIN_CONFIG_DIR")
                  .unwrap_or_else(|_| "/data/data/com.example.pumpkinmc/files/config".to_string())
                  .into()
          }
          
          pub fn get_data_dir() -> std::path::PathBuf {
              std::env::var("PUMPKIN_DATA_DIR")
                  .unwrap_or_else(|_| "/data/data/com.example.pumpkinmc/files".to_string())
                  .into()
          }
          EOF

      - name: Add Android module to lib.rs
        run: |
          sed -i '1i #[cfg(target_os = "android")]\npub mod android;' pumpkin/src/lib.rs

      - name: Fix WASI compile error for Android
        run: |
          sed -i 's/#\[cfg(target_os = "wasi")\]/#[cfg(all(target_os = "wasi", not(target_os = "android")))]/g' pumpkin/src/main.rs

      - name: Disable TTY mode on Android
        run: |
          python3 << 'PYEOF'
          import re
          
          with open('pumpkin/src/lib.rs', 'r') as f:
              content = f.read()
          
          old_pattern = r'(\s+)\) = if advanced_config\.commands\.use_tty && stdin\(\)\.is_terminal\(\) \{'
          new_text = r'''\1) = if cfg!(target_os = "android") {
            \1    // Android doesn't have a real TTY, use simple stdout
            \1    (Box::new(std::io::stdout()), None)
            \1} else if advanced_config.commands.use_tty && stdin().is_terminal() {
            \1    // Standard TTY mode for other platforms'''
          
          content = re.sub(old_pattern, new_text, content)
          
          with open('pumpkin/src/lib.rs', 'w') as f:
              f.write(content)
          PYEOF

      - name: Build PumpkinMC for Android ARM64
        run: |
          export CC_aarch64_linux_android="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang"
          export AR_aarch64_linux_android="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android-ar"
          export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${CC_aarch64_linux_android}"
          
          cargo build --release --target aarch64-linux-android --verbose

      - name: Strip debug symbols
        run: |
          ${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android-strip target/aarch64-linux-android/release/pumpkin

      - name: Create release artifacts
        run: |
          mkdir -p release_artifacts
          cp target/aarch64-linux-android/release/pumpkin release_artifacts/pumpkin-arm64
          cd release_artifacts
          sha256sum pumpkin-arm64 > SHA256SUMS

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: pumpkin-android-arm64
          path: release_artifacts/
          retention-days: 30

      - name: Build Summary
        run: |
          echo "## 🎯 Android ARM64 Build Summary" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Property | Value |" >> $GITHUB_STEP_SUMMARY
          echo "|----------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| **Target** | aarch64-linux-android |" >> $GITHUB_STEP_SUMMARY
          echo "| **NDK Version** | r27b |" >> $GITHUB_STEP_SUMMARY
          echo "| **File Size** | $(du -h release_artifacts/pumpkin-arm64 | cut -f1) |" >> $GITHUB_STEP_SUMMARY

  build-arm32:
    name: Build PumpkinMC Android Binary (ARM32)
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install Rust toolchain
        uses: dtolnay/rust-toolchain@stable
        with:
          toolchain: stable
          targets: armv7-linux-androideabi

      - name: Setup Android NDK
        uses: nttld/setup-ndk@v1
        with:
          ndk-version: r27b
          add-to-path: true

      - name: Configure Cargo for Android ARM32
        run: |
          mkdir -p ~/.cargo
          cat >> ~/.cargo/config.toml << 'EOF'
          [target.armv7-linux-androideabi]
          linker = "${{ env.ANDROID_NDK }}/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi-clang"
          ar = "${{ env.ANDROID_NDK }}/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi-ar"
          
          [build]
          target-dir = "target"
          EOF

      - name: Create Android module
        run: |
          mkdir -p pumpkin/src/android
          cat > pumpkin/src/android/mod.rs << 'EOF'
          //! Android-specific configuration and utilities
          
          #[cfg(target_os = "android")]
          pub const FORCE_DISABLE_TTY: bool = true;
          
          pub fn get_config_dir() -> std::path::PathBuf {
              std::env::var("PUMPKIN_CONFIG_DIR")
                  .unwrap_or_else(|_| "/data/data/com.example.pumpkinmc/files/config".to_string())
                  .into()
          }
          
          pub fn get_data_dir() -> std::path::PathBuf {
              std::env::var("PUMPKIN_DATA_DIR")
                  .unwrap_or_else(|_| "/data/data/com.example.pumpkinmc/files".to_string())
                  .into()
          }
          EOF

      - name: Add Android module to lib.rs
        run: |
          sed -i '1i #[cfg(target_os = "android")]\npub mod android;' pumpkin/src/lib.rs

      - name: Fix WASI compile error for Android
        run: |
          sed -i 's/#\[cfg(target_os = "wasi")\]/#[cfg(all(target_os = "wasi", not(target_os = "android")))]/g' pumpkin/src/main.rs

      - name: Disable TTY mode on Android
        run: |
          python3 << 'PYEOF'
          import re
          
          with open('pumpkin/src/lib.rs', 'r') as f:
              content = f.read()
          
          old_pattern = r'(\s+)\) = if advanced_config\.commands\.use_tty && stdin\(\)\.is_terminal\(\) \{'
          new_text = r'''\1) = if cfg!(target_os = "android") {
            \1    // Android doesn't have a real TTY, use simple stdout
            \1    (Box::new(std::io::stdout()), None)
            \1} else if advanced_config.commands.use_tty && stdin().is_terminal() {
            \1    // Standard TTY mode for other platforms'''
          
          content = re.sub(old_pattern, new_text, content)
          
          with open('pumpkin/src/lib.rs', 'w') as f:
              f.write(content)
          PYEOF

      - name: Build PumpkinMC for Android ARM32
        run: |
          export CC_armv7_linux_androideabi="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi21-clang"
          export AR_armv7_linux_androideabi="${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi-ar"
          export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="${CC_armv7_linux_androideabi}"
          
          cargo build --release --target armv7-linux-androideabi --verbose

      - name: Strip and prepare ARM32
        run: |
          ${ANDROID_NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/arm-linux-androideabi-strip target/armv7-linux-androideabi/release/pumpkin
          
          mkdir -p release_artifacts_arm32
          cp target/armv7-linux-androideabi/release/pumpkin release_artifacts_arm32/pumpkin-arm32
          cd release_artifacts_arm32
          sha256sum pumpkin-arm32 > SHA256SUMS

      - name: Upload ARM32 artifacts
        uses: actions/upload-artifact@v4
        with:
          name: pumpkin-android-arm32
          path: release_artifacts_arm32/
          retention-days: 30

      - name: Build Summary
        run: |
          echo "## 🎯 Android ARM32 Build Summary" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Property | Value |" >> $GITHUB_STEP_SUMMARY
          echo "|----------|-------|" >> $GITHUB_STEP_SUMMARY
          echo "| **Target** | armv7-linux-androideabi |" >> $GITHUB_STEP_SUMMARY
          echo "| **NDK Version** | r27b |" >> $GITHUB_STEP_SUMMARY
          echo "| **File Size** | $(du -h release_artifacts_arm32/pumpkin-arm32 | cut -f1) |" >> $GITHUB_STEP_SUMMARY
```

### Step 2: Push to Your Repository

1. Commit the file to your `android-build-workflow` branch
2. Push to GitHub
3. The workflow will automatically trigger on push

### Step 3: Download Build Artifacts

1. Go to **Actions** tab in your GitHub repository
2. Click on the **Build PumpkinMC for Android** workflow
3. Find the completed run
4. Download the artifacts:
   - `pumpkin-android-arm64` (for modern phones)
   - `pumpkin-android-arm32` (for older phones)

## 📦 Build Artifacts

After the build completes, you'll get:

```
pumpkin-arm64          # ARM64 binary (recommended)
pumpkin-arm32          # ARM32 binary (older devices)
SHA256SUMS             # Checksums for verification
```

### File Sizes (Approximate)
- **pumpkin-arm64**: 15-25 MB (after stripping)
- **pumpkin-arm32**: 12-20 MB (after stripping)

## 🔧 Using the Binary with Your Android Wrapper

Your `PumpkinMCGui` app can:

1. Download the binary from GitHub Actions
2. Extract it to the app's files directory
3. Set environment variables:
   ```kotlin
   val env = mapOf(
       "PUMPKIN_CONFIG_DIR" to "${getFilesDir()}/config",
       "PUMPKIN_DATA_DIR" to "${getFilesDir()}/data"
   )
   ```
4. Execute the binary:
   ```kotlin
   val process = ProcessBuilder("${getFilesDir()}/pumpkin-arm64")
       .apply { environment().putAll(env) }
       .redirectOutput(File("/dev/null"))
       .redirectError(File("/dev/null"))
       .start()
   ```

## 🐛 Troubleshooting

### Build Fails with "permission denied"
- Make sure `.github/workflows/build-android.yml` is properly formatted
- Check GitHub Actions logs for detailed error messages

### Large Binary Size
- The workflow already strips debug symbols
- For production, consider further optimization with `strip` or `cargo-bloat`

### Build Timeout
- PumpkinMC is a large project; builds can take 30-60 minutes
- GitHub Actions provides up to 6 hours per job

## 🔍 Workflow Triggers

The workflow automatically builds when:
- ✅ You push to `main`, `master`, or `dev` branches
- ✅ You create a pull request targeting these branches
- ✅ You manually trigger it via "Run workflow" button

## 📝 Customization

### To add more targets (e.g., x86_64)

Add another job section similar to `build-arm64`:

```yaml
  build-x86_64:
    name: Build PumpkinMC Android Binary (x86_64)
    runs-on: ubuntu-latest
    steps:
      # ... (similar steps, change target to x86_64-linux-android)
```

### To change NDK version

Modify this line in the workflow:
```yaml
ndk-version: r27b  # Change to your desired version
```

## 📚 Resources

- [Android NDK Documentation](https://developer.android.com/ndk)
- [Rust Android Targets](https://github.com/rust-lang/rust-platform-support)
- [PumpkinMC GitHub](https://github.com/Pumpkin-MC/Pumpkin)

## ✨ Next Steps

1. ✅ Create `.github/workflows/build-android.yml` in your fork
2. ✅ Push to trigger the first build
3. ✅ Download and test the binary on an Android device
4. ✅ Integrate into your `PumpkinMCGui` app
