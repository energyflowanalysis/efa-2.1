{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE KindSignatures #-}


module Modules.Optimisation.Base where

import qualified Modules.Optimisation as Optimisation
import qualified Modules.Utility as ModUt

import qualified EFA.Application.DoubleSweep as DoubleSweep
import qualified EFA.Application.ReqsAndDofs as ReqsAndDofs
import qualified EFA.Application.Type as Type
import qualified EFA.Application.OneStorage as One
import qualified EFA.Application.Sweep as Sweep
import qualified EFA.Application.Optimisation as AppOpt
import qualified EFA.Application.Utility as AppUt
import EFA.Application.Type (EnvResult)

import qualified EFA.Flow.Topology.Record as TopoRecord
import qualified EFA.Flow.Topology.Quantity as TopoQty
import qualified EFA.Flow.Topology.Index as TopoIdx

import qualified EFA.Flow.State.Index as StateIdx
import qualified EFA.Flow.State.Quantity as StateQty
import qualified EFA.Flow.State as State

import qualified EFA.Flow.Sequence as Sequence
import qualified EFA.Flow.Sequence.Quantity as SeqQty

import qualified EFA.Flow.Part.Map as PartMap
import qualified EFA.Flow.Storage as Storage

import qualified EFA.Flow.SequenceState.Index as Idx

import qualified EFA.Graph as Graph
import qualified EFA.Graph.Topology.Node as Node

import qualified EFA.Signal.Signal as Sig
import qualified EFA.Signal.Record as Record
import qualified EFA.Signal.Sequence as Sequ
import qualified EFA.Signal.Vector as Vec
import EFA.Signal.Data (Data(Data), Nil, (:>))

import qualified EFA.Equation.Arithmetic as Arith
import EFA.Equation.Result (Result(Determined))

import qualified Data.Map as Map; import Data.Map (Map)
import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Vector.Unboxed as UV
import Data.Vector (Vector)
import Data.Monoid (Monoid)

import Control.Monad (join)
import Control.Applicative (liftA2)


perStateSweep ::
  (Node.C node, Show node,
   Ord a, Show a, UV.Unbox a, Arith.ZeroTestable (sweep vec a),
   Arith.Product (sweep vec a), Arith.Constant a,
   Sweep.SweepVector vec a, Sweep.SweepMap sweep vec a a,
   Sweep.SweepClass sweep vec a,
   Monoid (sweep vec Bool),
   Sweep.SweepMap sweep vec a Bool,
   Sweep.SweepClass sweep vec Bool) =>
  One.SystemParams node a ->
  One.OptimisationParams node list sweep vec a ->
  StateQty.Graph node (Result (sweep vec a)) (Result (sweep vec a)) ->
  Map Idx.State (Map (list a) (Type.PerStateSweep node sweep vec a))
perStateSweep sysParams optParams stateFlowGraph  =
  Map.mapWithKey f states
  where states = StateQty.states stateFlowGraph
        reqsAndDofs = map TopoIdx.Power
                      $ ReqsAndDofs.unReqs (One.reqsPos optParams)
                        ++ ReqsAndDofs.unDofs (One.dofsPos optParams)

        f state _ = DoubleSweep.doubleSweep solveFunc (One.points optParams)
          where solveFunc =
                  Optimisation.solve
                    optParams
                    reqsAndDofs
                    (AppOpt.eraseXAndEtaFromState state stateFlowGraph)
                    (One.etaAssignMap sysParams)
                    (One.etaMap sysParams)
                    state
                    


forcing ::
  (Ord node, Show node,
   Sweep.SweepClass sweep vec a,
   Arith.Sum (sweep vec a),
   Sweep.SweepMap sweep vec a a,
   Arith.Constant a) =>
  Map node (One.SocDrive a)->
  One.OptimisationParams node list sweep vec a ->
  Idx.State ->
  Map Idx.State (Map node (Maybe (sweep vec a))) ->
  Result (sweep vec a)
forcing balanceForcing params state m = Determined $
  case Map.lookup state m of
    Nothing ->
      error $ "forcing failed, because state not found: " ++ show state
    Just powerMap ->
        Map.foldWithKey f zero balanceForcing
      where
        zero = Sweep.fromRational (One.sweepLength params) Arith.zero

        f stoNode forcingFactor acc = acc Arith.~+
          maybe (error $ "forcing failed, because node not found: " ++ show stoNode)
                (Sweep.map (One.getSocDrive forcingFactor Arith.~*))
                (join $ Map.lookup stoNode powerMap)


optimalObjectivePerState ::
  (Ord a, Arith.Constant a, Arith.Sum a, UV.Unbox a,
   Show node, Node.C node, Monoid (sweep UV.Vector  Bool),
   Ord (sweep UV.Vector  a),
   Arith.Product (sweep UV.Vector  a),
   Sweep.SweepVector UV.Vector  Bool,
   Sweep.SweepClass sweep UV.Vector  Bool,
   Sweep.SweepMap sweep UV.Vector  a Bool,
   Sweep.SweepVector UV.Vector  a,
   Sweep.SweepClass sweep UV.Vector  a,
   Sweep.SweepMap sweep UV.Vector  a a) =>
  One.OptimisationParams node list sweep UV.Vector a ->
  Map node (One.SocDrive a)->  
  Map Idx.State (Map (list a) (Type.PerStateSweep node sweep UV.Vector a)) ->
  Map Idx.State (Map (list a) (Maybe (a, a, EnvResult node a)))
optimalObjectivePerState params balanceForcing =
  Map.mapWithKey $
    Map.map
    . DoubleSweep.optimalSolutionState2
    . forcing balanceForcing params




expectedValuePerState ::
  (UV.Unbox a, 
   Arith.Constant a,
   Sweep.SweepClass sweep UV.Vector a,
   Sweep.SweepClass sweep UV.Vector Bool) =>
  Map Idx.State (Map (list a) (Type.PerStateSweep node sweep UV.Vector a)) ->
  Map Idx.State (Map (list a) (Maybe a))
expectedValuePerState =
  Map.map (Map.map DoubleSweep.expectedValue)

selectOptimalState ::
  (Ord a,Arith.Sum a,Show (One.StateForcing a), Show a) =>
  Map Idx.State (One.StateForcing a) -> 
  Map Idx.State (Map [a] (Maybe (a, a, EnvResult node a))) ->
  Map [a] (Maybe (a, a, Idx.State, EnvResult node a))
selectOptimalState stateForcing stateMap = if (Map.keys stateForcing) == (Map.keys stateMap) then
  List.foldl1' (Map.unionWith (liftA2 $ ModUt.maxBy ModUt.fst4))
  $ map (\(st, m) -> Map.map (fmap (\(objVal, eta, env) -> (objVal Arith.~+ (One.unpackStateForcing $ stateForcing Map.! st), eta, st, env))) m)
  $ Map.toList stateMap
  else error ("Error in findOtimalState - StateMap and StateForcings have different State Keys: " 
              ++ show stateForcing  ++ "\n" ++ show stateMap)

envToPowerRecord ::
  (Ord node) =>
  TopoQty.Section node (Result (Data (v :> Nil) a)) ->
  Record.PowerRecord node v a
envToPowerRecord =
  TopoRecord.sectionToPowerRecord
  . TopoQty.mapSection (AppUt.checkDetermined "envToPowerRecord")


convertRecord ::
  (Vec.Storage v d2, Vec.Storage t d2, Vec.Storage v d1,
   Vec.Storage t d1, Vec.Convert t v) =>
  Record.Record s1 s2 t1 t2 id t d1 d2 ->
  Record.Record s1 s2 t1 t2 id v d1 d2
convertRecord (Record.Record time sigMap) =
  Record.Record (Sig.convert time) (Map.map Sig.convert sigMap)


consistentRecord ::
  (Ord t5, Show t5, Arith.Constant t5) =>
  Record.Record t t3 t1 t4 k [] t2 t5 -> Bool
consistentRecord (Record.Record _ m) =
  case Map.elems m of
       [xs, ys] -> consistentIndices xs ys
       zs -> error $ "consistentRecord: more or less than exactly two signals: "
                     ++ show zs
  where consistentIndices (Sig.TC (Data xs)) (Sig.TC (Data ys)) =
          let zs = xs ++ ys
          in all (<= Arith.zero) zs || all (Arith.zero <=) zs


consistentSection ::
  (Ord t5, Show t5, Node.C node, Arith.Constant t5) =>
  One.SystemParams node a ->
  Sequ.Section (Record.Record t t3 t1 t4 (TopoIdx.Position node) [] t2 t5) ->
  Bool
consistentSection sysParams (Sequ.Section _ _ rec) =
  let recs = map f $ Graph.edges $ One.systemTopology sysParams
      f (Graph.DirEdge fr to) =
        Record.extract [TopoIdx.ppos fr to, TopoIdx.ppos to fr] rec
  in all consistentRecord recs


filterPowerRecordList ::
  (Ord a, Show a, Arith.Constant a, Node.C node) =>
  One.SystemParams node a ->
  Sequ.List (Record.PowerRecord node [] a) ->
  ( Sequ.List (Record.PowerRecord node [] a),
    Sequ.List (Record.PowerRecord node [] a) )
filterPowerRecordList sysParams (Sequ.List recs) =
  let (ok, bad) = List.partition (consistentSection sysParams) recs
  in (Sequ.List ok, Sequ.List bad)



-- HH: hier sollen tatsächlich params und ppos getrennt hineingefuehrt werden,
-- damit man die Funktion auch für andere Positionen verwenden kann.

signCorrectedOptimalPowerMatrices ::
  (Ord a, Arith.Sum a, Arith.Constant a, Show node, Ord node,
   Vec.Storage varVec (Maybe (Result a)),
   Vec.FromList varVec) =>
  One.SystemParams node a ->
  Map [a] (Maybe (a, a, Idx.State, EnvResult node a)) ->
  ReqsAndDofs.Dofs (TopoIdx.Position node) ->
  Map (TopoIdx.Position node) (Sig.PSignal2 Vector varVec (Maybe (Result a)))
signCorrectedOptimalPowerMatrices systemParams m (ReqsAndDofs.Dofs ppos) =
  Map.fromList $ map g ppos
  where g pos = (pos, ModUt.to2DMatrix $ Map.map f m)
          where f Nothing = Nothing
                f (Just (_, _, st, graph)) =
                  case StateQty.lookup (StateIdx.powerFromPosition st pos) graph of
                       Just sig -> Just $
                         if isFlowDirectionPositive systemParams st pos graph
                            then sig
                            else fmap Arith.negate sig
                       _ -> fmap (const (Determined Arith.zero))
                                 (getEdgeFromPosition st pos graph)






isFlowDirectionPositive ::
  (Ord node, Show node) =>
  One.SystemParams node a ->
  Idx.State ->
  TopoIdx.Position node ->
  EnvResult node a ->
  Bool
isFlowDirectionPositive sysParams state (TopoIdx.Position f t) graph =
  case Set.toList es of
       [Graph.DirEdge fe te] ->
         case flowTopoEs of
              Just set ->
                case ( Set.member (Graph.EDirEdge $ Graph.DirEdge fe te) set,
                       Set.member (Graph.EDirEdge $ Graph.DirEdge te fe) set ) of
                     (True, False)  -> True
                     (False, True)  -> False
                     tf -> error $ "isFlowDirectionPositive: "
                                   ++ "inconsisten flow graph " ++ show tf
              _ -> error $ "State (" ++ show state ++ ") not found"
       _ -> error $ "More or less than exactly one edge between nodes "
                    ++ show f ++ " and " ++ show t ++ " in " ++ show es
  where flowTopoEs = fmap Graph.edgeSet $ ModUt.getFlowTopology state graph
        topo = One.systemTopology sysParams
        es = Graph.adjacentEdges topo f
               `Set.intersection` Graph.adjacentEdges topo t


getEdgeFromPosition ::
  (Ord (e a), Ord a, Show (e a), Show a, Graph.Edge e) =>
  Idx.State ->
  TopoIdx.Position a ->
  State.Graph a e sectionLabel nl storageLabel el carryLabel ->
  Maybe (e a)
getEdgeFromPosition state (TopoIdx.Position f t) =
  let g flowTopo =
        case Set.toList es of
             [e] -> e
             _ -> error $ "More or less than exactly one edge between nodes "
                          ++ show f ++ " and " ++ show t ++ " in " ++ show es
        where es = Graph.adjacentEdges flowTopo f
                     `Set.intersection` Graph.adjacentEdges flowTopo t
  in fmap g . ModUt.getFlowTopology state



extractOptimalPowerMatricesPerState ::
  (Ord b, Ord node,
  Vec.Storage vec (vec (Maybe (Result a))),
  Vec.Storage vec (Maybe (Result a)),
  Vec.FromList vec) => 
  Map Idx.State (Map [b] (Maybe (a1, EnvResult node a))) ->
  [TopoIdx.Position node] ->
  Map (TopoIdx.Position node)
      (Map Idx.State (Sig.PSignal2 Vector vec (Maybe (Result a))))
extractOptimalPowerMatricesPerState m ppos =
  Map.map (Map.map ModUt.to2DMatrix)
  $ Map.fromList $ map (\p -> (p, Map.mapWithKey (f p) m)) ppos
  where f p st matrixMap = Map.map g matrixMap
          where pos = StateIdx.powerFromPosition st p
                g = join . fmap (StateQty.lookup pos . snd)


seqFlowBalance ::
  (Arith.Sum a, UV.Unbox a, Arith.Sum (sweep vec a)) =>
  Sequence.Graph node structEdge sectionLabel nodeLabel
                 (Result (sweep vec a)) boundaryLabel structLabel edgeLabel ->
  Map node (Result (sweep vec a))
seqFlowBalance = fmap (f . Storage.nodes . fst) . SeqQty.storages
  where f pm = liftA2 (Arith.~-) (PartMap.exit pm) (PartMap.init pm)


stateFlowBalance ::
  (Arith.Sum a, UV.Unbox a, Arith.Sum (sweep vec a)) =>
  EnvResult node (sweep vec a) ->
  Map node (Result (sweep vec a))
stateFlowBalance = fmap (f . Storage.nodes) . StateQty.storages
  where f pm = liftA2 (Arith.~-) (PartMap.exit pm) (PartMap.init pm)
