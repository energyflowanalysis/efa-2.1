{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}

module Main where


import qualified Modules.System as System
import qualified Modules.Optimisation as Optimisation


import Modules.Optimisation(EnvResult)
import Modules.System(Node(..))

-- import EFA.Utility.Async (concurrentlyMany_)

import qualified EFA.Application.OneStorage as One
import qualified EFA.Application.Sweep as Sweep
import qualified EFA.Application.Optimisation as AppOpt
import qualified EFA.Application.Simulation as AppSim
import qualified EFA.Application.Absolute as AppAbs
import qualified EFA.Application.Utility as AppUt

import qualified EFA.Flow.Sequence.Index as SeqIdx
import qualified EFA.Flow.State.Index as StateIdx
import qualified EFA.Graph.StateFlow.Environment as StateEnv
import qualified EFA.Graph.StateFlow as StateFlow
import qualified EFA.Graph.Draw as Draw
import qualified EFA.Graph.Flow as Flow
import qualified EFA.Graph.Topology as Topo
import qualified EFA.Graph.Topology.Index as Idx
import qualified EFA.Graph.Topology.Node as Node

import qualified Graphics.Gnuplot.Terminal.Default as DefaultTerm
--import qualified Graphics.Gnuplot.Terminal.PostScript as PostScript

import qualified EFA.Signal.Signal as Sig; import EFA.Signal.Signal (TC,Scalar)
import qualified EFA.Signal.PlotIO as PlotIO
import qualified EFA.Signal.Record as Record
import qualified EFA.Signal.Sequence as Seq
import qualified EFA.Signal.SequenceData as SD
import qualified EFA.Signal.ConvertTable as CT
import qualified EFA.Signal.Vector as Vec
import qualified EFA.Signal.Base as Base

import EFA.Signal.Data (Data(..), Nil, (:>))
import EFA.Signal.Typ (Typ, F, T, A, Tt)

import qualified EFA.IO.TableParser as Table

import qualified EFA.Equation.System as EqGen; import EFA.Equation.System ((.=))
import qualified EFA.Equation.Environment as EqEnv
import qualified EFA.Equation.Record as EqRecord
import qualified EFA.Equation.Result as Result
import qualified EFA.Equation.Arithmetic as Arith
import EFA.Equation.Result (Result(..))

import EFA.Utility.Bifunctor (second)

import qualified Graphics.Gnuplot.Frame.OptionSet as Opts
import qualified Graphics.Gnuplot.Graph.ThreeDimensional as Graph3D


import qualified Data.Map as Map; import Data.Map (Map)
import qualified Data.Vector as V

import Data.Monoid ((<>))
import Data.Tuple.HT (fst3, snd3, thd3)
import Data.Foldable (foldMap)

import Control.Functor.HT (for)


frameOpts ::
  Opts.T (Graph3D.T Double Double Double) ->
  Opts.T (Graph3D.T Double Double Double)
frameOpts = id
{-
--  Plot.heatmap .
  Plot.xyzrange3d (0.2, 2) (0.3, 3.3) (0, 1) .
  -- Plot.cbrange (0.2, 1) .
  Plot.xyzlabel "Load I Power [W]" "Load II Power [W]" "" .
  Plot.paletteGH
-}

noLegend :: Int -> String
noLegend =  (const "")

legend :: Int -> String
legend 0 = "Laden"
legend 1 = "Entladen"
legend _ = "Undefined"

scaleTableEta :: Map String (Double, Double)
scaleTableEta = Map.fromList $
  ("storage",     (3, 1)) :
  ("gas",         (3, 0.4)) :
  ("transformer", (3.0, 0.95)) :
  ("coal",        (10, 0.46)) :
  ("local",       (1, 1)) :
  ("rest",        (1, 1)) :
  []

restScale, localScale :: Double
restScale = 1.0
localScale = 1.0

------------------------------------------------------------------------

local, rest, water, gas :: [Double]
{-
local = [0.1, 0.5]
rest =  [0.2, 0.6]
water = [0.3, 0.7]
gas =   [0.4, 0.8]
-}
{-
local = [0.2, 0.7, 1.0, 1.9, 3]
rest =  [0.2, 0.7, 0.8, 1.9, 3]
water = [0.2, 0.3, 0.9, 1.9, 3]
gas =   [0.2, 0.7, 1.1, 2.7, 3]
-}

