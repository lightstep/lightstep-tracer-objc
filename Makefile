.PHONY: default
default:
	@echo Project targets:
	@echo "    publish"
	@echo "    build_samples"
	@echo "    clean"

CROUTON_THRIFT=$(GOPATH)/src/crouton/crouton.thrift
POD_VERSION := $(shell cat pod/lightstep/VERSION)
POD_SPEC := lightstep-pod-tmp/pod/lightstep/lightstep.podspec

.PHONY: build
build: build_thrift
	cd test/LightStepTestUI && xcodebuild clean build \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
	    -workspace LightStepTestUI.xcworkspace -scheme LightStepTestUI

.PHONY: build_thrift
build_thrift:
	thrift -r --gen cocoa -out pod/lightstep/Pod/Classes $(CROUTON_THRIFT)
	cd pod/lightstep && bash ./patch_thrift.sh


# NOTE: this can be appear to hang if you don't have the simulator for the given
# OS and platform. I believe it's downloading them in the background? Or maybe
# XCode is just hanging without any messages? Who knows?
.PHONY: test
test:
	cd test/LightStepTestUI && xcodebuild test \
	CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
	-workspace LightStepTestUI.xcworkspace -scheme LightStepTestUI \
	-destination 'platform=iOS Simulator,name=iPhone 6,OS=9.2'

open_xcode:
	cd test/LightStepTestUI && open LightStepTestUI.xcworkspace

publish: increment_version publish_source publish_pod

publish_pod:
	@echo "Cloning published source and publishing as a pod..."
	@echo "You make need to first run:"
	@echo "     pod trunk register communications@lightstep.com 'LightStep' --description='LightStep'"
	@echo
	@echo "...to ensure you have publish permissions."
	@echo
	git clone git@github.com:lightstephq/lightstep-tracer-objc lightstep-pod-tmp
	@echo "Updating the version string in the podspec..."
	sed 's/_VERSION_STRING_/$(POD_VERSION)/g' $(POD_SPEC) > $(POD_SPEC).tmp
	cp $(POD_SPEC).tmp $(POD_SPEC)
	rm $(POD_SPEC).tmp
	@echo "Pushing pod..."
	# --allow-warnings is needed for the Thrift code
	pod trunk push --allow-warnings lightstep-pod-tmp/pod/lightstep/lightstep.podspec
	rm -rf lightstep-pod-tmp

publish_source:
	node "$(GOPATH)/../node/tools/rpublish"

# Bumps the version number of the Pod
increment_version:
	awk 'BEGIN { FS = "." }; { printf("%d.%d.%d", $$1, $$2, $$3+1) }' pod/lightstep/VERSION > pod/lightstep/VERSION.incr
	mv pod/lightstep/VERSION.incr pod/lightstep/VERSION
	@echo Incremented version to `cat pod/lightstep/VERSION`

clean:
	rm -rf lightstep-pod-tmp
