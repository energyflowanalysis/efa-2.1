{-# LANGUAGE TypeFamilies #-}
module EFA.Flow.Draw (
   pdf, png, xterm,
   eps, plain, svg,
   fig, dot,
   title, bgcolour,

   seqFlowGraph,
   stateFlowGraph,

   Options, optionsDefault,
   absoluteVariable, deltaVariable,
   showVariableIndex, hideVariableIndex,
   showCarryEdge, hideCarryEdge,
   showStorage, hideStorage,
   showEtaNode, hideEtaNode,
   modifyTitle,

   cumulatedFlow,

   topology,
   labeledTopology,

   flowSection,
   flowTopology,
   flowTopologies,
   ) where

import qualified EFA.Flow.Sequence.Quantity as SeqFlowQuant
import qualified EFA.Flow.State.Quantity as StateFlowQuant
import qualified EFA.Flow.Cumulated.Quantity as CumFlowQuant
import qualified EFA.Flow.Storage.Quantity as StorageQuant
import qualified EFA.Flow.Storage.Index as StorageIdx
import qualified EFA.Flow.Storage as Storage
import qualified EFA.Flow.Topology.Quantity as FlowTopoQuant
import qualified EFA.Flow.Topology as FlowTopo
import qualified EFA.Flow.Part.Index as PartIdx
import qualified EFA.Flow.Part.Map as PartMap
import qualified EFA.Flow.SequenceState.Variable as Var
import qualified EFA.Flow.SequenceState.Index as Idx

import qualified EFA.Graph.Topology.Node as Node
import qualified EFA.Graph.Topology as Topo
import qualified EFA.Graph as Graph; import EFA.Graph (Graph)
import EFA.Graph.Topology (FlowTopology)
import EFA.Graph (DirEdge(DirEdge))

import qualified EFA.Report.Format as Format
import EFA.Report.FormatValue (FormatValue, formatValue, formatAssign)
import EFA.Report.Format (Format, Unicode(Unicode, unUnicode))

import qualified EFA.Equation.RecordIndex as RecIdx

import EFA.Signal.Signal (SignalIdx(SignalIdx), Range(Range))

import qualified EFA.Utility.Map as MapU
import EFA.Utility ((>>!))

import Data.GraphViz (
          GraphID(Num, Str), Number(Int),
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
          Attribute(Color, FillColor), Color(RGB), toColorList,
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
import Data.Tuple.HT (mapFst)
import Data.Monoid ((<>))

import Control.Category ((.))
import Control.Monad (void, guard)

import Prelude hiding (sin, reverse, init, last, sequence, (.))



topologyEdgeColour :: Attribute
topologyEdgeColour = Color $ toColorList [RGB 0 0 200]

carryEdgeColour :: Attribute
carryEdgeColour = Color $ toColorList [RGB 200 0 0]

contentEdgeColour :: Attribute
contentEdgeColour = Color $ toColorList [RGB 0 200 0]

shape :: Node.Type -> Viz.Shape
shape Node.Crossing = Viz.PlainText
shape Node.Source = Viz.DiamondShape
shape Node.AlwaysSource = Viz.MDiamond
shape Node.Sink = Viz.BoxShape
shape Node.AlwaysSink = Viz.MSquare
shape Node.Storage = Viz.Ellipse
shape _ = Viz.BoxShape

color :: Node.Type -> Attribute
color Node.Storage = FillColor $ toColorList [RGB 251 177 97] -- ghlightorange
color _ = FillColor $ toColorList [RGB 136 215 251]  -- ghverylightblue

nodeAttrs :: Node.Type -> Attribute -> [Attribute]
nodeAttrs nt label =
  [ label, Viz.Style [Viz.SItem Viz.Filled []],
    Viz.Shape (shape nt), color nt ]

attrsFromNode :: (Node.C node) => node -> Attribute -> [Attribute]
attrsFromNode node label = nodeAttrs (Node.typ node) label


data Triple a = Triple a a a

instance Foldable Triple where
   foldMap f (Triple pre eta suc) = f pre <> f eta <> f suc

data TopologyEdgeLabel =
     HideEtaNode [Unicode]
   | ShowEtaNode (Triple [Unicode])


dotFromFlowGraph ::
   (Part part, Node.C node) =>
   ([DotSubGraph T.Text], [DotEdge T.Text]) ->
   Map node
      ((Unicode, Unicode),
       Map (StorageIdx.Edge part) [Unicode]) ->
   Map part (String, Graph node Graph.EitherEdge Unicode TopologyEdgeLabel) ->
   DotGraph T.Text
dotFromFlowGraph (contentGraphs, contentEdges) sts sq =
   dotDirGraph $
   DotStmts {
      attrStmts = [],
      subGraphs =
         (Map.elems $ Map.mapWithKey dotFromPartGraph sq)
         ++
         dotFromInitExitNodes sq
            (Idx.NoExit Idx.Init, Idx.Exit)
            (fmap fst sts)
         ++
         contentGraphs,
      nodeStmts = [],
      edgeStmts =
         (dotFromCarryEdges $ fmap snd sts)
         ++
         contentEdges
   }


dotFromStorageGraphs ::
   (Node.C node, FormatValue a, Ord (edge node), Graph.Edge edge) =>
   Map node (Map Idx.Boundary a) ->
   Map Idx.Section (Graph node edge (FlowTopoQuant.Sums v) edgeLabel) ->
   ([DotSubGraph T.Text], [DotEdge T.Text])
dotFromStorageGraphs storages sequence =
   (Map.elems $ Map.mapWithKey dotFromStorageGraph $
    fmap (fmap formatValue) $ MapU.flip storages,
    (\(last, inner) ->
       dotFromContentEdge Nothing Idx.initSection
          (fmap (const $ Just Topo.In) storages) ++
       dotFromContentEdge (Just last) Idx.exitSection
          (fmap (const $ Just Topo.Out) storages) ++
       fold inner) $
    Map.mapAccumWithKey
       (\before current gr ->
          (Idx.afterSection current,
           dotFromContentEdge (Just before) (Idx.augment current) $
           fmap FlowTopoQuant.dirFromSums $
           Map.filterWithKey (\node _ -> Node.isStorage $ Node.typ node) $
           Graph.nodeLabels gr))
       Idx.initial sequence)

dotFromStorageGraph ::
   (Node.C node) =>
   Idx.Boundary -> Map node Unicode ->
   DotSubGraph T.Text
dotFromStorageGraph bnd ns =
   DotSG True
      (Just $ Str $ T.pack $ "b" ++ dotIdentFromBoundary bnd) $
   DotStmts
      [GraphAttrs [labelFromString $ "After " ++
       case bnd of
          Idx.Following Idx.Init -> "Init"
          Idx.Following (Idx.NoInit (Idx.Section s)) -> show s]]
      []
      (Map.elems $
       Map.mapWithKey
          (\node -> dotFromBndNode (Idx.PartNode bnd node)) ns)
      []


dotFromInitExitNodes ::
   (Part part, Node.C node) =>
   map part dummy ->
   (Idx.Augmented part, Idx.Augmented part) ->
   Map node (Unicode, Unicode) ->
   [DotSubGraph T.Text]
dotFromInitExitNodes _ (init, exit) initExit =
   dotFromInitOrExitNodes init "Init" (fmap fst initExit) :
   dotFromInitOrExitNodes exit "Exit" (fmap snd initExit) :
   []

dotFromInitOrExitNodes ::
   (Part part, Node.C node) =>
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
   (Part part, Node.C node) =>
   part ->
   (String,
    Graph node Graph.EitherEdge Unicode TopologyEdgeLabel) ->
   DotSubGraph T.Text
dotFromPartGraph current (subtitle, gr) =
   DotSG True (Just $ Str $ T.pack $ dotIdentFromPart current) $
   let (nodes, edges) = dotNodesEdgesFromPartGraph gr
   in  DotStmts
          [GraphAttrs [labelFromString subtitle]]
          []
          (map (dotNodeInPart current) nodes)
          (map (dotEdgeInPart current) edges)

dotNodesEdgesFromPartGraph ::
   Node.C node =>
   Graph node Graph.EitherEdge Unicode TopologyEdgeLabel ->
   ([DotNode T.Text], [DotEdge T.Text])
dotNodesEdgesFromPartGraph gr =
   let (etaNodes,edges) =
          fold $
          Map.mapWithKey
             (\e labels ->
                let eo = orientFlowEdge e
                in  case labels of
                       ShowEtaNode l ->
                          mapFst (:[]) $ dotFromTopologyEdgeEta eo l
                       HideEtaNode l ->
                          ([], [dotFromTopologyEdgeCompact eo l])) $
          Graph.edgeLabels gr
   in  ((Map.elems $
         Map.mapWithKey dotFromNode $
         Graph.nodeLabels gr)
          ++
          etaNodes,
        edges)


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

modifyTitle :: String -> DotGraph T.Text -> DotGraph T.Text
modifyTitle str =
  Accessor.modify (attrStmtsAcc . graphStatementsAcc) (map g)
  where g (GraphAttrs attrs) = GraphAttrs $ map f attrs
        g x = x
        f (Viz.Label (Viz.StrLabel txt)) =
          Viz.Label (Viz.StrLabel (T.append txt (T.pack str)))
        f x = x

bgcolour :: X11Colors.X11Color -> DotGraph T.Text -> DotGraph T.Text
bgcolour c =
   setGlobalAttrs $ GraphAttrs [Viz.BgColor $ toColorList [Colors.X11Color c]]


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


dotFromNode ::
   (Node.C node) =>
   node -> Unicode -> DotNode T.Text
dotFromNode node label =
   DotNode
      (dotIdentFromNode node)
      (attrsFromNode node $ labelFromUnicode label)

dotFromAugNode ::
   (Part part, Node.C node) =>
   Idx.Augmented part -> node -> Unicode -> DotNode T.Text
dotFromAugNode part node label =
   DotNode
      (dotIdentFromAugNode $ Idx.PartNode part node)
      (attrsFromNode node $ labelFromUnicode label)

dotFromBndNode ::
   (Node.C node) =>
   Idx.BndNode node -> Unicode -> DotNode T.Text
dotFromBndNode n label =
   DotNode
      (dotIdentFromBndNode n)
      (nodeAttrs Node.Storage $ labelFromUnicode label)

dotFromTopologyEdgeCompact ::
   (Node.C node) =>
   (DirEdge node, Viz.DirType, Order) ->
   [Unicode] -> DotEdge T.Text
dotFromTopologyEdgeCompact (DirEdge x y, dir, ord) label =
   DotEdge
      (dotIdentFromNode x)
      (dotIdentFromNode y)
      [labelFromLines $ order ord label,
       Viz.Dir dir, topologyEdgeColour]

dotFromTopologyEdgeEta ::
   (Node.C node) =>
   (DirEdge node, Viz.DirType, Order) ->
   Triple [Unicode] ->
   (DotNode T.Text, [DotEdge T.Text])
dotFromTopologyEdgeEta (DirEdge x y, dir, ord) label =
   let Triple pre eta suc = order ord label
       did = dotIdentFromEtaNode x y
   in  (DotNode did [labelFromLines eta],
        [DotEdge
            (dotIdentFromNode x) did
            [labelFromLines pre,
             Viz.Dir dir, topologyEdgeColour],
         DotEdge
            did (dotIdentFromNode y)
            [labelFromLines suc,
             Viz.Dir dir, topologyEdgeColour]])

dotFromCarryEdges ::
   (Node.C node, Part part) =>
   Map node (Map (StorageIdx.Edge part) [Unicode]) ->
   [DotEdge T.Text]
dotFromCarryEdges =
   fold .
   Map.mapWithKey
      (\node ->
         Map.elems .
         Map.mapWithKey
            (\edge -> dotFromCarryEdge (Idx.ForStorage edge node)))

dotFromCarryEdge ::
   (Node.C node, Part part) =>
   Idx.ForStorage (StorageIdx.Edge part) node ->
   [Unicode] -> DotEdge T.Text
dotFromCarryEdge e lns =
   DotEdge
      (dotIdentFromAugNode $ Idx.carryEdgeFrom e)
      (dotIdentFromAugNode $ Idx.carryEdgeTo   e)
      [labelFromLines lns, Viz.Dir Viz.Forward,
       carryEdgeColour, Viz.Constraint True]

dotFromContentEdge ::
   (Node.C node) =>
   Maybe Idx.Boundary ->
   Idx.AugmentedSection ->
   Map node (Maybe Topo.StoreDir) ->
   [DotEdge T.Text]
dotFromContentEdge mbefore aug =
   let dotEdge from to =
          DotEdge from to [Viz.Dir Viz.Forward, contentEdgeColour]
   in  fold .
       Map.mapWithKey
          (\n dir ->
             let sn = Idx.PartNode aug n
                 withBefore f =
                    foldMap (\before -> f $ Idx.PartNode before n) mbefore
                 withCurrent f =
                    foldMap (\current -> f $ Idx.PartNode current n) $
                    Idx.boundaryFromAugSection aug
             in  (withBefore $ \from ->
                  withCurrent $ \to ->
                  [dotEdge (dotIdentFromBndNode from) (dotIdentFromBndNode to)])
                 ++
                 case dir of
                    Nothing -> []
                    Just Topo.In ->
                       withCurrent $ \bn ->
                          [dotEdge (dotIdentFromAugNode sn) (dotIdentFromBndNode bn)]
                    Just Topo.Out ->
                       withBefore $ \bn ->
                          [dotEdge (dotIdentFromBndNode bn) (dotIdentFromAugNode sn)])



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


dotNodeInPart ::
   Part part =>
   part -> DotNode T.Text -> DotNode T.Text
dotNodeInPart part (DotNode x attrs) =
   DotNode (dotIdentInPart part x) attrs

dotEdgeInPart ::
   Part part =>
   part -> DotEdge T.Text -> DotEdge T.Text
dotEdgeInPart part (DotEdge x y attrs) =
   DotEdge (dotIdentInPart part x) (dotIdentInPart part y) attrs

dotIdentInPart ::
   (Part part) => part -> T.Text -> T.Text
dotIdentInPart s =
   T.append (T.pack $ "s" ++ dotIdentFromPart s)

dotIdentFromNode ::
   (Node.C node) => node -> T.Text
dotIdentFromNode n =
   T.pack $ "n" ++ Node.dotId n


dotIdentFromAugNode ::
   (Part part, Node.C node) => Idx.AugNode part node -> T.Text
dotIdentFromAugNode (Idx.PartNode b n) =
   T.pack $ "s" ++ dotIdentFromAugmented b ++ "n" ++ Node.dotId n

dotIdentFromAugmented :: (Part part) => Idx.Augmented part -> String
dotIdentFromAugmented =
   Idx.switchAugmented "init" "exit" dotIdentFromPart

dotIdentFromBndNode :: (Node.C node) => Idx.BndNode node -> T.Text
dotIdentFromBndNode (Idx.PartNode b n) =
   T.pack $ "b" ++ dotIdentFromBoundary b ++ "n" ++ Node.dotId n

dotIdentFromBoundary :: Idx.Boundary -> String
dotIdentFromBoundary (Idx.Following a) =
   case a of
      Idx.Init -> "init"
      Idx.NoInit s -> dotIdentFromPart s

dotIdentFromEtaNode ::
   (Node.C node) =>
   node -> node -> T.Text
dotIdentFromEtaNode x y =
   T.pack $
      "x" ++ Node.dotId x ++
      "y" ++ Node.dotId y


topology :: (Node.C node) => Topo.Topology node -> DotGraph T.Text
topology =
   dotFromTopology .
   Graph.mapNodeWithKey (\node () -> Node.display node) .
   Graph.mapEdge (const Format.empty)

labeledTopology ::
   (Node.C node) => Topo.LabeledTopology node -> DotGraph T.Text
labeledTopology =
   dotFromTopology .
   Graph.mapNodeWithKey
      (\node lab ->
         if null lab
           then Node.display node
           else Format.literal lab) .
   Graph.mapEdge Format.literal

dotFromTopology ::
   (Node.C node) =>
   Graph node Graph.DirEdge Unicode Unicode ->
   DotGraph T.Text
dotFromTopology g =
   DotGraph {
      strictGraph = False,
      directedGraph = False,
      graphID = graphIDInt 1,
      graphStatements =
         DotStmts {
            attrStmts = [],
            subGraphs = [],
            nodeStmts =
               Map.elems $ Map.mapWithKey dotFromTopoNode $ Graph.nodeLabels g,
            edgeStmts =
               Map.elems $ Map.mapWithKey dotFromTopoEdge $ Graph.edgeLabels g
         }
   }

dotFromTopoNode ::
   (Node.C node) =>
   node -> Unicode -> DotNode T.Text
dotFromTopoNode node lab =
   DotNode
      (dotIdentFromNode node)
      (attrsFromNode node $ labelFromUnicode lab)

dotFromTopoEdge ::
   (Node.C node) =>
   DirEdge node -> Unicode -> DotEdge T.Text
dotFromTopoEdge e lab =
   case orientDirEdge e of
      (DirEdge x y, _, _) ->
         DotEdge
            (dotIdentFromNode x)
            (dotIdentFromNode y)
            [ Viz.Dir Viz.NoDir, topologyEdgeColour, labelFromUnicode lab ]


flowTopologies ::
   (Node.C node) =>
   [FlowTopology node] -> DotGraph T.Text
flowTopologies ts =
   DotGraph False True Nothing $
   DotStmts [] (zipWith dotFromFlowTopology [0..] ts) [] []

dotFromFlowTopology ::
   (Node.C node) =>
   Int -> FlowTopology node -> DotSubGraph T.Text
dotFromFlowTopology ident topo =
   DotSG True (graphIDInt ident) $
   DotStmts
      [GraphAttrs [labelFromString $ show ident]] []
      (map dotNode $ Graph.nodes topo)
      (map dotEdge $ Graph.edges topo)
  where idf x = T.pack $ show ident ++ "_" ++ Node.dotId x
        dotNode node =
           DotNode (idf node)
              (attrsFromNode node $ labelFromUnicode $ formatTypedNode node)
        dotEdge edge =
           case orientEdge edge of
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
   Graph.EitherEdge node ->
   (DirEdge node, Viz.DirType, Order)
orientFlowEdge e =
   case e of
      Graph.EUndirEdge ue -> (orientUndirEdge ue, Viz.NoDir, Id)
      Graph.EDirEdge de -> orientDirEdge de

orientEdge ::
   (Ord node) =>
   Graph.EitherEdge node -> (DirEdge node, Viz.DirType, Order)
orientEdge e =
   case e of
      Graph.EUndirEdge ue -> (orientUndirEdge ue, Viz.NoDir, Id)
      Graph.EDirEdge de -> orientDirEdge de

orientUndirEdge :: Ord node => Graph.UndirEdge node -> DirEdge node
orientUndirEdge (Graph.UndirEdge x y) = DirEdge x y

orientDirEdge ::
   (Ord node) =>
   DirEdge node -> (DirEdge node, Viz.DirType, Order)
orientDirEdge (DirEdge x y) =
--   if comparing (\(Idx.SecNode s n) -> n) x y == LT
   if x < y
     then (DirEdge x y, Viz.Forward, Id)
     else (DirEdge y x, Viz.Back, Reverse)


showType :: Node.Type -> String
showType typ =
   case typ of
      Node.Storage       -> "Storage"
      Node.Sink          -> "Sink"
      Node.AlwaysSink    -> "AlwaysSink"
      Node.Source        -> "Source"
      Node.AlwaysSource  -> "AlwaysSource"
      Node.Crossing      -> "Crossing"
      Node.DeadNode      -> "DeadNode"
      Node.NoRestriction -> "NoRestriction"


formatNodeType ::
   (Format output) =>
   Node.Type -> output
formatNodeType = Format.literal . showType

formatTypedNode ::
   (Node.C node) =>
   node -> Unicode
formatTypedNode n =
   Unicode $ unUnicode (Node.display n) ++ " - " ++ showType (Node.typ n)


data Options output =
   Options {
      optRecordIndex :: output -> output,
      optVariableIndex :: Bool,
      optCarryEdge :: Bool,
      optStorage :: Bool,
      optEtaNode :: Bool
   }

optionsDefault :: Format output => Options output
optionsDefault =
   Options {
      optRecordIndex = id,
      optVariableIndex = False,
      optCarryEdge = True,
      optStorage = False,
      optEtaNode = False
   }

absoluteVariable, deltaVariable,
   showVariableIndex, hideVariableIndex,
   showCarryEdge, hideCarryEdge,
   showStorage, hideStorage,
   showEtaNode, hideEtaNode
   :: Format output => Options output -> Options output
absoluteVariable opts =
   opts { optRecordIndex = Format.record RecIdx.Absolute }

deltaVariable opts =
   opts { optRecordIndex = Format.record RecIdx.Delta }

showVariableIndex opts = opts { optVariableIndex = True }
hideVariableIndex opts = opts { optVariableIndex = False }

{-
If storage edges are shown then the subgraphs are not aligned vertically.
-}
showCarryEdge opts = opts { optCarryEdge = True }
hideCarryEdge opts = opts { optCarryEdge = False }

showStorage opts = opts { optStorage = True }
hideStorage opts = opts { optStorage = False }

showEtaNode opts = opts { optEtaNode = True }
hideEtaNode opts = opts { optEtaNode = False }



flowTopology ::
   (FormatValue v, Node.C node) =>
   Options Unicode -> FlowTopoQuant.Topology node v -> DotGraph T.Text
flowTopology opts =
   dotDirGraph .
   uncurry (DotStmts [] []) .
   dotNodesEdgesFromTopology opts

flowSection ::
   (FormatValue v, Node.C node) =>
   Options Unicode -> FlowTopoQuant.Section node v -> DotGraph T.Text
flowSection opts (FlowTopo.Section dt gr) =
   dotDirGraph .
   (\sgr ->
       DotStmts {
          subGraphs = [sgr],
          attrStmts = [],
          nodeStmts = [],
          edgeStmts = []
       }) $
   DotSG True Nothing $
   uncurry (DotStmts [GraphAttrs [labelFromString $ formatTime dt]] []) $
   dotNodesEdgesFromTopology opts gr

dotNodesEdgesFromTopology ::
   (FormatValue v, Node.C node) =>
   Options Unicode -> FlowTopoQuant.Topology node v ->
   ([DotNode T.Text], [DotEdge T.Text])
dotNodesEdgesFromTopology opts =
   dotNodesEdgesFromPartGraph .
   Graph.mapNodeWithKey
      (\node sums ->
         stateNodeShow node $
         guard False >>! FlowTopoQuant.sumIn sums) .
   Graph.mapEdgeWithKey
      (\edge flow ->
         topologyEdgeShow opts $
         FlowTopoQuant.liftEdgeFlow
            (FlowTopoQuant.mapFlowWithVar (formatAssignSidesWithOpts opts))
            edge flow)


seqFlowGraph ::
   (FormatValue a, FormatValue v, Node.C node) =>
   Options Unicode -> SeqFlowQuant.Graph node a v -> DotGraph T.Text
seqFlowGraph opts gr =
   dotFromFlowGraph
      (if optStorage opts
         then
            dotFromStorageGraphs
               (fmap snd $ SeqFlowQuant.storages gr)
               (fmap (FlowTopo.topology . snd) $ SeqFlowQuant.sequence gr)
         else ([], []))
      (Map.mapWithKey
          (\node -> storageGraphShow opts node . fst) $
       SeqFlowQuant.storages gr)
      (snd $
       Map.mapAccumWithKey
          (\before sec (rng, FlowTopo.Section dt topo) ->
             (,) (Idx.afterSection sec) $
             (show sec ++
              " / Range " ++ formatRange rng ++
              " / " ++ formatTime dt,
              Graph.mapNodeWithKey
                 (\node sums ->
                    let (Storage.Graph partMap _, stores) =
                           maybe (error "missing node") id $
                           Map.lookup node $
                           SeqFlowQuant.storages gr
                    in  formatNodeStorage opts node
                           (let content bnd =
                                   Map.findWithDefault
                                      (error "no storage content") bnd stores
                            in  (content before,
                                 content $ Idx.afterSection sec))
                           (fmap (maybe (error "missing section") (flip (,)) $
                                  PartMap.lookup sec partMap) $
                            FlowTopoQuant.dirFromSums sums)) $
              Graph.mapEdgeWithKey (structureSeqStateEdgeShow opts sec) topo))
          Idx.initial $
       SeqFlowQuant.sequence gr)


formatRange :: Range -> String
formatRange (Range (SignalIdx from) (SignalIdx to)) =
   show from ++ "-" ++ show to

formatNodeStorage ::
   (FormatValue a, Format output, Node.C node) =>
   Options output ->
   node ->
   (a, a) -> Maybe (Topo.StoreDir, a) -> output
formatNodeStorage opts node beforeAfter sinout =
   case Node.typ node of
      ty ->
         Format.lines $
         Node.display node :
         formatNodeType ty :
            case ty of
               Node.Storage ->
                  if optStorage opts
                    then formatStorageUpdate sinout
                    else formatStorageEquation beforeAfter sinout
               _ -> []


formatStorageUpdate ::
   (FormatValue a, Format output) =>
   Maybe (Topo.StoreDir, a) -> [output]
formatStorageUpdate sinout =
   case sinout of
      Just (_, s)  -> [formatValue s]
      Nothing -> []


formatStorageEquation ::
   (FormatValue a, Format output) =>
   (a, a) -> Maybe (Topo.StoreDir, a) -> [output]
formatStorageEquation (before, after) sinout =
   formatValue before :
   (case sinout of
      Just (Topo.In,  s) -> [Format.plus  Format.empty $ formatValue s]
      Just (Topo.Out, s) -> [Format.minus Format.empty $ formatValue s]
      Nothing -> []) ++
   Format.assign Format.empty (formatValue after) :
   []


stateFlowGraph ::
   (FormatValue a, FormatValue v, Node.C node) =>
   Options Unicode -> StateFlowQuant.Graph node a v -> DotGraph T.Text
stateFlowGraph opts gr =
   dotFromFlowGraph
      ([], [])
      (Map.mapWithKey (storageGraphShow opts) $
       StateFlowQuant.storages gr)
      (Map.mapWithKey
          (\state (FlowTopo.Section dt topo) ->
             (show state ++ " / " ++ formatTime dt,
              Graph.mapNodeWithKey
                 (\node _sums ->
                    stateNodeShow node $ PartMap.lookup state $
                    maybe (error "Draw.stateFlowGraph") Storage.nodes $
                    Map.lookup node $
                    StateFlowQuant.storages gr) $
              Graph.mapEdgeWithKey (structureSeqStateEdgeShow opts state) topo)) $
       StateFlowQuant.states gr)

storageGraphShow ::
   (StorageQuant.Carry carry, StorageQuant.CarryPart carry ~ part,
    PartIdx.Format part, Format output, Node.C node, FormatValue a) =>
   Options output ->
   node ->
   Storage.Graph part a (carry a) ->
   ((output, output), Map (StorageIdx.Edge part) [output])
storageGraphShow opts node (Storage.Graph partMap edges) =
   ((stateNodeShow node $ Just $ PartMap.init partMap,
     stateNodeShow node $ Just $ PartMap.exit partMap),
    if optCarryEdge opts
      then Map.mapWithKey (carryEdgeShow opts node) edges
      else Map.empty)

stateNodeShow ::
   (Node.C node, FormatValue a, Format output) =>
   node -> Maybe a -> output
stateNodeShow node msum =
   case Node.typ node of
      ty ->
         Format.lines $
         Node.display node :
         formatNodeType ty :
            case ty of
               Node.Storage -> maybeToList $ fmap formatValue msum
               _ -> []

carryEdgeShow ::
   (StorageQuant.Carry carry, StorageQuant.CarryPart carry ~ part,
    PartIdx.Format part, Node.C node, FormatValue a, Format output) =>
   Options output ->
   node ->
   StorageIdx.Edge part ->
   carry a ->
   [output]
carryEdgeShow opts node edge carry =
   Fold.toList $
   StorageQuant.mapCarryWithVar (formatAssignWithOpts opts) node edge carry


structureSeqStateEdgeShow ::
   (PartIdx.Format part, Node.C node, FormatValue a) =>
   Options Unicode ->
   part ->
   Graph.EitherEdge node ->
   Maybe (FlowTopoQuant.Flow a) ->
   TopologyEdgeLabel
structureSeqStateEdgeShow opts part edge flow =
   topologyEdgeShow opts $
   FlowTopoQuant.liftEdgeFlow
      (FlowTopoQuant.mapFlowWithVar (formatAssignSidesWithOpts opts . Idx.InPart part))
      edge flow

topologyEdgeShow ::
   Options Unicode ->
   Maybe (FlowTopoQuant.Flow (Unicode, Unicode)) -> TopologyEdgeLabel
topologyEdgeShow opts =
   if optEtaNode opts
     then ShowEtaNode . topologyEdgeShowEta
     else HideEtaNode . topologyEdgeShowCompact

topologyEdgeShowCompact ::
   (Format output) =>
   Maybe (FlowTopoQuant.Flow (output, output)) -> [output]
topologyEdgeShowCompact mlabels =
   case fmap (fmap (uncurry Format.assign)) mlabels of
      Nothing -> []
      Just labels ->
         FlowTopoQuant.flowXOut labels :
         FlowTopoQuant.flowEnergyOut labels :
         FlowTopoQuant.flowEta labels :
         FlowTopoQuant.flowEnergyIn labels :
         FlowTopoQuant.flowXIn labels :
         []

topologyEdgeShowEta ::
   (Format output) =>
   Maybe (FlowTopoQuant.Flow (output, output)) -> Triple [output]
topologyEdgeShowEta mlabels =
   case mlabels of
      Nothing -> Triple [] [] []
      Just flow ->
         case fmap (uncurry Format.assign) flow of
            labels ->
               Triple
                  (FlowTopoQuant.flowXOut labels :
                   FlowTopoQuant.flowEnergyOut labels :
                   [])
                  (snd (FlowTopoQuant.flowEta flow) :
                   [])
                  (FlowTopoQuant.flowEnergyIn labels :
                   FlowTopoQuant.flowXIn labels :
                   [])


cumulatedFlow ::
   (Node.C node, FormatValue a) =>
   CumFlowQuant.Graph node a ->
   DotGraph T.Text
cumulatedFlow =
   graph .
   Graph.mapNodeWithKey (const . dotFromCumNode) .
   Graph.mapEdgeWithKey
      (\e flow ->
         dotFromCumEdge e (CumFlowQuant.flowDTime flow) $
         map ($flow) $
            CumFlowQuant.flowXOut :
            CumFlowQuant.flowPowerOut :
            CumFlowQuant.flowEnergyOut :
            CumFlowQuant.flowEta :
            CumFlowQuant.flowEnergyIn :
            CumFlowQuant.flowPowerIn :
            CumFlowQuant.flowXIn :
            []) .
   CumFlowQuant.mapGraphWithVar formatAssign


dotFromCumNode ::
   (Node.C node) =>
   node -> DotNode T.Text
dotFromCumNode n =
   DotNode (dotIdentFromNode n) $
   attrsFromNode n $ labelFromUnicode $ Node.display n

dotFromCumEdge ::
   (Node.C node) =>
   Graph.DirEdge node -> Unicode -> [Unicode] -> DotEdge T.Text
dotFromCumEdge e hd label =
   case orientDirEdge e of
      (DirEdge x y, dir, ord) ->
         DotEdge
            (dotIdentFromNode x) (dotIdentFromNode y)
            [labelFromLines $ hd : order ord label,
             Viz.Dir dir, topologyEdgeColour]


graph ::
   (Node.C node) =>
   Graph node Graph.DirEdge (DotNode T.Text) (DotEdge T.Text) ->
   DotGraph T.Text
graph g =
   dotDirGraph $
   DotStmts {
      attrStmts = [],
      subGraphs = [],
      nodeStmts = Map.elems $ Graph.nodeLabels g,
      edgeStmts = Map.elems $ Graph.edgeLabels g
   }


dotDirGraph :: DotStatements str -> DotGraph str
dotDirGraph stmts =
   DotGraph {
      strictGraph = False,
      directedGraph = True,
      graphID = graphIDInt 1,
      graphStatements = stmts
   }

graphIDInt :: Int -> Maybe GraphID
graphIDInt = Just . Num . Int


formatTime :: FormatValue a => a -> String
formatTime dt =
   "Time " ++ unUnicode (formatValue dt)

formatAssignWithOpts ::
   (Node.C node, Var.FormatIndex idx, Idx.Identifier idx,
    FormatValue a, Format output) =>
   Options output -> idx node -> a -> output
formatAssignWithOpts opts idx val =
   uncurry Format.assign $ formatAssignSidesWithOpts opts idx val

formatAssignSidesWithOpts ::
   (Node.C node, Var.FormatIndex idx, Idx.Identifier idx,
    FormatValue a, Format output) =>
   Options output -> idx node -> a -> (output, output)
formatAssignSidesWithOpts opts idx val =
   (optRecordIndex opts $
    if optVariableIndex opts
      then Var.formatIndex idx
      else Idx.identifier idx,
    formatValue val)
