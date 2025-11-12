# bootstrap.yaml
# Idempotent bootstrap + verification
# Requires pipeline setting: "Allow scripts to access the OAuth token"

trigger:
  branches:
    include: [ main ]
pr: none

pool:
  vmImage: ubuntu-latest

variables:
  # ========= Service Connection (OIDC) =========
  OIDC_SERVICE_CONNECTION: 'My-ARM-Connection-OIDC'

  # ========= Infra / Backend =========
  LOCATION: 'eastus'
  STATE_RG: 'rg-example-tfstate'
  STATE_SA: 'stexampletfstate'           # must be globally unique
  STATE_CONTAINER: 'tfstate'
  KV_NAME: 'kv-example-platform'
  KV_RETENTION_DAYS: '30'              # applied on create only; immutable once set
  KV_PUBLIC_NETWORK_ACCESS: 'Disabled' # 'Enabled' or 'Disabled'

  # ========= Log Analytics =========
  LAW_NAME: 'law-example-platform'
  LAW_SKU: 'PerGB2018'

  # ========= ACR =========
  ACR_NAME: 'acrexampleplatform'         # must be globally unique
  ACR_SKU: 'Premium'                   # Premium required to disable public network / use private link
  ACR_PUBLIC_NETWORK_ENABLED: 'false'  # 'true' or 'false'

  # ========= Managed Identity for RBAC =========
  MI_RESOURCE_GROUP: 'rg-ado-wif'
  MI_NAME: 'ado-wif-mi'

  # ========= Tags =========
  TAG_BUSINESS_UNIT: 'core'
  TAG_ENV: 'prod'
  TAG_OWNER: 'platform-team'
  TAG_COST_CENTER: 'cc-001'
  TAG_SYSTEM: 'example-platform'
  TAG_COMPLIANCE: 'standard'
  TAG_LANDING_ZONE: 'lz-core'
  TAG_PROJECT: 'example'
  TAG_LIFECYCLE: 'long-lived'
  TAG_CONTACT: 'devops@example.com'

