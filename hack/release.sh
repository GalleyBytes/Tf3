#!/usr/bin/env zsh
##
## Before starting, the following assumptions are made:
## 1. All the code for the release is checked into origin/master
## 2. The currently checked out branch is the origin/master
## 3. The tag HAS NOT been created on the origin yet. (Happens during release)
##
## How to use this script:
##   Step 1: Fetch the latest from origin/master
##   Step 2: Create a branch locally `git tag v0.x.x`
##   Step 3: Update .rmgmt/changelogs/v0.x.x.md. The format should be:
##
##       ## Changes in v0.x.x since v0.y.y
##
##       **Features**
##       **Fixes**
##       **Changes**
##       **Breaking Changes**
##
##   Step 4: Release! `/bin/bash hack/release.sh`
##   Setp 5: Make a bundle. `make bundle`
##
## Next Steps:
##  - Update galleybytes-helm-charts; (copy any CRDs if nessesary)
##      Possible solution #1:
##          A) The currently checked out branch on this local system
##             must be the branch that contains an open PR.
##          B) merge the upstream branch
##  - Update Docs;
##      Possible solution #1:
##          A) Update all the docs before releasing
##          B) Run the make s3-deploy command
##  - Update CLI; When pod envs or images change this might need to be udpated
##  - Update API Depedents: All projects that use the api should be checked
##      that any new APIs will work correctly with the service.
##      See: https://github.com/galleybytes/tofu-kubed/network/dependents
set -o nounset
set -o errexit
set -o pipefail
set -x
gh auth status # use GH_TOKEN authentication
unset CDPATH
reporoot=$(git rev-parse --show-toplevel)
cd "$reporoot"

version=$(git describe --tags --dirty)

changelog=".rmgmt/changelogs/${version}.md"
stat "$changelog" >/dev/null

export ghcr="ghcr.io"
export gh_org=${gh_org:-"galleybytes"}
export image_name=${image_name:-"tf3"}
repo="$ghcr/$gh_org/$image_name"
export IMG=$repo:$version


tmpdir="$(mktemp -d)/tf3-tasks"
gh repo clone https://github.com/GalleyBytes/tf3-tasks.git "$tmpdir"
cd "$tmpdir/images"
poetry install --no-root

function check_build_exists {
    cd "$tmpdir/images"
    >&2 poetry run python tag_check.py --host "$ghcr" --org $gh_org --image $image_name --t $version --ismultiarch
    if [[ $? -eq 1 ]]; then
        printf "Found $IMG!\n"
        return
    fi
    # i=0
    # existing_builds=($(
    #     page="https://registry.hub.docker.com/v2/repositories/$repo/tags/?page=1"
    #     while [[ $? -eq 0 ]]; do
    #         results=$(curl -s "$page")

    #         if [[ $(jq '.count' <<< "$results") -eq 0 ]]; then
    #             break
    #         fi

    #         jq -r '."results"[]["name"]' <<< "$results"
    #         page=`jq -r '.next//empty' <<< "$results"`
    #         if [[ -z "$page" ]]; then
    #             break
    #         fi
    #     done
    # ))
    # if [[ " ${existing_builds[*]} " =~ " $version " ]]; then
    #     printf "Found $IMG!\n"
    #     return
    # fi
    >&2 printf "Not found $IMG.\n"
    return 1
}
# printf "Will build $repo:$version\n"

## Build and Push Release!
# export VERSION=$version
# make docker-build-local push
# unset GITHUB_TOKEN
cd "$reporoot"
git push origin tag $version
until check_build_exists;do sleep 60;done
cd "$reporoot"
gh release create  $version -t "$version release" -F "$changelog"
