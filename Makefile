.PHONY: default
default:
	@echo Please specify make target

CROUTON_THRIFT=$(GOPATH)/src/crouton/crouton.thrift
POD_SPEC := lightstep-pod-tmp/lightstep.podspec

.PHONY: build
build: 
	cd examples/LightStepTestUI && xcodebuild clean build \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
	    -workspace LightStepTestUI.xcworkspace -scheme LightStepTestUI

.PHONY: build_thrift
build_thrift:
	thrift -r --gen cocoa -out Pod/Classes $(CROUTON_THRIFT)
	bash ./patch_thrift.sh

# NOTE: this can be appear to hang if you don't have the simulator for the given
# OS and platform. I believe it's downloading them in the background? Or maybe
# XCode is just hanging without any messages? Who knows?
.PHONY: test
test:
	cd examples/LightStepTestUI && xcodebuild test \
	CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
	-workspace LightStepTestUI.xcworkspace -scheme LightStepTestUI \
	-destination 'platform=iOS Simulator,name=iPhone 6,OS=9.2'

xcode:
	cd examples/LightStepTestUI && open LightStepTestUI.xcworkspace

publish: increment_version publish_source publish_pod

publish_pod:
	@echo "Cloning published source and publishing as a pod..."
	@echo "You make need to first run:"
	@echo "     pod trunk register communications@lightstep.com 'LightStep' --description='LightStep'"
	@echo
	@echo "...to ensure you have publish permissions."
	@echo
	rm -rf lightstep-pod-tmp
	git clone git@github.com:lightstep/lightstep-tracer-objc lightstep-pod-tmp
	@echo "Updating the version string in the podspec..."
	sed 's/_VERSION_STRING_/$(shell cat VERSION)/g' $(POD_SPEC) > $(POD_SPEC).tmp
	cp $(POD_SPEC).tmp $(POD_SPEC)
	rm $(POD_SPEC).tmp
	@echo "Pushing pod..."
	# --allow-warnings is needed for the Thrift code
	pod trunk push --allow-warnings lightstep-pod-tmp/lightstep.podspec

publish_source:
	node "$(GOPATH)/../node/tools/rpublish"

# Bumps the version number of the Pod
increment_version:
	awk 'BEGIN { FS = "." }; { printf("%d.%d.%d", $$1, $$2, $$3+1) }' VERSION > VERSION.incr
	mv VERSION.incr VERSION
	echo "// GENERATED FILE: Do not edit directly\n#define LS_TRACER_VERSION @\"$(shell cat VERSION)\"\n" > Pod/Classes/LSVersion.h
	@echo Incremented version to `cat VERSION`

clean:
	rm -rf lightstep-pod-tmp
