{-# LANGUAGE TypeFamilies #-}
module EFA.Flow.Storage.Quantity where

import qualified EFA.Flow.Storage.Variable as StorageVar
import qualified EFA.Flow.Storage.Index as StorageIdx
import qualified EFA.Flow.Storage as Storage

import qualified EFA.Flow.Topology.Quantity as FlowTopo
import qualified EFA.Flow.Part.Index as PartIdx
import qualified EFA.Flow.Part.Map as PartMap

import qualified EFA.Flow.SequenceState.Variable as Var
import qualified EFA.Flow.SequenceState.Index as Idx
import EFA.Equation.Unknown (Unknown(unknown))

import qualified Data.Traversable as Trav
import qualified Data.Map as Map ; import Data.Map (Map)

import Control.Applicative (Applicative, pure, liftA2, (<*>), (<$>))
import Data.Foldable (Foldable)
import Data.Monoid (Monoid)


type Graph carry a = Storage.Graph (CarryPart carry) a (carry a)

class (Applicative f, Foldable f) => Carry f where
   carryEnergy, carryXOut, carryXIn :: f a -> a
   foldEnergy :: (Monoid m) => (a -> m) -> f a -> m

   type CarryPart f :: *
   carryVars ::
      (CarryPart f ~ part) =>
      f (StorageIdx.Edge part -> StorageVar.Scalar part)


mapGraphWithVar ::
   (Carry carry, CarryPart carry ~ part, PartIdx.Format part, Show part) =>
   (Idx.PartNode part node -> Maybe (FlowTopo.Sums v)) ->
   (Var.Scalar part node -> a0 -> a1) ->
   node ->
   Graph carry a0 ->
   Graph carry a1
mapGraphWithVar lookupSums f node (Storage.Graph partMap edges) =
   Storage.Graph
      (PartMap.mapWithVar
          (maybe
              (error "mapStoragesWithVar: missing corresponding sum")
              FlowTopo.dirFromSums .
           lookupSums)
          f node partMap)
      (Map.mapWithKey (mapCarryWithVar f node) edges)

mapCarryWithVar ::
   (Carry carry, CarryPart carry ~ part) =>
   (Var.Scalar part node -> a0 -> a1) ->
   node -> StorageIdx.Edge part -> carry a0 -> carry a1
mapCarryWithVar f node edge =
   liftA2 f (Idx.ForStorage <$> (carryVars <*> pure edge) <*> pure node)


mapGraph ::
   (Functor carry, CarryPart carry ~ part, Ord part) =>
   (a0 -> a1) ->
   Graph carry a0 -> Graph carry a1
mapGraph f =
   Storage.mapNode f . Storage.mapEdge (fmap f)

traverseGraph ::
   (Applicative f, Trav.Traversable carry, CarryPart carry ~ part, Ord part) =>
   (a0 -> f a1) ->
   Graph carry a0 -> f (Graph carry a1)
traverseGraph f =
   Storage.traverse f (Trav.traverse f)


forwardEdgesFromSums ::
   (Ord part) =>
   Map part (FlowTopo.Sums v) -> [StorageIdx.Edge part]
forwardEdgesFromSums stores = do
   let ins  = Map.mapMaybe FlowTopo.sumIn stores
   let outs = Map.mapMaybe FlowTopo.sumOut stores
   secin <- Idx.Init : map Idx.NoInit (Map.keys ins)
   secout <-
      (++[Idx.Exit]) $ map Idx.NoExit $ Map.keys $
      case secin of
         Idx.Init -> outs
         Idx.NoInit s -> snd $ Map.split s outs
   return $ StorageIdx.Edge secin secout

allEdgesFromSums ::
   (Ord part) =>
   Map part (FlowTopo.Sums a) -> [StorageIdx.Edge part]
allEdgesFromSums stores =
   liftA2 StorageIdx.Edge
      (Idx.Init : map Idx.NoInit (Map.keys (Map.mapMaybe FlowTopo.sumIn stores)))
      (Idx.Exit : map Idx.NoExit (Map.keys (Map.mapMaybe FlowTopo.sumOut stores)))

graphFromList ::
   (Carry carry, CarryPart carry ~ part, Ord part, Unknown a) =>
   [part] ->
   [StorageIdx.Edge part] ->
   Graph carry a
graphFromList sts edges =
   Storage.Graph
      (PartMap.constant unknown sts)
      (Map.fromListWith (error "duplicate storage edge") $
       map (flip (,) (pure unknown)) edges)



lookupEnergy ::
   (Carry carry, CarryPart carry ~ part, Ord part) =>
   StorageIdx.Energy part -> Graph carry a -> Maybe a
lookupEnergy (StorageIdx.Energy se) sgr =
   fmap carryEnergy $ Storage.lookupEdge se sgr

lookupX ::
   (Carry carry, CarryPart carry ~ part, Ord part) =>
   StorageIdx.X part -> Graph carry a -> Maybe a
lookupX (StorageIdx.X se) sgr =
   StorageIdx.withEdgeFromPosition
      (fmap carryXIn  . flip Storage.lookupEdge sgr)
      (fmap carryXOut . flip Storage.lookupEdge sgr)
      se

{- |
It is an unchecked error if you lookup StInSum where is only an StOutSum.
-}
lookupInSum ::
   (Carry carry, CarryPart carry ~ part, Ord part) =>
   StorageIdx.InSum part -> Graph carry a -> Maybe a
lookupInSum (StorageIdx.InSum aug) (Storage.Graph partMap _) =
   case aug of
      Idx.Exit -> return $ PartMap.exit partMap
      Idx.NoExit sec -> Map.lookup sec $ PartMap.parts partMap

{- |
It is an unchecked error if you lookup StOutSum where is only an StInSum.
-}
lookupOutSum ::
   (Carry carry, CarryPart carry ~ part, Ord part) =>
   StorageIdx.OutSum part -> Graph carry a -> Maybe a
lookupOutSum (StorageIdx.OutSum aug) (Storage.Graph partMap _) =
   case aug of
      Idx.Init -> return $ PartMap.init partMap
      Idx.NoInit sec -> Map.lookup sec $ PartMap.parts partMap


class (StorageVar.Index idx) => Lookup idx where
   lookup ::
      (Carry carry, CarryPart carry ~ StorageVar.Part idx) =>
      idx -> Graph carry a -> Maybe a

instance (PartIdx.Format sec, Ord sec) => Lookup (StorageIdx.Energy sec) where
   lookup = lookupEnergy

instance (PartIdx.Format sec, Ord sec) => Lookup (StorageIdx.X sec) where
   lookup = lookupX

instance (PartIdx.Format sec, Ord sec) => Lookup (StorageIdx.InSum sec) where
   lookup = lookupInSum

instance (PartIdx.Format sec, Ord sec) => Lookup (StorageIdx.OutSum sec) where
   lookup = lookupOutSum
