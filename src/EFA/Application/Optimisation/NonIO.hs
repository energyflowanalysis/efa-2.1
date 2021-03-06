{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}

module EFA.Application.Optimisation.NonIO where

import qualified EFA.Application.Optimisation.Optimisation as Optimisation
import qualified EFA.Application.Optimisation.Params as Params
import qualified EFA.Application.Optimisation.Balance as Balance
import qualified EFA.Application.Optimisation.Base as Base
import EFA.Application.Optimisation.Optimisation (external)
import qualified EFA.Application.Utility as AppUt

import qualified EFA.Application.Optimisation.ReqsAndDofs as ReqsAndDofs
import qualified EFA.Application.Type as Type
import qualified EFA.Application.Optimisation.Sweep as Sweep
--import qualified EFA.Application.Optimisation.Balance as Forcing
import qualified EFA.Application.Simulation as AppSim

import qualified EFA.Graph.Topology.Node as Node

import qualified EFA.Flow.Topology.Record as TopoRecord

import qualified EFA.Flow.Sequence.Absolute as SeqAbs
import qualified EFA.Flow.Sequence.Quantity as SeqQty
import qualified EFA.Flow.Sequence.Record as SeqRec
import qualified EFA.Flow.Sequence.Index as SeqIdx

import qualified EFA.Flow.State.Quantity as StateQty
import qualified EFA.Flow.State.Absolute as StateEqAbs

import qualified EFA.Flow.SequenceState.Index as Idx

import qualified EFA.Signal.Signal as Sig
import qualified EFA.Signal.Record as Record
import qualified EFA.Signal.Chop as Chop
import qualified EFA.Signal.Sequence as Sequ
import qualified EFA.Signal.Vector as SV
import EFA.Utility.List (vhead)

import EFA.Signal.Data (Data(Data), Nil)

import qualified EFA.Equation.Arithmetic as Arith
import EFA.Equation.Result (Result(Determined, Undetermined))

import qualified Data.Map as Map
import qualified Data.Vector.Unboxed as UV
import Data.Monoid (Monoid, mempty, (<>))

-- import Debug.Trace(trace)

interpolateOptimalSolutionPerState ::
  (Eq (vec1 a1), Ord a1, Show a1, Show (vec1 a1),
   Show node, SV.Zipper vec1, SV.Walker vec1,
   SV.Storage vec1 Bool, SV.Storage vec1 a1,
   SV.Storage vec1 (Maybe (Result a1)),
   SV.Singleton vec1, SV.Lookup vec1,
   SV.Len (vec1 a1), SV.FromList vec1,
   SV.Find vec1, SV.Convert vec1 vec1,
   Node.C node, Arith.Constant a1) =>
  Params.System node a1 ->
  Params.Optimisation node list sweep vec a ->
  Params.Simulation node vec1 a1 ->
  Type.OptimalSolutionPerState node a1 ->
  Map.Map Idx.State (Type.InterpolationOfOneState node vec1 a1)
interpolateOptimalSolutionPerState sysParams optParams simParams =
  Map.mapWithKey (interpolateOptimalSolutionForOneState sysParams optParams simParams)


interpolateOptimalSolutionForOneState ::
  (Eq (vec1 a1), Ord a1, Show node,-- SV.Storage vec2 (vec1 a4),
   Show (vec1 a1), Show a1, SV.Zipper vec1,
   SV.Walker vec1,
   SV.Storage vec1 (Maybe (Result a1)),
   SV.Storage vec1 a1, SV.Storage vec1 Bool,
   SV.Singleton vec1, SV.Lookup vec1,
   SV.Len (vec1 a1), SV.FromList vec1,
   SV.Find vec1, SV.Convert vec1 vec1,
   Node.C node, Arith.Constant a1) =>
  Params.System node a1 ->
  Params.Optimisation node list sweep vec a->
  Params.Simulation node vec1 a1 ->
  Idx.State ->
  Map.Map [a1] (Maybe (a1, a1, Int, Type.EnvResult node a1)) ->
  Type.InterpolationOfOneState node vec1 a1
