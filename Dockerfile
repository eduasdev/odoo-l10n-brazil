##########################################################################################
# Stage 1: fetch + flatten addons
##########################################################################################
ARG ODOO_VERSION=17.0

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

# ICP-Brasil certificate chain - Brazilian government webservices (SEFAZ/NF-e, Receita
# Federal, etc.) present TLS certificates issued under the ICP-Brasil PKI hierarchy.
# This hierarchy is NOT part of the standard Mozilla/Debian ca-certificates bundle and
# is not installed by any Linux distro by default.
#
# Source (official): ITI (Instituto Nacional de Tecnologia da Informação)
# https://www.gov.br/iti/pt-br/assuntos/repositorio/certificados-das-acs-da-icp-brasil-arquivo-unico-compactado
# "Cadeia Vigente" = current chain (root + all intermediate ACs, excludes expired/revoked).
#
# NOTE on the -k/--insecure flag below: acraiz.icpbrasil.gov.br serves this ZIP over
# HTTPS with a certificate that is itself only verifiable once ICP-Brasil is already
# trusted — a bootstrap problem. -k is deliberately scoped to this one download only;
# every other HTTPS call in this image (including the actual NF-e transmission at
# runtime) verifies normally once the chain below is installed.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip openssl \
    && update-ca-certificates \
    && mkdir -p /tmp/icpbrasil \
    && curl -k -fsS --max-time 60 -o /tmp/icpbrasil/ACcompactado.zip \
      https://acraiz.icpbrasil.gov.br/credenciadas/CertificadosAC-ICP-Brasil/ACcompactado.zip \
    && unzip -o -q /tmp/icpbrasil/ACcompactado.zip -d /tmp/icpbrasil/extraidos \
    && find /tmp/icpbrasil/extraidos -type f | while read -r f; do \
      name=$(basename "$f" | tr ' /' '__'); \
      out="/usr/local/share/ca-certificates/icpb-${name}.crt"; \
      openssl x509 -inform der -in "$f" -out "$out" 2>/dev/null \
        || openssl x509 -inform pem -in "$f" -out "$out" 2>/dev/null \
        || rm -f "$out"; \
    done \
    && update-ca-certificates \
    && rm -rf /tmp/icpbrasil \
    && rm -rf /var/lib/apt/lists/*

# Python's `requests`/`zeep` (used internally by erpbrasil.edoc/erpbrasil.transmissao)
# do NOT use the OS trust store above by default — they use their own bundled CA file
# via the `certifi` package, which does not include ICP-Brasil.
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

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
