Pod::Spec.new do |s|
  s.name = 'phonolite_opus'
  s.version = '0.0.1'
  s.summary = 'Opus decoder FFI bindings for Phonolite.'
  s.description = 'Native Opus decoder used by the Phonolite Flutter client.'
  s.homepage = 'https://example.invalid'
  s.license = { :type => 'MIT' }
  s.author = { 'Phonolite' => 'dev@phonolite' }
  s.source = { :path => '.' }
  s.platform = :osx, '13.0'

  s.source_files = 'Classes/phonolite_opus_link.m'
  s.vendored_libraries = 'libphonolite_opus.a'
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/libphonolite_opus.a"'
  }
  s.script_phase = {
    :name => 'Build phonolite_opus',
    :script => 'bash "${PODS_TARGET_SRCROOT}/build_opus_static.sh"',
    :execution_position => :before_compile,
    :output_files => ['${PODS_TARGET_SRCROOT}/libphonolite_opus.a'],
    :always_out_of_date => '1'
  }
end
