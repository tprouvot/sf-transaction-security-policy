#!/bin/bash

################################################################################
# Data Governance - Transaction Security Policies Deployment Script
################################################################################
# This script automates the deployment of Transaction Security Policies for
# Data Cloud governance.
#
# Prerequisites:
#   - Salesforce CLI (sf) installed
#   - jq installed (for JSON parsing)
#   - Authenticated to target org (sf org login web)
#
# Usage:
#   ./deployTransactionSecurityPolicies.sh [target_username]
#
# Parameters:
#   target_username (optional): Email address to use as notification recipient in policies
#                               If not provided, uses the authenticated org's username
#
# Examples:
#   ./deployTransactionSecurityPolicies.sh
#   ./deployTransactionSecurityPolicies.sh admin@company.com
#
# What this script does:
#   1. Prompt for target org alias
#   2. Retrieve org information (username)
#   3. Replace placeholder email in transaction security policy files
#   4. Deploy transaction security policies and flows to target org
#
# Files deployed:
#   - Transaction Security Policies
#   - Policy Condition Flows
#
# Note: This script only deploys transactionSecurityPolicies and flows folders.
#       Custom Permissions, Permission Sets, and Permission Set Groups must be
#       deployed separately if needed.
################################################################################

set -e  # Exit on error

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Parse command line arguments
CUSTOM_USERNAME="$1"

# Directory paths
METADATA_DIR="$SCRIPT_DIR/force-app/main/default"
POLICIES_DIR="$METADATA_DIR/transactionSecurityPolicies"
FLOWS_DIR="$METADATA_DIR/flows"

################################################################################
# Main Script
################################################################################

printf "%b\n" "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
printf "%b\n" "${MAGENTA}     Data Governance - Transaction Security Policies${NC}"
printf "%b\n" "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
echo ""

check_prerequisites

################################################################################
# Step 1: Get Default Org Information
################################################################################

printf "%b\n" "${CYAN}════════════════════════════════════════════════════════════${NC}"
printf "%b\n" "${CYAN}  STEP 1: Checking Default Org${NC}"
printf "%b\n" "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""
printf "%b\n" "${YELLOW}This script will deploy Transaction Security Policies and Flows.${NC}"
printf "%b\n" "${YELLOW}These policies protect critical Data Cloud permissions and exports.${NC}"
echo ""

printf "%b\n" "${BLUE}Retrieving default org information...${NC}"

# Get default org info without specifying target-org
if ! ORG_INFO=$(sf org display --json 2>/dev/null); then
    printf "%b\n" "${RED}Error: No default org found${NC}"
    printf "%b\n" "${RED}Please set a default org first:${NC}"
    echo "  sf config set target-org YOUR_ORG_ALIAS"
    echo "Or authenticate to an org:"
    echo "  sf org login web --set-default"
    exit 1
fi

# Validate JSON output
if ! echo "$ORG_INFO" | jq empty 2>/dev/null; then
    printf "%b\n" "${RED}Error: Invalid JSON response from Salesforce CLI${NC}"
    exit 1
fi

# Extract org information
TARGET_ORG_ALIAS=$(echo "$ORG_INFO" | jq -r '.result.alias // .result.username')
TARGET_ORG_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')
TARGET_ORG_USERNAME=$(echo "$ORG_INFO" | jq -r '.result.username')

if [ -z "$TARGET_ORG_URL" ] || [ "$TARGET_ORG_URL" = "null" ]; then
    printf "%b\n" "${RED}Error: Could not extract instanceUrl from org info${NC}"
    exit 1
fi

if [ -z "$TARGET_ORG_USERNAME" ] || [ "$TARGET_ORG_USERNAME" = "null" ]; then
    printf "%b\n" "${RED}Error: Could not extract username from org info${NC}"
    exit 1
fi

# Determine which username to use for policies
if [ -n "$CUSTOM_USERNAME" ]; then
    POLICY_USERNAME="$CUSTOM_USERNAME"
