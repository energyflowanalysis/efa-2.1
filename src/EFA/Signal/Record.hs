{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}


module EFA.Signal.Record where
import qualified EFA.Graph.Topology.Index as Idx
import qualified EFA.Signal.Signal as S
import qualified EFA.Signal.Data as D
import qualified EFA.Signal.Vector as V
import EFA.Report.Base (DispStorage1)
import EFA.Signal.Signal
          (TC, Signal, FSignal,TSamp,PSamp,PSamp1L,PSamp2LL,TSigL,UTSignal,TSignal)
          
import EFA.Signal.Typ (Typ, A, P, T, Tt, UT,F,D)
import EFA.Signal.Data (Data, (:>), Nil)
import EFA.Signal.Base (Sign, BSum, DArith0,BProd)

import EFA.Report.Report (ToTable(toTable), Table(..), tvcat)
import Text.Printf (PrintfArg)
import qualified Test.QuickCheck as QC
import System.Random (Random)

import qualified Data.Map as M
import qualified Data.List.HT as HTL
import qualified Data.List.Match as Match

import Data.NonEmpty ((!:))
import Data.Ratio (Ratio, (%))
import Data.List (transpose)
import Data.Tuple.HT (mapFst)
import Control.Monad (liftM2)
import EFA.Utility (checkedLookup)



newtype SigId = SigId String deriving (Show, Eq, Ord)


-- | Indices for Power Position
-- data PPosIdx = PPosIdx !Idx.Node !Idx.Node deriving (Show, Eq, Ord)

-----------------------------------------------------------------------------------
-- | Indices for Power Position
data PPosIdx nty = PPosIdx !nty !nty deriving (Show, Eq, Ord)

type instance D.Value (Record s t1 t2 id v a) = a


data Record s t1 t2 id v a =  Record (TC s t1 (Data (v :> Nil) a)) (M.Map id (TC s t2 (Data (v :> Nil) a))) deriving (Show, Eq)

type SignalRecord v a =  Record Signal (Typ A T Tt) (Typ UT UT UT)  SigId v a

type PowerRecord nty v a =  Record Signal (Typ A T Tt) (Typ A P Tt) (PPosIdx nty) v a 

type FlowRecord nty v a =  Record FSignal (Typ D T Tt) (Typ A F Tt) (PPosIdx nty) v a 

-- | Flow record to contain flow signals assigned to the tree
newtype FlowState nty = FlowState (M.Map (PPosIdx nty) Sign) deriving (Show)

getTime :: Record s t1 t2 id v a ->  TC s t1 (Data (v :> Nil) a) 
getTime (Record time _) = time

getSig :: (Show (v a),Ord id, Show id) => Record s t1 t2 id v a -> id -> TC s t2 (Data (v :> Nil) a)   
getSig (Record _ sigMap) key = checkedLookup sigMap key

-- | Use carefully -- removes signal jitter around zero 
removeZeroNoise :: (V.Walker v, V.Storage v a, Ord a, Num a) => PowerRecord nty v a -> a -> PowerRecord nty v a        
removeZeroNoise (Record time pMap) threshold = Record time (M.map f pMap)
  where f sig = S.map g sig
        g x | abs x < threshold = 0 
            | otherwise = x

-- | Generate a new Record with selected signals
extractRecord :: (Show (v a),Ord id, Show id) => [id] -> Record s t1 t2 id v a ->  Record s t1 t2 id v a
extractRecord xs rec@(Record time _ ) = Record time  (M.fromList $ zip xs (map f xs))
  where f x = getSig rec x
        
        
-- | Split SignalRecord in even Junks                          
splitRecord ::  (Ord id) => Int -> Record s t1 t2 id v a  -> [Record s t1 t2 id v a]                          
splitRecord n (Record time pMap)  = recList
  where (recList, _) = f ([],M.toList pMap)
        f (rs, []) = (rs,[])        
        f (rs, xs) = f (rs ++ [Record time (M.fromList $ take n xs)], drop n xs)
        

-- sortSigList ::  (Num a,
--                       Ord a,
--                       V.Walker v,
--                       V.Storage v a,
--                       BSum a) =>
--                 [ (SigId,TC Signal (Typ UT UT UT) (Data (v :> Nil) a))] ->  [(SigId, TC Signal (Typ UT UT UT) (Data (v :> Nil) a))]
-- sortSigList  sigList = L.sortBy g  sigList
--   where g (_,x) (_,y) = compare (S.sigSum x) (S.sigSum y) 

-- -- | Split PowerRecord in even Junks                          
-- splitPowerRecord ::  (Num a, Ord a, V.Walker v, V.Storage v a, BSum a) => PowerRecord nty v a -> Int -> [PowerRecord nty v a]                          
-- splitPowerRecord (Record time pMap) n  = recList
--   where (recList, _) = f ([],M.toList pMap)
--         f (rs, []) = (rs,[])        
--         f (rs, xs) = f (rs ++ [Record time (M.fromList $ take n xs)], drop n xs)
 

-----------------------------------------------------------------------------------
-- Functions to support Signal Selection
 
-- | List of Operations for pre-processing signals
        
