# lightstep_install.podspec is a hacky way of leveraging the !ProtoCompiler pod
# without bringing it into the main lightstep-tracer target (LightStep users
# don't need it; LightStep engineers do).
Pod::Spec.new do |s|
  s.name             = 'PodInstallTarget'
  s.version          = "0.0.1"
  s.summary          = "The LightStep Objective-C OpenTracing library."
  s.homepage         = "https://github.com/lightstep/lightstep-tracer-objc"
  s.license          = 'MIT'
  s.author           = { "LightStep" => "support@lightstep.com" }
  s.source           = { :git => "https://github.com/lightstep/lightstep-tracer-objc.git", :tag => s.version.to_s }

  s.dependency '!ProtoCompiler-gRPCPlugin', '~>1.0'

  pods_root = 'Pods'

  # Path where Cocoapods downloads protoc and the gRPC plugin
  protoc_dir = "#{pods_root}/!ProtoCompiler"
  protoc = "#{protoc_dir}/protoc"
  plugin = "#{pods_root}/!ProtoCompiler-gRPCPlugin/grpc_objective_c_plugin"

  # Path to the directory containing the LightStep .proto
  ls_proto_input_dir = "../lightstep-tracer-common"

  # Path to the directory that will contain the proto/grpc generated files
  ls_proto_output_dir = "./genproto"

  prepare_command = <<-CMD
    echo BHS > /Users/bhs/tmp/foo
    mkdir -p #{ls_proto_output_dir}
    #{protoc} \
        --plugin=protoc-gen-grpc=#{plugin} \
        --objc_out=#{ls_proto_output_dir} \
        --grpc_out=#{ls_proto_output_dir} \
        -I #{ls_proto_input_dir} \
        -I #{protoc_dir} \
        #{ls_proto_input_dir}/collector.proto
  CMD

  # system(<<-CMD
  #   mkdir -p #{ls_proto_output_dir}
  #   #{protoc} \
  #       --plugin=protoc-gen-grpc=#{plugin} \
  #       --objc_out=#{ls_proto_output_dir} \
  #       --grpc_out=#{ls_proto_output_dir} \
  #       -I #{ls_proto_input_dir} \
  #       -I #{protoc_dir} \
  #       #{ls_proto_input_dir}/collector.proto
  # CMD
  # )
end
