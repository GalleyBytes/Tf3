import json
import os
import build.builder as builder

if __name__ == "__main__":
    org = os.getenv("TFTASK_GH_ORG", "galleybytes")
    host = os.getenv("TFTASK_CONTAINER_REGISTRY_HOST", "ghcr.io")
    containerfile = os.getenv("TFTASK_CONTAINERFILE", "containerfiles/tftask-v1.Containerfile")
    platform = os.getenv("TFTASK_PLATFORM", "linux/amd64,linux/arm64")
    build_context = "."
    image = os.getenv("TFTASK_IMAGE", "infra3-tftask-v1")
    token = os.getenv("GITHUB_TOKEN") or exit("ERROR: GITHUB_TOKEN is missing!")

    key = "supported_terraform_versions"
    with open("versions.json") as f:
        versions = json.load(f).get(key) or exit("ERROR: '{key}' not found in versions.json")

    builder.docker_login_task("galleybytes", "ghcr.io", token)
    for version in versions:
        build_args = ["--build-arg", f"TF_IMAGE={version}"]
        tag = version
        builder.build_task(
            containerfile,
            platform,
            False,
            build_args,
            build_context,
            host,
            org,
            image,
            tag,
        )
