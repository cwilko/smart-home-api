# smart-home-api

A collection of small Python functions packaged for [Fission](https://fission.io), used to try out deploying function code that is built outside the cluster and fetched by URL (a Fission `Package` with `deployment.type: url`) instead of being embedded in the Package as a base64 literal. Every package in the repo is built and released together.

## Packages

Each package is a directory under `packages/`:

| Package | Route | What it does | Dependencies |
|---|---|---|---|
| `test-package` | `GET /test-package` | returns a plain-text status line (Python version and a humanize-formatted size) | `humanize` |
| `slugifier` | `GET /slugifier?text=...` | returns `{"text", "slug"}` as JSON, 400 if `text` is missing; shows reading a query parameter and returning JSON | `python-slugify`, `text-unidecode` |

A package directory holds:

- `main.py` - the function (`main.main`)
- `requirements.txt` - dependencies, vendored into the archive at build time (pure python only)
- `openapi.yaml` - template for the endpoint's OpenAPI document (`__NAME__` and `__SERVER_URL__` are filled in at release)
- `description.txt` - one line used as the catalog description annotation on the HTTPTrigger (avoid the characters `|`, `&` and backslash)

The directory name is the package name: it becomes the Fission Package, Function and HTTPTrigger name, and the route `/<name>`.

### Adding a package

1. Create `packages/<name>/` with the four files above (copy an existing package as a starting point).
2. Run `./build.sh v0.0.0-local <name>` to check it builds.
3. Push to `main`. The next release includes it automatically; there is nothing to register.

## Layout

- `build.sh` - builds `dist/<name>-<version>.zip` and its `.sha256` for every package (or only the ones named): the plain package, with no Fission deployment config in it

Release automation lives under `.github/`, apart from the packages themselves:

- `.github/workflows/release.yml` - builds on every push and pull request, and publishes a release or pre-release (see below)
- `.github/scripts/build-fission-package.sh` - for each built package, renders `dist/<name>-package.yaml` from the zip and checksum that `build.sh` produced, and renders the package's spec to `dist/<name>-openapi.yaml`
- `.github/fission/package.yaml.tmpl` - template shared by all packages for the Fission Package, Function and HTTPTrigger, including the catalog annotations
- `.github/scripts/prune-dev-releases.sh` - deletes old development pre-releases (see below)

## What gets published

| Event | Version | Result |
|---|---|---|
| pull request | `ci-<sha>` | build only, nothing published |
| push to `main` | `dev-<short sha>` | a GitHub **pre-release** with the assets below, then old dev pre-releases are pruned |
| push a `v*` tag | the tag, e.g. `v0.1.0` | a normal release with the assets below |

There is one release for the whole repo, versioned as a unit: every package is rebuilt and attached on every release, whether or not its code changed. Every build has its own URL and its own checksum, so a Package pointing at a build never changes underneath you.

Each release carries these assets for every package `<name>`:

| Asset | What it is |
|---|---|
| `<name>-<version>.zip` | `main.py` plus the vendored dependencies at the zip root |
| `<name>-<version>.zip.sha256` | the checksum |
| `<name>-package.yaml` | an example Fission deployment of the zip, from a separate workflow step: a `Package` (URL of the zip and its sha256), `Function` (`main.main`, newdeploy, scale to zero) and `HTTPTrigger` (`/<name>`) |
| `<name>-openapi.yaml` | the OpenAPI document for `/<name>`; the `HTTPTrigger` in `<name>-package.yaml` links to it through its `catalog.squirrelhome.co.uk/openapi` annotation |

The URL is the release asset, so the repository has to be public for the cluster to fetch it without credentials.

## Development workflow

1. Edit and try it locally: run `main()` directly, or `./build.sh v0.0.0-local <name>` and import `main` from the unpacked zip. (`slugifier` imports `flask`, which Fission's python environment provides, so install it locally to run that one.)
2. Push to `main`. About a minute later there is a `dev-<sha>` pre-release.
3. Pull the `<name>-package.yaml` you want and apply it:

   ```bash
   gh release list --repo cwilko/smart-home-api             # newest first; dev builds are marked Pre-release
   gh release download dev-1a2b3c4 --repo cwilko/smart-home-api --pattern 'slugifier-package.yaml' --output slugifier-package.yaml
   kubectl apply -f slugifier-package.yaml
   ```

4. When it's good, tag a real release: `git tag v0.2.0 && git push origin v0.2.0`.

### Pruning

Pruning is automatic. Each push to `main` publishes its `dev-<sha>` pre-release and then runs `.github/scripts/prune-dev-releases.sh`, which keeps the newest `KEEP_DEV_RELEASES` (5, set in the workflow) and deletes the rest together with their tags. It only ever selects pre-releases whose tag starts with `dev-`; `v*` releases (including `v*-rc` pre-releases) are never touched.

Because old dev builds disappear, a Package that still points at a pruned `dev-<sha>` URL can't fetch its code the next time Fission starts a pod for it. Apply a newer `<name>-package.yaml`, or tag a `v*` release for anything that has to stay deployed.

To prune by hand, or to keep a different number: `.github/scripts/prune-dev-releases.sh 3`.

## Building locally

```bash
./build.sh v0.0.0-local            # all packages
./build.sh v0.0.0-local slugifier  # just one
```

Needs `python` (with `pip`), `zip` and `shasum`. To also render the Fission manifests for those builds:

```bash
GITHUB_REPOSITORY=owner/repo API_BASE_URL=https://api.example.com .github/scripts/build-fission-package.sh v0.0.0-local
```

Set `FISSION_NAMESPACE` and `FISSION_ENVIRONMENT` (defaults `services` and `python`) to change what goes into the package YAMLs.

## Notes

- Fission's python environment runs `python:3.13-alpine` (musl), so only pure-python dependencies work. `build.sh` installs with `--only-binary=:all:` and fails if an archive contains any compiled `.so` file.
- The handler is `main.main` (module `main`, function `main`), the environment's default. Fission appends the extracted archive directory to `sys.path`, which is why the dependencies sit at the zip root.
- Release asset names changed with the move to multiple packages: `package.yaml` and `openapi.yaml` became `<name>-package.yaml` and `<name>-openapi.yaml`. Releases published before the change (for example `dev-09ef66d`) keep the old names.
