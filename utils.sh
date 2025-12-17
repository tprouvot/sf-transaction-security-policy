#!/bin/bash

################################################################################
# Shared Deployment Utilities
################################################################################
# This file contains reusable functions for Salesforce deployment scripts
# for Transaction Security Policy deployments.
#
# Usage:
#   source "$(dirname "$0")/path/to/utils.sh"
#
# Functions:
#   - check_prerequisites: Validates sf CLI and jq are installed
#   - get_org_info: Retrieves org URL, username, and API version
#   - replace_in_file: Generic file content replacement with reporting
################################################################################

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

check_prerequisites() {
    printf "%b\n" "${BLUE}Verifying prerequisites...${NC}"

    if ! command -v sf &> /dev/null; then
        printf "%b\n" "${RED}Error: Salesforce CLI (sf) is not installed${NC}"
        exit 1
    fi
    printf "%b\n" "${GREEN}✓ Salesforce CLI found${NC}"

    if ! command -v jq &> /dev/null; then
        printf "%b\n" "${RED}Error: jq is not installed. Please install it:${NC}"
        echo "  macOS: brew install jq"
        echo "  Linux: sudo apt-get install jq"
        exit 1
    fi
    printf "%b\n" "${GREEN}✓ jq found${NC}"
    echo ""
}

get_org_info() {
    local org_alias=$1
    local org_type=$2

    printf "%b\n" "${BLUE}Retrieving ${org_type} information...${NC}"

    # Run sf org display for the specified alias
    if ! ORG_INFO=$(sf org display --target-org "$org_alias" --json 2>/dev/null); then
        printf "%b\n" "${RED}Error: Failed to retrieve org information for alias: $org_alias${NC}"
        printf "%b\n" "${RED}Make sure you are authenticated to this org${NC}"
        echo ""
        printf "%b\n" "${YELLOW}To authenticate, run:${NC}"
        echo "  sf org login web --alias $org_alias"
        exit 1
    fi

    # Validate JSON output
    if ! echo "$ORG_INFO" | jq empty 2>/dev/null; then
        printf "%b\n" "${RED}Error: Invalid JSON response from Salesforce CLI${NC}"
        exit 1
    fi

    # Extract org URL
    ORG_URL=$(echo "$ORG_INFO" | jq -r '.result.instanceUrl')
    if [ -z "$ORG_URL" ] || [ "$ORG_URL" = "null" ]; then
        printf "%b\n" "${RED}Error: Could not extract instanceUrl from org info${NC}"
        exit 1
    fi

    # Extract org username
    ORG_USERNAME=$(echo "$ORG_INFO" | jq -r '.result.username')
    if [ -z "$ORG_USERNAME" ] || [ "$ORG_USERNAME" = "null" ]; then
        printf "%b\n" "${RED}Error: Could not extract username from org info${NC}"
        exit 1
    fi

    # Extract API version
    ORG_API_VERSION=$(echo "$ORG_INFO" | jq -r '.result.apiVersion')
    if [ -z "$ORG_API_VERSION" ] || [ "$ORG_API_VERSION" = "null" ]; then
        printf "%b\n" "${YELLOW}⚠️  Warning: Could not extract apiVersion, using default: 65.0${NC}"
        ORG_API_VERSION="65.0"
    fi

    printf "%b\n" "${GREEN}✓ ${org_type} URL: $ORG_URL${NC}"
    printf "%b\n" "${GREEN}✓ ${org_type} Username: $ORG_USERNAME${NC}"
    printf "%b\n" "${GREEN}✓ ${org_type} API Version: $ORG_API_VERSION${NC}"
    echo ""
}

replace_in_file() {
    local file=$1
    local search=$2
    local replace=$3
    local label=$4

    if grep -q "$search" "$file"; then
        COUNT=$(grep -o "$search" "$file" | wc -l | xargs)

        # Perform replacement (macOS and Linux compatible)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|$search|$replace|g" "$file"
        else
            sed -i "s|$search|$replace|g" "$file"
        fi

        printf "%b\n" "${GREEN}✓ Replaced $COUNT $label occurrence(s) in: $(basename "$file")${NC}"
        return 0
    else
        printf "%b\n" "${YELLOW}⚠️  No $label found in: $(basename "$file")${NC}"
        return 1
    fi
}

