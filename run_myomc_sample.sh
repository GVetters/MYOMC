#!/bin/bash
# run_myomc_sample.sh
#
# Run this as many times as you want, once setup_myomc_campaign.sh has
# been run successfully (once). Generates a random, high-entropy seed
# offset each run to avoid collisions with other collaborators running
# around the same time, then launches crun.py.
#
# Usage:
#   ./run_myomc_sample.sh <job_name> <fragment_path> <total_events> [njobs] [output_subdir] [custom_outEOS] [mem_mb]
#
# output_subdir defaults to job_name if not given, and only changes the
# name of the subdirectory under MYOMC_output/. custom_outEOS instead
# bypasses that convention entirely -- pass a full --outEOS-style path
# (e.g. /store/user/gvetters/MYOMC) to use an existing, established
# output area directly. Must start with /store or /user -- do NOT
# include the /eos/uscms or /eos/user mount prefix itself, since
# crun.py adds that automatically. mem_mb defaults to 16000 (MB),
# confirmed to avoid jobs going held for insufficient memory in practice.
#
# Example:
#   ./run_myomc_sample.sh my_sample_v1 fragment1.py 50000 10 "" /store/user/gvetters/MYOMC

set -e

CAMPAIGN="Run3Summer24wmLHEGS"

# ============================================================
# Argument handling
# ============================================================
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 <job_name> <fragment_path> <total_events> [njobs]"
    echo "Example: $0 my_sample_v1 /path/to/fragment1.py 50000 10"
    exit 1
fi

JOB_NAME=$1
FRAGMENT_PATH=$2
TOTAL_EVENTS=$3
NJOBS=${4:-10}  # default split across 10 jobs -- ADJUST based on your own knowledge of queue/walltime limits,
                # this default is NOT verified against actual queue policy, just a starting point
OUTPUT_SUBDIR=${5:-MYOMC_sample_run3_2024_HHbbWW_full_hadronic}
CUSTOM_OUTEOS=$6  # optional 6th arg: a full --outEOS override (e.g. /store/user/gavetter/MYOMC), bypassing
                   # the MYOMC_output/<subdir> convention entirely -- must start with /store or /user, per crun.py's
                   # own validation
MEM_MB=${7:-16000}  # Condor memory request in MB. 16000 is the value confirmed to avoid held jobs
                     # in practice -- override with a 7th argument if a specific campaign needs more/less.
                     # NOTE: flag name assumes crun.py exposes this as --mem (seen referenced in crun.py's
                     # own csub_command construction) -- confirm with `python3 crun.py --help | grep -i mem`
                     # on your own system before relying on this; adjust the flag name below if it differs.

if [ ! -f "$FRAGMENT_PATH" ]; then
    echo "[FAIL] Fragment file not found: $FRAGMENT_PATH"
    exit 1
fi
# Resolve to absolute NOW, before any 'cd' below -- a relative path
# passed in would otherwise silently break once we cd into bin/.
FRAGMENT_PATH=$(readlink -f "$FRAGMENT_PATH")

NEVENTS_PER_JOB=$(( TOTAL_EVENTS / NJOBS ))
if [ "$NEVENTS_PER_JOB" -lt 1 ]; then
    echo "[FAIL] --njobs ($NJOBS) exceeds --total_events ($TOTAL_EVENTS); each job would get 0 events."
    exit 1
fi

# ============================================================
# This script assumes it's run from the MYOMC root (where env.sh and
# campaigns/ live) -- same as setup_myomc_campaign.sh. It explicitly
# cd's into bin/ itself right before calling crun.py, matching the
# established practice of always submitting from bin/ where crun.py
# actually lives, rather than assuming crun.py can be called via a
# relative path from elsewhere (untested, and crun.py may have its own
# assumptions about running from within bin/ specifically).
# ============================================================

# ============================================================
# Precondition: has setup_myomc_campaign.sh actually been run?
# Checked from the MYOMC root, before cd'ing into bin/.
# ============================================================
CAMPAIGN_ARTIFACT="campaigns/$CAMPAIGN/env.tar.gz"
if [ ! -f "$CAMPAIGN_ARTIFACT" ]; then
    echo "[FAIL] $CAMPAIGN_ARTIFACT not found -- looks like setup_myomc_campaign.sh hasn't been run yet."
    echo "       Run that first (once), then come back to this script."
    exit 1
fi

echo "=========================================="
echo "MYOMC sample generation: $JOB_NAME"
echo "Campaign:      $CAMPAIGN"
echo "Total events:  $TOTAL_EVENTS across $NJOBS jobs ($NEVENTS_PER_JOB events/job)"
echo "Memory:        $MEM_MB MB per job"
echo "=========================================="

