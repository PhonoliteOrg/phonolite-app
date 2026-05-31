Pod::Spec.new do |s|
  s.name = 'phonolite_local_audio'
  s.version = '0.1.0'
  s.summary = 'Local MP3/FLAC decoder FFI bindings for Phonolite.'
  s.description = 'Rust/Symphonia local audio decoder used by the Phonolite Flutter app.'
  s.homepage = 'https://example.invalid'
  s.license = { :type => 'MIT' }
  s.author = { 'Phonolite' => 'dev@phonolite' }
  s.source = { :path => '.' }
  s.platform = :ios, '12.0'

  s.source_files = 'Classes/**/*.{m,h}'
  s.vendored_libraries = 'libphonolite_local_audio.a'

  s.script_phase = {
    :name => 'Build phonolite_local_audio',
    :script => 'bash "${PODS_TARGET_SRCROOT}/build_local_audio_static.sh"',
    :execution_position => :before_compile,
    :output_files => ['${PODS_TARGET_SRCROOT}/libphonolite_local_audio.a']
  }
end
