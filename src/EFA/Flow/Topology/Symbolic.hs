{-# LANGUAGE TypeFamilies #-}
module EFA.Flow.Topology.Symbolic (
   module EFA.Flow.Topology.Symbolic,
   (.=), (%=), (=%%=),
   Verify.Ignore,
   ) where

import qualified EFA.Flow.Topology.EquationSystem as EqSys
import qualified EFA.Flow.Topology.Quantity as FlowTopo
import qualified EFA.Flow.Topology.Variable as TopoVar
import EFA.Flow.Topology.EquationSystem ((.=), (%=), (=%%=))

import qualified EFA.Graph.Topology.Node as Node

import qualified EFA.Equation.RecordIndex as RecIdx
import qualified EFA.Equation.Record as EqRecord
import qualified EFA.Equation.Verify as Verify

import EFA.Utility (Pointed, point)

import qualified UniqueLogic.ST.TF.System as Sys

import Data.Monoid ((<>))


type Term term recIdx node = term (RecIdx.Record recIdx (TopoVar.Signal node))


type
   EquationSystem mode rec node s term =
      EqSys.EquationSystem mode rec node s
         (Term term (EqRecord.ToIndex rec) node)


symbol ::
   Pointed term =>
   RecIdx.Record recIdx (TopoVar.Signal node) ->
   Term term recIdx node
symbol = point

varSymbol ::
   (Pointed term, TopoVar.Index idx) =>
   RecIdx.Record recIdx (idx node) -> Term term recIdx node
varSymbol idx =
   symbol (fmap TopoVar.index idx)


given ::
   (Sys.Value mode t, t ~ Term term recIdx node,
    EqSys.Record rec, recIdx ~ EqRecord.ToIndex rec, Pointed term,
    TopoVar.Index idx, FlowTopo.Lookup idx, Node.C node) =>
   RecIdx.Record recIdx (idx node) ->
   EquationSystem mode rec node s term
given idx =
   idx .= varSymbol idx


infixr 6 =<>

(=<>) ::
   (Sys.Value mode t, t ~ Term term recIdx node,
    EqSys.Record rec, recIdx ~ EqRecord.ToIndex rec, Pointed term,
    TopoVar.Index idx, FlowTopo.Lookup idx, Node.C node) =>
   RecIdx.Record recIdx (idx node) ->
   EquationSystem mode rec node s term ->
   EquationSystem mode rec node s term
idx =<> eqsys = given idx <> eqsys
