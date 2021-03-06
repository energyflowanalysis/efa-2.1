{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module EFA.Flow.EquationSystem where

import qualified EFA.Flow.Topology.Index as Idx

import qualified EFA.Equation.RecordIndex as RecIdx
import qualified EFA.Equation.Record as Record
import qualified EFA.Equation.Verify as Verify
import qualified EFA.Equation.SystemRecord as SysRecord
import qualified EFA.Equation.Arithmetic as Arith
import EFA.Equation.SystemRecord (Expr, Record, Wrap(Wrap, unwrap))
import EFA.Equation.Result (Result)
import EFA.Equation.Arithmetic
          (Sum, (~+), (~-),
           Product, (~*), (~/),
           Constant, zero, ZeroTestable,
           Integrate, Scalar, integrate,
           Scale, scale)

import EFA.Report.FormatValue (FormatValue)

import EFA.Utility ((>>!))

import qualified UniqueLogic.ST.TF.Expression as Expr
import qualified UniqueLogic.ST.TF.System as Sys
import UniqueLogic.ST.TF.Expression ((=:=))


import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Reader (ReaderT)
import Control.Monad.Trans.Writer (WriterT, tell)

import Control.Monad.ST (ST)

import Control.Applicative (Applicative, pure, liftA, liftA2)

import qualified Data.NonEmpty as NonEmpty

import Data.Traversable (sequenceA, for)
import Data.Foldable (foldMap)
import Data.Monoid (Monoid, (<>), mempty, mappend)

import qualified Prelude as P
import Prelude hiding (sqrt)


type Writer mode s = WriterT (SysRecord.System mode s) (ST s)

newtype System mode s = System {runSystem :: Writer mode s ()}

instance Monoid (System mode s) where
   mempty = System $ return ()
   mappend (System x) (System y)  =  System $ x >>! y


infix 0 =&=

(=&=) ::
   (Record rec, Sys.Value mode a) =>
   Expr mode rec s a ->
   Expr mode rec s a ->
   System mode s
x =&= y  =  System $ tell $ SysRecord.equal x y


globalVariable ::
   (Verify.GlobalVar mode a (RecIdx.Record (Record.ToIndex rec) var),
    Sum a, Record rec, FormatValue var) =>
   var ->
   Writer mode s (SysRecord.Variable mode rec s a)
globalVariable var = do
   vars <-
      lift $ for Record.indices $ \recIdx ->
         Verify.globalVariable $ RecIdx.Record recIdx var
   tell $ SysRecord.rules vars
   return vars

globalVariableFromResult ::
   (Verify.GlobalVar mode a (RecIdx.Record (Record.ToIndex rec) var),
    Sum a, Record rec, FormatValue var) =>
   var -> rec (Result a) ->
   Writer mode s (SysRecord.Variable mode rec s a)
globalVariableFromResult varIdx val = do
   var <- globalVariable varIdx
   tell (SysRecord.equalResult var val)
   return var


localVariable ::
   (Record rec, Verify.LocalVar mode a, Sum a) =>
   Writer mode s (SysRecord.Variable mode rec s a)
localVariable = do
   vars <- lift $ sequenceA $ pure Verify.localVariable
   tell $ SysRecord.rules vars
   return vars

withLocalVar ::
   (Verify.LocalVar mode x, Sum x, Record rec) =>
   (Expr mode rec s x -> System mode s) ->
   System mode s
withLocalVar f = System $ do
   v <- localVariable
   case f $ SysRecord.exprFromVariable v of
      System act -> act


splitFactors ::
   (Verify.LocalVar mode x, Product x, ZeroTestable x, Record rec,
    rx ~ Expr mode rec s x) =>
   rx -> (secnode -> rx) ->
   rx -> (secnode -> rx) ->
   NonEmpty.T [] secnode -> System mode s
splitFactors s ef one xf ns =
   (s =&= NonEmpty.foldl1 (~+) (fmap ef ns))
   <>
   (one =&= NonEmpty.foldl1 (~+) (fmap xf ns))
   <>
   (foldMap (\n -> ef n =&= s ~* xf n) ns)

mixSumRules, mixFactorRules ::
   (Sys.Value mode v, Sum v, Record rec) =>
   Expr mode rec s v -> System mode s
mixSumRules =
   System . tell . SysRecord.mixSumRules . unwrap
mixFactorRules =
   System . tell . SysRecord.mixLevelRules Nothing . unwrap

mixLevelRules ::
   (Sys.Value mode v, Sum v, Record rec) =>
   Idx.Direction -> Expr mode rec s v -> System mode s
mixLevelRules dir =
   System . tell . SysRecord.mixLevelRules (Just dir) . unwrap



type Ctx mode vars s = ReaderT vars (Writer mode s)

type
   Expression mode vars s x =
      Context mode vars s (Expr.T mode s x)

type
   RecordExpression mode vars rec s x =
      Context mode vars s (SysRecord.Expr mode rec s x)


newtype Context mode vars s x = Context (Ctx mode vars s x)
   deriving (Functor, Applicative)

newtype
   VariableSystem mode vars s =
      VariableSystem {runVariableSystem :: Ctx mode vars s ()}

instance Monoid (VariableSystem mode vars s) where
   mempty = VariableSystem $ return ()
   mappend (VariableSystem x) (VariableSystem y) =
      VariableSystem $ x >>! y



liftF ::
   (Sys.Value mode y, Record rec, Sum y) =>
   (x -> y) ->
   RecordExpression mode var rec s x ->
   RecordExpression mode var rec s y
liftF = liftA . SysRecord.lift1 . Expr.fromRule2 . Sys.assignment2

liftF2 ::
   (Sys.Value mode z, Record rec, Sum z) =>
   (x -> y -> z) ->
   RecordExpression mode var rec s x ->
   RecordExpression mode var rec s y ->
   RecordExpression mode var rec s z
liftF2 = liftA2 . SysRecord.lift2 . Expr.fromRule3 . Sys.assignment3


instance (Sum x) => Sum (Context mode vars s x) where
   (~+) = liftA2 (~+)
   (~-) = liftA2 (~-)
   negate = fmap Arith.negate

instance (Product x) => Product (Context mode vars s x) where
   (~*) = liftA2 (~*)
   (~/) = liftA2 (~/)
   recip = fmap Arith.recip
   constOne = fmap Arith.constOne

instance (Constant x) => Constant (Context mode vars s x) where
   zero = pure zero
   fromInteger  = pure . Arith.fromInteger
   fromRational = pure . Arith.fromRational

instance (Integrate x) => Integrate (Context mode vars s x) where
   type Scalar (Context mode vars s x) = Context mode vars s (Scalar x)
   integrate = fmap integrate

instance (Scale x) => Scale (Context mode vars s x) where
   scale = liftA2 scale



instance (Num x) => Num (Context mode vars s x) where
   fromInteger = pure . fromInteger

   (*) = liftA2 (*)
   (+) = liftA2 (+)
   (-) = liftA2 (-)

   abs = fmap abs
   signum = fmap signum


instance (Fractional x) => Fractional (Context mode vars s x) where
   fromRational = pure . fromRational
   (/) = liftA2 (/)

sqrt ::
   (Sys.Value mode x, Sum x, Floating x, Record rec) =>
   RecordExpression mode vars rec s x ->
   RecordExpression mode vars rec s x
sqrt = liftF P.sqrt


infix 0 =.=, =%=

(=.=) ::
   (Sys.Value mode x) =>
   Expression mode vars s x ->
   Expression mode vars s x ->
   VariableSystem mode vars s
(Context xs) =.= (Context ys) =
   VariableSystem $ lift . tell . SysRecord.System =<< liftA2 (=:=) xs ys

(=%=) ::
   (Sys.Value mode x, Record rec) =>
   RecordExpression mode vars rec s x ->
   RecordExpression mode vars rec s x ->
   VariableSystem mode vars s
(Context xs) =%= (Context ys) =
   VariableSystem $ lift . tell =<< liftA2 SysRecord.equal xs ys


join ::
   Context mode vars s (VariableSystem mode vars s) ->
   VariableSystem mode vars s
join (Context m) =
   VariableSystem $ m >>= \(VariableSystem sys) -> sys


constant ::
   (Sys.Value mode x) =>
   x -> Expression mode vars s x
constant = pure . Expr.constant

constantRecord ::
   (Sys.Value mode x, Record rec) =>
   rec x -> RecordExpression mode vars rec s x
constantRecord = pure . Wrap . fmap Expr.constant
