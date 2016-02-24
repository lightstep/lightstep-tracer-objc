Pod::Spec.new do |s|
  s.name             = "lightstep"
  s.version          = "VERSION"
  s.summary          = "The LightStep Objective-C OpenTracing library."

  s.description      = <<-DESC
                       This space intentionally left blank.
                       DESC

  s.homepage         = "https://github.com/lightstephq/lightstep-tracer-objc"
  s.license          = 'MIT'
  s.author           = { "LightStep" => "support@lightstep.com" }
  s.source           = { :git => "https://github.com/lightstephq/lightstep-tracer-objc.git", :tag => s.version.to_s }

  s.platform     = :ios, '7.0'
  s.requires_arc = true

  s.source_files = 'pod/lightstep/Pod/Classes/**/*'
  s.resource_bundles = {
    'lightstep' => ['Pod/Assets/*.png']
  }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  s.dependency 'thrift', '~> 0.9.2'
end
