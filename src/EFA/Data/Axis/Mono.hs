{-# LANGUAGE FlexibleContexts #-}

module EFA.Data.Axis.Mono where

import EFA.Utility(Caller,merror, ModuleName(..),FunctionName, genCaller)
import qualified EFA.Data.Vector as DV
import qualified EFA.Data.OrdData as OrdData
import qualified EFA.Value as Value

-- | TODO -- how many points are allowed to have the same time, only two or more ?

m :: ModuleName
m = ModuleName "Axis.Mono"

nc :: FunctionName -> Caller
nc = genCaller m

-- | Datatype with monotonically rising values
data Axis inst label vec a = Axis {
  getLabel :: label,
  getVec :: vec a} deriving (Show,Eq)

newtype Idx = Idx {getInt :: Int} deriving (Show,Ord,Eq)

data Section = Section Idx Idx 

--data CutInfo = CutInfo NonEmpty Data.Set

apply :: (Int -> Int) -> Idx -> Idx
apply f (Idx x) = Idx $ f x

map ::
  (DV.Walker vec,
   DV.Storage vec b,
   DV.Storage vec a) =>
  (a -> b) -> Axis inst label vec a -> Axis inst label vec b
map f (Axis label vec) = Axis label $ DV.map f vec

imap ::
  (DV.Walker vec,
   DV.Storage vec b,
   DV.Storage vec a) =>
  (Idx -> a -> b) -> Axis inst label vec a -> Axis inst label vec b
imap f (Axis label vec) = Axis label $ DV.imap (f . Idx) vec

indexAdd :: Idx -> Int -> Idx
indexAdd (Idx idx) num = Idx $ (idx+num)

len ::
  (DV.Storage vec a, DV.Length vec)=>
  Axis inst label vec a -> Int
len (Axis _ vec) = DV.length vec

fromVec ::
  (DV.Storage vec Bool, DV.Singleton vec,
   DV.Zipper vec, DV.Storage vec a,Ord a) =>
  Caller -> label -> vec a -> Axis inst label vec a
fromVec caller label vec =
  if isMonoton then Axis label vec
  else merror caller m "fromVec" "Vector of elements is not monotonically rising"
    where isMonoton = DV.all (==True) $ DV.deltaMap (\ x1 x2 -> x2 >= x1) vec

findIndex ::
  (DV.Storage vec a, DV.Find vec)=>
  (a -> Bool) -> Axis inst label vec a -> Maybe Idx
findIndex f (Axis _ vec) = fmap Idx $ DV.findIndex f vec


lookupUnsafe ::
  DV.LookupUnsafe vec a =>
  Axis inst label vec a -> Idx -> a
lookupUnsafe (Axis _ axis) (Idx idx) = DV.lookupUnsafe axis idx

toIntervall ::
  (DV.Zipper vec,
   DV.Storage vec (Value.Intervall a),
   DV.Storage vec a,
   DV.Singleton vec) => 
  Axis (OrdData.Edge inst) label vec a -> 
  Axis (OrdData.Mid inst) label vec (Value.Intervall a)
toIntervall (Axis label vec) = Axis label (DV.deltaMap (\x y -> Value.Intervall x y) vec)  

findRightInterpolationIndex ::
  (DV.Storage vec a, DV.Find vec, Ord a, DV.Length vec) =>
  Axis inst label vec a -> a -> Idx
findRightInterpolationIndex axis x = rightIndex
  where
    idx = findIndex (>x) axis
    rightIndex = case idx of
      Just (Idx ix) -> if ix==0 then Idx 1 else Idx ix
      Nothing   -> Idx $ (len axis)-1