interpolateOptimalSolutionForOneState sysParams optParams simParams state optimalSolutionOfOneState =
  let (plocal,prest) =
        case map (Record.getSig demandSignals) (ReqsAndDofs.unReqs $ Params.reqsPos optParams) of
             [r, l] -> (r, l)
             _ -> error "NonIO.simulation: number of signals"

      demandSignals = Params.reqsRec simParams

      g _str x = x
      h m = Map.map (fmap (\(o,e,i,v) -> (o,e,state,i,v))) m

-- TODO: Determined sauber auspacken
      j m = Map.map (fmap (Determined . AppUt.fst4)) m

      optSignal = Sig.tzipWith (Sig.interp2WingProfile
                 ("interpolateOptimalSolutionForOneState - interpolate Signal - interpolate Index-Signal")
                 (g "X:" $ Params.varReqRoomPower1D simParams)
                 (g "Y:" $ Params.varReqRoomPower2D simParams)
                 $ (g "Z:" $ optimalObjectiveMatrix))
                (g "xSig:" plocal)
                (g "ySig:" prest)

{-      indexSignal = Sig.tzipWith (Sig.interp2WingProfile
                 ("interpolateOptimalSolutionForOneState - interpolate Signal - interpolate Index-Signal")
                 (g "X:" $ Params.varReqRoomPower1D simParams)
                 (g "Y:" $ Params.varReqRoomPower2D simParams)
                 $ (g "Z:" $ Sig.convert indexMat))
                (g "xSig:" plocal)
                (g "ySig:" prest)-}

--      indexMat = AppUt.nothing2Nan $ AppUt.to2DMatrix
--                 Map.map (fmap  AppUt.thd4) optimalSolutionOfOneState

      dofsSignals =  Map.mapWithKey f optimalControlMatrices
        where f key mat =
                Sig.tzipWith
                (Sig.interp2WingProfile
                 ("interpolateOptimalSolutionForOneState - interpolate Signals" ++ show (g "Position: " key))
                 (g "X:" $ Params.varReqRoomPower1D simParams)
                 (g "Y:" $ Params.varReqRoomPower2D simParams)
                 $ (g "Z:" $ Sig.convert mat))
                (g "xSig:" plocal)
                (g "ySig:" prest)

      optimalObjectiveMatrix = Sig.map AppUt.nothing2Nan $
          AppUt.to2DMatrix $ j optimalSolutionOfOneState


      optimalControlMatrices =
        Map.map (Sig.map AppUt.nothing2Nan) $
          Base.signCorrectedOptimalPowerMatrices
            sysParams
            (Params.dofsPos optParams)
            (h optimalSolutionOfOneState)

      demandAndControlSignals = Record.addSignals (Map.toList dofsSignals) demandSignals

  in Type.InterpolationOfOneState optimalControlMatrices optSignal demandAndControlSignals

optimalSignalBasedSolution ::
  (Ord node, SV.Storage vec Bool, SV.Storage vec [Idx.State],SV.Storage vec (a, a),
   SV.Singleton vec,Show a,Show node,
   SV.FromList vec,
   Arith.Constant a,RealFloat a,
   SV.Storage vec (Map.Map Idx.State a),
   Show (vec [Idx.State]),Show (vec Bool),
   Show (vec a), Node.C node,
   Ord a,
   SV.Zipper vec,
   SV.Walker vec,
   SV.Storage vec a) =>
  Type.InterpolationOfAllStates node vec a ->
  Balance.StateForcing ->
  Record.PowerRecord node vec a
optimalSignalBasedSolution interpolation statForcing = g "newRecord" $ Record.Record newTime (Map.mapWithKey f pMap)
  where -- (\x -> trace ("StateSignal: " ++ show x) x)
    indexSignal = Base.genOptimalStatesSignal statForcing interpolation
    g _ x  = x -- trace (str ++ ": " ++ show x) x
    newTime =  Base.genOptimalSteppedTime indexSignal time
    (Record.Record time pMap) =  g "firstStateRecord" $ Type.reqsAndDofsSignalsOfState $
              vhead "optimalSignalBasedSolution" $ Map.elems interpolation
    f key _ = Base.genOptimalSteppedSignal indexSignal time (signalMap key)
    signalMap k = Map.map (\ x -> Record.getSig (Type.reqsAndDofsSignalsOfState x) k) interpolation

