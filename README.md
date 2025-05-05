# Tf-Kubed (Tf3)

> A Kubernetes Custom Resource used to handle Terraform/OpenTofu operations and workflows

<p align="center">
<img src="https://s3.amazonaws.com/classic.isaaguilar.com/tfo-worm-logo-text.png" alt="Tf3 Logo"></img>
</p>


## What is tf3?

This project is:

- A way to run Terraform/OpenTofu in Kubernetes by defining tf deployments as Kubernetes manifests
- A controller that configures and starts [Workflows](http://tf3.galleybytes.com/docs/architecture/workflow/) when it sees changes to the Kubernetes manifest
- Workflow runner pods that execute plan/apply and other user-defined scripts

This project is not:

- An HCL to YAML converter or vice versa
- A Terraform Module or Registry

## Installation

The preferred method is to use helm. See [Install using Helm](http://tf3.galleybytes.com/docs/getting-started/installation/#install-using-helm) on the docs.

Another simple method is to install the resources under `deploy` & `deploy/crds`

```bash
git clone https://github.com/galleybytes/tf3.git
cd tf3
kubectl apply -f deploy/bundles/v0.17.1/v0.17.1.yaml
```

See [more installation options](http://tf3.galleybytes.com/docs/getting-started/installation/).

## Docs

Visit [http://tf3.galleybytes.com](http://tf3.galleybytes.com) to read the docs.

<p align="center">
<img src="https://s3.amazonaws.com/classic.isaaguilar.com/tfo-workflow-diagramv2.png" alt="Tf3 Workflow Diagram"></img>
</p>


## Related Projects and Tools

Here are some other projects that enhance the experience of Tf3.


### Debug With `tfo` CLI

Terraform/OpenTofu is great, but every now and then, a module takes a turn for the worse and the workflow fails. When this happens, a tf workflow will need to be "debugged."

Fortunately, the `tfo` cli (https://github.com/isaaguilar/tf3-cli) can be used to start a debug pod which is connected directly to the same tf session the workflow runs.  It does so by reading the TFO resource and generates a pod with the same environment vars, ConfigMaps, Secrets, and ServiceAccount as a regular workflow pod. Then it drops the user in a shell directly in the main module.

```bash
tfo debug my-tfo-resource --namespace default
```

The user should be ready to rock-n-roll and show off their mad debugging skills.

```bash
Connecting to my-tfo-resource-ca6ajn94-v2-debug-qmjd5.....

Try running 'terraform init'

/home/tfo-runner/generations/2/main$
```

Happy debugging!


## Join the Community

Currently, I'm experimenting with a Discord channel. It may be tough when taking into account juggling a full time job and full time parenting, but I'll see what comes of it. Join the channel https://discord.gg/J5vRmT2PWg

