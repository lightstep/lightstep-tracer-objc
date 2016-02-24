no_default:
	@echo Project has no default target

publish: increment_version publish_source publish_pod

publish_pod:
	# Update the cocoapods trunk. We need to allow warnings for thrift, of course!
	#
	# NOTE: this step requires that you've registered the
	# apis@resonancelabs.com account with your local machine... see
	# https://guides.cocoapods.org/making/getting-setup-with-trunk. That
	# email address is a google group; ask to be added if you're not
	# already a member and need to update the pod!
	@echo "Cloning published source and publishing as a pod..."
	git clone git@github.com:lightstephq/lightstep-tracer-objc lightstep-pod-tmp
	pod trunk push --allow-warnings lightstep-pod-tmp/pod/lightstep/lightstep.podspec
	rm -rf lightstep-pod-tmp

publish_source:
	node "$(GOPATH)/../node/tools/rpublish"

# Bumps the version number of the Pod
increment_version:
	awk 'BEGIN { FS = "." }; { printf("%d.%d.%d", $$1, $$2, $$3+1) }' pod/lightstep/VERSION > pod/lightstep/VERSION.incr
	mv pod/lightstep/VERSION.incr pod/lightstep/VERSION
	@echo Incremented version to `cat pod/lightstep/VERSION`
