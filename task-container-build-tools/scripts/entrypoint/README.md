# entrypoint

This binary sets up the infra3 task pod.

## Build

I use `clang++` but it should also work with `g++`.

### Alpine

To build on alpine, run:

```bash
apk add clang curl-dev build-base util-linux-dev
clang++ -static-libgcc -static-libstdc++ -std=c++17 entrypoint.cpp -lcurl -o entrypoint
```

Libraries `libstdc++` and `libgcc` are linked to ensure they don't have to be installed on target systems.

### MacOS


Run the following:

```
clang++ -std=c++17 -stdlib=libc++ -Wall -pedantic entrypoint.cpp -lcurl -o entrypoint
```

## Contribution

Issues, comments, and pull requests are welcomed.