
module Main where


import Data.Graph.Inductive

import qualified Data.List as L
import qualified Data.Set as S
import qualified Data.Map as M
import Data.Maybe

import Control.Monad.Error
import Control.Applicative

import Debug.Trace

import EFA.Topology.RandomTopology
import EFA.Topology.Topology
-- import EFA.Topology.GraphData

import EFA.Solver.Equation
import EFA.Solver.Horn
import EFA.Solver.DirEquation
import EFA.Solver.IsVar
import EFA.Solver.DependencyGraph

import EFA.Equation.Env
import EFA.Interpreter.Interpreter
import EFA.Interpreter.Arith

import EFA.Utility
import EFA.Signal.Sequence
import EFA.IO.Import

import EFA.Graph.Draw
import EFA.Example.SymSig

import EFA.Signal.Sequence
import EFA.Graph.Flow
--import EFA.Graph.Flow


-- import EFA.Example.LinearOne

-- define topology 
g' :: Gr NLabel ()
g' = mkGraph (makeNodes nodes) (makeEdges edges) 
   where nodes = [(0,Source),(1,Crossing),(2,Sink)]
         edges = [(0,1),(1,2)]

main :: IO ()
main = do
  rec@(Record time sigMap) <- modelicaCSVImport "./modLinearTwo.RectA_res.csv"
  
  let pRec = PowerRecord time pMap              
      pMap =  M.fromList [ (PPosIdx 0 1,  sigMap M.! (SigId "powercon1.u")),
                           (PPosIdx 1 0,  sigMap M.! (SigId "powercon2.u")),
                           (PPosIdx 1 2,  sigMap M.! (SigId "powercon2.u")),
                           (PPosIdx 2 1,  sigMap M.! (SigId "powercon3.u"))]


  --    pMap = M.fromList [ (PPosIdx 0 1,[0,1,2,2,3,4,5,-5,-3,-3,4])]
  --                        (PPosIdx 1 0,[0,1,2,-2,-3,4,5,-5,-3,-3,4])]   
      
      pRec0 = addZeroCrossings pRec        
      (sequ,sqPRec) = genSequ pRec0          
      
      sqFRec = genSequFlow sqPRec
      sqFStRec = genSequFState sqFRec
      
      sqFlowTops = genSequFlowTops g' sqFStRec
      sqSecTops = genSectionTopology sqFlowTops
      sqTopo = mkSequenceTopology sqSecTops
      
      SequData sqEnvs = fmap (map (\(s, rec) -> fromFlowRecord s (RecIdx 0) rec) . zip (map SecIdx $ listIdx sequ)) sqFRec
      sigs = M.unions (map powerMap sqEnvs)
      
      
      ts = envToEqTerms sigs ++ mkEdgeEq sqTopo ++ mkNodeEq sqTopo
      varset = L.foldl' f S.empty ts
      f acc (v := Given) = S.insert v acc
      f acc _ = acc
      isV = isVarFromEqs varset

      (given, noVariables, givExt, rest) = splitTerms isV ts

      ho = hornOrder isV givExt rest
      dirs = directEquations isV ho
      --envs = Envs sigs M.empty esigs M.empty xsigs M.empty
      envs = Envs sigs M.empty M.empty M.empty M.empty M.empty

      gd = map (eqToInTerm envs) (given ++ dirs)

      res :: Envs [Val]
      res = interpretFromScratch gd

  
  putStrLn "Sequence"
  putStrLn (myShowList sequ)
  
  putStrLn "PowerRecord"
  putStrLn (myShowList $ genXSig pRec)

  putStrLn "PowerRecord + ZeroPoints"
  putStrLn (myShowList $ genXSig pRec0)

  putStrLn "Sequence"
  putStrLn (show sqPRec)

  putStrLn "Sequence Flow"
  putStrLn (show sqFRec)

  putStrLn "Sequence Flow"
  putStrLn (show sqFStRec)
  
  putStrLn (showInTerms gd)
  
  
  drawTopologyX' sqTopo
  
  -- drawSequFlowTops sqFlowTops
  drawTopology sqTopo res
  print res
  
  
  
  return ()

