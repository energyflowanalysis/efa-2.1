{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

-- | PlotBase provide the basic functions to build Plots
module EFA.Data.Plot.D3 where

--import qualified EFA.Data.ND.Cube.Map as CubeMap
import qualified EFA.Data.ND as ND

--import qualified EFA.Value as Value
import qualified EFA.Value.Type as Type


--import qualified EFA.Signal.Sequence as Sequ
--import qualified EFA.Signal.Signal as S
--import qualified EFA.Signal.Data as D
--import qualified EFA.Data.Vector as DV
--import qualified EFA.Signal.Record as Record
--import qualified EFA.Signal.Colour as Colour

--import EFA.Signal.Record (Record(Record))
--import EFA.Signal.Signal (TC, toSigList, getDisplayType)
--import EFA.Signal.Data (Data, (:>), Nil, NestedList)

--import qualified EFA.Equation.Arithmetic as Arith
--import EFA.Equation.Arithmetic (Sum, Product, (~*), Constant)

--import qualified EFA.Graph.Topology.Node as Node

--import EFA.Report.Typ
--          (TDisp, DisplayType(Typ_T), getDisplayUnit, getDisplayTypName)
--import EFA.Report.Base (UnitScale(UnitScale), getUnitScale)

--import qualified EFA.Report.Format as Format
--import EFA.Report.FormatValue (FormatValue, formatValue)

--import EFA.Utility.Show (showNode)

--import qualified Graphics.Gnuplot.Advanced as Plot

import qualified Graphics.Gnuplot.Terminal as Terminal
--import qualified Graphics.Gnuplot.Plot as Plt
--import qualified Graphics.Gnuplot.Plot.TwoDimensional as Plot2D
import qualified Graphics.Gnuplot.Plot.ThreeDimensional as Plot3D
--import qualified Graphics.Gnuplot.Graph.TwoDimensional as Graph2D
import qualified Graphics.Gnuplot.Graph.ThreeDimensional as Graph3D

--import qualified Graphics.Gnuplot.Graph as Graph
import qualified Graphics.Gnuplot.Value.Atom as Atom
--import qualified Graphics.Gnuplot.Value.Tuple as Tuple

import qualified Graphics.Gnuplot.LineSpecification as LineSpec
--import qualified Graphics.Gnuplot.ColorSpecification as ColourSpec

--import qualified Graphics.Gnuplot.Frame as Frame
import qualified Graphics.Gnuplot.Frame.Option as Opt
import qualified Graphics.Gnuplot.Frame.OptionSet as Opts
--import qualified Graphics.Gnuplot.Frame.OptionSet.Style as OptsStyle
--import qualified Graphics.Gnuplot.Frame.OptionSet.Histogram as Histogram

--import qualified EFA.Data.Axis.Strict as Strict
import qualified EFA.Data.Plot as DataPlot

import qualified Data.Map as Map
--import qualified Data.List as List
import qualified Data.Foldable as Foldable
--import qualified Data.List.Key as Key
--import Data.Map (Map)
--import Control.Functor.HT (void)
--import Data.Foldable (foldMap)
--import Data.Monoid (mconcat)

--import EFA.Utility.Trace(mytrace)

import Prelude hiding (sequence)

import EFA.Utility(Caller,
                 --  merror,(|>),
                   ModuleName(..),FunctionName, genCaller)
--import qualified Data.List as List

modul :: ModuleName
modul = ModuleName "Data.Plot"

nc :: FunctionName -> Caller
nc = genCaller modul

data Cut label a = Cut (Map.Map ND.Idx (label, a, Type.Dynamic)) deriving Show

-- TODO showCut, dispCut -- wie eigene show functionen benennen ?
showCut :: (Show label, Show a) => Cut label a -> String
showCut  (Cut xs) = "Cut" ++ (concat $ map f $ map snd $ Map.toList xs)
  where f (label, x, typ) =  show label ++ " " ++ show x ++ " " ++ show typ

-- | Datatype extracting r
data PlotData id label a b =
  PlotData (DataPlot.PlotInfo id (Cut label a)) (D3RangeInfo label a b) (Plot3D.T a a b)

data D3RangeInfo label a b = D3RangeInfo
  (DataPlot.AxisInfo label a)
  (DataPlot.AxisInfo label a)
  (DataPlot.AxisInfo label b) deriving Show

collectPlotIds ::  (Show id) => [PlotData id label a b] -> [Maybe id]
collectPlotIds xs = map f xs
  where   f (PlotData (DataPlot.PlotInfo x _) _ _) = x

combineRange :: (Ord a, Ord b) =>
  D3RangeInfo label a b ->
  D3RangeInfo label a b ->
  D3RangeInfo label a b
combineRange (D3RangeInfo x y z) (D3RangeInfo x1 y1 z1) =
  D3RangeInfo
  (DataPlot.combine x x1)
  (DataPlot.combine y y1)
  (DataPlot.combine z z1)

combineRangeList :: (Ord b, Ord a) => D3RangeInfo label a b -> [D3RangeInfo label a b] -> D3RangeInfo label a b
combineRangeList x xs = foldl combineRange x xs

class GetD3RangeInfo d3data where
  getD3RangeInfo ::
    (d3data :: * -> * -> * -> (* -> *) -> * -> * -> *) typ dim label vec a b
    -> D3RangeInfo label a b

defaultFrameAttr :: (Atom.C a, Atom.C b) => Opts.T (Graph3D.T a a b)
defaultFrameAttr =
   Opts.add (Opt.custom "hidden3d" "") ["back offset 1 trianglepattern 3 undefined 1 altdiagonal bentover"] $
   Opts.grid True $
   Opts.deflt

blankStyle :: Int -> PlotData id label a b ->  ( Plot3D.T a a b ->  Plot3D.T a a b )
blankStyle _ _ = id

blankFrame ::
  (Atom.C a, Atom.C b) =>
  String ->
  [PlotData id label a b] ->
  (Opts.T (Graph3D.T a a b))
blankFrame title _ = Opts.title title $ defaultFrameAttr

plotInfo2lineTitle :: (Show id, Show a, Show label) => DataPlot.PlotInfo id (Cut label a) -> (LineSpec.T -> LineSpec.T)
plotInfo2lineTitle (DataPlot.PlotInfo _ (Just cut))  = LineSpec.title $ show cut
plotInfo2lineTitle (DataPlot.PlotInfo ident Nothing)  =  LineSpec.title $ show ident

plotInfo3lineTitles :: (Show label, Show id,Show a) => Int -> PlotData id label a b -> (LineSpec.T -> LineSpec.T)
plotInfo3lineTitles _ (PlotData info _ _) = plotInfo2lineTitle info

labledFrame ::
  (Ord a, Ord b, Show label, Show id, Atom.C a, Atom.C b) =>
  String -> [PlotData id label a b] -> Opts.T (Graph3D.T a a b)
labledFrame title xs =
  Opts.xLabel (DataPlot.makeAxisLabel ax1) $
  Opts.yLabel (DataPlot.makeAxisLabel ax2) $
  Opts.zLabel (DataPlot.makeAxisLabelWithIds plotIds ax3) $
  Opts.title title $ defaultFrameAttr
  where
    D3RangeInfo ax1 ax2 ax3 = combineRangeList (head rs) (tail rs)
    rs = map f xs
    f (PlotData _ rangeInfo _) = rangeInfo
    plotIds = collectPlotIds xs

allInOneIO ::(Terminal.C terminal, Atom.C a, Atom.C b)=>
  terminal ->
  ([PlotData id label a b] ->  Opts.T (Graph3D.T a a b)) ->
  (Int -> PlotData id label a b -> (LineSpec.T -> LineSpec.T)) ->
  [PlotData id label a b] ->
  IO()
allInOneIO terminal makeFrameStyle setGraphStyle xs =
  DataPlot.run terminal (makeFrameStyle xs) $ (Foldable.fold $ map g $ zip [0..] xs)
  where g (idx,plotData@(PlotData _ _ plot)) = fmap (Graph3D.lineSpec $ setGraphStyle idx plotData  $ LineSpec.deflt) plot

eachIO :: (Terminal.C terminal, Atom.C a, Atom.C b)=>
  terminal ->
  ([PlotData id label a b] ->  Opts.T (Graph3D.T a a b)) ->
  (Int -> PlotData id label a b -> (LineSpec.T -> LineSpec.T)) ->
  [PlotData id label a b] ->
  IO()
eachIO terminal makeFrameStyle setGraphStyle xs =
  mapM_ (DataPlot.run terminal (makeFrameStyle xs)) $ map g $ zip [0..] xs
  where g (idx,plotData@(PlotData _ _ plot)) = fmap (Graph3D.lineSpec $ setGraphStyle idx plotData $ LineSpec.deflt) plot


class ToPlotData ndContainer dim label vec a b where
  toPlotData :: Caller ->
             Maybe id ->
             (ndContainer :: * -> * -> * -> (* -> *) -> * -> * -> *) inst dim label vec a b ->
             [PlotData id label a b]