else
    POLICY_USERNAME="$TARGET_ORG_USERNAME"
fi

echo ""
printf "%b\n" "${GREEN}✓ Default Org Found:${NC}"
printf "%b\n" "${CYAN}  Alias/Username: $TARGET_ORG_ALIAS${NC}"
printf "%b\n" "${CYAN}  Org Username: $TARGET_ORG_USERNAME${NC}"
printf "%b\n" "${CYAN}  URL: $TARGET_ORG_URL${NC}"
echo ""
printf "%b\n" "${GREEN}Policy Notification Recipient:${NC}"
if [ -n "$CUSTOM_USERNAME" ]; then
    printf "%b\n" "${CYAN}  Username: $POLICY_USERNAME ${YELLOW}(custom)${NC}"
else
    printf "%b\n" "${CYAN}  Username: $POLICY_USERNAME ${YELLOW}(from org)${NC}"
fi
echo ""

# Ask for confirmation
read -p "$(printf "%b" "${YELLOW}Do you want to deploy to this org? [y/N]: ${NC}")" CONFIRM_DEPLOY
CONFIRM_DEPLOY=${CONFIRM_DEPLOY:-n}

if [[ ! "$CONFIRM_DEPLOY" =~ ^[Yy]$ ]]; then
    printf "%b\n" "${YELLOW}Deployment cancelled by user${NC}"
    exit 0
fi

echo ""
printf "%b\n" "${GREEN}✓ Deployment confirmed${NC}"
echo ""

################################################################################
# Step 2: Update User Email in Transaction Security Policies
################################################################################

printf "%b\n" "${BLUE}════════════════════════════════════════════════════════════${NC}"
printf "%b\n" "${BLUE}  Updating Transaction Security Policy Metadata${NC}"
printf "%b\n" "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Dynamically find all policy files that contain <user> tags
printf "%b\n" "${BLUE}Scanning for policy files with notification recipients...${NC}"
POLICY_FILES=()
while IFS= read -r -d '' file; do
    # Only include files that have a <user> tag (need email replacement)
    if grep -q '<user>' "$file" 2>/dev/null; then
        POLICY_FILES+=("$file")
    fi
done < <(find "$POLICIES_DIR" -name "*.transactionSecurityPolicy-meta.xml" -print0 2>/dev/null)

