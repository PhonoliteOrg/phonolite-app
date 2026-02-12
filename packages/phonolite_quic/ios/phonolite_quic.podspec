Pod::Spec.new do |s|
  s.name = 'phonolite_quic'
  s.version = '0.1.0'
  s.summary = 'QUIC client FFI bindings for Phonolite.'
  s.description = 'Rust QUIC client used by the Phonolite Flutter app.'
  s.homepage = 'https://example.invalid'
  s.license = { :type => 'MIT' }
  s.author = { 'Phonolite' => 'dev@phonolite' }
  s.source = { :path => '.' }
  s.platform = :ios, '12.0'

  s.source_files = 'Classes/**/*.{m,h}'
  s.vendored_libraries = 'libphonolite_quic.a'

  s.script_phase = {
    :name => 'Build phonolite_quic',
    :script => 'bash "${PODS_TARGET_SRCROOT}/build_quic_static.sh"',
    :execution_position => :before_compile,
    :output_files => ['${PODS_TARGET_SRCROOT}/libphonolite_quic.a']
  }
end