local = [0.2, 3]
rest =  [0.2, 3]
water = [-0.3, 0.3, 0.7]
gas =   [0.4, 3]

sweepPts :: Sweep.Points Double
sweepPts = Sweep.Points [local, rest] [water, gas]

optimalPower :: One.OptimalPower Node
optimalPower =
  One.optimalPower [(Optimisation.state0, lst), (Optimisation.state1, lst)]
  where lst = [(Network, Water), (LocalNetwork, Gas)]

force :: One.SocDrive Double
force = One.ChargeDrive 0

initStorage :: (Arith.Constant a) => [(Node, a)]
initStorage = [(System.Water, Arith.fromRational $ 0.7*3600*1000)]

unzipMap :: Map k (a, b) -> (Map k a, Map k b)
unzipMap m = (Map.map fst m, Map.map snd m)

unzip3Map :: Map k (a, b, c) -> (Map k a, Map k b, Map k c)
unzip3Map m = (Map.map fst3 m, Map.map snd3 m, Map.map thd3 m)



-- @HT Hier wollen wir unabhaengig von Node und Double werden
-- also z.B. nur Typvariablen node und v sollen vorkommen.
optimalEtasWithPowers ::
  One.OptimalEnvParams Node Double ->
  One.SocDrive Double ->
  StateEnv.Complete Node (Data Nil Double) (Data Nil Double) ->
  One.OptimalEtaWithEnv Node Double
optimalEtasWithPowers params forceFactor env =
  Map.foldWithKey f Map.empty op
  where op = One.optimalPowers params
        forcing = One.noforcing forceFactor
        stateFlowGraph = One.stateFlowGraph params
        etaMap = One.etaMap params
        f state ps acc = Map.insert state (Map.fromList res) acc
          where 
                solveFunc =
                  Optimisation.solve
                    stateFlowGraph
                    System.etaAssignState
                    etaMap
                    env
                    state

                envsSweep :: Map [Double] [EnvResult Double]
                envsSweep =
                  Sweep.doubleSweep solveFunc (One.points params)

                optEtaEnv = for envsSweep $
                  Sweep.optimalSolutionState 
                    --One.nocondition
                    Optimisation.condition
                    forcing
                    stateFlowGraph

                res = map g ps
                g p = (p, h p optEtaEnv)
                h (n0, n1) = Map.mapMaybe (fmap (fmap (AppUt.lookupDetPowerState q)))
                  where q = StateIdx.power state n0 n1

------------------------------------------------------------------------

-- | Warning -- only works for one section in env
envToPowerRecord ::
  Sig.TSignal [] Double ->
  StateEnv.Complete System.Node (Result (Data  Nil Double)) (Result (Data ([] :> Nil) Double)) ->
  Record.PowerRecord System.Node [] Double
envToPowerRecord time env =
  (Seq.addZeroCrossings
  . Record.Record time
  . Map.map i
  . Map.mapKeys h 
  . Map.filterWithKey p
  . StateEnv.powerMap
  . StateEnv.signal) env
  where p (Idx.InPart st _) _ = st == Idx.State 0
        h (Idx.InPart _ (Idx.Power edge)) = Idx.PPos edge

        i (Determined dat) = Sig.TC dat
        i Undetermined =
          error "envToPowerRecord - undetermined data"

external ::
  (Eq (v a), Arith.Constant a, Base.BSum a, Vec.Zipper v,
  Vec.Walker v, Vec.Singleton v, Vec.Storage v a, Node.C node) =>
  [(node, a)] ->
  Flow.RangeGraph node ->
  SD.SequData
    (Record.Record Sig.Signal Sig.FSignal
      (Typ A T Tt) (Typ A F Tt) (Idx.PPos node) v a a) ->
  EqEnv.Complete node (Result (Data Nil a)) (Result (Data (v :> Nil) a))

external initSto sfTopo sfRec =
  EqEnv.completeFMap EqRecord.unAbsolute EqRecord.unAbsolute $
  EqGen.solveFromMeasurement sfTopo $
  (AppAbs.fromEnvSignal $ AppAbs.envFromFlowRecord (fmap Record.diffTime sfRec))
  <> foldMap f initSto
  where f (st, val) = 
          Idx.absolute (SeqIdx.storage Idx.initial st) .= Data val