{-
interpolateOptimalSolution ::
  (Eq (vec2 b), Ord b, Show b, Show (vec2 b),
   Show node, SV.Zipper vec2, SV.Walker vec2,
   SV.Storage vec2 Bool, SV.Storage vec2 b,
   SV.Storage vec2 (Maybe (Result b)),
   SV.Singleton vec2, SV.Lookup vec2, SV.Len (vec2 b),
   SV.FromList vec2, SV.Find vec2, SV.Convert vec2 vec2,
   Node.C node, Arith.Constant b) =>
  Params.System node b->
  Params.Optimisation node list sweep vec a->
  Params.Simulation node vec2 b->
  Type.OptimalSolution node b ->
  Type.Interpolation node vec2 b
interpolateOptimalSolution sysParams optParams simParams optimalSolution =
  let (plocal,prest) =
        case map (Record.getSig demandSignals) (ReqsAndDofs.unReqs $ Params.reqsPos optParams) of
             [r, l] -> (r, l)
             _ -> error "NonIO.simulation: number of signals"

      demandSignals = Params.reqsRec simParams

      g _str x = x -- trace (str ++": " ++ show x) x

      dofsSignals =  Map.mapWithKey f optimalControlMatrices
        where f key mat =
                Sig.tzipWith
                (Sig.interp2WingProfile
                 ("simulation-interpolate Signals" ++ show (g "Position: " key))
                 (g "X:" $ Params.varReqRoomPower1D simParams)
                 (g "Y:" $ Params.varReqRoomPower2D simParams)
                 $ (g "Z:" $ Sig.convert mat))
                (g "xSig:" plocal)
                (g "ySig:" prest)

      optimalControlMatrices =
        Map.map (Sig.map AppUt.nothing2Nan) $
          Base.signCorrectedOptimalPowerMatrices
            sysParams
            optimalSolution
            (Params.dofsPos optParams)

      demandAndControlSignals = Record.addSignals (Map.toList dofsSignals) demandSignals

  in Type.Interpolation optimalControlMatrices demandAndControlSignals
-}

simulation ::
  (Ord a, Show a,
   SV.Zipper vec,
   SV.Walker vec,
   SV.Storage vec Bool,
   SV.Storage vec a,
   SV.Singleton vec,
   SV.Len (vec a),
   SV.FromList vec,
   Node.C node,
   Arith.ZeroTestable a,
   Arith.Constant a) =>
  Params.System node a ->
  Record.PowerRecord node vec a ->
  Type.Simulation node vec a
simulation sysParams givenSigs = Type.Simulation envSim rec
  where
      envSim =
        AppSim.solve
          (Params.systemTopology sysParams)
          (Params.etaAssignMap sysParams)
          (Params.etaMap sysParams)
          givenSigs

      rec = (Base.envToPowerRecord envSim)
              { Record.recordTime = Record.recordTime givenSigs }


energyFlowAnalysis ::
  (Ord a, Show node, SV.Convert [] vec,
   Eq (vec a), SV.Storage vec Bool,
   SV.Storage vec a, SV.Convert vec [],
   SV.Walker vec, SV.Singleton vec,
   SV.Zipper vec,
   Show a, Node.C node,
   Arith.ZeroTestable a,
   Show (vec a),
   Arith.Constant a) =>
  Params.System node a ->
  Params.Simulation node vec a ->
  Record.PowerRecord node vec a ->
  Type.EnergyFlowAnalysis node vec a
