{-# LANGUAGE TypeFamilies #-}
module EFA.Flow.Draw (
   pdf, png, xterm,
   eps, plain, svg,
   fig, dot,
   title, bgcolour,

   sequFlowGraph,
   stateFlowGraph,

   Options, optionsDefault,
   absoluteVariable, deltaVariable,
   showVariableIndex, hideVariableIndex,
   showStorageEdge, hideStorageEdge,
   showStorage, hideStorage,
   showEtaNode, hideEtaNode,

   cumulatedFlow,

   topologyWithEdgeLabels,
   topology,
   flowTopologies,
   ) where

import qualified EFA.Flow.Sequence.Quantity as SeqFlowQuant
import qualified EFA.Flow.State.Quantity as StateFlowQuant
import qualified EFA.Flow.Cumulated.Quantity as CumFlowQuant
import qualified EFA.Flow.Quantity as FlowQuant

import qualified EFA.Flow.Sequence as SeqFlow
import qualified EFA.Flow.State as StateFlow

import qualified EFA.Report.Format as Format
import EFA.Report.FormatValue (FormatValue, formatValue)
import EFA.Report.Format (Format, Unicode(Unicode, unUnicode))

import qualified EFA.Equation.Variable as Var

import qualified EFA.Signal.SequenceData as SD
import EFA.Signal.Signal (SignalIdx(SignalIdx))

import qualified EFA.Graph.Topology.Index as Idx
import qualified EFA.Graph.Topology.Node as Node
import qualified EFA.Graph.Topology as Topo
import qualified EFA.Graph as Gr
import EFA.Graph.Topology (FlowTopology)
import EFA.Graph (DirEdge(DirEdge))

import Data.GraphViz (
          GraphID(Int, Str),
          GlobalAttributes(GraphAttrs),
          DotEdge(DotEdge),
          DotGraph(DotGraph),
          DotNode(DotNode),
          DotSubGraph(DotSG),
          DotStatements(DotStmts),
          attrStmts, nodeStmts, edgeStmts, graphStatements,
          directedGraph, strictGraph, subGraphs,
          graphID)

import Data.GraphViz.Attributes.Complete (
          Attribute(Color, FillColor), Color(RGB),
          )

import qualified Data.GraphViz.Commands as VizCmd
import qualified Data.GraphViz.Attributes.Complete as Viz
import qualified Data.GraphViz.Attributes.Colors as Colors
import qualified Data.GraphViz.Attributes.Colors.X11 as X11Colors

import qualified Data.Accessor.Basic as Accessor

import qualified Data.Text.Lazy as T

import qualified Data.Foldable as Fold
import qualified Data.Map as Map
import qualified Data.List as List

import Data.Map (Map)
import Data.Foldable (Foldable, foldMap, fold)
import Data.Maybe (maybeToList)
import Data.Tuple.HT (mapFst, mapSnd, mapFst3, mapThd3, fst3, thd3)
import Data.Monoid ((<>))

import Control.Category ((.))
import Control.Monad (void, mplus)

import Prelude hiding (sin, reverse, init, (.))



structureEdgeColour :: Attribute
structureEdgeColour = Color [RGB 0 0 200]

storageEdgeColour :: Attribute
storageEdgeColour = Color [RGB 200 0 0]

shape :: Topo.NodeType a -> Viz.Shape
shape Topo.Crossing = Viz.PlainText
shape Topo.Source = Viz.DiamondShape
shape Topo.AlwaysSource = Viz.MDiamond
shape Topo.Sink = Viz.BoxShape
shape Topo.AlwaysSink = Viz.MSquare
shape (Topo.Storage _) = Viz.Ellipse
shape _ = Viz.BoxShape

color :: Topo.NodeType a -> Attribute
color (Topo.Storage _) = FillColor [RGB 251 177 97] -- ghlightorange
color _ = FillColor [RGB 136 215 251]  -- ghverylightblue

nodeAttrs :: Topo.NodeType a -> Attribute -> [Attribute]
nodeAttrs nt label =
  [ label, Viz.Style [Viz.SItem Viz.Filled []],
    Viz.Shape (shape nt), color nt ]


data Triple a = Triple a a a

instance Foldable Triple where
   foldMap f (Triple pre eta suc) = f pre <> f eta <> f suc

data StructureEdgeLabel =
     HideEtaNode [Unicode]
   | ShowEtaNode (Triple [Unicode])


dotFromSeqFlowGraph ::
   (NodeType node) =>
   SeqFlow.Graph node Gr.EitherEdge
      String Unicode Unicode Unicode Unicode
      StructureEdgeLabel [Unicode] ->
   DotGraph T.Text
dotFromSeqFlowGraph g =
   dotDirGraph $
   DotStmts {
      attrStmts = [],
      subGraphs =
         (Map.elems $
          Map.mapWithKey (\sec -> dotFromPartGraph sec . snd) $
          SeqFlow.sequence g)
         ++
         (dotFromInitExitNodes
             (Idx.NoExit Idx.Init :: Idx.AugmentedState,
              Idx.Exit :: Idx.AugmentedState) $
          fmap fst3 $ SeqFlow.storages g),
      nodeStmts = [],
      edgeStmts = dotFromStorageEdges $ fmap thd3 $ SeqFlow.storages g
   }

dotFromStateFlowGraph ::
   (NodeType node) =>
   StateFlow.Graph node Gr.EitherEdge
      String Unicode Unicode Unicode
      StructureEdgeLabel [Unicode] ->
   DotGraph T.Text
dotFromStateFlowGraph g =
   dotDirGraph $
   DotStmts {
      attrStmts = [],
      subGraphs =
         (Map.elems $
          Map.mapWithKey dotFromPartGraph $
          StateFlow.states g)
         ++
         (dotFromInitExitNodes
             (Idx.NoExit Idx.Init :: Idx.AugmentedState,
              Idx.Exit :: Idx.AugmentedState) $
          fmap fst $ StateFlow.storages g),
      nodeStmts = [],
      edgeStmts = dotFromStorageEdges $ fmap snd $ StateFlow.storages g
   }


dotFromInitExitNodes ::
   (Part part, NodeType node) =>
   (Idx.Augmented part, Idx.Augmented part) ->
   Map node (Unicode, Unicode) ->
   [DotSubGraph T.Text]
dotFromInitExitNodes (init, exit) initExit =
   dotFromInitOrExitNodes init "Init" (fmap fst initExit) :
   dotFromInitOrExitNodes exit "Exit" (fmap snd initExit) :
   []

dotFromInitOrExitNodes ::
   (Part part, NodeType node) =>
   Idx.Augmented part ->
   String ->
   Map node Unicode ->
   DotSubGraph T.Text
dotFromInitOrExitNodes part name initExit =
   DotSG True (Just $ Str $ T.pack $ dotIdentFromAugmented part) $
   DotStmts
      [GraphAttrs [labelFromString name]]
      []
      (Map.elems $ Map.mapWithKey (dotFromAugNode part) initExit)
      []


dotFromPartGraph ::
   (Part part, NodeType node) =>
   part ->
   (String,
    Gr.Graph node Gr.EitherEdge Unicode StructureEdgeLabel) ->
   DotSubGraph T.Text
dotFromPartGraph current (subtitle, gr) =
   let (etaNodes,edges) =
          fold $
          Map.mapWithKey
             (\e labels ->
                case labels of
                   ShowEtaNode l ->
                      mapFst (:[]) $ dotFromStructureEdgeEta current e l
                   HideEtaNode l ->
                      ([], [dotFromStructureEdge current e l])) $
          Gr.edgeLabels gr
   in  DotSG True (Just $ Str $ T.pack $ dotIdentFromPart current) $
       DotStmts
          [GraphAttrs [labelFromString subtitle]]
          []
          ((Map.elems $
            Map.mapWithKey (dotFromAugNode (Idx.augment current)) $
            Gr.nodeLabels gr)
           ++
           etaNodes)
          edges


graphStatementsAcc ::
   Accessor.T (DotGraph t) (DotStatements t)
graphStatementsAcc =
   Accessor.fromSetGet (\s g -> g { graphStatements = s }) graphStatements

attrStmtsAcc ::
   Accessor.T (DotStatements n) [GlobalAttributes]
attrStmtsAcc =
   Accessor.fromSetGet (\stmts as -> as { attrStmts = stmts }) attrStmts

setGlobalAttrs :: GlobalAttributes -> DotGraph T.Text -> DotGraph T.Text
setGlobalAttrs attr =
   Accessor.modify (attrStmtsAcc . graphStatementsAcc) (attr:)

title :: String -> DotGraph T.Text -> DotGraph T.Text
title ti =
   setGlobalAttrs $ GraphAttrs [labelFromString ti]

bgcolour :: X11Colors.X11Color -> DotGraph T.Text -> DotGraph T.Text
bgcolour c =
   setGlobalAttrs $ GraphAttrs [Viz.BgColor [Colors.X11Color c]]


pdf, png, eps, svg, plain, fig, dot :: FilePath -> DotGraph T.Text -> IO ()
pdf   = runGraphvizCommand VizCmd.Pdf
png   = runGraphvizCommand VizCmd.Png
eps   = runGraphvizCommand VizCmd.Eps
svg   = runGraphvizCommand VizCmd.Svg
fig   = runGraphvizCommand VizCmd.Fig
dot   = runGraphvizCommand VizCmd.DotOutput
plain = runGraphvizCommand VizCmd.Plain

runGraphvizCommand ::
   VizCmd.GraphvizOutput -> FilePath -> DotGraph T.Text -> IO ()
runGraphvizCommand target path g =
   void $ VizCmd.runGraphvizCommand VizCmd.Dot g target path

xterm :: DotGraph T.Text -> IO ()
xterm g = void $ VizCmd.runGraphvizCanvas VizCmd.Dot g VizCmd.Xlib


dotFromAugNode ::
   (Part part, NodeType node) =>
   Idx.Augmented part -> node -> Unicode -> DotNode T.Text
dotFromAugNode part n label =
   DotNode
      (dotIdentFromAugNode $ Idx.PartNode part n)
      (nodeAttrs (nodeType n) $ labelFromUnicode label)


dotFromStructureEdge ::
   (Node.C node, Part part) =>
   part -> Gr.EitherEdge node -> [Unicode] -> DotEdge T.Text
dotFromStructureEdge part e label =
   let (DirEdge x y, dir, ord) = orientFlowEdge $ Idx.InPart part e
   in  DotEdge
          (dotIdentFromPartNode x) (dotIdentFromPartNode y)
          [labelFromLines $ order ord label,
           Viz.Dir dir, structureEdgeColour]

dotFromStructureEdgeEta ::
   (Node.C node, Part part) =>
   part -> Gr.EitherEdge node ->
   Triple [Unicode] ->
   (DotNode T.Text, [DotEdge T.Text])
dotFromStructureEdgeEta part e label =
   let (DirEdge x y, dir, ord) = orientFlowEdge $ Idx.InPart part e
       Triple pre eta suc = order ord label
       did = dotIdentFromEtaNode x y
   in  (DotNode did [labelFromLines eta],
        [DotEdge
            (dotIdentFromPartNode x) did
            [labelFromLines pre,
             Viz.Dir dir, structureEdgeColour],
         DotEdge
            did (dotIdentFromPartNode y)
            [labelFromLines suc,
             Viz.Dir dir, structureEdgeColour]])

dotFromStorageEdges ::
   (Node.C node, Part part) =>
   Map node (Map (Idx.StorageEdge part node) [Unicode]) ->
   [DotEdge T.Text]
dotFromStorageEdges =
   fold .
   Map.mapWithKey
      (\node ->
         Map.elems .
         Map.mapWithKey
            (\edge -> dotFromStorageEdge (Idx.ForNode edge node)))

dotFromStorageEdge ::
   (Node.C node, Part part) =>
   Idx.ForNode (Idx.StorageEdge part) node ->
   [Unicode] -> DotEdge T.Text
dotFromStorageEdge e lns =
   DotEdge
      (dotIdentFromAugNode $ Idx.storageEdgeFrom e)
      (dotIdentFromAugNode $ Idx.storageEdgeTo   e)
      [labelFromLines lns, Viz.Dir Viz.Forward,
       storageEdgeColour, Viz.Constraint True]


labelFromLines :: [Unicode] -> Attribute
labelFromLines = labelFromString . concatMap (++"\\l") . map unUnicode

labelFromUnicode :: Unicode -> Attribute
labelFromUnicode = labelFromString . unUnicode

labelFromString :: String -> Attribute
labelFromString = Viz.Label . Viz.StrLabel . T.pack


class Part part where
   dotIdentFromPart :: part -> String

instance Part Idx.Section where
   dotIdentFromPart (Idx.Section s) = show s

instance Part Idx.State where
   dotIdentFromPart (Idx.State s) = show s


dotIdentFromPartNode ::
   (Part part, Node.C node) => Idx.PartNode part node -> T.Text
dotIdentFromPartNode (Idx.PartNode s n) =
   T.pack $ "s" ++ dotIdentFromPart s ++ "n" ++ Node.dotId n

dotIdentFromAugNode ::
   (Part part, Node.C node) => Idx.AugNode part node -> T.Text
dotIdentFromAugNode (Idx.PartNode b n) =
   T.pack $ "s" ++ dotIdentFromAugmented b ++ "n" ++ Node.dotId n

dotIdentFromAugmented :: (Part part) => Idx.Augmented part -> String
dotIdentFromAugmented =
   Idx.switchAugmented "init" "exit" dotIdentFromPart


dotIdentFromEtaNode ::
   (Node.C node, Part part) =>
   Idx.PartNode part node -> Idx.PartNode part node -> T.Text
dotIdentFromEtaNode (Idx.PartNode s x) (Idx.PartNode _s y) =
   T.pack $
      "s" ++ dotIdentFromPart s ++
      "x" ++ Node.dotId x ++
      "y" ++ Node.dotId y

dotIdentFromNode :: (Node.C node) => node -> T.Text
dotIdentFromNode n = T.pack $ Node.dotId n


topology :: (Node.C node) => Topo.Topology node -> DotGraph T.Text
topology topo = dotFromTopology Map.empty topo

topologyWithEdgeLabels ::
   (Node.C node) =>
   Map (node, node) String -> Topo.Topology node -> DotGraph T.Text
topologyWithEdgeLabels edgeLabels topo =
   dotFromTopology edgeLabels topo

dotFromTopology ::
   (Node.C node) =>
   Map (node, node) String ->
   Topo.Topology node -> DotGraph T.Text
dotFromTopology edgeLabels g =
   DotGraph {
      strictGraph = False,
      directedGraph = False,
      graphID = Just (Int 1),
      graphStatements =
         DotStmts {
            attrStmts = [],
            subGraphs = [],
            nodeStmts = map dotFromTopoNode $ Gr.labNodes g,
            edgeStmts = map (dotFromTopoEdge edgeLabels) $ Gr.edges g
         }
   }

dotFromTopoNode ::
  (Node.C node, StorageLabel store) =>
  Gr.LNode node (Topo.NodeType store) -> DotNode T.Text
dotFromTopoNode (x, typ) =
  DotNode
    (dotIdentFromNode x)
    (nodeAttrs typ $ labelFromUnicode $ Node.display x)

dotFromTopoEdge ::
  (Node.C node) =>
  Map (node, node) String ->
  DirEdge node -> DotEdge T.Text
dotFromTopoEdge edgeLabels e =
  case orientDirEdge e of
     (DirEdge x y, _, _) ->
           let lab = T.pack $ fold $ Map.lookup (x, y) edgeLabels
           in  DotEdge
                 (dotIdentFromNode x)
                 (dotIdentFromNode y)
                 [ Viz.Dir Viz.NoDir, structureEdgeColour,
                   Viz.Label $ Viz.StrLabel lab, Viz.EdgeTooltip lab ]


flowTopologies ::
   (Node.C node) =>
   [FlowTopology node] -> DotGraph T.Text
flowTopologies ts = DotGraph False True Nothing stmts
   where stmts = DotStmts attrs subgs [] []
         subgs = zipWith dotFromFlowTopology [0..] ts
         attrs = []

dotFromFlowTopology ::
   (Node.C node) =>
   Int -> FlowTopology node -> DotSubGraph T.Text
dotFromFlowTopology ident topo =
   DotSG True (Just (Int ident)) $
   DotStmts
      [GraphAttrs [labelFromString $ show ident]] []
      (map mkNode $ Gr.labNodes topo)
      (map mkEdge $ Gr.edges topo)
  where idf x = T.pack $ show ident ++ "_" ++ Node.dotId x
        mkNode x@(n, t) =
           DotNode (idf n)
              (nodeAttrs t $ labelFromUnicode $ formatTypedNode x)
        mkEdge el =
           case orientEdge el of
              (DirEdge x y, d, _) ->
                 DotEdge (idf x) (idf y) [Viz.Dir d]


class Reverse s where
   reverse :: s -> s

instance Reverse [s] where
   reverse = List.reverse

instance (Reverse a) => Reverse (Triple a) where
   reverse (Triple pre eta suc) =
      Triple (reverse suc) (reverse eta) (reverse pre)


data Order = Id | Reverse deriving (Eq, Show)

order :: Reverse s => Order -> s -> s
order Id = id
order Reverse = reverse


orientFlowEdge ::
   (Ord node) =>
   Idx.InPart part Gr.EitherEdge node ->
   (DirEdge (Idx.PartNode part node), Viz.DirType, Order)
orientFlowEdge (Idx.InPart sec e) =
   mapFst3 (fmap (Idx.PartNode sec)) $
   case e of
      Gr.EUnDirEdge ue -> (orientUndirEdge ue, Viz.NoDir, Id)
      Gr.EDirEdge de -> orientDirEdge de

orientEdge ::
   (Ord node) =>
   Gr.EitherEdge node -> (DirEdge node, Viz.DirType, Order)
orientEdge e =
   case e of
      Gr.EUnDirEdge ue -> (orientUndirEdge ue, Viz.NoDir, Id)
      Gr.EDirEdge de -> orientDirEdge de

orientUndirEdge :: Ord node => Gr.UnDirEdge node -> DirEdge node
orientUndirEdge (Gr.UnDirEdge x y) = DirEdge x y

orientDirEdge ::
   (Ord node) =>
   DirEdge node -> (DirEdge node, Viz.DirType, Order)
orientDirEdge (DirEdge x y) =
--   if comparing (\(Idx.SecNode s n) -> n) x y == LT
   if x < y
     then (DirEdge x y, Viz.Forward, Id)
     else (DirEdge y x, Viz.Back, Reverse)


class StorageLabel a where
   formatStorageLabel :: a -> String

instance StorageLabel () where
   formatStorageLabel () = ""

instance Show a => StorageLabel (Maybe a) where
   formatStorageLabel Nothing = ""
   formatStorageLabel (Just dir) = " " ++ show dir


showType :: StorageLabel store => Topo.NodeType store -> String
showType typ =
   case typ of
      Topo.Storage store -> "Storage" ++ formatStorageLabel store
      Topo.Sink          -> "Sink"
      Topo.AlwaysSink    -> "AlwaysSink"
      Topo.Source        -> "Source"
      Topo.AlwaysSource  -> "AlwaysSource"
      Topo.Crossing      -> "Crossing"
      Topo.DeadNode      -> "DeadNode"
      Topo.NoRestriction -> "NoRestriction"


formatNodeType ::
   (Format output, StorageLabel store) =>
   Topo.NodeType store -> output
formatNodeType = Format.literal . showType

formatTypedNode ::
   (Node.C node, StorageLabel store) =>
   (node, Topo.NodeType store) -> Unicode
formatTypedNode (n, l) =
   Unicode $ unUnicode (Node.display n) ++ " - " ++ showType l


data Options output =
   Options {
      optRecordIndex :: output -> output,
      optVariableIndex :: Bool,
      optStorageEdge :: Bool,
      optStorage :: Bool,
      optEtaNode :: Bool
   }

optionsDefault :: Format output => Options output
optionsDefault =
   Options {
      optRecordIndex = id,
      optVariableIndex = False,
      optStorageEdge = True,
      optStorage = False,
      optEtaNode = False
   }

absoluteVariable, deltaVariable,
   showVariableIndex, hideVariableIndex,
   showStorageEdge, hideStorageEdge,
   showStorage, hideStorage,
   showEtaNode, hideEtaNode
   :: Format output => Options output -> Options output
absoluteVariable opts =
   opts { optRecordIndex = Format.record Idx.Absolute }

deltaVariable opts =
   opts { optRecordIndex = Format.record Idx.Delta }

showVariableIndex opts = opts { optVariableIndex = True }
hideVariableIndex opts = opts { optVariableIndex = False }

{-
If storage edges are shown then the subgraphs are not aligned vertically.
-}
showStorageEdge opts = opts { optStorageEdge = True }
hideStorageEdge opts = opts { optStorageEdge = False }

showStorage opts = opts { optStorage = True }
hideStorage opts = opts { optStorage = False }

showEtaNode opts = opts { optEtaNode = True }
hideEtaNode opts = opts { optEtaNode = False }



sequFlowGraph ::
   (FormatValue a, FormatValue v, NodeType node) =>
   Options Unicode -> SeqFlowQuant.Graph node a v -> DotGraph T.Text
sequFlowGraph opts =
   dotFromSeqFlowGraph
   .
   (\gr ->
      SeqFlow.Graph {
         SeqFlowQuant.storages =
            Map.mapWithKey
               (\node ((init,exit), bnds, edges) ->
                  ((stateNodeShow node (Just init),
                    stateNodeShow node (Just exit)),
                   fmap formatValue bnds,
                   Map.mapWithKey (storageEdgeSeqShow opts node) edges)) $
            SeqFlowQuant.storages gr,
         SeqFlowQuant.sequence =
            Map.mapWithKey
               (\sec (rng, (dt,topo)) ->
                  (,) rng $
                  (show sec ++
                   " / Range " ++ formatRange rng ++
                   " / Time " ++ unUnicode (formatValue dt),
                   Gr.mapNodeWithKey
                      (\node sums ->
                         stateNodeShow node $
                         fmap SeqFlowQuant.carrySum $
                         mplus
                            (SeqFlowQuant.sumOut sums)
                            (SeqFlowQuant.sumIn sums)) $
                   Gr.mapEdgeWithKey
                      (\edge ->
                         if optEtaNode opts
                           then ShowEtaNode . structureEdgeShowEta opts sec edge
                           else HideEtaNode . structureEdgeShow opts sec edge)
                      topo)) $
            SeqFlowQuant.sequence gr
      })
   .
   (\g ->
      if optStorageEdge opts
        then g
        else g {SeqFlowQuant.storages =
                  fmap (mapThd3 $ const Map.empty) $
                  SeqFlowQuant.storages g})


formatRange :: SD.Range -> String
formatRange (SignalIdx from, SignalIdx to) =
   show from ++ "-" ++ show to

stateFlowGraph ::
   (FormatValue a, FormatValue v, NodeType node) =>
   Options Unicode -> StateFlowQuant.Graph node a v -> DotGraph T.Text
stateFlowGraph opts =
   dotFromStateFlowGraph
   .
   (\gr ->
      StateFlow.Graph {
         StateFlowQuant.storages =
            Map.mapWithKey
               (\node ((init,exit), edges) ->
                  ((stateNodeShow node (Just init),
                    stateNodeShow node (Just exit)),
                   Map.mapWithKey (storageEdgeStateShow opts node) edges)) $
            StateFlowQuant.storages gr,
         StateFlowQuant.states =
            Map.mapWithKey
               (\state (dt,topo) ->
                  (show state ++ " / Time " ++ unUnicode (formatValue dt),
                   Gr.mapNodeWithKey
                      (\node sums ->
                         stateNodeShow node $
                         fmap StateFlowQuant.carrySum $
                         mplus
                            (StateFlowQuant.sumOut sums)
                            (StateFlowQuant.sumIn sums)) $
                   Gr.mapEdgeWithKey
                      (\edge ->
                         if optEtaNode opts
                           then ShowEtaNode . structureEdgeShowEta opts state edge
                           else HideEtaNode . structureEdgeShow opts state edge)
                      topo)) $
            StateFlowQuant.states gr
      })
   .
   (\g ->
      if optStorageEdge opts
        then g
        else g {StateFlowQuant.storages =
                  fmap (mapSnd $ const Map.empty) $
                  StateFlowQuant.storages g})


stateNodeShow ::
   (NodeType node, FormatValue a, Format output) =>
   node -> Maybe a -> output
stateNodeShow node msum =
   case nodeType node of
      ty ->
         Format.lines $
         Node.display node :
         formatNodeType ty :
            case ty of
               Topo.Storage _ -> maybeToList $ fmap formatValue msum
               _ -> []

storageEdgeSeqShow ::
   (Node.C node, FormatValue a, Format output) =>
   Options output ->
   node ->
   Idx.StorageEdge Idx.Section node ->
   SeqFlowQuant.Carry a ->
   [output]
storageEdgeSeqShow opts node edge carry =
   case SeqFlowQuant.mapCarryWithVar
           (formatAssignWithOpts opts) node edge carry of
      labels ->
         SeqFlowQuant.carryMaxEnergy labels :
         SeqFlowQuant.carryEnergy labels :
         SeqFlowQuant.carryXOut labels :
         SeqFlowQuant.carryXIn labels :
         []

storageEdgeStateShow ::
   (Node.C node, FormatValue a, Format output) =>
   Options output ->
   node ->
   Idx.StorageEdge Idx.State node ->
   StateFlowQuant.Carry a ->
   [output]
storageEdgeStateShow opts node edge carry =
   case StateFlowQuant.mapCarryWithVar
           (formatAssignWithOpts opts) node edge carry of
      labels ->
         StateFlowQuant.carryEnergy labels :
         StateFlowQuant.carryXOut labels :
         StateFlowQuant.carryXIn labels :
         []

structureEdgeShow ::
   (Node.C node, Ord part, FormatValue a, Format.Part part, Format output) =>
   Options output ->
   part -> Gr.EitherEdge node ->
   Maybe (FlowQuant.Flow a) -> [output]
structureEdgeShow opts part =
   FlowQuant.switchEdgeFlow (const []) $ \edge flow ->
   case FlowQuant.mapFlowWithVar (formatAssignWithOpts opts) part edge flow of
      labels ->
         FlowQuant.flowEnergyOut labels :
         FlowQuant.flowXOut labels :
         FlowQuant.flowEta labels :
         FlowQuant.flowXIn labels :
         FlowQuant.flowEnergyIn labels :
         []

structureEdgeShowEta ::
   (Node.C node, Ord part, FormatValue a, Format.Part part, Format output) =>
   Options output ->
   part -> Gr.EitherEdge node ->
   Maybe (FlowQuant.Flow a) -> Triple [output]
structureEdgeShowEta opts part =
   FlowQuant.switchEdgeFlow (const $ Triple [] [] []) $ \edge flow ->
   case FlowQuant.mapFlowWithVar (formatAssignWithOpts opts) part edge flow of
      labels ->
         Triple
            (FlowQuant.flowEnergyOut labels :
             FlowQuant.flowXOut labels :
             [])
            (formatValue (FlowQuant.flowEta flow) :
             [])
            (FlowQuant.flowXIn labels :
             FlowQuant.flowEnergyIn labels :
             [])


cumulatedFlow ::
   (NodeType node, FormatValue a) =>
   CumFlowQuant.Graph node a ->
   DotGraph T.Text
cumulatedFlow =
   graph .
   Gr.mapNodeWithKey (const . dotFromCumNode) .
   Gr.mapEdge (labelFromLines . Fold.toList) .
   CumFlowQuant.mapGraphWithVar formatAssign


dotFromCumNode ::
   (NodeType node) =>
   node -> Viz.Attributes
dotFromCumNode x =
   nodeAttrs (nodeType x) $ labelFromUnicode $ Node.display x


class Node.C node => NodeType node where
   nodeType :: node -> Topo.NodeType ()


graph ::
   (Node.C node) =>
   Gr.Graph node Gr.DirEdge Viz.Attributes Attribute ->
   DotGraph T.Text
graph g =
   dotDirGraph $
   DotStmts {
      attrStmts = [],
      subGraphs = [],
      nodeStmts = map dotFromNode $ Gr.labNodes g,
      edgeStmts = map dotFromEdge $ Gr.labEdges g
   }

dotFromNode ::
   (Node.C node) =>
   Gr.LNode node Viz.Attributes -> DotNode T.Text
dotFromNode (n, attrs) =
   DotNode (dotIdentFromNode n) attrs

dotFromEdge ::
   (Node.C node) =>
   Gr.LEdge Gr.DirEdge node Attribute -> DotEdge T.Text
dotFromEdge (e, label) =
   case orientDirEdge e of
      (DirEdge x y, dir, _) ->
         DotEdge
            (dotIdentFromNode x) (dotIdentFromNode y)
            [label, Viz.Dir dir, structureEdgeColour]


dotDirGraph :: DotStatements str -> DotGraph str
dotDirGraph stmts =
   DotGraph {
      strictGraph = False,
      directedGraph = True,
      graphID = Just (Int 1),
      graphStatements = stmts
   }


formatAssign ::
   (FormatValue var, FormatValue a, Format output) =>
   var -> a -> output
formatAssign var val =
   Format.assign (formatValue var) (formatValue val)

formatAssignWithOpts ::
   (Node.C node, Var.FormatIndex idx, Format.EdgeIdx idx,
    FormatValue a, Format output) =>
   Options output -> idx node -> a -> output
formatAssignWithOpts opts idx val =
   Format.assign
      (if optVariableIndex opts
         then Var.formatIndex idx
         else Format.edgeIdent idx)
      (formatValue val)