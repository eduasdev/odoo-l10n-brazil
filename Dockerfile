##########################################################################################
# Stage 1: fetch + flatten addons
##########################################################################################

FROM alpine/git:2.54.0 AS addons-fetch

# Copy the fetch_addon_mod.sh script and make it executable
COPY scripts/fetch_addon_mod.sh /usr/local/bin/fetch_addon_mod.sh
RUN chmod +x /usr/local/bin/fetch_addon_mod.sh

# Fetch OCA Brazilian Localization modules for Odoo 18.0
RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/l10n-brazil

# Fetch OCA Brazilian Localization module dependencies for Odoo 18.0
RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/account-payment \
 account_due_list account_due_list_payment_mode

RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/bank-payment \
 account_payment_order account_payment_partner account_payment_mode

RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/currency \
 currency_rate_update

RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/hr \
 hr_employee_relative

RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/mis-builder \
 mis_builder

RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/product-attribute \
 uom_alias

RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/reporting-engine \
 report_xlsx

RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/sale-workflow \
 sale_invoice_plan

RUN /usr/local/bin/fetch_addon_mod.sh 18.0 oca/server-ux \
 date_range

##########################################################################################
# Stage 2 (dev-only, testing phase): internal dependency check
# Never built by default - Used to run after build to verify that all module dependencies
# are satisfied.
##########################################################################################

FROM odoo:18.0 AS deps-verification

COPY --from=addons-fetch /addons /mnt/br-addons
COPY scripts/verify_deps.py /verify_deps.py

RUN python3 /verify_deps.py

##########################################################################################
# Stage 3: Odoo 18.0 + OCA Brazilian Localization
##########################################################################################

FROM odoo:18.0

USER root

# Bake the extra addons into the image (no separate addons volume needed).
COPY --from=addons-fetch /addons /mnt/br-addons

# Remove the apt-installed pyopenssl before running pip. Without this step
# pip installs the upgraded pyopenssl to /usr/local/lib/python3.x/dist-packages/
# but Python's path resolution still finds the old apt copy first at
# /usr/lib/python3/dist-packages/OpenSSL/, causing the GEN_EMAIL crash.
# dpkg --purge removes only the pyopenssl files with no cascade side-effects;
# the || true makes the step a no-op if the package isn't present.
RUN dpkg --purge python3-openssl 2>/dev/null || true

# External (python) dependencies declared by the modules above, installed
# via pip. PEP 668 ("externally managed environment") on the Debian Bookworm
# base requires --break-system-packages. --ignore-installed is also needed
# because some requirements (e.g. typing_extensions, pulled in transitively)
# want a newer version than the one apt/dpkg already put in site-packages;
# pip can't "uninstall" a dpkg-owned package (no RECORD file), so without
# this flag it aborts instead of just shadowing it with the newer version.
# pyopenssl is listed explicitly to keep it in sync with whatever version of
# cryptography the OCA requirements install.
COPY --from=addons-fetch /build/requirements.txt /tmp/requirements.txt

RUN pip3 install --no-cache-dir --break-system-packages --ignore-installed \
 -r /tmp/requirements.txt pyopenssl \
 && rm -f /tmp/requirements.txt

USER odoo
