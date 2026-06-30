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

# External (python) dependencies declared by the modules above, installed
# via pip. PEP 668 ("externally managed environment") on the Ubuntu Noble
# base requires --break-system-packages. --ignore-installed is also needed
# because some requirements (e.g. typing_extensions, pulled in transitively)
# want a newer version than the one apt/dpkg already put in site-packages;
# pip can't "uninstall" a dpkg-owned package (no RECORD file), so without
# this flag it aborts instead of just shadowing it with the newer version.
#
# pyopenssl is explicitly included here to prevent a version mismatch:
# if OCA requirements pull in a newer `cryptography` (which dropped the
# cffi `_lib.GEN_EMAIL` attribute in favour of Rust bindings), the system
# apt-installed pyopenssl still references that old cffi API and crashes
# Odoo on startup. Upgrading pyopenssl alongside cryptography keeps both
# packages on a compatible pair.
COPY --from=addons-fetch /build/requirements.txt /tmp/requirements.txt

RUN pip3 install --no-cache-dir --break-system-packages --ignore-installed \
 -r /tmp/requirements.txt pyopenssl \
 && rm -f /tmp/requirements.txt

USER odoo
