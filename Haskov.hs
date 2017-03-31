module Haskov where

import System.Random
import Data.Map.Strict (Map, keys)
import qualified Data.Map.Strict as Map
import Numeric.Container (sub, scale)
import qualified Numeric.Container as Con
import Numeric.LinearAlgebra.Data (Matrix, matrix, col, cols, ident, tr, accum)
import qualified Numeric.LinearAlgebra.Data as Lin
import Numeric.LinearAlgebra.Algorithms (luSolve, luPacked)
import qualified Numeric.LinearAlgebra.Algorithms as Alg
import Numeric.LinearAlgebra.HMatrix (sumElements, cmap)
import qualified Numeric.LinearAlgebra.HMatrix as Hma

-- Markov Type --
data Markov a = Markov { imap :: Map a Int
                                     , hmap :: Map (a, a) Double }
                                     
instance (Show a, Ord a) => Show (Markov a) where 
    show haskov = "fromList " ++ (show $ toList haskov) 

-- Query --
-- Safe query
lookup :: (Ord a) => a -> a -> Markov a -> Maybe Double
lookup i j (Markov imap hmap) = Map.lookup (i, j) hmap

-- Returns number of states
size :: (Ord a) => Markov a -> Int
size (Markov imap hmap) = Map.size imap

-- Returns true if the chain is empty
null :: (Ord a) => Markov a -> Bool
null (Markov imap hmap) = Map.null imap 

-- Returns true if input is a state of the chain
member :: (Ord a) => a -> Markov a -> Bool
member i (Markov imap hmap)
    | (Map.member i imap) = True
    | otherwise = False

-- Returns true if input is not a state of the chain
notMember :: (Ord a) => a -> Markov a -> Bool
notMember i haskov = not (member i haskov)

-- States of the Markov chain 
states :: (Ord a) => Markov a -> [a]
states (Markov imap hmap) = keys imap

statesI :: (Ord a) => Markov a -> Map a Int
statesI (Markov imap hmap) = imap

-- Construction --
empty :: Markov a
empty = Markov (Map.empty) (Map.empty)

--insert :: (Ord a) => a -> a -> Double -> Markov a -> Markov a

-- Lists --
fromList :: (Ord a) => [((a, a), Double)] -> Markov a
fromList list = 
    let hmap = Map.fromList list
        klist = map (fst . fst) list
        imap = foldl (\acc x -> if Map.notMember x acc then Map.insert x (Map.size acc) acc else acc) Map.empty klist
    in Markov imap hmap

toList :: (Ord a) => Markov a -> [((a, a), Double)]
toList (Markov imap hmap) = Map.toList hmap

-- Matrices --
hmatrix :: (Ord a) => Markov a -> Matrix Double
hmatrix (Markov imap hmap) =
    let m = Map.size imap
        zeros = matrix m (replicate (m*m) 0)
        hlist = map (el2I imap) (Map.toList hmap)
    in  Lin.accum zeros (+) hlist

el2I :: (Ord a) => Map a Int -> ((a, a), Double) -> ((Int, Int), Double)
el2I imap ((i, j), d) = ((imap Map.! i, imap Map.! j), d)  


-- Chains -- 
walk :: (Ord a) => Markov a -> Int -> IO [a]
walk haskov n = do 
    gen <- getStdGen
    let mat = hmatrix haskov
        ss = tr . steady $ mat
    return (steps (statesI haskov) mat ss n gen)
    
steps :: (Ord a) => Map a Int -> Matrix Double -> Matrix Double -> Int -> StdGen -> [a]
steps _ _ _ 0 _ = []
steps imap mat row n gen
    | (sumElements row) == 0 = []
    | otherwise = choice : steps imap mat newRow (n-1) (snd rand) 
    where 
        rand = random gen
        choice = keys imap !! randomStep row (fst rand) 0.0 0
        newRow = normalize $ mat Lin.? [(imap Map.! choice)]
        
randomStep :: Matrix Double -> Double -> Double -> Int -> Int
randomStep row rand total j
    | newTotal < rand = randomStep row rand newTotal newJ
    | otherwise       = j
    where
        newTotal = total + (row Lin.! 0 Lin.! j)
        newJ = (j + 1) `mod` (cols row)
        
steadyState :: (Ord a) =>  Markov a -> [(a, Double)]
steadyState haskov = zip (states haskov) (concat . Lin.toLists $ steady (hmatrix haskov))
        
steady :: Matrix Double -> Matrix Double
steady mat =
    let m = Lin.rows mat -- Number of states
        q = tr $ sub (ident m) mat -- Transpose (I-matrix size m - hmatrix)
        e = col ((replicate (m-1) 0) ++ [1.0]) -- col of zeros size m, last element is 1.0
        x = luSolve (luPacked q) e -- Solve linear system of Q and e (Qx = e)
    in  scale (1 / (sumElements x)) x  -- Divide x by sum of elements

normalize :: Matrix Double -> Matrix Double
normalize hmatrix = cmap (/ (sumElements hmatrix)) hmatrix 

-- Machine Epsilon    
machineE :: Double
machineE = until ((== 1) . (+1)) (/2) 1
