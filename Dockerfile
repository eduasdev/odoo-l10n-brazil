##########################################################################################
# Stage 1: fetch + flatten addons
##########################################################################################
FROM alpine/git:2.54.0 AS addons-fetch


COPY scripts/fetch_from_lockfile.sh /usr/local/bin/fetch_from_lockfile.sh
RUN chmod +x /usr/local/bin/fetch_from_lockfile.sh

COPY modules.lock /modules.lock
RUN /usr/local/bin/fetch_from_lockfile.sh 17.0 /modules.lock

##########################################################################################
# Stage 2 (dev-only, testing phase): internal dependency check
# Never built by default — run after build to verify all module dependencies are satisfied
##########################################################################################
FROM odoo:17.0 AS deps-verification

COPY --from=addons-fetch /addons /mnt/br-addons
COPY scripts/verify_deps.py /verify_deps.py
RUN python3 /verify_deps.py

##########################################################################################
# Stage 3: final image
##########################################################################################
FROM odoo:17.0

USER root

# Bake the extra addons into the image (no separate addons volume needed)
COPY --from=addons-fetch /addons /mnt/br-addons

# Build tools required by some Python dependency C extensions (e.g. M2Crypto via SWIG)
RUN apt-get update && apt-get install -y --no-install-recommends \
      swig build-essential python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Python dependencies declared by the fetched modules.
# --ignore-installed: allows pip to shadow dpkg-owned packages with newer versions.
COPY --from=addons-fetch /build/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir --ignore-installed \
      -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt

# Compatibility fixes for packages upgraded by OCA requirements:
#   - lxml >= 5.0 split lxml.html.clean into a separate project
#   - pyopenssl < 24.0.0 is incompatible with cryptography >= 42
RUN pip3 install --no-cache-dir lxml_html_clean \
    && pip3 install --no-cache-dir --ignore-installed --no-deps --upgrade \
      --target=/usr/lib/python3/dist-packages "pyopenssl>=24.0.0"

USER odoo
