Pod::Spec.new do |s|
  s.name = 'phonolite_opus'
  s.version = '0.0.1'
  s.summary = 'Opus decoder FFI bindings for Phonolite.'
  s.description = 'Native Opus decoder used by the Phonolite Flutter client.'
  s.homepage = 'https://example.invalid'
  s.license = { :type => 'MIT' }
  s.author = { 'Phonolite' => 'dev@phonolite' }
  s.source = { :path => '.' }
  s.platform = :osx, '10.13'

  opus_root = 'third_party/opus'

  s.source_files = [
    'src/*.{c,h}',
    "#{opus_root}/celt/**/*.{c,h}",
    "#{opus_root}/silk/**/*.{c,h}",
    "#{opus_root}/src/**/*.{c,h}",
    "#{opus_root}/include/**/*.h"
  ]

  s.exclude_files = [
    "#{opus_root}/celt/arm/**/*",
    "#{opus_root}/dnn/**/*",
    "#{opus_root}/doc/**/*",
    "#{opus_root}/docs/**/*",
    "#{opus_root}/test/**/*",
    "#{opus_root}/tests/**/*",
    "#{opus_root}/examples/**/*",
    "#{opus_root}/apps/**/*",
    "#{opus_root}/tools/**/*",
    "#{opus_root}/dump_modes/**/*",
    "#{opus_root}/cmake/**/*",
    "#{opus_root}/training/**/*",
    "#{opus_root}/x86/**/*"
  ]

  header_paths = [
    '$(PODS_TARGET_SRCROOT)/third_party/opus/include',
    '$(PODS_TARGET_SRCROOT)/third_party/opus/celt',
    '$(PODS_TARGET_SRCROOT)/third_party/opus/silk',
    '$(PODS_TARGET_SRCROOT)/third_party/opus/silk/float',
    '$(PODS_TARGET_SRCROOT)/src'
  ]

  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => header_paths.map { |p| '"' + p + '"' }.join(' '),
    'CLANG_C_STANDARD' => 'c99',
    'OTHER_CFLAGS' => '-DOPUS_BUILD -DHAVE_LRINTF -DHAVE_LRINT -DUSE_ALLOCA -std=c99'
  }
  s.compiler_flags = '-DOPUS_BUILD -DHAVE_LRINTF -DHAVE_LRINT -DUSE_ALLOCA -std=c99'
end
