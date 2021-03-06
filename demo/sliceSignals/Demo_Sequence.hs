
-- | Demonstriert das Plotten von Signalen.

module Main where

import qualified EFA.Application.Plot as PlotIO

import qualified EFA.Flow.Topology.Index as XIdx

import qualified EFA.Signal.Signal as S
import qualified EFA.Signal.Chop as Chop
import qualified EFA.Signal.Sequence as Sequ

import EFA.Signal.Record (PowerRecord, Record(Record))
import EFA.Signal.Signal (PSignal, (.++))

import qualified Data.Map as Map
import Data.Map (Map)

import qualified Graphics.Gnuplot.Terminal.Default as DefaultTerm


mkSig :: Int -> [Double] -> PSignal [] Double
mkSig m = S.fromList . concat . replicate m

mkSigEnd :: Int -> [Double] -> PSignal [] Double
mkSigEnd m s = mkSig m s  .++  S.fromList [head s]

time :: [Double]
time = take 13 [0 ..]

s01, s10, s12, s21, s13, s31 :: [Double]
s01 = [0, 2, 2, 0, 0, 0]
s10 = [0, 0.8, 0.8, 0, 0, 0]
s12 = [0.3, 0.3, 0.3, 0.3, 0.3, 0.3]
s21 = [0.2, 0.2, 0.2, 0.2, 0.2, 0.2]
s13 = [0, 0.5, 0.5, -0.3, -0.3, -0.3]
s31 = [0, 0.25, 0.25, 0, -0.6, -0.6]

n :: Int
n = 2

pMap :: Map (XIdx.Position Int) (PSignal [] Double)
pMap =
   Map.fromListWith (error "duplicate keys") $
      (XIdx.ppos 0 1, mkSigEnd n s01) :
      (XIdx.ppos 1 0, mkSigEnd n s10) :
      (XIdx.ppos 1 2, mkSigEnd n s12) :
      (XIdx.ppos 2 1, mkSigEnd n s21) :
      (XIdx.ppos 1 3, mkSigEnd n s13) :
      (XIdx.ppos 3 1, mkSigEnd n s31) :
      []


pRec, pRec0 :: (PowerRecord Int [] Double)
pRec = Record (S.fromList time) pMap
pRec0 = Chop.addZeroCrossings pRec

sequRecA, sequRecB :: Sequ.List (PowerRecord Int [] Double)
sequRecA = Chop.genSequ pRec0

sequRecB = Chop.chopAtZeroCrossingsPowerRecord True pRec


main :: IO ()
main = do
  print time
  print pRec
  print pRec0

  PlotIO.record "PowerRecord" DefaultTerm.cons show id pRec
  PlotIO.sequence "SequA" DefaultTerm.cons show id sequRecA
  PlotIO.sequence "SequB" DefaultTerm.cons show id sequRecB

{-
  {-
  The result looks awful, because many parts overlap.
  -}
  void $ Plot.plot (PS.cons "sequence.eps") $
     (\xs ->
        MultiPlot.simpleFromPartArray $
        let width = 3
        in  Array.listArray ((1,1), (divUp (length xs) width, width)) $
            map MultiPlot.partFromFrame xs ++
            repeat (MultiPlot.partFromFrame Frame.empty)) $
     rPlotCore "Sequ" sequRecB
-}
