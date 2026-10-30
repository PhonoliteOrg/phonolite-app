use std::path::{Path, PathBuf};

fn main() {
    let opus_package = Path::new("../../../phonolite_opus");
    assert!(
        opus_package
            .join("third_party/opus/CMakeLists.txt")
            .is_file(),
        "The phonolite_opus package's bundled Opus sources are required"
    );
    println!("cargo:rerun-if-changed=opus/CMakeLists.txt");
    println!(
        "cargo:rerun-if-changed={}",
        opus_package.join("third_party/opus").display()
    );
    println!(
        "cargo:rerun-if-changed={}",
        opus_package.join("cmake").display()
    );

    let mut config = cmake::Config::new("opus");
    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
        // MSBuild's file tracker still has a 260-character path limit. Keep its
        // compiler probes under the Cargo target tree without the long crate
        // prefix and nested OUT_DIR/build path. Cargo's fingerprint isolates
        // profiles, target architectures and build-script configurations.
        let cargo_out = PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
        let fingerprint = cargo_out
            .parent()
            .and_then(Path::file_name)
            .and_then(|name| name.to_str())
            .and_then(|name| name.rsplit('-').next())
            .unwrap();
        config.out_dir(
            cargo_out
                .ancestors()
                .nth(4)
                .unwrap()
                .join("opus")
                .join(std::env::var("PROFILE").unwrap())
                .join(fingerprint),
        );
        if config.get_profile() == "Debug" {
            config.profile("RelWithDebInfo").cflag("/Z7").cflag("/Od");
        }
        let static_crt = std::env::var("CARGO_CFG_TARGET_FEATURE")
            .unwrap_or_default()
            .split(',')
            .any(|feature| feature == "crt-static");
        config
            .static_crt(static_crt)
            .env("MSBUILDDISABLENODEREUSE", "1")
            .define("OPUS_STATIC_RUNTIME", if static_crt { "ON" } else { "OFF" });
    }
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        configure_android(&mut config);
    }
    let destination = config
        .define("BUILD_SHARED_LIBS", "OFF")
        .define("OPUS_BUILD_SHARED_LIBRARY", "OFF")
        .define("BUILD_TESTING", "OFF")
        .define("OPUS_BUILD_TESTING", "OFF")
        .define("OPUS_BUILD_PROGRAMS", "OFF")
        .define("OPUS_FIXED_POINT", "OFF")
        .define("OPUS_INSTALL_PKG_CONFIG_MODULE", "OFF")
        .define("OPUS_INSTALL_CMAKE_CONFIG_MODULE", "OFF")
        .define("CMAKE_POSITION_INDEPENDENT_CODE", "ON")
        .define("CMAKE_INSTALL_LIBDIR", "lib")
        .build();
    println!(
        "cargo:rustc-link-search=native={}",
        destination.join("lib").display()
    );
    println!("cargo:rustc-link-lib=static=opus");
    if std::env::var("CARGO_CFG_TARGET_FAMILY").as_deref() == Ok("unix") {
        println!("cargo:rustc-link-lib=m");
    }
}

fn configure_android(config: &mut cmake::Config) {
    println!("cargo:rerun-if-env-changed=ANDROID_NDK_HOME");
    println!("cargo:rerun-if-env-changed=ANDROID_NDK_ROOT");
    println!("cargo:rerun-if-env-changed=CARGO_NDK_ANDROID_PLATFORM");
    let ndk = std::env::var_os("ANDROID_NDK_HOME")
        .or_else(|| std::env::var_os("ANDROID_NDK_ROOT"))
        .map(PathBuf::from)
        .expect("Set ANDROID_NDK_HOME to the NDK used by cargo ndk");
    let abi = match std::env::var("CARGO_CFG_TARGET_ARCH").as_deref() {
        Ok("arm") => "armeabi-v7a",
        Ok("aarch64") => "arm64-v8a",
        Ok("x86_64") => "x86_64",
        Ok("x86") => "x86",
        _ => panic!("unsupported Android architecture"),
    };
    config
        .generator("Ninja")
        .define(
            "CMAKE_TOOLCHAIN_FILE",
            ndk.join("build/cmake/android.toolchain.cmake"),
        )
        .define("ANDROID_ABI", abi)
        .define(
            "ANDROID_PLATFORM",
            format!(
                "android-{}",
                std::env::var("CARGO_NDK_ANDROID_PLATFORM").unwrap_or_else(|_| "21".into())
            ),
        );
}
