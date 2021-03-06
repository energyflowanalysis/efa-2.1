{-# LANGUAGE TemplateHaskell #-}


module EFA.Test.Solver where



import qualified Data.Set as S
import qualified Data.List as L
import Data.Graph.Inductive

import Test.QuickCheck
import Test.QuickCheck.All

import Debug.Trace


import EFA.Topology.RandomTopology
import EFA.Topology.Topology
import EFA.Solver.Equation
import EFA.Solver.Horn
import EFA.Solver.IsVar
import EFA.Solver.DirEquation
import EFA.Interpreter.Arith
import EFA.Equation.Env
import EFA.Utility


-- | Given x and eta environments, the number of all solved (directed) equations should be equal the
-- double of the number of edges in the graph, that is, every power position has been calculated.
-- This is a good example for the use of various functions together.
prop_solver :: Int -> Gen Bool
prop_solver seed = do
  ratio <- choose (2.0, 5.0)
  let g = randomTopology 0 50 ratio

      terms = map give [ PowerIdx 0 0 0 1 ]

      xenvts = envToEqTerms (randomXEnv 0 1 g)
      eenvts = envToEqTerms (randomEtaEnv 17 1 g)

      ts = terms ++ xenvts ++ eenvts ++ mkEdgeEq g ++ mkNodeEq g
      isV = isVar g ts
      (given, nov, givExt, rest) = splitTerms isV ts
      ss = givExt ++ rest

      ho = hornOrder isV ss
      dirs = directEquations isV ho
      noEdges = length (edges g)

  -- For every edge one x plus all PowerIdx minus one, because one PowerIdx is given.
  return $ length dirs == noEdges + (2*noEdges - 1)


prop_orderOfEqs :: Int ->  Gen Bool
prop_orderOfEqs seed = do
  ratio <- choose (2.0, 6.0)
  let g = randomTopology seed 50 ratio

      terms = map give [ PowerIdx 0 0 0 1 ]

      xenvts = envToEqTerms (randomXEnv 0 1 g)
      eenvts = envToEqTerms (randomEtaEnv 17 1 g)

      ts = terms ++ xenvts ++ eenvts ++ mkEdgeEq g ++ mkNodeEq g
      isV = isVar g ts
      (given, nov, givExt, rest) = splitTerms isV ts
      ss = givExt ++ rest

      ho = hornOrder isV ss
      dirs = directEquations isV ho
      dirsets = L.scanl S.union S.empty $ map (mkVarSet isV) dirs -- For _:a:b:_, b includes a
      atMostOneMore (s, t) = S.size (s S.\\ t) <= 1

  return $ all atMostOneMore (pairs dirsets)

runTests = $quickCheckAll
