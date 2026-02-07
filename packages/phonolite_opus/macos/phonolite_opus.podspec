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

  opus_root = File.expand_path('../third_party/opus', __dir__)

  s.source_files = [
    File.join(__dir__, '..', 'src', '*.{c,h}'),
    File.join(opus_root, 'celt', '**', '*.{c,h}'),
    File.join(opus_root, 'silk', '**', '*.{c,h}'),
    File.join(opus_root, 'src', '**', '*.{c,h}'),
    File.join(opus_root, 'include', '**', '*.h')
  ]

  s.exclude_files = [
    File.join(opus_root, 'celt', 'arm', '**', '*'),
    File.join(opus_root, 'dnn', '**', '*'),
    File.join(opus_root, 'doc', '**', '*'),
    File.join(opus_root, 'docs', '**', '*'),
    File.join(opus_root, 'test', '**', '*'),
    File.join(opus_root, 'tests', '**', '*'),
    File.join(opus_root, 'examples', '**', '*'),
    File.join(opus_root, 'apps', '**', '*'),
    File.join(opus_root, 'tools', '**', '*'),
    File.join(opus_root, 'dump_modes', '**', '*'),
    File.join(opus_root, 'cmake', '**', '*'),
    File.join(opus_root, 'training', '**', '*'),
    File.join(opus_root, 'x86', '**', '*')
  ]

  header_paths = [
    File.join(opus_root, 'include'),
    File.join(opus_root, 'celt'),
    File.join(opus_root, 'silk'),
    File.join(opus_root, 'silk', 'float'),
    File.join(__dir__, '..', 'src')
  ]

  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => header_paths.map { |p| '"' + p + '"' }.join(' '),
    'CLANG_C_STANDARD' => 'c99',
    'OTHER_CFLAGS' => '-DOPUS_BUILD -DHAVE_LRINTF -DHAVE_LRINT -DUSE_ALLOCA -std=c99'
  }
  s.compiler_flags = '-DOPUS_BUILD -DHAVE_LRINTF -DHAVE_LRINT -DUSE_ALLOCA -std=c99'
end
