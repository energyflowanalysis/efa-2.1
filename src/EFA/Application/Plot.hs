{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}

-- | Module to offer most common plots
module EFA.Application.Plot (
   Plot.Labeled, Plot.label,
   signal,
   xy,
   surface, surfaceWithOpts,
   record,
   recordList,
   sequence,
--   recordSplitPlus,
   recordSplit,
   sequenceSplit,
   recordList_extract,
   recordList_extractWithLeadSignal,
--   recordSelect,
--   sequenceSelect,
   stack,
   stacks,
   stackFromEnv,
   recordStackRow,
   sectionStackRow,
   etaDistr1Dim,
   etaDistr1DimfromRecordList,
   aggregatedStack,
   ) where

import qualified EFA.Application.AssignMap as AssignMap

import qualified EFA.Flow.Sequence.Quantity as SeqFlow
import qualified EFA.Flow.Sequence.Index as XIdx
import qualified EFA.Flow.SequenceState.Variable as Var

import qualified EFA.Flow.Topology.Index as TopoIdx

import qualified EFA.Signal.Plot as Plot
import qualified EFA.Signal.Signal as Sig
import qualified EFA.Signal.Sequence as Sequ
import qualified EFA.Signal.Vector as SV
import qualified EFA.Signal.Record as Record
import EFA.Signal.Record (Record)

import qualified EFA.Report.Format as Format
import EFA.Report.FormatValue (FormatValue, formatValue)
import EFA.Report.Typ (TDisp)

import qualified EFA.Equation.RecordIndex as RecIdx
import qualified EFA.Equation.Arithmetic as Arith
import EFA.Equation.Arithmetic (Constant)
import EFA.Equation.Result (Result)
import EFA.Equation.Stack (Stack)

import qualified EFA.Graph.Topology.Node as Node

import qualified Graphics.Gnuplot.Frame.OptionSet as Opts
import qualified Graphics.Gnuplot.Advanced as PlotAdv
import qualified Graphics.Gnuplot.Terminal as Terminal
import qualified Graphics.Gnuplot.Terminal.Default as DefaultTerm
import qualified Graphics.Gnuplot.Graph.ThreeDimensional as Graph3D
--import qualified Graphics.Gnuplot.Graph.TwoDimensional as Graph2D

import qualified Graphics.Gnuplot.Value.Atom as Atom
import qualified Graphics.Gnuplot.Value.Tuple as Tuple

import qualified Graphics.Gnuplot.LineSpecification as LineSpec

import qualified Graphics.Gnuplot.Frame as Frame

import qualified Data.Map as Map ; import Data.Map (Map)
import qualified Data.Foldable as Fold

import Control.Monad (zipWithM_)
import Control.Functor.HT (void)
import Data.Monoid ((<>))

import Prelude hiding (sequence)


-- | Simple Signal Plotting -- plot signal values against signal index --------------------------------------------------------------


signal ::
   (Plot.Signal signal, Terminal.C term) =>
   String -> term -> (LineSpec.T -> LineSpec.T) -> signal -> IO ()
signal ti terminal opts x = Plot.run terminal (Plot.signalFrameAttr ti x) (Plot.signal opts x)

{-
tableLinear, tableLinear2D, tableSurface ::
  (Terminal.C term) =>
  term -> String -> Table.Map Double -> IO ()
tableLinear term str = run term . plotTable id str
tableLinear2D term str = run term . plotTable tail str
-}

-- | Plotting Surfaces


surfaceWithOpts ::
  (Plot.Surface tcX tcY tcZ, Terminal.C term) =>
  String ->
  term ->
  (LineSpec.T -> LineSpec.T) ->
  (Graph3D.T (Plot.Value tcX) (Plot.Value tcY) (Plot.Value tcZ) ->
    Graph3D.T (Plot.Value tcX) (Plot.Value tcY) (Plot.Value tcZ)) ->
  (Opts.T (Graph3D.T (Plot.Value tcX) (Plot.Value tcY) (Plot.Value tcZ)) ->
    Opts.T (Graph3D.T (Plot.Value tcX) (Plot.Value tcY) (Plot.Value tcZ))) ->
  tcX -> tcY -> tcZ -> IO ()
surfaceWithOpts ti terminal opts surfstyle fopts x y z =
  Plot.run terminal
    (fopts $ Plot.xyFrameAttr ti x y)
    (fmap surfstyle $ Plot.surface opts x y z)

surface ::
  (Plot.Surface tcX tcY tcZ, Terminal.C term) =>
  String -> term ->
  tcX -> tcY -> tcZ -> IO ()
surface ti terminal x y z =
  surfaceWithOpts ti terminal id id id x y z


-- | Plotting Signals against each other -----------------------------


