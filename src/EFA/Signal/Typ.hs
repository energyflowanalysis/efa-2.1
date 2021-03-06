{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE EmptyDataDecls #-}

module EFA.Signal.Typ where


--------------------------------
-- Type Variable
data Typ d t p

-- d = delta flag
-- t = EFA Typ
-- p = partial flag
-- a = average flag

--------------------------------
-- Accessors to the type parameters
getDelta :: Typ d t p -> d
getDelta _ = error "Signal.Typ.getDelta: got phantom type"

getType :: Typ d t p -> t
getType _ = error "Signal.Typ.getType: got phantom type"

getPartial :: Typ d t p -> p
getPartial _ = error "Signal.Typ.getPartial: got phantom type"


data UT -- Untyped

--------------------------------
-- | Physical Types & Classification

-- Time Variables
data T -- Time
data P -- Power
data P' -- Power Derivate dP/dt


-- Flow Variable (Edges)
-- data PF -- Power
data F -- Energy Flow is F = DE ?
data N -- Flow Efficiency
data X -- Flow Divider
data Y -- Flow Merger

-- Flow Variables (Knodes)
data FI -- Sum Flow in
data FO -- Sum Flow out

-- Storage Variables
data E -- Energy Storage or Consumption
data NE -- Efficiency of Stored Energy
data M -- Storage Mix

-- Logic Variables
data BZ -- Bool State
data IZ -- Int State
data UZ -- User Defined State


-- Zero Crossing
data SZ -- sign State
data STy -- step stype
data ETy -- event type

-------------------------------------
-- | Delta Flag
data A -- Absolute
data D -- Delta
data DD -- Delta Delta
data DDD -- Delta Delta Delta

class DSucc d1 d2 | d1 -> d2
instance DSucc A D
instance DSucc D DD
instance DSucc DD DDD


--data Neutral
--data Zero
--data Succ a

--type A = Zero
--type D = Succ Zero
--type DD = Succ (Succ Zero)

-------------------------------------
-- | Partial Flag

data Tt -- Total
data Pt -- Partial



{-
class Succ d1 d2 | d1 -> d2, d2 -> d1
instance Succ A D
instance Succ D DD
instance Succ DD DDD

class Prec d1 d2
instance Succ d1 d2 => Prec d2 d1
-}
-------------------------------------
--  |Type Arithmetic
-- Typ aendert sich
-- delta und partial spielen hin und wieder eine Rolle

class TProd t1 t2 t3 | t1 t2 -> t3, t2 t3 -> t1, t1 t3 -> t2

-- F = P*dt - Flow and Power
-- Power Slope -- Interpolation
instance  TProd (Typ A P' p) (Typ D T p) (Typ D P p)
instance  TProd (Typ D T p) (Typ A P' p) (Typ D P p)

instance  TProd (Typ A P' p) (Typ A T p) (Typ A P p)
instance  TProd (Typ A T p) (Typ A P' p) (Typ A P p)

-- Time to Flow
instance  TProd (Typ D T p) (Typ A P p) (Typ A F p)
instance TProd (Typ A P p) (Typ D T p) (Typ A F p)

-- F=N*F -- Flow and Flow Efficiency
instance TProd (Typ d F p) (Typ d N p) (Typ d F p)
instance TProd (Typ d N p) (Typ d F p) (Typ d F p)

instance TProd (Typ d P p) (Typ d N p) (Typ d P p)
instance TProd (Typ d N p) (Typ d P p) (Typ d P p)

-- E=M*E -- Energy mix and Mix Part
instance TProd (Typ d E Tt) (Typ d M Tt) (Typ d E Pt)
instance TProd (Typ d M Tt) (Typ d E Tt) (Typ d E Pt)

-- F=X*FO -- Energy mix and Mix Part
instance TProd (Typ d FO Tt) (Typ d X Tt) (Typ d F Pt)
instance TProd (Typ d X Tt) (Typ d FO Tt) (Typ d F Pt)

-- F=Y*FI -- Energy mix and Mix Part
instance TProd (Typ d FI Tt) (Typ d Y Tt) (Typ d F Pt)
instance TProd (Typ d Y Tt) (Typ d FI Tt) (Typ d F Pt)

-- Untyped remains untyped
instance TProd (Typ UT UT UT) (Typ UT UT UT) (Typ UT UT UT)



-- Addition & Subtraction

-- Alles muss Identisch sein, nur Delta veraendert sich

class TSum t1 t2 t3 | t1 t2 -> t3, t2 t3 -> t1, t1 t3 -> t2

instance TSum (Typ A t p) (Typ D t p) (Typ A t p)
instance TSum (Typ D t p) (Typ A t p) (Typ A t p)
--instance TSum (Typ Zero t p) (Typ (Succ Zero) t p) (Typ Zero t p)

--instance (TSum (Typ d t p) (Type (Succ d) t p) (Type d t p)) => TSum (Typ (Succ d) t p) (Typ (Succ (Succ d)) t p) (Typ (Succ d) t p)

--instance TSum (Typ DD t p) (Typ D t p) (Typ D t p)



instance TSum (Typ D t p) (Typ DD t p) (Typ D t p)
instance TSum (Typ DD t p) (Typ D t p) (Typ D t p)

instance TSum (Typ DD t p) (Typ DDD t p) (Typ DD t p)
instance TSum (Typ DDD t p) (Typ DD t p) (Typ DD t p)

-- Untyped remains untyped
instance TSum (Typ UT UT UT) (Typ UT UT UT) (Typ UT UT UT)
