Pod::Spec.new do |s|
  s.name             = "lightstep"
  s.version          = "1.2.12"
  s.summary          = "The LightStep Objective-C OpenTracing library."

  s.description      = <<-DESC
                       LightStep (lightstep.com) bindings for the OpenTracing API (opentracing.io).
                       DESC

  s.homepage         = "https://github.com/lightstep/lightstep-tracer-objc"
  s.license          = 'MIT'
  s.author           = { "LightStep" => "support@lightstep.com" }
  s.source           = { :git => "https://github.com/lightstep/lightstep-tracer-objc.git", :tag => s.version.to_s }

  s.platform     = :ios, '7.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes/**/*'
  s.resource_bundles = {
  }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  s.dependency 'opentracing', '~>0.1.0'
end