xy ::
   (Plot.XY tcX tcY, Terminal.C term) =>
   String -> term -> (LineSpec.T -> LineSpec.T)-> tcX -> tcY -> IO ()
xy ti terminal opts x y =
   Plot.run terminal (Plot.xyFrameAttr ti x y) (Plot.xy opts x y)


-- | Plotting Records ---------------------------------------------------------------

record :: (Terminal.C term,
             Constant d2,
             Constant d1,
             Ord id,
             SV.Walker v,
             SV.Storage v d2,
             SV.Storage v d1,
             SV.FromList v,
             TDisp t2,
             TDisp t1,
             Atom.C d2,
             Atom.C d1,
             Tuple.C d2,
             Tuple.C d1) =>
            String ->
            term ->
            (id -> String) ->
            (LineSpec.T -> LineSpec.T) ->
            Record s1 s2 t1 t2 id v d1 d2 -> IO ()
record ti term showKey opts x =
   Plot.run term (Plot.recordFrameAttr ti) (Plot.record showKey opts x)



recordList ::
   (Ord id,
    SV.Walker v,
    SV.FromList v,
    TDisp t1,
    TDisp t2,
    Constant d2,
    Constant d1,
    SV.Storage v d2,
    SV.Storage v d1,
    Atom.C d2,
    Atom.C d1,
    Tuple.C d2,
    Tuple.C d1,
    Terminal.C term) =>
   String ->
   term ->
   (id -> String) ->
   (LineSpec.T -> LineSpec.T) ->
   [(Record.Name,Record s1 s2 t1 t2 id v d1 d2)] -> IO ()
recordList ti term showKey opts x =
   Plot.run term (Plot.recordFrameAttr ti) (Plot.recordList showKey opts varOpts x)
   where
     varOpts n = LineSpec.lineStyle n

recordList_extract ::
   (Record.Index id,
    SV.Walker v,
    SV.FromList v,
    TDisp t1,
    TDisp t2,
    Constant d2,
    Constant d1,
    SV.Storage v d2,
    SV.Storage v d1,
    Atom.C d2,
    Atom.C d1,
    Tuple.C d2,
    Tuple.C d1,
    Terminal.C term) =>
   String ->
   term ->
   (id -> String) ->
   (LineSpec.T -> LineSpec.T) ->
   [(Record.Name,Record s1 s2 t1 t2 id v d1 d2)] ->
   [id] ->
   IO ()
recordList_extract ti term showKey opts xs idList =
   Plot.run term (Plot.recordFrameAttr ti) (Plot.recordList showKey opts varOpts
     $ map (\(x,y) -> (x,Record.extract idList y)) xs)
   where
     varOpts n = LineSpec.lineStyle n

