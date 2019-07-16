Pod::Spec.new do |s|
  s.name             = "lightstep"
  s.version          = "3.2.12"
  s.summary          = "The LightStep Objective-C OpenTracing library."

  s.description      = <<-DESC
                       LightStep (lightstep.com) bindings for the OpenTracing API (opentracing.io).
                       DESC

  s.homepage         = "https://github.com/lightstep/lightstep-tracer-objc"
  s.license          = 'MIT'
  s.author           = { "LightStep" => "support@lightstep.com" }
  s.source           = { :git => "https://github.com/lightstep/lightstep-tracer-objc.git", :tag => s.version.to_s }

  s.platforms        = { :ios => '8.0', :osx => '10.11', :tvos => '9.0' }

  s.source_files = 'Pod/Classes/*'
  s.requires_arc = true
  s.dependency 'opentracing', '~>0.5.1'

end
