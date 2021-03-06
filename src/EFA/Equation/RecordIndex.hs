module EFA.Equation.RecordIndex where

import qualified EFA.Equation.Mix as Mix


data Absolute = Absolute deriving (Show, Eq, Ord)


data Delta = Before | Delta | After deriving (Show, Eq, Ord)

data ExtDelta rec = ExtDelta Delta rec deriving (Show, Eq, Ord)


data Mix dir pos = MixTotal | MixComponent pos deriving (Show, Eq, Ord)

data ExtMix dir pos rec = ExtMix (Mix dir pos) rec deriving (Show, Eq, Ord)

type SinkMix = Mix Mix.Sink
type SourceMix = Mix Mix.Source

type ExtSinkMix = ExtMix Mix.Sink
type ExtSourceMix = ExtMix Mix.Source


data Record rec idx = Record rec idx deriving (Show, Eq)

-- this ordering is easier to read than the default one
instance (Ord rec, Ord idx) => Ord (Record rec idx) where
   compare (Record rx ix) (Record ry iy) =
      case compare ix iy of
         EQ -> compare rx ry
         o -> o

instance Functor (Record rec) where
   fmap f (Record rec idx) = Record rec $ f idx

absolute :: idx -> Record Absolute idx
absolute = Record Absolute

delta :: idx -> Record Delta idx
delta = Record Delta

before :: idx -> Record Delta idx
before = Record Before

after :: idx -> Record Delta idx
after = Record After


mixTotal :: (Mix.Direction dir) => idx -> Record (Mix dir pos) idx
mixTotal = Record MixTotal

mixComponent :: (Mix.Direction dir) => pos -> idx -> Record (Mix dir pos) idx
mixComponent = Record . MixComponent