-- | create a Record of selected, and sign corrected signals
extractLogSignals ::  (V.Walker v,
                      V.Storage v a,
                      DArith0 a, 
                      Show (v a)) => 
                      SignalRecord v a -> 
                      [(SigId, TC Signal (Typ UT UT UT) (Data (v :> Nil) a) 
                               -> TC Signal (Typ UT UT UT) (Data (v :> Nil) a))] -> 
                      SignalRecord  v a        
extractLogSignals rec@(Record time _) idList = Record time (M.fromList $ map f idList)
  where f (SigId sigId,sigFunct) = (SigId sigId, sigFunct $ getSig rec (SigId sigId)) 


genPowerRecord :: (Show (v a),
                   V.Zipper v,
                   V.Walker v,
                   V.Storage v a,
                   BProd a a, 
                   BSum a, 
                   Ord nty) => 
                  TSignal v a -> [(PPosIdx nty, UTSignal v a, UTSignal v a)] -> PowerRecord nty v a 
genPowerRecord time sigList = Record time (M.fromList $ concat $ map f sigList) 
  where f (pposIdx, sigA, sigB) = [(pposIdx, S.setType $ sigA),(swap pposIdx, S.setType $ sigB)]
          where 
               swap (PPosIdx n1 n2) = PPosIdx n2 n1
          
-----------------------------------------------------------------------------------
-- Various Class and Instance Definition for the different Sequence Datatypes 

instance (QC.Arbitrary nty) => QC.Arbitrary (PPosIdx nty) where
   arbitrary = liftM2 PPosIdx QC.arbitrary QC.arbitrary
   shrink (PPosIdx from to) = map (uncurry PPosIdx) $ QC.shrink (from, to)

instance
   (Show (v a), Sample a, V.FromList v, V.Storage v a,QC.Arbitrary nty,Ord nty) =>
      QC.Arbitrary (PowerRecord nty v a) where
   arbitrary = do
      xs <- QC.listOf arbitrarySample
      n <- QC.choose (1,5)
      ppos <- QC.vectorOf n QC.arbitrary
      let vectorSamples =
             HTL.switchR [] (\equalSized _ -> equalSized) $
             HTL.sliceVertical n xs
      return $
         Record (S.fromList $ Match.take vectorSamples $ iterate (1+) 0) $
         M.fromList $ zip ppos $ map S.fromList $ transpose vectorSamples

{-
we need this class,
because QC.choose requires a Random instance
but there is no Random Ratio instance
-}
class Num a => Sample a where arbitrarySample :: QC.Gen a
instance Sample Double where arbitrarySample = QC.choose (-1,1)
instance (Random a, Integral a) => Sample (Ratio a) where
   arbitrarySample = do
      x <- QC.choose (-100,100)
      y <- QC.choose (-100,100)
      return $
         case compare (abs x) (abs y) of
            LT -> x%y
            GT -> y%x
            EQ -> 1 -- prevent 0/0


instance
   (V.Walker v, V.Singleton v, V.FromList v, V.Storage v a, DispStorage1 v,
    Ord a, Fractional a, PrintfArg a) =>
   ToTable (SignalRecord v a) where
   toTable os (ti, Record time sigs) =
      [Table {
         tableTitle = "SignalRecord - " ++ ti ,
         tableData = tableData t,
         tableFormat = tableFormat t,
         tableSubTitle = ""}]

      where t = tvcat $ S.toTable os ("Time",time) !:
                        concatMap (toTable os . mapFst show) (M.toList sigs)

instance
   (V.Walker v, V.Singleton v, V.FromList v, V.Storage v a, DispStorage1 v,
    Ord a, Fractional a, PrintfArg a, Show nty) =>
   ToTable (PowerRecord nty v a) where
   toTable os (ti, Record time sigs) =
      [Table {
         tableTitle = "PowerRecord - " ++ ti ,
         tableData = tableData t,
         tableFormat = tableFormat t,
         tableSubTitle = ""}]

      where t = tvcat $ S.toTable os ("Time",time) !:
                        concatMap (toTable os . mapFst show) (M.toList sigs)


------------------------------------
-- RSignal als Transponierte Form


type RSig = (TSigL, PSamp2LL)
type RSamp1 = (TSamp, PSamp1L)
type RSamp = (TSamp, PSamp)

{-
{-# DEPRECATED rhead, rtail "use rviewL instead" #-}
{-# DEPRECATED rlast, rinit "use rviewR instead" #-}

rhead :: RSig -> RSamp1
rhead (t,ps) = (S.head t, S.head ps)

rtail :: RSig -> RSig
rtail (t,ps) = (S.tail t, S.tail ps)

rlast :: RSig -> RSamp1
rlast (t,ps) = (S.last t, S.last ps)

rinit :: RSig -> RSig
rinit (t,ps) = (S.init t, S.init ps)
-}


rviewL :: RSig -> Maybe (RSamp1, RSig)
rviewL (t,ps) =
   liftM2 zipPairs (S.viewL t) (S.viewL ps)

rviewR :: RSig -> Maybe (RSig, RSamp1)
rviewR (t,ps) =
   liftM2 zipPairs (S.viewR t) (S.viewR ps)

zipPairs :: (a,b) -> (c,d) -> ((a,c), (b,d))
zipPairs (a,b) (c,d) = ((a,c), (b,d))

rlen :: RSig -> Int
rlen  (t,ps) = min (S.len t) (S.len ps)

rsingleton :: RSamp1 -> RSig
rsingleton (t,ps) = (S.singleton t, S.singleton ps)


