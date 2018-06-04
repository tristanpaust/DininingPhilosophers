module DiningPhilosopers where

import Control.Concurrent (threadDelay, forkIO, killThread, ThreadId)
import Control.Concurrent.STM (STM, atomically, retry, TMVar, newTMVarIO, isEmptyTMVar, putTMVar, takeTMVar, check)

import Control.Concurrent.STM.TQueue
  (TQueue, newTQueueIO, writeTQueue, readTQueue, isEmptyTQueue)

import System.IO.Unsafe (unsafePerformIO)
import System.Random (randomRIO)
import Data.Traversable (for)
import Control.Monad (forever)

data Fork = Fork Int
type OutputQ = TQueue String

-- Wait for a random number of seconds within the given range.
wait :: Int -> Int -> IO ()
wait n m = do
  delay <- randomRIO (n*10^6, m*10^6)
  threadDelay delay

-- Check whether left fork is available right now and return true if so
checkLeftForkStatus :: [TMVar Fork] -> Int -> STM Bool
checkLeftForkStatus forks i = isEmptyTMVar (forks !! (i - 1 `mod` (length forks)))

-- Check whether right fork is available right now and return true if so
checkRightForkStatus :: [TMVar Fork] -> Int -> STM Bool
checkRightForkStatus forks i = isEmptyTMVar (forks !! (i `mod` (length forks)))

-- Get the fork on the left
getLeftFork :: [TMVar Fork] -> Int -> TMVar Fork
getLeftFork forks i = ((forks !! (i - 1 `mod` (length forks))))

-- Get the fork on the right
getRightFork :: [TMVar Fork] -> Int -> TMVar Fork
getRightFork forks i = ((forks !! (i `mod` (length forks))))

-- Get the corret fork ids for the current philosopher (eg 0,1 for the first philosopher, or 0,4 for the fifth one)
getLeftForkID :: Int -> Int -> Int
getLeftForkID i n = (i - 1 `mod` n)

getRightForkID :: Int -> Int -> Int
getRightForkID i n = (i `mod` n)

forkAvailable :: TMVar Fork -> STM Bool
forkAvailable forkTV = not <$> isEmptyTMVar forkTV

philosophers :: [TMVar Fork] -> Int -> Int -> IO ()
philosophers forks i n = forever $ do 
  (leftFork, rightFork) <- atomically $ do
    takeLeftFork  <- forkAvailable (getLeftFork forks i) -- Is left fork free?
    takeRightFork <- forkAvailable (getRightFork forks i) -- Is right fork free?
    if (takeLeftFork && takeRightFork) then do -- True, True -> Take them both and start eating, otherwise keep on trying
      a <- takeTMVar (getLeftFork forks i) 
      b <- takeTMVar (getRightFork forks i)
      return (a,b)
    else retry
  say $ "Philosopher " ++ show i ++ " is eating with forks " ++ show (getLeftForkID i n, getRightForkID i n)
  wait 5 20
  atomically $ do -- Done eating, put forks aside and go back to thinking for some time
    putTMVar (getLeftFork forks i) leftFork
    putTMVar (getRightFork forks i) rightFork
  say $ "Philosopher " ++ show i ++ " puts the forks aside and starts thinking "
  wait 5 20

-- Messaging part
say :: String -> IO ()
say = sayIO stdoutQ

stdoutQ :: OutputQ
stdoutQ = unsafePerformIO newTQueueIO

sayIO :: OutputQ -> String -> IO ()
sayIO out message = atomically (sayTo out message)

sayTo :: OutputQ -> String -> STM ()
sayTo out message = writeTQueue out message

processOutput :: OutputQ -> IO ThreadId
processOutput out = forkIO $ forever $ do
  message <- atomically (readTQueue out)
  putStrLn message
  return ()

processStdout :: IO ThreadId
processStdout = processOutput stdoutQ

waitForOutput :: OutputQ -> IO ()
waitForOutput out = atomically $ do
  b <- isEmptyTQueue out
  check b

waitForStdout :: IO ()
waitForStdout = waitForOutput stdoutQ

-- End of messaging part

main :: IO ()
main = do
  -- Number of philosophers
  let n = 5
  forks <- mapM (newTMVarIO . Fork) [1..n]
  outp <- processStdout
  philosophy <- for [1..n] $ \i -> do 
    forkIO $ (philosophers forks i n)

  -- Wait for user to press enter to end the simulation
  getLine

  -- Shut down all processes
  for philosophy killThread
  waitForStdout
  killThread outp