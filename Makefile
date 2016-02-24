no_default:
	@echo Project targets:
	@echo "    publish"
	@echo "    test"

# Runs the 'test' that essentially just checks if the code compiles!
.PHONY: test
test:
	cd test/test_cruntime && bash ./scripts/build.sh

publish: increment_version publish_source publish_pod

# Update the cocoapods trunk. We need to allow warnings for thrift, of course!
#
# NOTE: this step requires that you've registered the
# apis@resonancelabs.com account with your local machine... see
# https://guides.cocoapods.org/making/getting-setup-with-trunk. That
# email address is a google group; ask to be added if you're not
# already a member and need to update the pod!
POD_VERSION := $(shell cat lightstep-pod-tmp/pod/lightstep/VERSION)
POD_SPEC := lightstep-pod-tmp/pod/lightstep/lightstep.podspec
publish_pod:
	@echo "Cloning published source and publishing as a pod..."
	@echo "You make need to first run: pod trunk register communications@lightstep.com 'LightStep' --description='LightStep'"
	git clone git@github.com:lightstephq/lightstep-tracer-objc lightstep-pod-tmp
	@echo $(POD_SPEC)
	sed 's/_VERSION_STRING_/$(POD_VERSION)/g' $(POD_SPEC) > $(POD_SPEC).tmp
	cp $(POD_SPEC).tmp $(POD_SPEC)
	rm $(POD_SPEC).tmp
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