stages:
# =========================
# Stage 1: Bootstrap (create/update only)
# =========================
- stage: Bootstrap
  displayName: Bootstrap Infra
  jobs:
  - job: Bootstrap
    displayName: Ensure baseline infra exists (no delete) + tags + RBAC
    steps:
    - task: AzureCLI@2
      displayName: 'Bootstrap'
      inputs:
        azureSubscription: '$(OIDC_SERVICE_CONNECTION)'
        scriptType: bash
        scriptLocation: inlineScript
        inlineScript: |
          set -euo pipefail

          echo ">> Using subscription:"
          az account show --query "{id:id,name:name,tenantId:tenantId}" -o tsv | awk '{printf "   - %s (tenant %s)\n",$2,$3}'

          subId="$(az account show --query id -o tsv)"
          rgId="/subscriptions/${subId}/resourceGroups/$(STATE_RG)"

          # ---------- TAG builder ----------
          declare -a AZ_TAG_ARGS=()
          AZ_TAG_ARGS+=("BusinessUnit=$(TAG_BUSINESS_UNIT)")
          AZ_TAG_ARGS+=("Environment=$(TAG_ENV)")
          AZ_TAG_ARGS+=("Owner=$(TAG_OWNER)")
          AZ_TAG_ARGS+=("CostCenter=$(TAG_COST_CENTER)")
          AZ_TAG_ARGS+=("System=$(TAG_SYSTEM)")
          AZ_TAG_ARGS+=("Compliance=$(TAG_COMPLIANCE)")
          AZ_TAG_ARGS+=("LandingZone=$(TAG_LANDING_ZONE)")
          AZ_TAG_ARGS+=("Project=$(TAG_PROJECT)")
          AZ_TAG_ARGS+=("Lifecycle=$(TAG_LIFECYCLE)")
          AZ_TAG_ARGS+=("Contact=$(TAG_CONTACT)")

          tag_merge() { az resource tag --ids "$1" --is-incremental --tags "${@:2}" --only-show-errors >/dev/null; }

          # ---------- RG ----------
          echo ">> Ensure Resource Group exists (no delete)"
          if az group show -n "$(STATE_RG)" >/dev/null 2>&1; then
            echo "   - RG exists. Merging tags."
            tag_merge "$rgId" "${AZ_TAG_ARGS[@]}"
          else
            echo "   - RG missing. Creating."
            az group create -n "$(STATE_RG)" -l "$(LOCATION)" --tags "${AZ_TAG_ARGS[@]}" -o none
          fi

          # ---------- Storage Account ----------
          echo ">> Ensure Storage Account exists (no delete)"
          if az storage account show -g "$(STATE_RG)" -n "$(STATE_SA)" >/dev/null 2>&1; then
            echo "   - SA exists. Merging tags."
            SA_ID="$(az storage account show -g "$(STATE_RG)" -n "$(STATE_SA)" --query id -o tsv)"
            tag_merge "$SA_ID" "${AZ_TAG_ARGS[@]}"
          else
            echo "   - SA missing. Creating."
            az storage account create \
              -g "$(STATE_RG)" -n "$(STATE_SA)" -l "$(LOCATION)" \
              --sku Standard_LRS --kind StorageV2 \
              --min-tls-version TLS1_2 \
              --allow-blob-public-access false \
              --https-only true \
              --tags "${AZ_TAG_ARGS[@]}" \
              -o none
          fi

          echo ">> Ensure Blob Container exists (containers are not ARM-tagged)"
          az storage container create \
            --name "$(STATE_CONTAINER)" \
            --account-name "$(STATE_SA)" \
            --auth-mode login \
            --public-access off \
            -o none >/dev/null

          SA_ID="$(az storage account show -g "$(STATE_RG)" -n "$(STATE_SA)" --query id -o tsv)"

          # ---------- Key Vault (hardened) ----------
          echo ">> Ensure Key Vault exists and is hardened (no delete, safe on retention)"
          kv_exists=true
          if ! az keyvault show -n "$(KV_NAME)" -g "$(STATE_RG)" >/dev/null 2>&1; then kv_exists=false; fi

          if [[ "$kv_exists" == false ]]; then
            echo "   - KV missing. Creating hardened."
            az keyvault create -n "$(KV_NAME)" -g "$(STATE_RG)" -l "$(LOCATION)" \
              --enable-rbac-authorization true \
              --retention-days "$(KV_RETENTION_DAYS)" \
              --public-network-access "$(KV_PUBLIC_NETWORK_ACCESS)" \
              --tags "${AZ_TAG_ARGS[@]}" \
              -o none
            az keyvault update -n "$(KV_NAME)" -g "$(STATE_RG)" --enable-purge-protection true -o none
          else
            echo "   - KV exists. Enforcing secure settings (skip retention change if already set) + merging tags."
            KV_JSON="$(az keyvault show -n "$(KV_NAME)" -g "$(STATE_RG)")"
            KV_ID="$(echo "$KV_JSON" | jq -r '.id')"
            tag_merge "$KV_ID" "${AZ_TAG_ARGS[@]}"

            az keyvault update -n "$(KV_NAME)" -g "$(STATE_RG)" --enable-rbac-authorization true -o none
            az keyvault update -n "$(KV_NAME)" -g "$(STATE_RG)" --public-network-access "$(KV_PUBLIC_NETWORK_ACCESS)" -o none || true

            purgeEnabled="$(echo "$KV_JSON" | jq -r '.properties.enablePurgeProtection // false')"
            if [[ "$purgeEnabled" != "true" ]]; then
              az keyvault update -n "$(KV_NAME)" -g "$(STATE_RG)" --enable-purge-protection true -o none
            fi

            haveRet="$(echo "$KV_JSON" | jq -r '.properties.softDeleteRetentionInDays // empty')"
            if [[ -n "$haveRet" && "$haveRet" != "$(KV_RETENTION_DAYS)" ]]; then
              echo "   ! KV retention is ${haveRet} days (immutable). Skipping change to $(KV_RETENTION_DAYS)."
            fi
          fi
          KV_ID="$(az keyvault show -n "$(KV_NAME)" -g "$(STATE_RG)" --query id -o tsv)"

          # ---------- Log Analytics Workspace ----------
          echo ">> Ensure Log Analytics Workspace exists (no delete)"
          if az monitor log-analytics workspace show -g "$(STATE_RG)" -n "$(LAW_NAME)" >/dev/null 2>&1; then
            echo "   - LAW exists. Merging tags."
            LAW_ID="$(az monitor log-analytics workspace show -g "$(STATE_RG)" -n "$(LAW_NAME)" --query id -o tsv)"
            tag_merge "$LAW_ID" "${AZ_TAG_ARGS[@]}"
          else
            echo "   - LAW missing. Creating with tags."
            az monitor log-analytics workspace create \
              -g "$(STATE_RG)" -n "$(LAW_NAME)" -l "$(LOCATION)" \
              --sku "$(LAW_SKU)" \
              --tags "${AZ_TAG_ARGS[@]}" \
              -o none
            LAW_ID="$(az monitor log-analytics workspace show -g "$(STATE_RG)" -n "$(LAW_NAME)" --query id -o tsv)"
          fi

          # ---------- Diagnostic Settings helper ----------
          enable_diag() {
            local rid="$1" name="$2" lawId="$3"
            local cats logs metrics
            cats="$(az monitor diagnostic-settings categories list --resource "$rid" 2>/dev/null || echo '{}')"
            logs="[]"; metrics="[]"
            echo "$cats" | jq -e '.value[] | select(.type=="Log" and .name=="AuditEvent")' >/dev/null 2>&1 && logs='[{"category":"AuditEvent","enabled":true}]'
            echo "$cats" | jq -e '.value[] | select(.type=="Metric" and .name=="AllMetrics")' >/dev/null 2>&1 && metrics='[{"category":"AllMetrics","enabled":true}]'

            # create or update (two-step create to avoid transient errors)
            az monitor diagnostic-settings list --resource "$rid" -o tsv --query "value[?name=='$name'].name" | grep -q . \
              && az monitor diagnostic-settings update --name "$name" --resource "$rid" --workspace "$lawId" --logs "$logs" --metrics "$metrics" >/dev/null \
              || (az monitor diagnostic-settings create --name "$name" --resource "$rid" --workspace "$lawId" --logs "$logs" --metrics "$metrics" >/dev/null 2>/dev/null \
                  || az monitor diagnostic-settings create --name "$name" --resource "$rid" --workspace "$lawId" --logs "$logs" --metrics "$metrics" >/dev/null)
          }

          echo ">> Ensure diagnostic settings -> LAW"
          enable_diag "$KV_ID"  "ds-kv"  "$LAW_ID"
          enable_diag "$SA_ID"  "ds-sa"  "$LAW_ID"

          # ---------- ACR ----------
          echo ">> Ensure ACR exists (public network policy + SKU safety) + merge tags"
          want_pna="$(ACR_PUBLIC_NETWORK_ENABLED)"
          want_sku="$(ACR_SKU)"

          ensure_acr_premium_if_needed() {
            local name="$1" rg="$2" pna="$3"
            local cur_sku
            cur_sku="$(az acr show -g "$rg" -n "$name" --query sku.name -o tsv)"
            if [[ "$pna" == "false" && "$cur_sku" != "Premium" ]]; then
              echo "   - Upgrading ACR SKU from ${cur_sku} -> Premium to support public-network-disabled/private access."
              az acr update -n "$name" --sku Premium --only-show-errors >/dev/null
            fi
          }

          if az acr show -g "$(STATE_RG)" -n "$(ACR_NAME)" >/dev/null 2>&1; then
            echo "   - ACR exists. Evaluating SKU/network settings and merging tags."
            ACR_ID="$(az acr show -g "$(STATE_RG)" -n "$(ACR_NAME)" --query id -o tsv)"
            ensure_acr_premium_if_needed "$(ACR_NAME)" "$(STATE_RG)" "$want_pna"
            if [[ "$want_pna" == "false" ]]; then
              az acr update -n "$(ACR_NAME)" --public-network-enabled false --only-show-errors >/dev/null
            else
              az acr update -n "$(ACR_NAME)" --public-network-enabled true --only-show-errors >/dev/null
            fi
            tag_merge "$ACR_ID" "${AZ_TAG_ARGS[@]}"
          else
            echo "   - ACR missing. Creating with appropriate SKU and tags."
            if [[ "$want_pna" == "false" && "$want_sku" != "Premium" ]]; then
              echo "   - Forcing ACR SKU to Premium to support public-network-disabled."
              want_sku="Premium"
            fi
            az acr create \
              -g "$(STATE_RG)" -n "$(ACR_NAME)" -l "$(LOCATION)" \
              --sku "$want_sku" \
              --admin-enabled false \
              --public-network-enabled "$want_pna" \
              --tags "${AZ_TAG_ARGS[@]}" \
              -o none
            ACR_ID="$(az acr show -g "$(STATE_RG)" -n "$(ACR_NAME)" --query id -o tsv)"
          fi

          # ACR diagnostics if LAW present
          if [[ -n "${ACR_ID:-}" ]]; then
            enable_diag "$ACR_ID" "ds-acr" "$LAW_ID"
          fi

          # ---------- Managed Identity RBAC (best-effort) ----------
          echo ">> Ensure Managed Identity RBAC bindings (AcrPull, Blob Data Contributor, KV Secrets User)"
          MI_PRINCIPAL_ID="$(az identity show -g "$(MI_RESOURCE_GROUP)" -n "$(MI_NAME)" --query principalId -o tsv 2>/dev/null || true)"
          if [[ -z "$MI_PRINCIPAL_ID" ]]; then
            echo "   ! Managed Identity $(MI_RESOURCE_GROUP)/$(MI_NAME) not found; skipping RBAC."
          else
            assign_role() {
              local scope="$1" role="$2"
              if ! az role assignment list --assignee-object-id "$MI_PRINCIPAL_ID" --scope "$scope" \
                    --query "[?roleDefinitionName=='$role']|[0]" -o tsv | grep -q .; then
                echo "   - Granting $role at $scope"
                az role assignment create --assignee-object-id "$MI_PRINCIPAL_ID" --role "$role" --scope "$scope" >/dev/null 2>&1 \
                  || echo "   ! Could not create role assignment ($role @ $scope). Ensure MI (or caller) has 'User Access Administrator' or 'Owner' and rerun."
              else
                echo "   - $role already present at scope."
              fi
            }
            [[ -n "${ACR_ID:-}" ]] && assign_role "$ACR_ID" "AcrPull"
            assign_role "$SA_ID"  "Storage Blob Data Contributor"
            assign_role "$KV_ID"  "Key Vault Secrets User"
          fi

          echo "✓ Bootstrap complete:"
          echo "   RG='$(STATE_RG)', SA='$(STATE_SA)', container='$(STATE_CONTAINER)'"
          echo "   KV='$(KV_NAME)' (RBAC, purge-protection, PNA=$(KV_PUBLIC_NETWORK_ACCESS))"
          echo "   LAW='$(LAW_NAME)' + diag (AuditEvent/AllMetrics when supported)"
          echo "   ACR='$(ACR_NAME)' (SKU=$(ACR_SKU), public-network=$(ACR_PUBLIC_NETWORK_ENABLED))"

