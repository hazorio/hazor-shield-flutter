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
end