{-# WARNING  recordList_extractWithLeadSignal "pg: Lead signals still need to be highlighted or scale to be displayed " #-}
recordList_extractWithLeadSignal :: (Terminal.C term,
                                       Constant d2,
                                       Constant d1,
                                       Record.Index id,
                                       SV.Walker v,
                                       SV.Storage v d2,
                                       SV.Storage v d1,
                                       SV.FromList v,
                                       TDisp t2,
                                       TDisp t1,
                                       Atom.C d2,
                                       Atom.C d1,
                                       Tuple.C d2,
                                       Tuple.C d1,
                                       Ord d2,
                                       Show (v d2),
                                       SV.Singleton v) =>
                                      String ->
                                      term ->
                                      (id -> String) ->
                                      (LineSpec.T -> LineSpec.T) ->
                                      (Record.RangeFrom id, Record.ToModify id) ->
                                      [(Record.Name, Record s1 s2 t1 t2 id v d1 d2)] -> IO ()
recordList_extractWithLeadSignal ti term showKey opts (extract, leadIds) recList =
   Plot.run term (Plot.recordFrameAttr ti) (Plot.recordList showKey opts  (\n -> LineSpec.pointType n) $ finalRecs)
  where extractedRecList = case extract of
          Record.RangeFrom idList -> map (\(x,y) -> (x,Record.extract idList y)) recList
          Record.RangeFromAll -> recList

        finalRecs = map (\(x,y)->(x,Record.normSignals2Max75 (extract, leadIds) y)) extractedRecList

-------------------------------------------
-- Futher Record Plot Variants

recordSplit ::
   (Terminal.C term,
    Constant d1,
    Constant d2,
    Record.Index id,
    SV.Walker v,
    SV.Storage v d1,
    SV.Storage v d2,
    SV.FromList v,
    TDisp t1,
    TDisp t2,
    Atom.C d1,
    Atom.C d2,
    Tuple.C d1,
    Tuple.C d2) =>
   Int ->
   String ->
   term ->
   (id -> String) ->
   (LineSpec.T -> LineSpec.T) ->
   Record s1 s2 t1 t2 id v d1 d2 -> IO ()
recordSplit n ti term showKey opts r =
   zipWithM_
      (\k -> record (ti ++ " - Part " ++ show (k::Int)) term showKey opts)
      [0..] (Record.split n r)

{-
recordSplitPlus ::
   (TDisp t1, TDisp t2,
    Ord id,
    Constant d,
    Tuple.C d, Atom.C d,
    SV.Walker v,
    SV.Storage v d,
    SV.FromList v,
    Terminal.C term,
    SV.Len (v d)) =>
   Int ->
   String ->
   term ->
   (LineSpec.T -> LineSpec.T) ->
   Record s1 s2 t1 t2 id v d d ->
   [(id, TC s2 t2 (Data (v :> Nil) d))] -> IO ()
recordSplitPlus n ti term opts r list =
   zipWithM_
      (\k -> record (ti ++ " - Part " ++ show (k::Int)) term opts)
      [0 ..] (map (Record.addSignals list) (Record.split n r))
-}
--------------------------------------------
-- record command to plot selected Signals only
{-
sequenceFrame ::
   (Constant d,
    Ord id,
    SV.Walker v, SV.Storage v d, SV.FromList v,
    TDisp t2, TDisp t1,
    Tuple.C d, Atom.C d) =>
   String ->
   (LineSpec.T -> LineSpec.T) ->
   Sequ.List (Record s1 s2 t1 t2 id v d d) ->
   Sequ.List (Frame.T (Graph2D.T d d))

sequenceFrame ti opts =
   Sequ.mapWithSection
      (\x ->
         Frame.cons (recordFrame ("Sequence " ++ ti ++ ", Record of " ++ show x)) .
         record opts)
-}

sequence ::
   (Constant d1,
    Constant d2,
    Ord id,
    SV.Walker v,
    SV.Storage v d1,
    SV.Storage v d2,
    SV.FromList v,
    TDisp t1,
    TDisp t2,
    Atom.C d1,
    Atom.C d2,
    Tuple.C d1,
    Tuple.C d2,
    Terminal.C term) =>
   String ->
   term ->
   (id -> String) ->
   (LineSpec.T -> LineSpec.T) ->
   Sequ.List (Record s1 s2 t1 t2 id v d1 d2) -> IO ()
sequence ti term showKey opts =
  Fold.sequence_ .  Sequ.mapWithSection (\ x -> record (ti ++ " - "++ show x) term showKey opts)
   -- (Plot.plotSync term) . sequenceFrame ti opts

sequenceSplit ::
   (Constant d2,
    Constant d1,
    Record.Index id,
    SV.Walker v,
    SV.Storage v d2,
    SV.Storage v d1,
    SV.FromList v,
    TDisp t2,
    TDisp t1,
    Atom.C d2,
    Atom.C d1,
    Tuple.C d2,
    Tuple.C d1,
    Terminal.C term) =>
   Int ->
   String ->
   term ->
   (id -> String) ->
   (LineSpec.T -> LineSpec.T) ->
   Sequ.List (Record s1 s2 t1 t2 id v d1 d2) -> IO ()
sequenceSplit n ti term showKey opts =
   Fold.sequence_ .
   Sequ.mapWithSection (\ x -> recordSplit n (ti ++ " - "++ show x) term showKey opts)

-- | Plotting Stacks ---------------------------------------------------------------

stack ::
   (FormatValue term, Ord term) =>
   String -> Format.ASCII -> Map term Double -> IO ()
stack title var =
   void
   . PlotAdv.plotSync DefaultTerm.cons
   . Frame.cons (Plot.stackFrameAttr title var)
   . Plot.stack


{- |
The length of @[var]@ must match the one of the @[Double]@ lists.
-}
stacks ::
   (Ord term, FormatValue term) =>
   String -> [Format.ASCII] -> Map term [Double] -> IO ()
stacks title vars =
   void
   . PlotAdv.plotSync DefaultTerm.cons
   . Frame.cons (Plot.stacksFrameAttr title vars)
   . Plot.stacks


stackFromEnv ::
   (Node.C node, Ord i, FormatValue i) =>
   String ->
   XIdx.Energy node ->
   Double ->
   (Record.DeltaName,
    SeqFlow.Graph node t (Result (Stack i Double))) ->
   IO ()

stackFromEnv ti energyIndex eps (Record.DeltaName recName, env) = do
   stack ("Record " ++ recName ++ "-" ++ ti)
      (formatValue $ RecIdx.delta $ Var.index energyIndex)
      (AssignMap.threshold eps $ AssignMap.lookupStack energyIndex env)

recordStackRow ::
   (Node.C node, Ord i, FormatValue i) =>
   String ->
   [Record.DeltaName] ->
   XIdx.Energy node ->
   Double ->
   [SeqFlow.Graph node t (Result (Stack i Double))] ->
   IO ()

recordStackRow ti deltaSets energyIndex eps =
   stacks ti
      (map (Format.literal . (\ (Record.DeltaName x) -> x)) deltaSets) .
   AssignMap.simultaneousThreshold eps .
   AssignMap.transpose .
   map (AssignMap.lookupStack energyIndex)

sectionStackRow ::
   (Node.C node, Ord i, FormatValue i) =>
   String ->
   TopoIdx.Energy node ->
   Double ->
   SeqFlow.Graph node a (Result (Stack i Double)) ->
   IO ()
sectionStackRow ti energyIndex eps env =
   case unzip $ Map.toList $ AssignMap.lookupEnergyStacks energyIndex env of
      (idxs, energyStacks) ->
         stacks ti (map (Format.literal . show) idxs) $
         AssignMap.simultaneousThreshold eps . AssignMap.transpose $
         map (Map.mapKeys AssignMap.deltaIndexSet) energyStacks

aggregatedStack ::
   (Node.C node, Ord i, FormatValue i) =>
   String ->
   TopoIdx.Energy node ->
   Double ->
   SeqFlow.Graph node t (Result (Stack i Double)) ->
   IO ()

aggregatedStack ti energyIndex eps env =
   stack ti (formatValue $ RecIdx.delta energyIndex) $
   AssignMap.threshold eps $
   Map.mapKeys AssignMap.deltaIndexSet $ Fold.fold $
   AssignMap.lookupEnergyStacks energyIndex env


-- | Plotting Average Efficiency Curves over Energy Flow Distribution -------------------------------

-- | Simple plot with provided data p and n time signals, ideally sorted, fDist is energy distribution over power
-- | and nDist is the averaged efficiency over power
-- | pg: currently plots over input power, one should be able to choose
etaDistr1Dim :: (Constant d,
                  SV.Walker v,
                  SV.Storage v d,
                  SV.FromList v,
                  Atom.C d,
                  Tuple.C d) =>
                 String -> Sig.PFSignal v d -> Sig.NFSignal v d ->
                 Sig.PDistr v d -> Sig.FDistr v d -> Sig.NDistr v d -> IO ()
etaDistr1Dim ti p n pDist fDist nDist =
  Plot.run DefaultTerm.cons (Plot.xyFrameAttr ti p n) $
  Plot.xy id p (Plot.label "Efficiency Operation Points over Power" n) <>
  Plot.xy id pDist (Plot.label "Averaged Efficiency over Power" nDist) <>
  Plot.xy id pDist (Plot.label "Input Energy Distribution over Power" fDist)


-- | Plot efficiency distribution from List of Records
-- | pg: currently plots over input power, one should be able to choose
-- | You however can choose which power you want to plot and classify over (abscissa)
etaDistr1DimfromRecordList ::
   (Node.C node,
    Show (v d),
    Ord d,
    RealFrac d,
    Constant d,
    Atom.C d,
    Tuple.C d,
    SV.Zipper v,
    SV.Walker v,
    SV.Storage v (d, d),
    SV.Storage v d,
    SV.FromList v,
    SV.SortBy v,
    SV.Unique v (Sig.Class d),
    SV.Storage v Sig.SignalIdx,
    SV.Storage v Int,
    SV.Storage v (Sig.Class d),
    SV.Storage v ([Sig.Class d], [Sig.SignalIdx]),
    SV.Lookup v,
    SV.Find v,
    SV.Storage v (d, (d, d)),
    SV.Singleton v) =>
   String  -> d -> d ->
   [(Record.Name, Record.DTimeFlowRecord node v d)] ->
   (String, (TopoIdx.Position node, TopoIdx.Position node, TopoIdx.Position node)) -> IO ()

etaDistr1DimfromRecordList ti  interval offset rList  (plotTitle, (idIn,idOut,idAbscissa)) = mapM_ f rList
  where f (Record.Name recTitle, rec) = do
          let ein = Record.getSig rec idIn
              eout = Record.getSig rec idOut
              eAbscissa = Record.getSig rec idAbscissa
              pAbscissa = eAbscissa Sig../dtime
              dtime = Record.getTime rec
              eta = Sig.calcEtaWithSign eout ein eout
              (pDist, einDist , _ , nDist) = Sig.etaDistribution1D interval offset
                                                 dtime ein eout eout
              (x,y) = Sig.sortTwo (pAbscissa,eta)
          etaDistr1Dim (ti ++ "_" ++ plotTitle ++ "_" ++ recTitle) x y  pDist
            (Sig.scale (Arith.fromInteger 100) $ Sig.norm einDist) nDist