# =========================
# Stage 2: Verify (read-only checks; runs always)
# =========================
- stage: Verify
  displayName: Verify Infra
  dependsOn: Bootstrap
  condition: always()
  jobs:
  - job: Verify
    displayName: Validate existence, diagnostics, ACR settings, MI RBAC
    steps:
    - task: AzureCLI@2
      displayName: 'Verify baseline (read-only)'
      inputs:
        azureSubscription: '$(OIDC_SERVICE_CONNECTION)'
        scriptType: bash
        scriptLocation: inlineScript
        inlineScript: |
          set -euo pipefail

          vso_warn()  { echo "##vso[task.logissue type=warning]$*"; }
          vso_info()  { echo "##vso[task.logissue type=info]$*"; }
          vso_section(){ echo; echo "===== $* ====="; }

          SUB_ID="$(az account show --query id -o tsv)"
          RG_NAME="$(STATE_RG)"
          SA_NAME="$(STATE_SA)"
          KV_NAME="$(KV_NAME)"
          LAW_NAME="$(LAW_NAME)"
          ACR_NAME="$(ACR_NAME)"
          MI_RG="$(MI_RESOURCE_GROUP)"
          MI_NAME="$(MI_NAME)"

          # helpers
          get_id() { az "$1" "$2" show -g "$3" -n "$4" --query id -o tsv 2>/dev/null || true; }
          exists() { [[ -n "$(get_id "$1" "$2" "$3" "$4")" ]]; }

          vso_section "Existence"
          RG_OK=0; SA_OK=0; KV_OK=0; LAW_OK=0; ACR_OK=0

          if az group show -n "$RG_NAME" >/dev/null 2>&1; then
            echo "✅ RG: $RG_NAME"
            RG_OK=1
          else
            vso_warn "❌ RG missing: $RG_NAME"
          fi

          SA_ID="$(az storage account show -g "$RG_NAME" -n "$SA_NAME" --query id -o tsv 2>/dev/null || true)"
          if [[ -n "$SA_ID" ]]; then
            echo "✅ Storage Account: $SA_NAME"
            SA_OK=1
          else
            vso_warn "❌ Storage Account missing: $SA_NAME"
          fi

          KV_ID="$(az keyvault show -g "$RG_NAME" -n "$KV_NAME" --query id -o tsv 2>/dev/null || true)"
          if [[ -n "$KV_ID" ]]; then
            echo "✅ Key Vault: $KV_NAME"
            KV_OK=1
          else
            vso_warn "❌ Key Vault missing: $KV_NAME"
          fi

          LAW_ID="$(az monitor log-analytics workspace show -g "$RG_NAME" -n "$LAW_NAME" --query id -o tsv 2>/dev/null || true)"
          if [[ -n "$LAW_ID" ]]; then
            echo "✅ Log Analytics: $LAW_NAME"
            LAW_OK=1
          else
            vso_warn "❌ Log Analytics Workspace missing: $LAW_NAME"
          fi

          ACR_ID="$(az acr show -g "$RG_NAME" -n "$ACR_NAME" --query id -o tsv 2>/dev/null || true)"
          if [[ -n "$ACR_ID" ]]; then
            echo "✅ ACR: $ACR_NAME"
            ACR_OK=1
          else
            vso_warn "❌ ACR missing: $ACR_NAME"
          fi

          vso_section "Diagnostics → LAW"
          check_diag() {
            local rid="$1" label="$2"
            [[ -z "$rid" || -z "$LAW_ID" ]] && { vso_warn "⚠️  Skip diag check for $label (missing RID or LAW)"; return 0; }
            local ds; ds="$(az monitor diagnostic-settings list --resource "$rid" -o json 2>/dev/null || echo '{"value":[]}' )"
            local toLaw; toLaw="$(echo "$ds" | jq -r --arg law "$LAW_ID" '[.value[] | select(.workspaceId==$law)] | length')" || toLaw=0
            if [[ "$toLaw" -ge 1 ]]; then
              echo "✅ $label: has diagnostic settings to LAW"
              # Optional categories
              local hasAudit hasMetrics
              hasAudit="$(echo "$ds" | jq -r --arg law "$LAW_ID" \
                '[.value[] | select(.workspaceId==$law) | .logs[]? | select(.category=="AuditEvent" and .enabled==true)] | length')" || hasAudit=0
              hasMetrics="$(echo "$ds" | jq -r --arg law "$LAW_ID" \
                '[.value[] | select(.workspaceId==$law) | .metrics[]? | select(.category=="AllMetrics" and .enabled==true)] | length')" || hasMetrics=0
              [[ "$hasAudit" -ge 1 ]] || vso_warn "⚠️  $label: AuditEvent not enabled to LAW"
              [[ "$hasMetrics" -ge 1 ]] || vso_warn "⚠️  $label: AllMetrics not enabled to LAW"
            else
              vso_warn "❌ $label: no diagnostic settings pointing to LAW"
            fi
          }
          check_diag "$KV_ID"  "KeyVault"
          check_diag "$SA_ID"  "StorageAccount"
          check_diag "$ACR_ID" "ACR"

          vso_section "ACR network/SKU"
          if [[ -n "$ACR_ID" ]]; then
            ACR_SKU_CUR="$(az acr show -g "$RG_NAME" -n "$ACR_NAME" --query sku.name -o tsv)"
            ACR_PNE="$(az acr show -g "$RG_NAME" -n "$ACR_NAME" --query publicNetworkAccess -o tsv)"
            echo "   - SKU: $ACR_SKU_CUR"
            echo "   - publicNetworkAccess: $ACR_PNE"
            if [[ "$(ACR_PUBLIC_NETWORK_ENABLED)" == "false" ]]; then
              [[ "$ACR_SKU_CUR" == "Premium" ]] || vso_warn "⚠️  ACR should be Premium when public network is disabled"
              [[ "$ACR_PNE" == "Disabled" ]] || vso_warn "⚠️  ACR public network expected Disabled"
            fi
          fi

          vso_section "RBAC (Managed Identity on resource scopes)"
          MI_PID="$(az identity show -g "$MI_RG" -n "$MI_NAME" --query principalId -o tsv 2>/dev/null || true)"
          if [[ -z "$MI_PID" ]]; then
            vso_warn "⚠️  Managed Identity not found: $MI_RG/$MI_NAME — skipping RBAC checks"
          else
            check_role() {
              local rid="$1" role="$2" label="$3"
              [[ -z "$rid" ]] && { vso_warn "⚠️  Skip RBAC for $label (resource missing)"; return 0; }
              local has
              has="$(az role assignment list --assignee-object-id "$MI_PID" --scope "$rid" --query "[?roleDefinitionName=='$role']|length(@)" -o tsv 2>/dev/null || echo 0)"
              if [[ "$has" -ge 1 ]]; then
                echo "✅ $label: $role present"
              else
                vso_warn "❌ $label: missing role '$role' for MI at scope"
              fi
            }
            check_role "$ACR_ID" "AcrPull"                       "ACR"
            check_role "$SA_ID"  "Storage Blob Data Contributor" "StorageAccount"
            check_role "$KV_ID"  "Key Vault Secrets User"        "KeyVault"
          fi

          vso_section "Summary"
          printf "%-28s %s\n" "Resource Group"   "$( [[ $RG_OK -eq 1 ]] && echo OK || echo MISSING )"
          printf "%-28s %s\n" "Storage Account"  "$( [[ $SA_OK -eq 1 ]] && echo OK || echo MISSING )"
          printf "%-28s %s\n" "Key Vault"        "$( [[ $KV_OK -eq 1 ]] && echo OK || echo MISSING )"
          printf "%-28s %s\n" "Log Analytics"    "$( [[ $LAW_OK -eq 1 ]] && echo OK || echo MISSING )"
          printf "%-28s %s\n" "ACR"              "$( [[ $ACR_OK -eq 1 ]] && echo OK || echo MISSING )"

          # Mark stage as succeeded-with-issues if anything warned but don't hard fail the pipeline.
          echo "##vso[task.complete result=SucceededWithIssues;]Verification completed (see warnings above if any)"
