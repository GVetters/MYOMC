# Run NANOGEN
# Local example:
# source run.sh MyMCName /path/to/fragment.py 1000
# 
# Batch example:
# python crun.py MyMCName /path/to/fragment.py --outEOS /store/user/myname/somefolder --keepMini --nevents_job 10000 --njobs 100 --env
# See crun.py for full options, especially regarding transfer of outputs.
# Make sure your gridpack is somewhere readable, e.g. EOS or CVMFS.
# Make sure to run setup_env.sh first to create a CMSSW tarball (have to patch the DR step to avoid taking forever to uniqify the list of 300K pileup files)
echo $@

if [ -z "$1" ]; then
    echo "Argument 1 (name of job) is mandatory."
    exit 1
fi
NAME=$1

if [ -z $2 ]; then
    echo "Argument 2 (fragment path) is mandatory."
    exit 1
fi
FRAGMENT=$2
echo "Input arg 2 = $FRAGMENT"
FRAGMENT=$(readlink -e $FRAGMENT)
echo "After readlink fragment = $FRAGMENT"

if [ -z "$3" ]; then
    NEVENTS=100
else
    NEVENTS=$3
fi

if [ -z "$4" ]; then
    JOBINDEX=1
else
    JOBINDEX=$4
fi


if [ -z "$5" ]; then
    MAX_NTHREADS=8
else
    MAX_NTHREADS=$5
fi

RSEED=$((JOBINDEX * MAX_NTHREADS * 100 + 1001)) # Space out seeds; Madgraph concurrent mode adds idx(thread) to random seed


echo "Fragment=$FRAGMENT"
echo "Job name=$NAME"
echo "NEvents=$NEVENTS"
echo "Random seed=$RSEED"

TOPDIR=$PWD

# NANOGEN
# Setup CMSSW and merge NANOGEN stuff
# UPDATED to Run3-appropriate release/arch, matching the proven-working
# Run3Summer24wmLHEGS campaign (same CMSSW_14_0_18, same el8_amd64_gcc12).
# Check tightened to CMSSW_14_0_18/src (not just the bare top-level dir)
# to match Run3Summer24wmLHEGS's own, more robust pattern.
export SCRAM_ARCH=el8_amd64_gcc12

source /cvmfs/cms.cern.ch/cmsset_default.sh
if [ -r CMSSW_14_0_18/src ] ; then
    echo release CMSSW_14_0_18 already exists
else
    scram p CMSSW CMSSW_14_0_18
fi
cd CMSSW_14_0_18/src
eval `scram runtime -sh`

# NOTE: mirrors Run3Summer24wmLHEGS/run.sh's own "mv ../../Configuration ."
# step here. Only include this if ../../Configuration genuinely exists
# relative to the NANOGEN campaign directory the same way it does for
# Run3Summer24wmLHEGS -- confirm with:
#   ls ../../Configuration
# before relying on this. Left in to match the proven pattern; if it's
# not needed here, the resulting "mv: cannot stat" error will make that
# obvious immediately rather than failing silently later.
mv ../../Configuration .
scram b
cd $TOPDIR

# Setup fragment
mkdir -pv $CMSSW_BASE/src/Configuration/GenProduction/python
cp $FRAGMENT $CMSSW_BASE/src/Configuration/GenProduction/python/fragment.py
if [ ! -f "$CMSSW_BASE/src/Configuration/GenProduction/python/fragment.py" ]; then
    echo "Fragment copy failed"
    exit 1
fi
cd $CMSSW_BASE/src
scram b
cd $TOPDIR

#cat $CMSSW_BASE/src/Configuration/GenProduction/python/fragment.py

# cmsDriver and run
# UPDATED: --conditions, --beamspot, --era now match Run3Summer24wmLHEGS's
# proven values (its LHE,GEN,SIM step specifically, since that's the
# closest-matching stage to NANOGEN's own LHE,GEN portion -- both are
# pre-reconstruction). --era Run3_2024 alone (no NanoAOD-specific
# modifier) matches what Run3Summer24wmLHEGS's OWN NanoAOD-producing NANO
# step already uses successfully, so the old run2_nanoAOD_106Xv2-style
# suffix is dropped, not replaced with a Run3 equivalent.
#
# UNCHANGED, deliberately: --step LHE,GEN,NANOGEN, --eventcontent
# NANOAODGEN, --datatier NANOGEN, and all NANOGEN-specific filenames --
# this is what actually makes this campaign produce NANOGEN output
# instead of duplicating Run3Summer24wmLHEGS's full chain.
cmsDriver.py Configuration/GenProduction/python/fragment.py \
    --python_filename "NANOGEN_${NAME}_cfg.py" \
    --eventcontent NANOAODGEN \
    --customise Configuration/DataProcessing/Utils.addMonitoring,PhysicsTools/NanoAOD/nanogen_cff.setGenFullPrecision \
    --datatier NANOGEN \
    --fileout "file:NANOGEN_$NAME_$JOBINDEX.root" \
    --conditions 140X_mcRun3_2024_realistic_v26 \
    --beamspot DBrealistic \
    --step LHE,GEN,NANOGEN \
    --geometry DB:Extended \
    --era Run3_2024 \
    --no_exec \
    --mc \
    --nThreads $(( $MAX_NTHREADS < 8 ? $MAX_NTHREADS : 8 )) \
    --number $NEVENTS \
    --number_out $NEVENTS \
    --customise_commands "process.RandomNumberGeneratorService.externalLHEProducer.initialSeed=${RSEED}\\n\
process.source.numberEventsInLuminosityBlock=cms.untracked.uint32(1000)\\n"

cmsRun "NANOGEN_${NAME}_cfg.py"
if [ ! -f "NANOGEN_$NAME_$JOBINDEX.root" ]; then
    echo "NANOGEN_$NAME_$JOBINDEX.root not found. Exiting."
    return 1
fi
