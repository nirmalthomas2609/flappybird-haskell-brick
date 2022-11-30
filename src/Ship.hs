{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE TemplateHaskell #-}
module Ship
  ( initGame
  , step
  , turn
  , Game(..)
  , Direction(..)
  , dead, rocks, score, ship
  , height, width
  ) where

import Control.Applicative ((<|>))
import Control.Monad (guard)
import Data.Maybe (fromMaybe)

import Control.Lens hiding ((<|), (|>), (:>), (:<))
import Control.Monad.Trans.Maybe
import Control.Monad.Trans.State
import Control.Monad.Extra (orM)
import Data.Sequence (Seq(..), (<|))
import qualified Data.Sequence as S
import Linear.V2 (V2(..), _x, _y)
import System.Random (Random(..), newStdGen)

data Game = Game
  { _ship  :: Ship        -- ^ snake as a sequence of points in N2
  , _rocks   :: [Rock]        -- ^ location of the food
  , _rockGenerator  :: [(Int, Int)] -- ^ infinite list of random next food locations
  , _dead   :: Bool         -- ^ game over flag
  , _score  :: Int          -- ^ score
  } deriving (Show)

type Coord = (Int, Int)

type Rock = (Coord, Int)

type Ship = [Coord]

data Stream a = a :| Stream a
  deriving (Show)

data Direction
  = North
  | South
  | East
  | West
  deriving (Eq, Show)

makeLenses ''Game

-- Constants

height, width :: Int
height = 30
width = 30

nextRocks :: State Game ()
nextRocks = do
  (f : fs) <- use rockGenerator
  rockGenerator .= fs
  rocks .= rocks ++ [rockProducer f]
  return ()



-- killRocks :: Game -> Game
-- killRocks g@Game {_rocks = (r:rs)}
--   | r == ((0, 0), 1) = killRocks (g & rocks .~ rs)

isRockEnd :: Rock -> Bool
isRockEnd ((0, _), 1)       = True
isRockEnd ((x, _), 0)
  | x == width-1  = True
  | otherwise   = False
isRockEnd _                 = False

killRocks :: [Rock] -> [Rock]
killRocks rrs@(r:rs)
  | isRockEnd r  = killRocks rs
  | otherwise    = rrs
killRocks [] = []

moveRocks :: [Rock] -> [Rock]
moveRocks []                = []
moveRocks (((x, y), 0):rs)  = ((x+1, y), 0):moveRocks rs
moveRocks (((x, y), 1):rs)  = ((x-1, y), 1):moveRocks rs

moveSpace :: Game -> Game
moveSpace g@Game { _rocks = rrs } = g & rocks .~ (killRocks (moveRocks rrs))

startingCoords :: Ship
startingCoords = [(5, 5)]

rockProducer :: (Int, Int) -> Rock
rockProducer (0, x) = ((0, x), 0)
rockProducer (_, x) = ((width - 1, x), 1)

rocksGenerator :: IO [(Int, Int)]
rocksGenerator = do
  g <- newStdGen
  return $ randomRs ((0, 5) , (1, height - 1)) g

hasCollided :: Ship -> Rock -> Bool
hasCollided (s:ss) (rc, rd) = s==rc || hasCollided ss (rc, rd)
hasCollided [] _            = False

hasCollidedRocks :: Ship -> [Rock] -> Bool
hasCollidedRocks s (r:rs)   = hasCollided s r || hasCollidedRocks s rs
hasCollidedRocks s []       = False

addRocksAtRandom :: State Game ()
addRocksAtRandom = do
  (f : fs) <- use rockGenerator
  rockGenerator .= fs
  case f of
    (0, _) -> return ()
    (_, _) -> nextRocks

resetShip :: Game -> Game
resetShip g = g & ship .~ startingCoords

die :: Game -> Game
die g@Game {_ship = s, _rocks = rss}
  | hasCollidedRocks s rss  = resetShip g
  | otherwise               = g

-- movesSpace, die, addRocksAtRandom
step :: Game -> Game
step g = execState addRocksAtRandom (moveSpace (die g))
-- step s = flip execState s . runMaybeT $ do
--   s_ = moveSpace s
--   -- Make sure the game isn't paused or over
--   MaybeT $ guard . not <$> orM [use dead]

--   -- die (moved into boundary), eat (moved into food), or move (move into space)
--   die <|> MaybeT (Just <$> modify move)

directionStep :: Direction -> Coord -> Coord
directionStep d (x,y)
  | d == North  = (x, (y + 1) `mod` height)
  | d == South  = (x, (y - 1) `mod` height)
  | d == East   = ((x + 1) `mod` width, y)
  | otherwise   = ((x - 1) `mod` width, y)

moveShip :: Direction -> Ship -> Ship
moveShip d s = map (directionStep d) s

turn :: Direction -> Game -> Game
turn d g@Game { _ship = s } = g & ship .~ (moveShip d s)

-- turn :: Direction -> Game -> Game
-- turn d g@Game { _snake = (s :|> _) } = if g ^. locked
--   then g
--   else let g_ = (g & dir %~ turnDir d) in g_ & snake .~ (moveShip g_ <| s) & paused .~ False & locked .~ True

initGame :: IO Game
initGame = do
  (f:fs) <- rocksGenerator
  let xm = width `div` 2
      ym = height `div` 2
      g  = Game
        { _ship  = startingCoords 
        , _rocks  = []
        , _rockGenerator  = fs
        , _score  = 0
        , _dead   = False
        }
  return g