varRestPower', varLocalPower' :: [[Double]]
(varLocalPower', varRestPower') = CT.varMat local rest

restSig :: Sig.PSignal V.Vector Double
restSig = Sig.fromList rest

varRestPower :: Sig.PSignal2 V.Vector V.Vector Double
varRestPower = Sig.fromList2 varRestPower'

varLocalPower :: Sig.PSignal2 V.Vector V.Vector Double
varLocalPower = Sig.fromList2 varLocalPower'



to2DMatrix ::
  (Vec.Storage v1 a, Vec.Storage v2 (v1 a),
  Vec.FromList v1, Vec.FromList v2, Ord a) =>
  Map [a] a ->
  TC tr (Typ x y z)  (Data (v2 :> v1 :> Nil) a)
to2DMatrix =
  Sig.fromList2 . map snd . Map.toList . Map.foldWithKey f Map.empty 
  where f [line, _] v = Map.insertWith (++) line [v]
        f _ _ = error $ "to2DMatrix: more than two values in the key of map"

optimalMaps :: (Num a, Ord a, Ord node) =>
  Map Idx.State (Map (node, node) (Map [a] (a, a))) ->
  ( Sig.NSignal2 V.Vector V.Vector a,
    Sig.UTSignal2 V.Vector V.Vector a,
    Map (node, node) (Sig.PSignal2 V.Vector V.Vector a) )
optimalMaps =
  (\(eta, st, power) -> (head $ Map.elems eta, head $ Map.elems st, power))
  . unzip3Map
  . Map.map (h . unzip3Map)
  . Map.unionsWith (Map.unionWith max)
  . Map.elems
  . Map.mapWithKey f
  where f st = Map.map (Map.map (g st))
        g st (eta, power) = (eta, st, power)
        h (eta, st, power) =
          (to2DMatrix eta, to2DMatrix (Map.map unpackState st), to2DMatrix power)
        unpackState (Idx.State s) = fromIntegral s


givenSignals ::
  Ord node =>
  Sig.TSignal [] Double ->
  Map (node, node) (Sig.PSignal [] Double) ->
  [(node, node, Sig.PSignal [] Double)] ->
  Record.PowerRecord node [] Double
givenSignals time optps ns =
  Seq.addZeroCrossings
  $ Record.Record time
  $ Map.fromList
  $ Map.foldWithKey g ns' optps
  where fromto n0 n1 = Idx.PPos $ Idx.StructureEdge n0 n1
        ns' = map (\(n0, n1, sig) -> (fromto n0 n1, sig)) ns
        g (n0, n1) sig = ((fromto n0 n1, sig):)

solveAndCalibrateAvgEffWithGraph ::
  Sig.TSignal [] Double ->
  Sig.PSignal [] Double ->
  Sig.PSignal [] Double ->
  Map String (Double -> Double) ->
  ( Topo.StateFlowGraph Node,
    StateEnv.Complete Node (Data Nil Double) (Data Nil Double) ) ->
  IO ( Topo.StateFlowGraph Node,
    StateEnv.Complete Node (Data Nil Double) (Data Nil Double) )