if [ ${#POLICY_FILES[@]} -eq 0 ]; then
    printf "%b\n" "${YELLOW}⚠️  No policy files with <user> tags found in: $POLICIES_DIR${NC}"
    printf "%b\n" "${YELLOW}Will proceed with deployment without email updates${NC}"
else
    printf "%b\n" "${GREEN}✓ Found ${#POLICY_FILES[@]} policy file(s) with notification recipients${NC}"
fi
echo ""

printf "%b\n" "${BLUE}Updating notification recipient in policy files...${NC}"
TOTAL_REPLACEMENTS=0
for file in "${POLICY_FILES[@]}"; do
    # Extract current user value from the file
    CURRENT_USER=$(grep -oP '(?<=<user>)[^<]+(?=</user>)' "$file" 2>/dev/null || grep -o '<user>[^<]*</user>' "$file" | sed 's/<user>//;s/<\/user>//')

    if [ -n "$CURRENT_USER" ]; then
        printf "%b\n" "${YELLOW}  $(basename "$file"):${NC}"
        printf "%b\n" "${YELLOW}    From: $CURRENT_USER${NC}"
        printf "%b\n" "${YELLOW}    To:   $POLICY_USERNAME${NC}"

        # Replace current user with target username
        if replace_in_file "$file" "$CURRENT_USER" "$POLICY_USERNAME" "email"; then
            TOTAL_REPLACEMENTS=$((TOTAL_REPLACEMENTS + 1))
        fi
    else
        printf "%b\n" "${YELLOW}⚠️  No <user> tag found in: $(basename "$file")${NC}"
    fi
done
echo ""
printf "%b\n" "${GREEN}✅ Updated $TOTAL_REPLACEMENTS policy file(s)${NC}"
echo ""

################################################################################
# Step 3: Deploy Metadata
################################################################################

printf "%b\n" "${BLUE}════════════════════════════════════════════════════════════${NC}"
printf "%b\n" "${BLUE}  Deploying Transaction Security Policies and Flows${NC}"
printf "%b\n" "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
printf "%b\n" "${BLUE}Deploying to: $TARGET_ORG_ALIAS${NC}"
echo ""

# Deploy only transactionSecurityPolicies and flows folders (using default org)
if ! sf project deploy start --source-dir "$POLICIES_DIR" --source-dir "$FLOWS_DIR" --wait 10; then
    echo ""
    printf "%b\n" "${RED}✗ Deployment failed${NC}"
    exit 1
fi

echo ""
printf "%b\n" "${GREEN}✅ Deployment successful!${NC}"
echo ""

################################################################################
# Final Summary
################################################################################

# Count deployed files dynamically
POLICY_COUNT=$(find "$POLICIES_DIR" -name "*.transactionSecurityPolicy-meta.xml" 2>/dev/null | wc -l | xargs)
FLOW_COUNT=$(find "$FLOWS_DIR" -name "*.flow-meta.xml" 2>/dev/null | wc -l | xargs)

printf "%b\n" "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
printf "%b\n" "${GREEN}✅ Deployment Complete!${NC}"
printf "%b\n" "${MAGENTA}════════════════════════════════════════════════════════════${NC}"
echo ""
printf "%b\n" "${GREEN}What was done:${NC}"
echo ""

printf "%b\n" "${CYAN}TARGET ORG ($TARGET_ORG_ALIAS):${NC}"
echo "  ✓ Deployed Transaction Security Policies ($POLICY_COUNT policies)"
echo "  ✓ Deployed Policy Condition Flows ($FLOW_COUNT flows)"
echo "  ✓ Configured notification recipient: $POLICY_USERNAME"
echo "  ✓ URL: $TARGET_ORG_URL"
echo ""

printf "%b\n" "${GREEN}Deployed Policies:${NC}"
# List all deployed policies dynamically
while IFS= read -r -d '' file; do
    POLICY_NAME=$(basename "$file" .transactionSecurityPolicy-meta.xml)
    # Extract master label from the file if available
    MASTER_LABEL=$(grep -oP '(?<=<masterLabel>)[^<]+' "$file" 2>/dev/null || echo "$POLICY_NAME")
    echo "  • $POLICY_NAME - $MASTER_LABEL"
done < <(find "$POLICIES_DIR" -name "*.transactionSecurityPolicy-meta.xml" -print0 2>/dev/null | sort -z)
echo ""

printf "%b\n" "${YELLOW}Next Steps:${NC}"
echo ""
printf "%b\n" "${YELLOW}1. Verify Transaction Security Policies${NC}"
echo "   - Log into: $TARGET_ORG_ALIAS"
echo "   - Navigate to: Setup → Security → Transaction Security Policies"
echo "   - Verify all policies are Active"
echo ""
printf "%b\n" "${YELLOW}2. Test Policy Enforcement${NC}"
echo "   - Try to assign a protected Data Cloud permission"
echo "   - Verify the policy blocks the action and sends notifications"
echo ""
printf "%b\n" "${YELLOW}3. Configure Additional Recipients (Optional)${NC}"
echo "   - Navigate to each policy in Setup"
echo "   - Add additional email recipients for notifications"
echo ""
printf "%b\n" "${YELLOW}4. Deploy Additional Metadata (If Needed)${NC}"
echo "   - Custom Permissions (customPermissions folder)"
echo "   - Permission Sets (permissionsets folder)"
echo "   - Permission Set Groups (permissionsetgroups folder)"
echo ""


