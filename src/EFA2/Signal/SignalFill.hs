{-# LANGUAGE TypeFamilies #-}

{- |
@zip@-based functions that automatically fill
the smallest dimensions with constant signals
in order to match different structures.

I expect that these functions are rarely used
and maybe we remove them eventually.
-}
module EFA2.Signal.SignalFill where

import EFA2.Signal.Signal
          (TC(TC), Sample, Arith, toSample, fromSample)

import qualified EFA2.Signal.Data as D
import EFA2.Signal.Data (Data, Nil, Zip)
import EFA2.Signal.Base (BSum(..), BProd(..))
import EFA2.Signal.Typ (TSum, TProd)

import Data.Function (($))
import qualified Prelude as P



zipWith ::
   (D.ZipWithFill c1 c2, Zip c1 c2 ~ c3,
    D.Storage c1 d1, D.Storage c2 d2, D.Storage c3 d3) =>
   (d1 -> d2 -> d3) ->
   TC s1 typ1 (Data c1 d1) ->
   TC s2 typ2 (Data c2 d2) ->
   TC (Arith s1 s2) typ3 (Data c3 d3)
zipWith f (TC da1) (TC da2) =
   TC $ D.zipWithFill f da1 da2

zip ::
   (D.ZipWithFill c1 c2, Zip c1 c2 ~ c3, (d1, d2) ~ d3,
    D.Storage c1 d1, D.Storage c2 d2, D.Storage c3 d3) =>
   TC s typ (Data c1 d1) ->
   TC s typ (Data c2 d2) ->
   TC (Arith s s) typ (Data c3 d3)
zip = zipWith (,)


----------------------------------------------------------------
-- Getyptes ZipWithFill
tzipWith ::
   (D.ZipWithFill c1 c2, Zip c1 c2 ~ c3,
    D.Storage c1 d1, D.Storage c2 d2, D.Storage c3 d3) =>
   (TC Sample typ1 (Data Nil d1) ->
    TC Sample typ2 (Data Nil d2) ->
    TC Sample typ3 (Data Nil d3)) ->
   TC s1 typ1 (Data c1 d1) ->
   TC s2 typ2 (Data c2 d2) ->
   TC (Arith s1 s2) typ3 (Data c3 d3)
tzipWith f = zipWith g
   where g x y = fromSample $ f (toSample x) (toSample y)

(.*) ::
   (TProd t1 t2 t3, D.ZipWithFill c1 c2, Zip c1 c2 ~ c3,
    D.Storage c1 a1, D.Storage c2 a2, D.Storage c3 a1, BProd a1 a2) =>
   TC s1 t1 (Data c1 a1) ->
   TC s2 t2 (Data c2 a2) ->
   TC (Arith s1 s2) t3 (Data c3 a1)
(.*) = zipWith (..*)

(./) ::
   (TProd t1 t2 t3, D.ZipWithFill c1 c2, Zip c1 c2 ~ c3,
    D.Storage c1 a1, D.Storage c2 a2, D.Storage c3 a1, BProd a1 a2) =>
   TC s1 t3 (Data c1 a1) ->
   TC s2 t2 (Data c2 a2) ->
   TC (Arith s1 s2) t1 (Data c3 a1)
(./) = zipWith (../)

(.+) ::
   (TSum t1 t2 t3, D.ZipWithFill c1 c2, Zip c1 c2 ~ c3,
    D.Storage c1 a, D.Storage c2 a, D.Storage c3 a, BSum a) =>
   TC s1 t1 (Data c1 a) ->
   TC s2 t2 (Data c2 a) ->
   TC (Arith s1 s2) t3 (Data c3 a)
(.+) = zipWith (..+)

(.-) ::
   (TSum t1 t2 t3, D.ZipWithFill c1 c2, Zip c1 c2 ~ c3,
    D.Storage c1 a, D.Storage c2 a, D.Storage c3 a, BSum a) =>
   TC s1 t3 (Data c1 a) ->
   TC s2 t2 (Data c2 a) ->
   TC (Arith s1 s2) t1 (Data c3 a)
(.-) = zipWith (..-)


infix 7 .*, ./
infix 6 .+,.-