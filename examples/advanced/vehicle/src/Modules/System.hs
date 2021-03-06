{-# LANGUAGE FlexibleContexts #-}

module Modules.System where

import EFA.Application.Utility (topologyFromLabeledEdges)

import qualified EFA.Flow.Topology.Index as TopoIdx

import EFA.Signal.Record (SigId(SigId))

import qualified EFA.Graph.Topology.Node as Node
import qualified EFA.Graph.Topology as Topo

import qualified Data.Map as Map
import Data.Map (Map)


data Node =
     Tank
--   | EngineFlange
   | ConBattery
   | Battery
   | ConES
--   | MotorFlange
   | ConFrontBrakes
   | Chassis
   | Resistance
   | ElectricSystem
   | FrontBrakes
   | VehicleInertia
   | RearBrakes
   deriving (Eq, Ord, Enum, Show)

instance Node.C Node where
   display = Node.displayDefault
   subscript = Node.subscriptDefault
   dotId = Node.dotIdDefault
   typ t =
      case t of
         Tank -> Node.Source
         ConBattery -> Node.Crossing
         Battery -> Node.storage
         ConES -> Node.Crossing
         ConFrontBrakes -> Node.Crossing
         Chassis -> Node.Crossing
         Resistance -> Node.Sink
         ElectricSystem -> Node.Sink
         FrontBrakes -> Node.Sink
         RearBrakes -> Node.Sink
         VehicleInertia -> Node.storage

----------------------------------------------------------------------
-- * Define System Topology
topology :: Topo.Topology Node
topology = Topo.plainFromLabeled labeledTopology

labeledTopology :: Topo.LabeledTopology Node
labeledTopology = topologyFromLabeledEdges edgeList

-- Define Edges with all their Properties
edgeList :: [(Node, Node, String, String, String)]
edgeList = [(Tank, ConBattery, "Engine&Generator", "Fuel","GeneratorClamps"),
            (ConBattery, ConES,"Wire","Wire","Wire"),
            (ConES, ConFrontBrakes,"Motor&Gearbox","MotorClamps","OutShaft"),
            (ConFrontBrakes, Chassis, "FrontWheels","FrontWheelHub","FrontTires"),
            (Chassis, Resistance,"ToResistance","ToResistance","ToResistance"),
            (ConBattery, Battery,"BatteryResistance","BatteryClamps","BatteryCore"),
            (ConES, ElectricSystem,"DCDC","HighVoltage","LowVoltage"),
            (ConFrontBrakes, FrontBrakes,"ToFrontBrakes","ToFrontBrakes","ToFrontBrakes"),
            (Chassis, RearBrakes,"RearWheels","RearTires", "RearWheelHubs"),
            (Chassis, VehicleInertia,"ToIntertia","ToInertia", "ToInertia")]


powerPositonNames :: Map (TopoIdx.Position Node) SigId
powerPositonNames = Map.fromList $ concat $ map f edgeList
  where f (n1,n2,_,l1,l2) = [(TopoIdx.ppos n1 n2, SigId $ "Power-"++l1),
                             (TopoIdx.ppos n2 n1, SigId $ "Power-"++l2)]

showPowerId :: TopoIdx.Position Node -> String
showPowerId ppos =
  maybe (show ppos) show $ Map.lookup  ppos powerPositonNames

convertPowerId :: TopoIdx.Position Node -> SigId
convertPowerId ppos =
  Map.findWithDefault (SigId $ show ppos) ppos powerPositonNames