# ============================================================
# Proxy check -- still worth doing every run, since this script is
# meant to be run many times, potentially over days/weeks, and a
# campaign build + generation chain can run for many hours -- better
# to fail in seconds here than discover an expired proxy at the final
# write step (as happened for real earlier).
# ============================================================
echo ""
echo "[Check] Verifying grid proxy..."
if ! voms-proxy-info -exists 2>/dev/null; then
    echo "[FAIL] No valid proxy found. Run 'voms-proxy-init --voms cms --rfc --valid 192:00' first."
    exit 1
fi
PROXY_HOURS_LEFT=$(voms-proxy-info -timeleft 2>/dev/null | awk '{print int($1/3600)}')
if [ "$PROXY_HOURS_LEFT" -lt 24 ]; then
    echo "[FAIL] Proxy has less than 24 hours left (${PROXY_HOURS_LEFT}h). Refresh it before running a long job."
    exit 1
fi
echo "[OK] Proxy valid, ${PROXY_HOURS_LEFT}h remaining."

echo ""
echo "[Check] Sourcing environment..."
source "$PWD/env.sh"
CERNNAME=$(whoami)

if [[ $HOSTNAME == *"lpc"* ]]; then
    HOST_TYPE="lpc"
elif [[ $HOSTNAME == *"lxplus"* ]]; then
    HOST_TYPE="lxplus"
else
    echo "[FAIL] Unrecognized host ($HOSTNAME) -- this script only supports lpc or lxplus."
    exit 1
fi
echo "[OK] Detected host type: $HOST_TYPE ($HOSTNAME)"

# EOS path conventions genuinely differ by site, not just by prefix --
# CERN's /eos/user/ uses a first-letter subdirectory
# (/user/<letter>/<username>/...); LPC's /eos/uscms/store/user/ does not
# (/store/user/<username>/...). crun.py itself prepends the site-specific
# mount prefix (eosuser.cern.ch vs root://cmseos.fnal.gov) -- --outEOS
# only needs to be the part after that.
if [ -n "$CUSTOM_OUTEOS" ]; then
    if [[ "${CUSTOM_OUTEOS:0:6}" != "/store" ]] && [[ "${CUSTOM_OUTEOS:0:5}" != "/user" ]]; then
        echo "[FAIL] Custom output path must start with /store or /user (per crun.py's own validation): $CUSTOM_OUTEOS"
        exit 1
    fi
    OUT_EOS="$CUSTOM_OUTEOS"
elif [[ $HOST_TYPE == "lpc" ]]; then
    #OUT_EOS="/store/user/${CERNNAME}/MYOMC/${OUTPUT_SUBDIR}"
    OUT_EOS="/store/group/lpcsusystealth/MYOMC/${OUTPUT_SUBDIR}"
#else
#    OUT_EOS="/user/${CERNNAME:0:1}/${CERNNAME}/MYOMC/${OUTPUT_SUBDIR}"
fi

# ============================================================
# Generate a random, high-entropy seed offset
# Pulled from /dev/urandom, NOT bash's $RANDOM (low-entropy, risks
# correlated draws between processes launched close together in time --
# exactly the multi-collaborator scenario this needs to handle).
# Bounded well under typical 32-bit seed limits to leave headroom for
# the RSeed formula (JOBINDEX * MAX_NTHREADS * 100 + 1001) that
# multiplies this further per-job. Verified via a 10,000-draw test:
# zero collisions, well-distributed across the full bounded range.
# ============================================================
echo ""
echo "[Step] Generating seed offset..."
SEED_OFFSET=$(( $(od -An -N4 -tu4 /dev/urandom | tr -d ' ') % 100000000 ))
echo "[OK] Seed offset for this run: $SEED_OFFSET"
echo "     (Logged here for reproducibility -- if this sample ever needs to be traced back, this is the value that produced it.)"

# ============================================================
# Launch generation -- cd into bin/ first, since that's where crun.py
# actually lives and is normally run from. Fragment path was already
# resolved to absolute above, so it survives this directory change.
# NOTE: --outEOS destination below is a placeholder -- update this to
# wherever your own output should land.
# ============================================================
echo ""
echo "[Step] Launching crun.py: $NJOBS jobs x $NEVENTS_PER_JOB events..."
cd bin || { echo "[FAIL] bin/ directory not found -- is this being run from the MYOMC root?"; exit 1; }
python3 crun.py "$JOB_NAME" "$FRAGMENT_PATH" "$CAMPAIGN" \
    --pileup_file \
    --nevents_job "$NEVENTS_PER_JOB" \
    --njobs "$NJOBS" \
    --keepNANO \
    --seed_offset "$SEED_OFFSET" \
    --mem "$MEM_MB" \
    --outEOS "$OUT_EOS"

echo ""
echo "=========================================="
echo "Done. Seed offset used: $SEED_OFFSET"
echo "=========================================="
