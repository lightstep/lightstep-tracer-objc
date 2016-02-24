
Subdirectories:

* `pod` is a proper part of the reslabs repo and should be used for the pull requests to update the code
* `api-cocoa-repo` is a submodule that points to the official, flattened, public version of the cocoa code
* `test` contains a "test" that ensures the code builds and nothing more

Use `rbuild`'s `publish-cocoa` target to increment version numbers, copy the former to the latter, and publish the pod accordingly.
