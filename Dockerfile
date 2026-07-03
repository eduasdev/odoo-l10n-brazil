##########################################################################################
# Stage 1: fetch + flatten addons
##########################################################################################

ARG ODOO_VERSION
FROM alpine/git:2.54.0 AS addons-fetch

ARG ODOO_VERSION

COPY scripts/fetch_from_lockfile.sh /usr/local/bin/fetch_from_lockfile.sh
RUN chmod +x /usr/local/bin/fetch_from_lockfile.sh

COPY modules.lock /modules.lock
RUN /usr/local/bin/fetch_from_lockfile.sh "$ODOO_VERSION" /modules.lock

##########################################################################################
# Stage 2 (dev-only, testing phase): internal dependency check
# Never built by default — run after build to verify all module dependencies are satisfied
##########################################################################################

ARG ODOO_VERSION
FROM odoo:${ODOO_VERSION} AS deps-verification

COPY --from=addons-fetch /addons /mnt/br-addons
COPY scripts/verify_deps.py /verify_deps.py
RUN python3 /verify_deps.py

##########################################################################################
# Stage 3: final image
##########################################################################################

ARG ODOO_VERSION
FROM odoo:${ODOO_VERSION}

USER root

# Bake the extra addons into the image (no separate addons volume needed)
COPY --from=addons-fetch /addons /mnt/br-addons

# Build tools required by some Python dependency C extensions (e.g. M2Crypto via SWIG)
RUN apt-get update && apt-get install -y --no-install-recommends \
      swig build-essential python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies declared by the fetched modules.
# --break-system-packages is required on Ubuntu Noble (PEP 668, pip >= 23) but
# not available on older Ubuntu releases — detect at build time to stay generic.
# --ignore-installed: allows pip to shadow dpkg-owned packages with newer versions.
COPY --from=addons-fetch /build/requirements.txt /tmp/requirements.txt
RUN if pip3 --help 2>&1 | grep -q break-system-packages; then \
      pip3 install --no-cache-dir --ignore-installed --break-system-packages \
        -r /tmp/requirements.txt; \
    else \
      pip3 install --no-cache-dir --ignore-installed \
        -r /tmp/requirements.txt; \
    fi \
    && rm -f /tmp/requirements.txt

# Force a newer pyOpenSSL over the distro-packaged one to satisfy cryptography
# version constraints pulled in transitively by some OCA modules
RUN pip3 install --no-cache-dir --ignore-installed --no-deps --upgrade \
      --target=/usr/lib/python3/dist-packages "pyopenssl>=24.0.0"

USER odoo
