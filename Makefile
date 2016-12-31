.PHONY: default
default:
	@echo Please specify make target

POD_SPEC := lightstep.podspec

.PHONY: build
build:
	cd examples/LightStepTestUI && xcodebuild clean build \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
	    -workspace LightStepTestUI.xcworkspace -scheme LightStepTestUI

# NOTE: this can be appear to hang if you don't have the simulator for the given
# OS and platform. I believe it's downloading them in the background? Or maybe
# XCode is just hanging without any messages? Who knows?
.PHONY: test
test:
	cd examples/LightStepTestUI && xcodebuild test \
	CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
	-workspace LightStepTestUI.xcworkspace -scheme LightStepTestUI \
	-destination 'platform=iOS Simulator,name=iPhone 6,OS=10.0'

xcode:
	cd examples/LightStepTestUI && open LightStepTestUI.xcworkspace

publish: increment_version publish_pod

publish_pod:
	@echo "Publishing as a pod..."
	@echo "You may need to first run:"
	@echo "     pod trunk register communications@lightstep.com 'LightStep' --description='LightStep'"
	@echo
	@echo "...to ensure you have publish permissions."
	@echo
	@echo "Pushing pod..."
	pod trunk push --allow-warnings --verbose lightstep.podspec

# Bumps the version number of the Pod
increment_version:
	awk 'BEGIN { FS = "." }; { printf("%d.%d.%d", $$1, $$2, $$3+1) }' VERSION > VERSION.incr
	mv VERSION.incr VERSION
	echo "// GENERATED FILE: Do not edit directly\n#define LSTP_TRACER_VERSION @\"$(shell cat VERSION)\"\n" > Pod/Classes/LSTPVersion.h
	@echo "Updating the version string in the podspec..."
	sed 's/_VERSION_STRING_/$(shell cat VERSION)/g' lightstep.podspec.src > lightstep.podspec	
	git add .
	git commit -m "Increment version to $(shell cat VERSION)"
	git tag $(shell cat VERSION)
	git push -u origin master
	git push -u origin master --tags
	@echo Incremented version to `cat VERSION`

clean:
