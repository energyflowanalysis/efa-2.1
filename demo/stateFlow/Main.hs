module Main where

import qualified EFA.Application.Absolute as EqGen
import EFA.Application.Utility ( makeEdges )
import EFA.Application.Absolute ( (.=) )

import qualified EFA.Flow.Sequence.Index as XIdx

import qualified EFA.Graph.StateFlow as StateFlow
import qualified EFA.Graph.Flow as Flow
import qualified EFA.Graph.Topology.StateAnalysis as StateAnalysis
import qualified EFA.Graph.Topology.Node as Node
import qualified EFA.Graph.Topology.Index as Idx
import qualified EFA.Graph.Topology as TD
import qualified EFA.Graph.Draw as Draw
import qualified EFA.Graph as Gr

import qualified EFA.Signal.SequenceData as SD

import qualified EFA.Report.Format as Format

import qualified EFA.Utility.Stream as Stream
import EFA.Utility.Async (concurrentlyMany_)
import EFA.Utility.Stream (Stream((:~)))

import Data.Monoid (Monoid, mconcat)


sec0, sec1, sec2, sec3, sec4 :: Idx.Section
sec0 :~ sec1 :~ sec2 :~ sec3 :~ sec4 :~ _ = Stream.enumFrom $ Idx.Section 0

node0, node1, node2, node3 :: Node
node0 :~ node1 :~ node2 :~ node3 :~ _ = Stream.enumFrom $ Node 0

newtype Node = Node Int deriving (Show, Eq, Ord)

instance Enum Node where
   toEnum = Node
   fromEnum (Node n) = n

instance Node.C Node where
   display (Node 0) = Format.literal "null"
   display (Node 1) = Format.literal "eins"
   display (Node 2) = Format.literal "zwei"
   display (Node 3) = Format.literal "drei"
   display n = Format.literal $ show n

   subscript (Node n) = Format.literal $ show n
   dotId = Node.dotIdDefault


topoDreibein :: TD.Topology Node
topoDreibein = Gr.fromList ns (makeEdges es)
  where ns = [(node0, TD.Source),
              (node1, TD.Sink),
              (node2, TD.Crossing),
              (node3, TD.storage)]
        es = [(node0, node2), (node1, node2), (node2, node3)]

given :: EqGen.EquationSystem Node s Double Double
given =
   mconcat $

   (XIdx.dTime sec0 .= 0.5) :
   (XIdx.dTime sec1 .= 2) :
   (XIdx.dTime sec2 .= 1) :

   (XIdx.storage (Idx.afterSection sec2) node3 .= 10.0) :


   (XIdx.power sec0 node2 node3 .= 4.0) :

   (XIdx.x sec0 node2 node3 .= 0.32) :

   (XIdx.power sec1 node3 node2 .= 5) :
   (XIdx.power sec2 node3 node2 .= 6) :
   (XIdx.power sec3 node3 node2 .= 7) :
   (XIdx.power sec4 node3 node2 .= 8) :

   (XIdx.eta sec0 node3 node2 .= 0.25) :
   (XIdx.eta sec0 node2 node1 .= 0.5) :
   (XIdx.eta sec0 node0 node2 .= 0.75) :

   (XIdx.eta sec1 node3 node2 .= 0.25) :
   (XIdx.eta sec1 node2 node1 .= 0.5) :
   (XIdx.eta sec1 node0 node2 .= 0.75) :
   (XIdx.power sec1 node1 node2 .= 4.0) :


   (XIdx.eta sec2 node3 node2 .= 0.75) :
   (XIdx.eta sec2 node2 node1 .= 0.5) :
   (XIdx.eta sec2 node0 node2 .= 0.75) :
   (XIdx.power sec2 node1 node2 .= 4.0) :

   (XIdx.eta sec1 node2 node3 .= 0.25) :

   []

{-
stateEnv ::
  (Ord node) => TD.StateFlowGraph node -> StFlEnv.Complete node a v
-}


main :: IO ()
main = do

  let sequ =
        fmap (StateAnalysis.bruteForce topoDreibein !!) $
        SD.fromList [1, 0, 1]
      sequFlowGraph = Flow.sequenceGraph sequ
      env = EqGen.solve sequFlowGraph given

      stateFlowGraph =
        StateFlow.stateGraphActualStorageEdges sequ
      stateFlowEnv =
        StateFlow.envFromSequenceEnvResult
          (snd $ StateFlow.stateMaps sequ) env

  concurrentlyMany_ $ map Draw.xterm $
    Draw.sequFlowGraphAbsWithEnv sequFlowGraph env :
    Draw.stateFlowGraphWithEnv Draw.optionsDefault stateFlowGraph stateFlowEnv :
    []