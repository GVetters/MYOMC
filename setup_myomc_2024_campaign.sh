#!/bin/bash
# setup_myomc_campaign.sh
#
# ONE-TIME setup for Run3Summer24wmLHEGS: builds the campaign and fetches
# the pileup file. Run this once. After it succeeds, use
# run_myomc_sample.sh (a separate script) as many times as you want to
# actually generate samples -- these are two genuinely separate
# lifecycles (setup once vs. generate repeatedly), kept as two scripts
# rather than one with skip-logic, since that's simpler and safer than
# one script trying to guess whether setup already happened.
#
# Usage:
#   ./setup_myomc_campaign.sh [campaign_name] [cern_username]
#
# campaign_name defaults to Run3Summer24wmLHEGS if not given.
# cern_username is OPTIONAL and only relevant for the rare case where
# your local system username genuinely differs from your actual CERN
# identity (confirmed to happen for some accounts, e.g. LPC's local
# username vs. the separate CERN username tied to your grid
# certificate). Most collaborators won't need this at all -- if your
# usernames already match everywhere, just run this with no 2nd
# argument, exactly as before. Only pass it explicitly if
# getpileupfiles.sh's Rucio step fails with a "Cannot authenticate to
# account <username>" error, which is the specific symptom of this
# mismatch.
#
# Example (local and CERN usernames differ):
#   ./setup_myomc_campaign.sh Run3Summer24wmLHEGS gavetter

set -e

CAMPAIGN=${1:-Run3Summer24wmLHEGS}

echo "=========================================="
echo "MYOMC one-time setup: $CAMPAIGN"
echo "=========================================="

# ============================================================
# Step 0: proxy check
# ============================================================
echo ""
echo "[Step 0] Checking grid proxy..."
if ! voms-proxy-info -exists 2>/dev/null; then
    echo "[FAIL] No valid proxy found. Run 'voms-proxy-init --voms cms --rfc --valid 192:00' first, then re-run this script."
    exit 1
fi
PROXY_HOURS_LEFT=$(voms-proxy-info -timeleft 2>/dev/null | awk '{print int($1/3600)}')
if [ "$PROXY_HOURS_LEFT" -lt 24 ]; then
    echo "[FAIL] Proxy has less than 24 hours left (${PROXY_HOURS_LEFT}h). Refresh it before running this."
    exit 1
fi
echo "[OK] Proxy valid, ${PROXY_HOURS_LEFT}h remaining."

# ============================================================
# Step 1: environment + host detection
# ============================================================
echo ""
echo "[Step 1] Detecting host and loading environment..."
if [ -z ${MYOMCPATH+x} ]; then
    source "$PWD/env.sh"
fi

if [[ $HOSTNAME == *"lpc"* ]]; then
    HOST_TYPE="lpc"
    echo "[OK] Detected cmslpc host."
elif [[ $HOSTNAME == *"lxplus"* ]]; then
    HOST_TYPE="lxplus"
    echo "[OK] Detected lxplus host."
else
    echo "[FAIL] Unrecognized host ($HOSTNAME) -- this script only supports lpc or lxplus."
    exit 1
fi

# CERNNAME defaults to the local system username, which is correct on
# lxplus (local username == CERN identity there) but NOT guaranteed
# elsewhere -- confirmed directly: on LPC, whoami returns the local FNAL
# account ("gvetters"), while the actual grid certificate's identity is
# the separate, real CERN username ("gavetter"). Passing the wrong one
# to getpileupfiles.sh's Rucio call produces a real, confirmed failure:
# "Cannot authenticate to account <local_username> with given
# credentials" -- the certificate is valid, it just doesn't match the
# account name being requested. Override with a 2nd argument if your
# local and CERN usernames differ.
CERNNAME=${2:-$(whoami)}
echo "[OK] Using CERN username: $CERNNAME"

# ============================================================
# Step 2: build ONLY Run3Summer24wmLHEGS (not all 5 campaigns
# firsttime.sh would build). Checks for env.tar.gz first -- the actual,
# confirmed artifact setup_env.sh produces on success (its last line is
# 'tar -czf env.tar.gz ./CMSSW*; mv env.tar.gz ..'), so re-running this
# script is a safe, cheap no-op if setup already succeeded once.
# ============================================================
echo ""
TOPDIR=$PWD
CAMPAIGN_ARTIFACT="campaigns/$CAMPAIGN/env.tar.gz"

if [ -f "$CAMPAIGN_ARTIFACT" ]; then
    echo "[Step 2] Campaign already built ($CAMPAIGN_ARTIFACT exists) -- skipping."
    echo "         Delete that file first if you genuinely need to rebuild."
else
    echo "[Step 2] Building campaign: $CAMPAIGN..."
    cd "campaigns/$CAMPAIGN" || { echo "[FAIL] campaigns/$CAMPAIGN not found -- is MYOMCPATH/env.sh set up correctly?"; exit 1; }

    if [[ $HOST_TYPE == "lpc" ]]; then
        cmssw-el8 -p --bind "$(readlink "$HOME")" --bind "$(readlink -f "${HOME}/nobackup/")" --bind /uscms_data --bind /cvmfs -- ./setup_env.sh
    else
        cmssw-el8 -p --bind "$(readlink -f "$PWD")" --bind "$(readlink -f "$HOME/private")" -- ./setup_env.sh
    fi

    if [ $? -ne 0 ]; then
        echo "[FAIL] setup_env.sh failed for $CAMPAIGN -- stopping here."
        cd "$TOPDIR"
        exit 1
    fi
    cd "$TOPDIR"
    if [ ! -f "$CAMPAIGN_ARTIFACT" ]; then
        echo "[FAIL] setup_env.sh reported success but $CAMPAIGN_ARTIFACT wasn't found -- something's off, check the build output above."
        exit 1
    fi
    echo "[OK] Campaign built successfully."
fi

# ============================================================
# Step 3: pileup file
# ============================================================
echo ""
echo "[Step 3] Fetching pileup file..."
cd "campaigns/$CAMPAIGN" || { echo "[FAIL] campaigns/$CAMPAIGN not found."; exit 1; }
if [ -e "getpileupfiles.sh" ]; then
    source getpileupfiles.sh "$CERNNAME"
    if [ $? -ne 0 ]; then
        echo "[FAIL] getpileupfiles.sh failed."
        cd "$TOPDIR"
        exit 1
    fi
    echo "[OK] Pileup file ready."
else
    echo "[FAIL] getpileupfiles.sh not found in campaigns/$CAMPAIGN -- cannot continue."
    cd "$TOPDIR"
    exit 1
fi
cd "$TOPDIR"

echo ""
echo "=========================================="
echo "Setup complete. You can now run run_myomc_sample.sh as many times as you want."
echo "=========================================="
