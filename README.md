# Odoo 18.0 + OCA Brazilian Localization

Docker build for Odoo 18.0 bundled with the [OCA Brazilian Localization](https://github.com/OCA/l10n-brazil) addons and their module/python dependencies, ready to deploy via `docker compose`.

## How it works

`Dockerfile` is a 3-stage build:

1. **`addons-fetch`** — clones the pinned OCA repos (`l10n-brazil` plus the specific modules it depends on from `account-payment`, `bank-payment`, `currency`, `hr`, `mis-builder`, `product-attribute`, `reporting-engine`, `sale-workflow`, and `server-ux`) for the `18.0` branch, flattens them into `/addons`, and aggregates any `requirements.txt` files it finds along the way.
2. **`deps-verification`** (dev-only, not built by default) — copies the fetched addons into an `odoo:18.0` image and runs `scripts/verify_deps.py`, which checks that every fetched OCA module's `depends` list is actually satisfied by another core module/addon in the build. See [Dependency checks](#dependency-checks-stage-2) below.
3. **Final stage** — bakes the addons into `odoo:18.0` and installs the aggregated python `requirements.txt`. This is what a plain `docker build .` produces.

## Setup

Build and run locally with Compose:

```bash
cp odoo.conf.example odoo.conf
# edit odoo.conf, then mount it where docker-compose.yaml expects it
docker compose up -d
```

Or build the final image directly:

```bash
docker build -t odoo-l10n-brazil:18.0 .
```

## Dependency checks (Stage 2)

A normal `docker build .` skips Stage 2 entirely — it only ever builds Stage 1 (fetch) and the final stage. Stage 2 exists purely so you can verify, *before* deploying, that every fetched OCA module's `depends` list is actually satisfied by another core module/addon in the build. An unmet dependency doesn't fail anything at build time; it just makes the module show up as "Not Installable" in Odoo's Apps list later, with no obvious explanation.

To run the check, build Stage 2 explicitly by name:

```bash
docker build --target deps-verification -t odoo-l10n-brazil:depcheck .
```

This re-runs Stage 1 (fetch) and then Stage 2. The check itself (`scripts/verify_deps.py`) executes as a `RUN` step, so its output prints straight into the build log — either:

```
[dep-check] OK: all N module(s) have satisfied dependencies.
```

or a list of `module -> requires 'missing_dependency'` lines to investigate. No container needs to be run afterward; the build log is the result. If you've changed the module list in the Dockerfile and want a clean re-fetch + re-check (bypassing layer cache), add `--no-cache`:

```bash
docker build --no-cache --target deps-verification -t odoo-l10n-brazil:depcheck .
```

## Configuration

`odoo.conf.example` documents the supported options (addons path, worker counts, memory limits, request limits, etc.). Copy it to `odoo.conf`, fill in `admin_passwd` and DB credentials, and mount it at deploy time. `odoo.conf` itself is `.gitignore`d on purpose — never commit a real one.

## CI/CD

`.github/workflows/docker-build.yml` builds and pushes the image to Docker Hub on every push to a `*.0` branch (e.g. `18.0`, `19.0`), tagging it with the branch name plus a SHA-suffixed tag. It needs the `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repo secrets; the `DOKPLOY_*` secrets are optional and, if set, trigger a Dokploy redeploy after the image is pushed.

## License

MIT — see [LICENSE](LICENSE). This license covers the build tooling in this repository (Dockerfile, scripts, Compose file) only. The bundled OCA addons are fetched at build time, not committed to this repo, and keep their own upstream licenses (mostly AGPL-3/LGPL-3 — check each module's `__manifest__.py` for specifics).