solveAndCalibrateAvgEffWithGraph time prest plocal etaMap (stateFlowGraph, env) = do
  let sectionFilterTime ::  TC Scalar (Typ A T Tt) (Data Nil Double)
      sectionFilterTime = Sig.toScalar 0

      sectionFilterEnergy ::  TC Scalar (Typ A F Tt) (Data Nil Double)
      sectionFilterEnergy = Sig.toScalar 0

      optParams =
        One.OptimalEnvParams 
          etaMap
          sweepPts
          optimalPower
          stateFlowGraph

      optEtaWithPowers ::
        Map Idx.State (Map (Node, Node) (Map [Double] (Double, Double)))
      optEtaWithPowers = optimalEtasWithPowers optParams force env
      (_optEta, _optState, optPower) = optimalMaps optEtaWithPowers

      optPowerInterp ::
        Map (Node, Node) (Sig.PSignal [] Double)
      optPowerInterp = for optPower $ \powerStateOpt ->
        let f = Sig.interp2WingProfile "solveAndCalibrateAvgEffWithGraph"
                                       restSig varLocalPower
        in  Sig.tzipWith (f powerStateOpt) prest plocal


      givenSigs :: Record.PowerRecord Node [] Double
      givenSigs = givenSignals time optPowerInterp $
        (LocalRest, LocalNetwork, plocal) :
        (Rest, Network, prest) : []

      envSims =
        AppSim.solve
          System.topology
          System.etaAssignState
          etaMap
          givenSigs

      recZeroCross = envToPowerRecord time envSims

      sequencePowers :: SD.SequData (Record.PowerRecord System.Node [] Double)
      sequencePowers = Seq.genSequ recZeroCross

      sequenceFlowsFilt :: SD.SequData (Record.FlowRecord Node [] Double)
      sequenceFlowsFilt =
        snd
        $ SD.unzip
        $ SD.filter (Record.major sectionFilterEnergy sectionFilterTime . snd)
        $ fmap (\x -> (x, Record.partIntegrate x)) sequencePowers

      flowStatesWithAdj ::
        ( SD.SequData (Record.FlowState Node), 
          SD.SequData (Record.FlowRecord Node [] Double) )
      flowStatesWithAdj =
        SD.unzip
        $ fmap (\rec ->
                 let flowState = Flow.genFlowState rec
                 in  (flowState, Flow.adjustSigns System.topology flowState rec))
        sequenceFlowsFilt

      stateFlowEnvWithGraph ::
        ( Topo.StateFlowGraph Node,
          StateEnv.Complete Node (Data Nil Double) (Data Nil Double) )

      stateFlowEnvWithGraph =
        let sequ = Flow.genSequFlowTops System.topology (fst flowStatesWithAdj)
            envLocal = external initStorage 
                           (Seq.makeSeqFlowTopology sequ) (snd flowStatesWithAdj)
            e = second (fmap Arith.integrate) envLocal
            sm = snd $ StateFlow.stateMaps sequ
        in  ( StateFlow.stateGraphAllStorageEdges sequ,
              StateEnv.mapMaybe Result.toMaybe Result.toMaybe $
                StateFlow.envFromSequenceEnvResult sm e)

  Draw.xterm $ Draw.stateFlowGraph (fst stateFlowEnvWithGraph)

  PlotIO.record "Calculated Signals" DefaultTerm.cons show id recZeroCross

  Draw.xterm $ uncurry (Draw.stateFlowGraphWithEnv Draw.optionsDefault)
                           stateFlowEnvWithGraph
  return stateFlowEnvWithGraph




{-
solveAndCalibrateAvgEff ::
  (Sig.TSignal [] Double, [Sig.PSignal [] Double]) ->
  Map String (Double -> Double) ->
  ( Topo.StateFlowGraph Node,
    StateEnv.Complete Node (Data Nil Double) (Data Nil Double) ) ->
  [(Topo.StateFlowGraph Node,
    StateEnv.Complete Node (Data Nil Double) (Data Nil Double))]
solveAndCalibrateAvgEff sigs etaMap envWithGraph =
  List.iterate ( -- fmap (AppOpt.givenAverageWithoutState Optimisation.state0)
                 solveAndCalibrateAvgEffWithGraph sigs etaMap) 
               envWithGraph
-}

main :: IO()
main = do

  -- | Import Maps and power demand profiles

  tabEta <- Table.read "../maps/eta.txt"
  tabPower <- Table.read "../maps/power.txt"

  let etaMap = CT.makeEtaFunctions2D scaleTableEta tabEta
      initEnv = AppOpt.initialEnv System.Water System.stateFlowGraph


      (time, [pwind, psolar, phouse, pindustry]) =
        CT.getPowerSignalsWithSameTime tabPower
          ["wind", "solar", "house", "industry"]

      prest = Sig.scale restScale pwind
      plocal = Sig.offset 0.4 $ Sig.scale localScale $
        psolar Sig..+ Sig.makeDelta phouse Sig..+ Sig.makeDelta pindustry


  new1 <- solveAndCalibrateAvgEffWithGraph
            time prest plocal
            etaMap
            (System.stateFlowGraph, initEnv)

  new2 <- solveAndCalibrateAvgEffWithGraph
            time prest plocal
            etaMap
            new1

  new3 <- solveAndCalibrateAvgEffWithGraph
            time prest plocal
            etaMap
            new2

  _ <- solveAndCalibrateAvgEffWithGraph
            time prest plocal
            etaMap
            new3

  return ()