##########################################################################################
# Stage 1: fetch + flatten addons
##########################################################################################
FROM alpine/git:2.54.0 AS addons-fetch

# Copy the fetch_addon_mod.sh script and make it executable
COPY scripts/fetch_addon_mod.sh /usr/local/bin/fetch_addon_mod.sh
RUN chmod +x /usr/local/bin/fetch_addon_mod.sh

# Fetch OCA Brazilian Localization modules for Odoo 17.0
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/l10n-brazil

# Fetch OCA Brazilian Localization module dependencies for Odoo 17.0
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/account-payment \
      account_due_list account_due_list_payment_mode

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/bank-payment \
      account_payment_order account_payment_partner account_payment_mode

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/currency \
      currency_rate_update

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/hr \
      hr_employee_relative

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/mis-builder \
      mis_builder

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/product-attribute \
      uom_alias

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/reporting-engine \
      report_xlsx

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/server-ux \
      date_range

# NOTE: oca/sale-workflow (sale_invoice_plan) was required in 18.0 but is NOT needed
# in 17.0 — l10n_br_sale@17.0 dropped that dependency.
#
# NOTE: base_address_extended is a built-in Odoo 17.0 CE module (odoo/addons/) —
# no OCA fetch required even though l10n_br_base lists it as a dependency.

##########################################################################################
# Stage 2 (dev-only, testing phase): internal dependency check
# Never built by default - Used to run after build to verify that all module dependencies
# are satisfied.
##########################################################################################
FROM odoo:17.0 AS deps-verification

COPY --from=addons-fetch /addons /mnt/br-addons
COPY scripts/verify_deps.py /verify_deps.py

RUN python3 /verify_deps.py

##########################################################################################
# Stage 3: Odoo 17.0 + OCA Brazilian Localization
##########################################################################################
FROM odoo:17.0

USER root

# Bake the extra addons into the image (no separate addons volume needed).
COPY --from=addons-fetch /addons /mnt/br-addons

COPY --from=addons-fetch /build/requirements.txt /tmp/requirements.txt

RUN pip3 install --no-cache-dir --break-system-packages --ignore-installed \
      -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt

RUN pip3 install --no-cache-dir --ignore-installed --no-deps --upgrade \
      --target=/usr/lib/python3/dist-packages "pyopenssl>=24.0.0"

USER odoo
