#!/bin/bash
# patch-android.sh
# Android compatibility patches for Pumpkin

set -euo pipefail

echo "=== Applying Android patches ==="

# ---------------------------------------------------
# CHECK ROOT
# ---------------------------------------------------

if [ ! -f "Cargo.toml" ]; then
  echo "ERROR: Jalankan script dari root repo Pumpkin."
  exit 1
fi

mkdir -p .patches-backup

# ---------------------------------------------------
# PATCH 1: RELEASE PROFILE
# ---------------------------------------------------

echo "[1] Menambahkan profile release-android..."

if grep -q '\[profile\.release-android\]' Cargo.toml; then
  echo "    release-android sudah ada, skip."
else
  cp Cargo.toml .patches-backup/Cargo.toml.bak

  cat >> Cargo.toml << 'EOF'

[profile.release-android]
inherits = "release"
opt-level = "s"
lto = "thin"
codegen-units = 1
panic = "abort"
strip = "symbols"
debug = 0
incremental = false
EOF

  echo "    Ditambahkan."
fi

# ---------------------------------------------------
# PATCH 2: LIBC ANDROID DEP
# ---------------------------------------------------

echo "[2] Memastikan libc tersedia untuk Android..."

if grep -q 'cfg(target_os = "android")' pumpkin/Cargo.toml 2>/dev/null; then
  echo "    Android dependency section sudah ada, skip."
else
  cp pumpkin/Cargo.toml .patches-backup/pumpkin_Cargo.toml.bak

  cat >> pumpkin/Cargo.toml << 'EOF'

[target.'cfg(target_os = "android")'.dependencies]
libc = "0.2"
EOF

  echo "    Ditambahkan."
fi

# ---------------------------------------------------
# PATCH 3: ANDROID COMPAT MODULE
# ---------------------------------------------------

echo "[3] Membuat android_compat.rs..."

COMPAT="pumpkin/src/android_compat.rs"

if [ -f "$COMPAT" ]; then
  echo "    File sudah ada, skip."
else
  cat > "$COMPAT" << 'EOF'
//! Android / Termux compatibility layer for Pumpkin.

#![allow(dead_code)]

use std::sync::atomic::{AtomicBool, Ordering};

static DONE: AtomicBool = AtomicBool::new(false);

/// Init Android compatibility settings.
/// Panggil sekali di awal main().
pub fn init() {
    if DONE.swap(true, Ordering::SeqCst) {
        return;
    }

    // Android stack default kecil.
    if std::env::var("RUST_MIN_STACK").is_err() {
        unsafe {
            std::env::set_var("RUST_MIN_STACK", "8388608");
        }
    }

    // Temp dir lebih aman untuk Termux.
    if std::env::var("TMPDIR").is_err() {
        if let Ok(prefix) = std::env::var("PREFIX") {
            unsafe {
                std::env::set_var("TMPDIR", format!("{}/tmp", prefix));
            }
        }
    }

    ignore_sigpipe();
}

#[cfg(target_os = "android")]
fn ignore_sigpipe() {
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_IGN);
    }
}

#[cfg(not(target_os = "android"))]
fn ignore_sigpipe() {}

pub fn temp_dir() -> std::path::PathBuf {
    if let Ok(tmp) = std::env::var("TMPDIR") {
        return std::path::PathBuf::from(tmp);
    }

    std::env::temp_dir()
}
EOF

  echo "    Dibuat: $COMPAT"
fi

# ---------------------------------------------------
# PATCH 4: PATCH MAIN.RS
# ---------------------------------------------------

echo "[4] Patch pumpkin/src/main.rs..."

MAIN_RS="pumpkin/src/main.rs"

if [ ! -f "$MAIN_RS" ]; then
  echo "    WARNING: main.rs tidak ditemukan, skip."
else
  cp "$MAIN_RS" ".patches-backup/main.rs.bak"

  if ! grep -q "mod android_compat;" "$MAIN_RS"; then
    sed -i '1i #[cfg(target_os = "android")]\nmod android_compat;\n' "$MAIN_RS"

    echo "    mod android_compat ditambahkan."
  else
    echo "    mod android_compat sudah ada."
  fi

  if ! grep -q "android_compat::init();" "$MAIN_RS"; then
    sed -i '/fn main/a\
\
    #[cfg(target_os = "android")]\
    android_compat::init();\
' "$MAIN_RS"

    echo "    android_compat::init() ditambahkan."
  else
    echo "    init() sudah ada."
  fi
fi

# ---------------------------------------------------
# PATCH 5: WASMTIME WARNING
# ---------------------------------------------------

echo "[5] Mengecek wasmtime..."

if grep -R "wasmtime" pumpkin/Cargo.toml >/dev/null 2>&1; then
  echo ""
  echo "    WARNING:"
  echo "    wasmtime ditemukan."
  echo "    wasmtime sering gagal di Android ARM."
  echo ""
  echo "    Pindahkan dependency menjadi:"
  echo ""
  echo "    [target.'cfg(not(target_os = \"android\"))'.dependencies]"
  echo "    wasmtime = { workspace = true }"
  echo "    wasmtime-wasi = { workspace = true }"
  echo ""
else
  echo "    wasmtime tidak ditemukan."
fi

# ---------------------------------------------------
# PATCH 6: VERIFY NDK
# ---------------------------------------------------

echo "[6] Verifikasi Android NDK..."

NDK="${NDK_PATH:-${ANDROID_NDK_HOME:-}}"

if [ -z "$NDK" ]; then
  echo "    WARNING: NDK_PATH / ANDROID_NDK_HOME tidak di-set."
else
  CLANG="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android28-clang"

  if [ -f "$CLANG" ]; then
    echo "    NDK OK:"
    "$CLANG" --version | head -1
  else
    echo "    ERROR: clang tidak ditemukan:"
    echo "    $CLANG"
    exit 1
  fi
fi

echo ""
echo "=== Android patches selesai ==="
