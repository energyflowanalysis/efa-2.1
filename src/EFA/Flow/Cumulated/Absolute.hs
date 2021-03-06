{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE FlexibleContexts #-}
module EFA.Flow.Cumulated.Absolute (
   module EFA.Flow.Cumulated.Absolute,
   Abs.liftF, Abs.liftF2,
   (=.=),
   ) where

import qualified EFA.Flow.Cumulated.EquationSystem as EqSys
import qualified EFA.Flow.Cumulated.Quantity as CumFlow
import qualified EFA.Flow.Cumulated.Variable as CumVar
import qualified EFA.Flow.Absolute as Abs
import EFA.Flow.Cumulated.EquationSystem ((=.=))

import qualified EFA.Equation.RecordIndex as RecIdx
import qualified EFA.Equation.Record as Record
import qualified EFA.Equation.Verify as Verify
import qualified EFA.Equation.Arithmetic as Arith
import EFA.Equation.Result(Result)

import qualified EFA.Graph.Topology.Node as Node

import qualified UniqueLogic.ST.TF.System as Sys

import qualified Control.Monad.Exception.Synchronous as ME

import Data.Tuple.HT (mapFst)


type
   EquationSystem mode node s a =
      EqSys.EquationSystem mode Record.Absolute node s a

type
   Expression mode node s a x =
      EqSys.Expression mode Record.Absolute node s a x


type
   EquationSystemIgnore node s a =
      EqSys.EquationSystem Verify.Ignore Record.Absolute node s a

type
   ExpressionIgnore node s a x =
      EqSys.Expression Verify.Ignore Record.Absolute node s a x

type VarAny node = CumVar.RecordAny Record.Absolute node


withExpressionGraph ::
   (Node.C node,
    Verify.GlobalVar mode v (VarAny node)) =>
   (CumFlow.Graph node (Expression mode node s v v) ->
    EquationSystem mode node s v) ->
   EquationSystem mode node s v
withExpressionGraph f =
   EqSys.withExpressionGraph $
      f . CumFlow.mapGraph (fmap (Record.unAbsolute . EqSys.unwrap))


solve ::
   (Eq a, Arith.Product a, Arith.ZeroTestable a, Node.C node) =>
   CumFlow.Graph node (Result a) ->
   (forall s. EquationSystem Verify.Ignore node s a) ->
   CumFlow.Graph node (Result a)
solve graph sys =
   CumFlow.mapGraph Record.unAbsolute $
   EqSys.solve (CumFlow.mapGraph Record.Absolute graph) sys

solveTracked ::
   (Verify.GlobalVar (Verify.Track output) a (VarAny node),
    Arith.Product a, Arith.ZeroTestable a, Node.C node) =>
   CumFlow.Graph node (Result a) ->
   (forall s. EquationSystem (Verify.Track output) node s a) ->
   (ME.Exceptional
      (Verify.Exception output)
      (CumFlow.Graph node (Result a)),
    Verify.Assigns output)
solveTracked graph sys =
   mapFst (fmap (CumFlow.mapGraph Record.unAbsolute)) $
   EqSys.solveTracked (CumFlow.mapGraph Record.Absolute graph) sys


constant ::
   (Sys.Value mode a) =>
   a -> Expression mode node s a a
constant = EqSys.constant

variable ::
   (Sys.Value mode a, CumFlow.Lookup idx, Node.C node) =>
   idx node -> Expression mode node s a a
variable = EqSys.variable . RecIdx.absolute


infix 0 .=, =%%=

(.=) ::
   (Sys.Value mode a, CumFlow.Lookup idx, Node.C node) =>
   idx node -> a -> EquationSystem mode node s a
evar .= val  =  variable evar =.= constant val


(=%%=) ::
   (Sys.Value mode a, CumFlow.Lookup idx, Node.C node) =>
   idx node -> idx node -> EquationSystem mode node s a
(=%%=) = (EqSys.=%%=)
