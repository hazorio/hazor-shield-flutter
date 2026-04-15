Pod::Spec.new do |s|
  s.name             = 'hazor_shield'
  s.version          = '1.0.0'
  s.summary          = 'Hazor Shield Flutter plugin — iOS platform code.'
  s.homepage         = 'https://hazor.io'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Hazor' => 'support@hazor.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'

  # Native Rust core from hazor-shield-mobile-rs. Vendored as an
  # XCFramework so the same SDK works on device + simulator slices.
  # Build it with `make -C ../hazor-shield-mobile-rs flutter-install-ios`
  # — that target copies the XCFramework to Frameworks/.
  if File.directory?(File.join(__dir__, 'Frameworks', 'ShieldMobile.xcframework'))
    s.vendored_frameworks = 'Frameworks/ShieldMobile.xcframework'
  end

  # Link CommonCrypto + DeviceCheck (App Attest lives in DeviceCheck.framework).
  s.frameworks = 'DeviceCheck', 'Security'
end
