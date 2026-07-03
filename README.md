# Odoo + OCA Brazilian Localization

Docker image bundling [Odoo](https://hub.docker.com/_/odoo) with the [OCA Brazilian Localization](https://github.com/OCA/l10n-brazil) addons and their dependencies, ready to deploy via `docker compose`.

Each supported Odoo major version lives on its own branch (`17.0`, `18.0`, etc.), mirroring OCA's own branching convention. The branch you are on determines what gets built.

---

## How it works

The build is a 3-stage Dockerfile:

**Stage 1 — `addons-fetch`**
Clones every OCA repo listed in `modules.lock` at the pinned commit SHA, copies the specified modules into `/addons`, and aggregates all `requirements.txt` files it finds into a single `/build/requirements.txt`.

**Stage 2 — `deps-verification`** *(dev-only, not built by default)*
Installs the fetched addons into a real Odoo image and runs `scripts/verify_dependencies.py`, which checks that every module's `depends` list is satisfied. See [Dependency verification](#dependency-verification-stage-2) below.

**Stage 3 — final image**
Bakes the addons into the Odoo base image and installs the aggregated Python dependencies. This is what a plain `docker build` produces.

---

## modules.lock

`modules.lock` is the single file that differs between branches. It pins every OCA repo to an exact commit SHA, making builds fully reproducible — the same `modules.lock` always produces the same image, regardless of what changed upstream.

**Format:**
```
# repo                    sha                               modules (* = all addons)
oca/l10n-brazil           a3f82c1d4e5f67890abc123def456789  *
oca/account-payment       d91e4b72c3d4e5f6a1b2c3d4e5f6a1b2  account_due_list account_due_list_payment_mode
oca/bank-payment          c04a1128d2e3f4a5b6c7d8e9f0a1b2c3  account_payment_order account_payment_partner
```

- Lines starting with `#` are comments and are ignored.
- A `*` in the modules column (or omitting it entirely) copies all Odoo addons found in the repo root.
- Listing specific module names copies only those folders.

**To update a dependency** to a newer upstream commit:

```sh
# Get the current HEAD SHA of a branch
git ls-remote https://github.com/oca/l10n-brazil.git refs/heads/18.0

# Update the SHA in modules.lock, then commit
# The CI/CD pipeline will trigger automatically on the next push
```

---

## Deploying with Docker Compose

Copy the example files, fill in your credentials, and start the stack:

```sh
cp .env.example .env
# edit .env: set ODOO_VERSION, POSTGRES_USER, POSTGRES_PASSWORD
cp odoo.conf.example odoo.conf
# edit odoo.conf: set admin_passwd, db credentials, workers, etc.

docker compose up -d
```

`odoo.conf` and `.env` are `.gitignore`d — never commit either with real credentials.

## Configuration reference

`odoo.conf.example` documents all supported options: addons path, database credentials, worker counts, memory limits, request timeouts, and more. Copy it to `odoo.conf`, fill in your values, and mount it at deploy time.

---

## Building locally

Use the current git branch as the Odoo version:

```sh
docker build \
  --build-arg ODOO_VERSION=$(git branch --show-current) \
  -t odoo-l10n-brazil:$(git branch --show-current) \
  .
```

To see full build output (useful for debugging fetch/install steps):

```sh
docker build \
  --progress=plain \
  --build-arg ODOO_VERSION=$(git branch --show-current) \
  -t odoo-l10n-brazil:$(git branch --show-current) \
  .
```

To force a clean build ignoring all layer cache (e.g. after updating `modules.lock`):

```sh
docker build \
  --progress=plain \
  --no-cache \
  --build-arg ODOO_VERSION=$(git branch --show-current) \
  -t odoo-l10n-brazil:$(git branch --show-current) \
  .
```

---

## Dependency verification (Stage 2)

An unmet module dependency doesn't fail the build — it just makes the module appear as "Not Installable" in Odoo's Apps list with no obvious explanation. Stage 2 exists to catch this before deploying.

A normal `docker build` skips Stage 2 entirely. To run it explicitly:

```sh
docker build \
  --progress=plain \
  --target deps-verification \
  --build-arg ODOO_VERSION=$(git branch --show-current) \
  -t odoo-l10n-brazil:deps-verification \
  .
```

The check runs as a `RUN` step inside the build, so the result prints directly into the build log — no container needs to start. Output is either:

```
[deps-verification] OK: all N module(s) have satisfied dependencies.
```

or a list of unsatisfied dependencies to investigate:

```
[deps-verification] MISSING: sale_invoice_plan requires 'account_payment_order'
```

To bypass the layer cache and force a full re-fetch before checking:

```sh
docker build \
  --progress=plain \
  --no-cache \
  --target deps-verification \
  --build-arg ODOO_VERSION=$(git branch --show-current) \
  -t odoo-l10n-brazil:deps-verification \
  .
```

---

## CI/CD

`.github/workflows/docker-build.yml` builds a multi-arch image (amd64 + arm64) and pushes it to Docker Hub on every push to a `*.0` branch, but only when files that affect the image actually change (`Dockerfile`, `scripts/**`, `modules.lock`). It tags the image with the branch name and a SHA-suffixed immutable tag:

```
eduasdev/odoo-l10n-brazil:18.0
eduasdev/odoo-l10n-brazil:18.0-abc1234
```

The floating tag (`18.0`) always points to the latest build. The SHA-suffixed tag is pinned forever and can be used to roll back to a previous image without rebuilding.

The workflow can also be triggered manually from the Actions tab via **Run workflow**.

**Required secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | `eduasdev` |
| `DOCKERHUB_TOKEN` | Docker Hub access token (not your account password) |

---

## License

MIT — see [LICENSE](LICENSE). This covers the build tooling in this repository (Dockerfile, scripts, Compose file) only. The OCA addons are fetched at build time and are not committed here — they carry their own upstream licenses (mostly AGPL-3/LGPL-3; check each module's `__manifest__.py` for specifics).
