{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE Rank2Types #-}


module EFA.Signal.Vector where

import qualified Data.Vector.Unboxed as UV
import qualified Data.Vector as V

import qualified Data.List as L
import qualified Data.List.HT as LH

import Data.Maybe.HT (toMaybe)
import Data.Eq (Eq((==)))
import Data.Function ((.), ($), id, flip)
import Data.Maybe (Maybe)
import Data.Bool (Bool(False, True), (&&), not)
import Prelude (Int, Ord, error, (++), (-), Show, show)


{- |
We could replace this by suitable:Suitable.
-}
class Storage vector y where
   data Constraints vector y :: *
   constraints :: vector y -> Constraints vector y

instance Storage [] y where
   data Constraints [] y = ListConstraints
   constraints _ = ListConstraints

instance Storage V.Vector y where
   data Constraints V.Vector y = VectorConstraints
   constraints _ = VectorConstraints

instance (UV.Unbox y) => Storage UV.Vector y where
   data Constraints UV.Vector y = UV.Unbox y => UnboxedVectorConstraints
   constraints _ = UnboxedVectorConstraints

readUnbox ::
   (UV.Unbox a => UV.Vector a -> b) ->
   (Storage UV.Vector a => UV.Vector a -> b)
readUnbox f x = case constraints x of UnboxedVectorConstraints -> f x

writeUnbox ::
   (UV.Unbox a => UV.Vector a) ->
   (Storage UV.Vector a => UV.Vector a)
writeUnbox x =
   let z = case constraints z of UnboxedVectorConstraints -> x
   in  z



--------------------------------------------------------------
-- Singleton Class

{-# DEPRECATED head, tail "use viewL instead" #-}
{-# DEPRECATED last, init "use viewR instead" #-}

class Singleton vec where
   maximum :: (Ord d, Storage vec d) => vec d -> d
   minimum :: (Ord d, Storage vec d) => vec d -> d
   singleton :: (Storage vec d) => d -> vec d
   empty :: (Storage vec d) => vec d
   append :: (Storage vec d) => vec d -> vec d -> vec d
   concat :: (Storage vec d) => [vec d] -> vec d
   head :: (Storage vec d) => vec d -> d
   tail :: (Storage vec d) => vec d -> vec d
   last :: (Storage vec d) => vec d -> d
   init :: (Storage vec d) => vec d -> vec d
   viewL :: (Storage vec d) => vec d -> Maybe (d, vec d)
   viewR :: (Storage vec d) => vec d -> Maybe (vec d, d)
   all :: (Storage vec d) => (d -> Bool) -> vec d -> Bool
   any :: (Storage vec d) => (d -> Bool) -> vec d -> Bool

instance Singleton V.Vector where
   maximum x = V.maximum x
   minimum x = V.minimum x
   singleton x = V.singleton x
   empty = V.empty
   append = (V.++)
   concat = V.concat
   head = V.head
   tail = V.tail
   last = V.last
   init = V.init
   viewL xs = toMaybe (not $ V.null xs) (V.head xs, V.tail xs)
   viewR xs = toMaybe (not $ V.null xs) (V.init xs, V.last xs)
   all = V.all
   any = V.any

instance Singleton UV.Vector where
   maximum x = readUnbox UV.maximum x
   minimum x = readUnbox UV.minimum x
   singleton x = writeUnbox (UV.singleton x)
   empty = writeUnbox UV.empty
   append = readUnbox (UV.++)
   concat xs = writeUnbox (UV.concat xs)
   head = readUnbox UV.head
   tail = readUnbox UV.tail
   last = readUnbox UV.last
   init = readUnbox UV.init
   viewL = readUnbox (\xs -> toMaybe (not $ UV.null xs) (UV.head xs, UV.tail xs))
   viewR = readUnbox (\xs -> toMaybe (not $ UV.null xs) (UV.init xs, UV.last xs))
   all f = readUnbox (UV.all f)
   any f = readUnbox (UV.any f)

instance Singleton [] where
   maximum x = L.maximum x
   minimum x = L.minimum x
   singleton x = [x]
   empty = []
   append = (++)
   concat = L.concat
   head = L.head
   tail = L.tail
   last = L.last
   init = L.init
   viewL = LH.viewL
   viewR = LH.viewR
   all = L.all
   any = L.any


------------------------------------------------------------
-- | Functor
class Walker vec where
   map :: (Storage vec a, Storage vec b) => (a -> b) -> vec a -> vec b
   foldr :: (Storage vec a) => (a -> b -> b) -> b -> vec a -> b
   foldl :: (Storage vec a) => (b -> a -> b) -> b -> vec a -> b
   {- |
   For fully defined values it holds
   @equalBy f xs ys  ==  (and (zipWith f xs ys) && length xs == length ys)@
   but for lists @equalBy@ is lazier.
   -}
   equalBy :: (Storage vec a, Storage vec b) => (a -> b -> Bool) -> vec a -> vec b -> Bool

instance Walker [] where
   map = L.map
   foldr = L.foldr
   foldl = L.foldl'
   equalBy f =
      let go (x:xs) (y:ys) = f x y && go xs ys
          go [] [] = True
          go _ _ = False
      in  go

instance Walker UV.Vector where
   map f xs = writeUnbox (readUnbox (UV.map f) xs)
   foldr f a = readUnbox (UV.foldr f a)
   foldl f a = readUnbox (UV.foldl' f a)
   equalBy f =
      readUnbox (\xs ->
      readUnbox (\ys ->
         UV.length xs == UV.length ys  &&  UV.and (UV.zipWith f xs ys)))

instance Walker V.Vector where
   map = V.map
   foldr = V.foldr
   foldl = V.foldl'
   equalBy f xs ys =
      V.length xs == V.length ys  &&  V.and (V.zipWith f xs ys)


------------------------------------------------------------
-- | Zipper

class Zipper vec where
   zipWith ::
      (Storage vec a, Storage vec b, Storage vec c) =>
      (a -> b -> c) -> vec a -> vec b -> vec c

zip ::
   (Zipper vec, Storage vec a, Storage vec b, Storage vec (a,b)) =>
   vec a -> vec b -> vec (a, b)
zip = zipWith (,)


instance Zipper [] where
   zipWith f x y = L.zipWith f x y -- if V.lenCheck x y then zipWith f x y else error "Error in V.lenCheck List -- unequal Length"

instance Zipper V.Vector where
   zipWith f x y = V.zipWith f x y -- if V.lenCheck x y then V.zipWith f x y else error "Error in V.lenCheck V -- unequal Length"

instance Zipper UV.Vector where
   zipWith f xs ys = writeUnbox (readUnbox (readUnbox (UV.zipWith f) xs) ys)
   -- if V.lenCheck x y then UV.zipWith f x y else error "Error in V.lenCheck UV -- unequal Length"


deltaMap ::
   (Storage vec b, Storage vec c, Singleton vec, Zipper vec) =>
   (b -> b -> c) -> vec b -> vec c
deltaMap f l = zipWith f l (tail l)

deltaMapReverse ::
   (Storage vec b, Storage vec c, Singleton vec, Zipper vec) =>
   (b -> b -> c) -> vec b -> vec c
deltaMapReverse f l = zipWith f (tail l) l


------------------------------------------------------------
-- | Zipper4

class Zipper4 vec where
   zipWith4 ::
      (Storage vec a, Storage vec b, Storage vec c, Storage vec d, Storage vec e) =>
      (a -> b -> c -> d -> e) -> vec a -> vec b -> vec c -> vec d -> vec e

instance Zipper4 [] where
   zipWith4 f w x y z = L.zipWith4 f w x y z -- if V.lenCheck x y then zipWith f x y else error "Error in V.lenCheck List -- unequal Length"

instance Zipper4 V.Vector where
   zipWith4 f w x y z = V.zipWith4 f w x y z -- if V.lenCheck x y then V.zipWith f x y else error "Error in V.lenCheck V -- unequal Length"

instance Zipper4 UV.Vector where
   zipWith4 f w x y z =
      writeUnbox (readUnbox (readUnbox (readUnbox (readUnbox (UV.zipWith4 f) w) x) y) z) -- if V.lenCheck x y then UV.zipWith f x y else error "Error in V.lenCheck UV -- unequal Length"


{-
deltaMap2:: (a -> a -> b -> b -> c)  -> vec a -> vec a -> vec b  -> vec b -> vec c
deltaMap2 f xs ys = zipWith4 f xs (tail xs) ys (tail ys)

deltaMapReverse2 :: (a -> a -> b -> b -> c) -> vec a -> vec a -> vec b  -> vec b -> vec c
deltaMapReverse2 f xs ys = zipWith4 f (tail xs) xs (tail ys) ys
-}

--------------------------------------------------------------
-- Vector conversion
class Convert c1 c2 where
   convert :: (Storage c1 a, Storage c2 a) => c1 a -> c2 a

instance Convert UV.Vector V.Vector where
   convert x = readUnbox UV.convert x

instance Convert V.Vector UV.Vector where
   convert x = writeUnbox (V.convert x)

instance Convert UV.Vector UV.Vector where
   convert = id

instance Convert V.Vector V.Vector where
   convert = id

instance Convert [] [] where
   convert = id

instance Convert [] UV.Vector where
   convert x = writeUnbox (UV.fromList x)

instance Convert [] V.Vector where
   convert x = V.fromList x

instance Convert V.Vector [] where
   convert x = V.toList x

instance Convert UV.Vector [] where
   convert x = readUnbox UV.toList x

--------------------------------------------------------------
-- Length & Length Check

class Len s where
   len :: s -> Int

instance Len [d] where
   len = L.length

instance Len (V.Vector d) where
   len = V.length

instance UV.Unbox d => Len (UV.Vector d) where
   len = UV.length


lenCheck ::
   (Len v1, Len v2) =>
   v1 -> v2 -> Bool
lenCheck x y = len x == len y


class Length vec where
   length :: Storage vec a => vec a -> Int

instance Length [] where
   length = L.length

instance Length V.Vector where
   length = V.length

instance Length UV.Vector where
   length = readUnbox UV.length


--------------------------------------------------------------
-- Transpose Class
class Transpose v1 v2 where
   transpose :: (Storage v1 d) => v2 (v1 d) -> v2 (v1 d)

instance Transpose [] [] where
   transpose x = if L.all (== L.head lens) lens then L.transpose x else error "Error in V.Transpose -- unequal length"
                         where lens = map len x

instance Transpose V.Vector V.Vector where
   transpose xs = if all (== len0) lens then V.map (flip V.map xs) fs else error "Error in V.Transpose -- unequal length"
    where fs = V.map (flip (V.!)) $ V.fromList [0..len0-1]
          lens = V.map len xs
          len0 = V.head lens

instance Transpose UV.Vector V.Vector where
   transpose xs =
      case constraints $ head xs of
         UnboxedVectorConstraints ->
            let fs = V.map (flip (UV.!)) $ V.fromList [0..len0-1]
                lens = V.map len xs
                len0 = V.head lens
            in  if all (== len0) lens
                  then V.map (convert . flip V.map xs) fs
                  else error "Error in V.Transpose -- unequal length"



class FromList vec where
   fromList :: (Storage vec d) => [d] -> vec d
   toList :: (Storage vec d) => vec d -> [d]

instance FromList [] where
   fromList x = x
   toList x = x

instance FromList V.Vector where
   fromList = V.fromList
   toList = V.toList

instance FromList UV.Vector where
   fromList x = writeUnbox (UV.fromList x)
   toList x = readUnbox UV.toList x



class Sort vec where
   sort :: (Ord d, Storage vec d) => vec d -> vec d

instance Sort [] where
   sort = L.sort

instance Sort V.Vector where
   sort = V.fromList . L.sort . V.toList

instance Sort UV.Vector where
   sort = readUnbox (UV.fromList . L.sort . UV.toList)


class Filter vec where
   filter :: Storage vec d => (d -> Bool) -> vec d -> vec d

instance Filter [] where
   filter = L.filter

instance Filter V.Vector where
   filter = V.filter

instance Filter UV.Vector where
   filter f = readUnbox (UV.filter f)


class Lookup vec where
   lookUp :: (Storage vec d, Eq d) => vec d -> [Int] -> vec d

instance Lookup [] where
   lookUp xs = lookUpGen (V.fromList xs V.!? )

instance Lookup V.Vector where
   lookUp xs = V.fromList . lookUpGen (xs V.!?)

instance Lookup UV.Vector where
   lookUp =
      readUnbox (\xs -> UV.fromList . lookUpGen (xs UV.!?))

{-# INLINE lookUpGen #-}
lookUpGen :: Show i => (i -> Maybe a) -> [i] -> [a]
lookUpGen look idxs =
   case LH.partitionMaybe look idxs of
      (ys, []) -> ys
      (_, invalidIdxs) ->
         error $ "Error in vLookup - indices out of Range: " ++ show invalidIdxs


class Reverse v where
   reverse :: (Storage v d) => v d -> v d

instance Reverse [] where
   reverse = L.reverse

instance Reverse V.Vector where
   reverse = V.reverse

instance Reverse UV.Vector where
   reverse = readUnbox UV.reverse