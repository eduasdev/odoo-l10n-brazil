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
      report_xlsx report_wkhtmltopdf_param

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/server-ux \
      date_range base_technical_features

# l10n_br_sale_invoice_plan requires sale_invoice_plan
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/sale-workflow \
      sale_invoice_plan

# l10n_br_contract / l10n_br_product_contract
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/contract \
      contract product_contract

# l10n_br_purchase_request
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/purchase-workflow \
      purchase_request

# l10n_br_stock_account requires stock_picking_invoicing and its sub-deps
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/account-invoicing \
      stock_picking_invoicing

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/stock-logistics-workflow \
      stock_picking_invoice_link

RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/server-tools \
      base_view_inheritance_extension base_sparse_field_list_support

# l10n_br_hr_expense_invoice
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/hr-expense \
      hr_expense_invoice

# l10n_br_setup_tests and l10n_br_account_reconciliation require web modules
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/web \
      web_responsive web_theme_classic

# l10n_br_account requires account_usability
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/account-financial-tools \
      account_usability

# l10n_br_account_reconciliation requires account_reconcile_oca and related modules
RUN /usr/local/bin/fetch_addon_mod.sh 17.0 oca/account-reconcile \
      account_reconcile_oca account_reconcile_model_oca account_statement_base

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

RUN apt-get update && apt-get install -y --no-install-recommends \
      swig build-essential python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Removed --break-system-packages 
RUN pip3 install --no-cache-dir --ignore-installed \
      -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt

RUN pip3 install --no-cache-dir --ignore-installed --no-deps --upgrade \
      --target=/usr/lib/python3/dist-packages "pyopenssl>=24.0.0"

USER odoo
