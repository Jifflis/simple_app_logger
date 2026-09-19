Pod::Spec.new do |s|
  s.name             = 'simple_app_logger'
  s.version          = '0.0.1'
  s.summary          = 'Native crash capture for Simple App Logger.'
  s.description      = 'Self-hosted native crash journaling for Simple App Logger.'
  s.homepage         = 'https://github.com/Jifflis/simple_app_logger'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ID Makers' => 'support@id-makers.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
