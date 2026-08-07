import FWCore.ParameterSet.Config as cms

externalLHEProducer = cms.EDProducer("ExternalLHEProducer",
                                     args = cms.vstring('/cvmfs/cms.cern.ch/phys_generator/gridpacks/RunIII/13p6TeV/slc7_amd64_gcc10/Powheg/V2/ggHH_slc7_amd64_gcc10_CMSSW_12_4_13_patch1_aworkdir2.tgz'),
                                     nEvents = cms.untracked.uint32(10000),
                                     numberOfParameters = cms.uint32(1),
                                     outputFile = cms.string('cmsgrid_final.lhe'),
                                     scriptName = cms.FileInPath('GeneratorInterface/LHEInterface/data/run_generic_tarball_cvmfs.sh'),
                                     generateConcurrently = cms.untracked.bool(True),
                                     )

from Configuration.Generator.Pythia8CommonSettings_cfi import *
from Configuration.Generator.MCTunesRun3ECM13p6TeV.PythiaCP5Settings_cfi import *
from Configuration.Generator.PSweightsPythia.PythiaPSweightsSettings_cfi import *
from Configuration.Generator.Pythia8PowhegEmissionVetoSettings_cfi import *

generator = cms.EDFilter(
    "Pythia8ConcurrentHadronizerFilter",
    maxEventsToPrint=cms.untracked.int32(1),
    pythiaPylistVerbosity=cms.untracked.int32(1),
    filterEfficiency=cms.untracked.double(1.0),
    pythiaHepMCVerbosity=cms.untracked.bool(False),
    comEnergy=cms.double(13600.0),
    PythiaParameters=cms.PSet(
        pythia8CommonSettingsBlock,
        pythia8CP5SettingsBlock,
        pythia8PSweightsSettingsBlock,
        pythia8PowhegEmissionVetoSettingsBlock,
        processParameters = cms.vstring(
            "POWHEG:nFinal = 2",
    
            # Z boson
            "23:mMin = 0.05",
            "23:onMode = on",

            # W boson (hope)fully hadronic
            "24:mMin = 0.05",
            "24:onMode = off",
            "24:onIfMatch = 2 -1", #u dbar
            "24:onIfMatch = 2 -3", #u sbar
            "24:onIfMatch = 4 -1", #c dbar 
            "24:onIfMatch = 4 -3", #c sbar

            # Higgs decays
            "25:m0 = 125.0",
            "25:onMode = off",
            "25:onIfMatch = 5 -5",
            "25:onIfMatch = 24 -24",
            "25:onIfMatch = 23 23",

            # ResonanceDecayFilter match quark-level hadronic decays
            "ResonanceDecayFilter:filter = on",
            "ResonanceDecayFilter:exclusive = on",
            #"ResonanceDecayFilter:udscAsEquivalent = on",
            "ResonanceDecayFilter:mothers = 25",
            "ResonanceDecayFilter:daughters = 5,5,24,24",
        ),       
        parameterSets=cms.vstring(
            "pythia8CommonSettings",
            "pythia8CP5Settings",
            "pythia8PSweightsSettings",
            "pythia8PowhegEmissionVetoSettings",
            "processParameters",
        ),
    ),
)

ProductionFilterSequence = cms.Sequence(generator)
