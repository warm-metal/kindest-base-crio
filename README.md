# kindest-base-crio

This repo creates a base image for kind nodes with cri-o instead of containerd.
Most of the files are replicated from the [kind project](https://github.com/kubernetes-sigs/kind/).

## How to use
We have a pre-built image for the amd64 architecture on DockerHub.
You can use it to build your own node images for any K8s versions.

```
kind build node-image --base-image warmmetal/kindest-base-crio:v20221010-effaebd
```

You may get a failure log like the one below in building, just ignore it.
```
Image build Failed! Failed to tear down containerd after loading images command "docker exec --privileged kind-build-1665377339-1220979344 pkill containerd" failed with error: exit status 1
```

We also provide a node image for K8s v1.25.2 on DockerHub.
```
docker push warmmetal/kindest-node-crio:v1.25.2
```

## Build

### Other versions
The current version of cri-o is 1.25.
If you'd like to use other versions, modify **CRIO_VERSION** in the Dockerfile,
then execute `make update-shasums` to update checksums in the Dockerfile.
And, run `make quick` to build the base image for amd64.

### Multiple platforms
Currently, amd64, arm64, and s390x are all supported, run `make build` to build them all.