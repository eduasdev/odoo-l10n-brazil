##########################################################################################
# Stage 1: fetch + flatten addons
##########################################################################################
ARG ODOO_VERSION=18.0

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

FROM odoo:${ODOO_VERSION} AS deps-verification

COPY --from=addons-fetch /addons /mnt/br-addons
COPY scripts/verify_deps.py /verify_deps.py
RUN python3 /verify_deps.py

##########################################################################################
# Stage 3: final image
##########################################################################################

FROM odoo:${ODOO_VERSION}

USER root

# Bake the extra addons into the image (no separate addons volume needed)
COPY --from=addons-fetch /addons /mnt/br-addons

# Python dependencies declared by the fetched modules.
# --break-system-packages is required when the EXTERNALLY-MANAGED marker file is
# present (Ubuntu Noble / PEP 668). We detect it via the file rather than pip --help
# since some pip builds enforce PEP 668 without advertising the flag in help text.
# --ignore-installed: allows pip to shadow dpkg-owned packages with newer versions.
COPY --from=addons-fetch /build/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir --ignore-installed --break-system-packages \
      -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt

# Force a newer pyOpenSSL over the distro-packaged one to satisfy cryptography
# version constraints pulled in transitively by some OCA modules
RUN pip3 install --no-cache-dir --ignore-installed --no-deps --upgrade \
      --target=/usr/lib/python3/dist-packages "pyopenssl>=24.0.0"

USER odoo
