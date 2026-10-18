Pod::Spec.new do |s|
  s.name = 'hiker_circle_security_bridge'
  s.version = '0.0.1'
  s.summary = 'Private HikerCircle headless database-key bridge.'
  s.description = s.summary
  s.homepage = 'https://hiker-circle.web.app'
  s.license = { :type => 'Unspecified - internal package' }
  s.author = 'HikerCircle'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
