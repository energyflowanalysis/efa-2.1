{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}

module EFA.Data.Axis.Strict where

import EFA.Utility(Caller,merror, ModuleName(..),FunctionName, genCaller)
import qualified EFA.Data.Vector as DV

import qualified EFA.Reference.Base as Ref

import qualified Data.Map as Map

m :: ModuleName
m = ModuleName "Axis.Axis"

nc :: FunctionName -> Caller
nc = genCaller m

-- | Datatype with strict monotonically rising values
data Axis typ label vec a = Axis {
  getLabel :: label,
  getVec :: vec a} deriving (Show,Eq)

instance (Show label,Ref.ToData (vec a)) =>
         Ref.ToData (Axis typ label vec a) where
  toData (Axis label vec) = Ref.DataMap "Axis" $ Map.fromList [(show label, Ref.toData vec)]

newtype Idx = Idx {getInt :: Int} deriving Show

instance Ref.ToData Idx where
  toData (Idx x) = Ref.StringData "Idx" (show x)

imap ::
  (DV.Walker vec,
   DV.Storage vec b,
   DV.Storage vec a) =>
  (Idx -> a -> b) -> Axis typ label vec a -> Axis typ label vec b
imap f (Axis label vec) = Axis label $ DV.imap (f . Idx) vec

indexAdd :: Idx -> Int -> Idx
indexAdd (Idx idx) num = Idx $ (idx+num)

len ::
  (DV.Storage vec a, DV.Length vec)=>
  Axis typ label vec a -> Int
len (Axis _ vec) = DV.length vec

fromVec ::
  (DV.Storage vec Bool, DV.Singleton vec,
   DV.Zipper vec, DV.Storage vec a,Ord a) =>
  Caller -> label -> vec a -> Axis typ label vec a
fromVec caller label vec =
  if isMonoton then Axis label vec
  else merror caller m "fromVec" "Vector of elements is not strict monotonically rising"
    where isMonoton = DV.all (==True) $ DV.deltaMap (\ x1 x2 -> x2 > x1) vec

findIndex ::
  (DV.Storage vec a, DV.Find vec)=>
  (a -> Bool) -> Axis typ label vec a -> Maybe Idx
findIndex f (Axis _ vec) = fmap Idx $ DV.findIndex f vec


lookupUnsafe ::
  DV.LookupUnsafe vec a =>
  Axis typ label vec a -> Idx -> a
lookupUnsafe (Axis _ axis) (Idx idx) = DV.lookupUnsafe axis idx

findRightInterpolationIndex ::
  (DV.Storage vec a, DV.Find vec, Ord a, DV.Length vec) =>
  Axis typ label vec a -> a -> Idx
findRightInterpolationIndex axis x = rightIndex
  where
    idx = findIndex (>x) axis
    rightIndex = case idx of
      Just (Idx ix) -> if ix==0 then Idx 1 else Idx ix
      Nothing   -> Idx $ (len axis)-1

-- | TODO -- Code ist wrong -- exact point hits have to be considered
-- | get all Points involved in the interpolation of a point on the given coordinates
getSupportPoints ::
  (Ord a,
   DV.Storage vec a,
   DV.Length vec,
   DV.Find vec,
   DV.LookupUnsafe vec a) =>
  Axis typ label vec a ->  a -> ((Idx,Idx),(a,a))
getSupportPoints axis x = ((leftIndex,rightIndex),
                                 (lookupUnsafe axis leftIndex, lookupUnsafe axis rightIndex))
  where rightIndex = findRightInterpolationIndex axis x
        leftIndex = indexAdd rightIndex (-1)  