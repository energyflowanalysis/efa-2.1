{-# LANGUAGE TypeFamilies #-}
module EFA.Flow.Topology.Symbolic (
   module EFA.Flow.Topology.Symbolic,
   (.=), (%=), (=%%=),
   Verify.Ignore,
   ) where

import qualified EFA.Flow.Topology.EquationSystem as EqSys
import qualified EFA.Flow.Topology.Quantity as FlowTopo
import EFA.Flow.Topology.EquationSystem ((.=), (%=), (=%%=))

import qualified EFA.Graph.Topology.Index as Idx
import qualified EFA.Graph.Topology.Node as Node

import qualified EFA.Equation.Record as EqRecord
import qualified EFA.Equation.Verify as Verify
import qualified EFA.Equation.Variable as Var

import EFA.Utility (Pointed, point)

import qualified UniqueLogic.ST.TF.System as Sys

import Data.Monoid ((<>))


type
   Term recIdx term node =
      term (Idx.Record recIdx (Var.Signal node))

type
   EquationSystem mode rec node s term =
      EqSys.EquationSystem mode rec node s
         (Term (EqRecord.ToIndex rec) term node)


symbol ::
   Pointed term =>
   Idx.Record recIdx (Var.Signal node) ->
   Term recIdx term node
symbol = point

varSymbol ::
   (Pointed term, Var.SignalIndex idx) =>
   Idx.Record recIdx (idx node) -> Term recIdx term node
varSymbol idx =
   symbol (fmap Var.signalIndex idx)


given ::
   (Sys.Value mode t, t ~ Term recIdx term node,
    EqSys.Record rec, recIdx ~ EqRecord.ToIndex rec, Pointed term,
    Var.SignalIndex idx, FlowTopo.Lookup idx, Node.C node) =>
   Idx.Record recIdx (idx node) ->
   EquationSystem mode rec node s term
given idx =
   idx .= varSymbol idx


infixr 6 =<>

(=<>) ::
   (Sys.Value mode t, t ~ Term recIdx term node,
    EqSys.Record rec, recIdx ~ EqRecord.ToIndex rec, Pointed term,
    Var.SignalIndex idx, FlowTopo.Lookup idx, Node.C node) =>
   Idx.Record recIdx (idx node) ->
   EquationSystem mode rec node s term ->
   EquationSystem mode rec node s term
idx =<> eqsys = given idx <> eqsys