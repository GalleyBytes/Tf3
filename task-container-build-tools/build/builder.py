import click
import os
import subprocess
import requests
import base64


global_options = [
    click.option("--host", default="ghcr.io", help="Container registry hostname (default: ghcr.io)"),
    click.option("--org", required=True, help="GitHub organization"),
    click.option("--image", required=False, help="Name of the container image (excluding tag)"),
    click.option("--tag", "-t", required=False, help="Version tag of the container image"),
]


def add_options(options):
    def _add_options(func):
        for option in reversed(options):
            func = option(func)
        return func

    return _add_options


@click.group()
def cli(**kwargs):
    """CLI tool for container image management."""
    os.environ["DOCKER_CLI_EXPERIMENTAL"] = "enabled"


@cli.command()
@add_options(global_options)
def docker_login(**kwargs):
    """Authenticate with GitHub Container Registry."""
    host = kwargs.get("host") or exit("ERROR: '--host' is required!")
    org = kwargs.get("org") or exit("ERROR: '--org' is required!")
    token = os.getenv("GITHUB_TOKEN") or exit("ERROR: GITHUB_TOKEN is missing!")
    docker_login_task(org, host, token)


def docker_login_task(org, host, token):
    subprocess.run(
        ["docker", "login", host, "--username", org, "--password-stdin"],
        input=token.encode(),
        check=True,
    )


@click.command()
@click.option("--containerfile", "-f", default="Containerfile", help="Build platform architectures")
@click.option("--platform", default="linux/amd64,linux/arm64", help="Build platform architectures")
@click.option("--nocache", is_flag=True, default=False, help="Disable cached layers")
@click.option("--build-arg", multiple=True, help="Disable cached layers")
@click.option("--build-context", "-c", default=".", help="Build context (default='.')")
@add_options(global_options)
def build(containerfile, platform, nocache, build_arg, build_context, **kwargs):
    """Wrapper around `docker buildx` to build and push container image."""
    build_context = build_context or "."
    host = kwargs.get("host") or exit("ERROR: '--host' is required!")
    org = kwargs.get("org") or exit("ERROR: '--org' is required!")
    image = kwargs.get("image") or exit("ERROR: '--image' is required!")
    tag = kwargs.get("tag") or exit("ERROR: '--tag' is required!")

    build_arg_prefix = "--build-arg "
    build_args = " ".join(build_arg_prefix + arg for arg in build_arg).split(" ")

    build_task(
        containerfile,
        platform,
        nocache,
        build_args,
        build_context,
        host,
        org,
        image,
        tag,
    )


def build_task(containerfile, platform, nocache, build_args, build_context, host, org, image, tag):
    repo = f"{host}/{org}/{image}"
    if not release_manifest_exists(host, org, image, tag, platform.split(",")):
        cmd = [
            "docker",
            "buildx",
            "build",
            "--platform",
            platform,
            *build_args,
            "--tag",
            f"{repo}:{tag}",
            "-f",
            containerfile,
            "--push",
            build_context,
        ]
        click.echo(f"Running command: {' '.join(cmd)}")
        subprocess.run(
            cmd,
            check=True,
        )
    else:
        click.echo(f"{repo}:{tag} already exists", err=True)


# @click.command()
# @click.pass_context
# def delete(ctx):
#     """Delete container image."""
#     repo = f"{ctx.host}/{ctx.org}/{ctx.image}"
#     subprocess.run(f"docker rmi {repo}:{ctx.tag}", shell=True, check=True)

# cli.add_command(delete)


def release_manifest_exists(host, org, image, tag, platforms):
    url = f"https://{host}/v2/{org}/{image}"
    headers = {"Accept": "application/vnd.oci.image.index.v1+json"}
    try:
        ghcr_auth = base64.b64encode(os.environ["GITHUB_TOKEN"].encode())
        headers["Authorization"] = f"Bearer {ghcr_auth.decode()}"
    except KeyError as e:
        print("Require GITHUB_TOKEN", e)
        exit(1)

    # In order for this to be true, it must exist and contain all the expected platforms
    manifest_response = requests.get(f"{url}/manifests/{tag}", headers=headers)

    if manifest_response.status_code != 200:
        if manifest_response.status_code == 401:
            exit(f"Status Code: {manifest_response.status_code}, {manifest_response.content}")
        # print(manifest_response.status_code, manifest_response.content)
        return False

    if manifest_contains_archs(
        manifest_response.json(),
        platforms,
    ):
        return True

    return False


def manifest_contains_archs(data, desired_architectures):
    manifests = data.get("manifests")
    if manifests is None:
        return False

    architectures = []
    for manifest in manifests:
        platform = manifest.get("platform", {})

        architectures.append(f"{platform.get('os', 'unknown')}/{platform.get('architecture', 'unknown')}")

    for architecture in desired_architectures:
        if architecture not in architectures:
            return False

    return True


if __name__ == "__main__":
    cli.add_command(docker_login)
    cli.add_command(build)
    cli()