energyFlowAnalysis sysParams simParams powerRecord =
      -- Liefert nur delta-Zeiten und keinen Zeitvektor
      -- Deshalb wird der urspruenglichen Zeitvektor behalten
  let recZeroCross = --(\x -> trace ("recZeroCross" ++ show x) x) $
        Chop.addZeroCrossings $ Base.convertRecord powerRecord

      sequencePowerRecord = --(\x -> trace ("sequencePowerRecord" ++ show x) x) $
                            Sequ.mapWithSection (\ _ r ->  Base.convertRecord r)
                            $ Chop.genSequ recZeroCross

      thrT = Params.sequFilterTime simParams
      thrE = Params.sequFilterEnergy simParams

      (_, sequenceFlowsFilt) =
        Sequ.unzip $
        Sequ.filter (Record.major (Sig.toScalar thrE)
                                  (Sig.toScalar thrT) . snd) $
        fmap (\x -> (x, Record.partIntegrate x)) sequencePowerRecord


      sequenceFlowGraph =
        SeqAbs.solveOpts
          (SeqAbs.independentInOutSums SeqAbs.optionsDefault)
          (SeqRec.flowGraphFromSequence $
            fmap (TopoRecord.flowTopologyFromRecord (Params.systemTopology sysParams)) $
            sequenceFlowsFilt)
          (Map.foldWithKey
            (\st val -> ((SeqIdx.storage Idx.initial st SeqAbs..= Data val) <>))
            mempty (Params.unInitStorageSeq $ Params.initStorageSeq sysParams))

      stateFlowGraph =
        StateEqAbs.solveOpts
          Optimisation.optionsScalar
           (StateQty.graphFromCumResult $
           StateQty.fromSequenceFlowResult False $
           SeqQty.mapGraph id (fmap Arith.integrate) $
           external (Params.initStorageState sysParams) sequenceFlowGraph)
          mempty

{-
      stateFlowGraphSweep =
        StateEqAbs.solveOpts
          Optimisation.options
          (toSweep params $
           StateQty.graphFromCumResult $
           StateQty.fromSequenceFlowResult False $
           SeqQty.mapGraph id (fmap Arith.integrate) $
           external (Params.initStorageState params) sequenceFlowGraphSim)
          mempty
-}

  in Type.EnergyFlowAnalysis sequencePowerRecord sequenceFlowGraph stateFlowGraph


toSweep ::
  (Sweep.SweepClass sweep vec a, Arith.Constant a) =>
  Params.Optimisation node list sweep vec a ->
  StateQty.Graph node (Result (Data Nil a)) (Result (Data Nil a)) ->
  StateQty.Graph node (Result (sweep vec a)) (Result (sweep vec a))
toSweep params = StateQty.mapGraph f f
  where one = Sweep.fromRational (Params.sweepLength params) Arith.one
        f (Determined (Data x)) = Determined $ Sweep.replicate one x
        f Undetermined = Undetermined
optimiseAndSimulateSignalBased ::
  (efaVec ~ simVec,intVec ~ simVec,Show d,Arith.ZeroTestable d,
   Arith.Constant d,
   Sweep.SweepClass sweep UV.Vector Bool,
   a ~ d,intVec ~ [],
   Ord (sweep UV.Vector d),
   RealFloat d,
   Show node,
   Monoid (sweep UV.Vector Bool),
   UV.Unbox d,
   Node.C node,
   Arith.Sum d,
   Arith.Product (sweep UV.Vector d),
   Sweep.SweepClass sweep UV.Vector d,
   Sweep.SweepClass sweep UV.Vector (d, d),
   Sweep.SweepClass sweep UV.Vector (d, Bool)) =>
   Params.System node a ->
   Params.Optimisation node [] sweep UV.Vector a ->
   Params.Simulation node intVec a ->
   Balance.Forcing node a ->
   Balance.StateForcing ->
   Map.Map Idx.State (Map.Map [a] (Type.SweepPerReq node sweep UV.Vector a)) ->
   Balance.IndexConversionMap ->
   Type.SignalBasedOptimisation node sweep UV.Vector a intVec b simVec c efaVec d
optimiseAndSimulateSignalBased sysParams optParams simParams balanceForcing statForcing perStateSweep _indexConversionMap =
  let perStateOptimum  = Base.optimalObjectivePerState optParams balanceForcing perStateSweep
      perStateAverage = Base.expectedValuePerState perStateSweep
      -- do we want optimal solution Maps for display ? - probably Yes
--      optimalSolution = Base.selectOptimalState optParams stateForcing perStateOptimum indexConversionMap
      interpolation = interpolateOptimalSolutionPerState sysParams optParams simParams perStateOptimum
      optimalSignalSolution = optimalSignalBasedSolution interpolation statForcing
      sim = simulation sysParams $ optimalSignalSolution
      efa = energyFlowAnalysis sysParams simParams $ Type.signals sim
      sfgSweep = toSweep optParams $ Type.stateFlowGraph efa

  in Type.SignalBasedOptimisation perStateOptimum perStateAverage interpolation sim efa sfgSweep
