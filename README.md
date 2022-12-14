# kindest-base-crio

This repo creates a base image for kind nodes with cri-o instead of containerd.
Most of the files are replicated from the [kind project](https://github.com/kubernetes-sigs/kind/).

## How to use
We have a pre-built image for the amd64 architecture on DockerHub.
You can use it to build your own node images for any K8s versions.

```
./kind-build.sh
# Or,
kind build node-image --base-image warmmetal/kindest-base-crio:latest
```

You may get a failure log like the one below in building, just ignore it.
```
Image build Failed! Failed to tear down containerd after loading images command "docker exec --privileged kind-build-1665377339-1220979344 pkill containerd" failed with error: exit status 1
```

We also provide a node image for K8s v1.25.2 on DockerHub.
```
docker pull warmmetal/kindest-node-crio:v1.25.2
# Or,
kind create cluster --image docker.io/warmmetal/kindest-node-crio:v1.25.2
```

You can load local images to kind clusters through `kind load`, 
but only OCI image is correctly supported as podman assumes images to be loaded are OCI images.
Loading docker images will get images with the wrong name. And prior podman can only load docker images.
See [containers/common#793](https://github.com/containers/common/pull/793) and [containers/common#853](https://github.com/containers/common/pull/853) for more details.

## Build

### Other versions
The current version of cri-o is v1.20.9.
We use this version to work around [#6069](https://github.com/cri-o/cri-o/issues/6069) as all later versions don't get fixed.
If you'd like to use other versions, modify **CRIO_VERSION** in the Dockerfile,
then execute `make update-shasums` to update checksums in the Dockerfile.
And, run `make quick` to build the base image for amd64.

### Multiple platforms
As crio only releases its binaries for both amd64 and arm64,
you can run `make build` to build the base images for both of them.
