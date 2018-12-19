module Main where
--- IMPORTS -----------------------------------------------------------------------------------
import qualified Control.Concurrent      as C
import qualified STMContainers.Map       as M
import qualified Data.List               as L
import qualified Data.Text               as T
import           Network.Connection(initConnectionContext, Connection(..))
import           Control.Exception (try, SomeException)
import           Data.Foldable (traverse_)
import           Data.Maybe    (catMaybes)
import           Control.Monad (zipWithM)
import           Control.Concurrent.STM (atomically)

import Bot.Network
import Bot.Socket
import Bot.StateType
import Bot.Servers
import GHC.Conc (numCapabilities)
--- FUNCTIONS ---------------------------------------------------------------------------------

-- creates a thread and adds its thread ID to an MVar list, kills all
-- listed threads when finished
forkWithKill :: C.MVar [C.ThreadId] -> IO Quit -> IO (C.MVar ())
forkWithKill tids act = do
  handle <- C.newEmptyMVar
  let f (Right AllNetworks)    = kill >> C.putMVar handle ()
      f (Right CurrentNetwork) = C.putMVar handle ()
      f (Left e)               = C.putMVar handle () >> print (show e <> " in forkWithKill")
  C.forkFinally spawn f
  return handle
  where
    spawn = withThread act tids
    kill  = do
      threads <- C.readMVar tids
      mytid   <- C.myThreadId
      traverse_ C.killThread (filter (/= mytid) threads)

withThread :: IO a -> C.MVar [C.ThreadId] -> IO a
withThread act tids = do
  tid <- C.myThreadId
  modifyVar (:) tid *> act <* modifyVar L.delete tid
  where
    modifyVar f tid = C.modifyMVar_ tids (return . f tid)
 --- ENTRY POINT ------------------------------------------------------------------------------

main :: IO ()
main = do
  putStrLn $ "number of cores: " ++ show numCapabilities
  nets  <- readNetworks "data/networks.json"
  state <- toGlobalState <$> M.newIO
  case nets of
       Nothing       -> putStrLn "ERROR loading servers from JSON"
       Just networks -> do
         initHash networks (hash state)
         servMap <- initAllServer
         tids    <- C.newMVar []
         ctx     <- initConnectionContext
         let listenTry :: (Connection, C.MVar Quit) -> IRCNetwork -> IO (Either SomeException Quit)
             listenTry x n = try (listen x servMap (netServer n) state)
             listenRetry network (Right x) = return x
             listenRetry network (Left e) = do
               x <- reconnectNetwork servMap ctx network
               listenTry x network >>= listenRetry network
         handles <- do
           mConnVar    <- traverse (startNetwork servMap ctx) networks
           let connVar = catMaybes mConnVar
           zipWithM (\x n -> forkWithKill tids
                             $ listenTry x n >>= listenRetry n) connVar networks
         traverse_ C.takeMVar handles
  where
    initHash :: [IRCNetwork] -> M.Map T.Text HashStorage -> IO ()
    initHash net ht = atomically . sequence_ $ do
      x             <- net
      (chan, modes) <- fromStateConfig (netState x)
      let serv      = netServer x
      return $ M.insert modes (serv <> chan) ht
