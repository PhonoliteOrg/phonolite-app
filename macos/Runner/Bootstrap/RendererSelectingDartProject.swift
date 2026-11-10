import Darwin
import FlutterMacOS

/// Flutter project that selects the renderer for the host Mac before the engine launches.
///
/// Impeller rasterized Phonolite frames at 57–75 ms on an Intel Mac where Skia took under 10 ms, so Intel hosts use
/// Skia. Apple Silicon keeps Impeller, including when the Intel slice runs under Rosetta. An explicit
/// `FLTEnableImpeller` Info.plist value still takes precedence.
final class RendererSelectingDartProject: FlutterDartProject {
  static let impellerInfoKey = "FLTEnableImpeller"

  private let impellerEnabled: Bool

  init(
    infoValue: Any? = Bundle.main.object(forInfoDictionaryKey: impellerInfoKey),
    hostIsAppleSilicon: Bool = RendererSelectingDartProject.hostIsAppleSilicon()
  ) {
    impellerEnabled = Self.impellerEnabled(infoValue: infoValue, hostIsAppleSilicon: hostIsAppleSilicon)
    super.init(precompiledDartBundle: nil)
  }

  /// Overrides the engine's internal `-[FlutterDartProject enableImpeller]`, which otherwise reads the same
  /// Info.plist key and defaults to Impeller. If a future engine stops consulting it, every Mac falls back to Impeller.
  @objc var enableImpeller: Bool { impellerEnabled }

  static func impellerEnabled(infoValue: Any?, hostIsAppleSilicon: Bool) -> Bool {
    if let explicit = infoValue as? NSNumber { return explicit.boolValue }

    return hostIsAppleSilicon
  }

  /// `hw.optional.arm64` reports the hardware, not the running slice, so Rosetta processes still see Apple Silicon.
  static func hostIsAppleSilicon() -> Bool {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size

    return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
  }
}
