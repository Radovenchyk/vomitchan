{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ScopedTypeVariables #-}
--- MODULE DEFINITION -------------------------------------------------------------------------
module Bot.Message (
  respond
) where
--- IMPORTS -----------------------------------------------------------------------------------
import qualified Data.Text          as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString    as BS
import qualified Data.Set           as S
import           Data.Foldable

import qualified Control.Exception      as Exception
import           Control.Concurrent.STM
import           Control.Monad.Reader

import qualified Text.URI as URI

import qualified Network.HTTP.Client as Client
import qualified Network.HTTP.Req    as Req

import qualified Bot.Modifier      as Modifier
import           Bot.Commands
import           Bot.EffType
import           Bot.FileOps
import           Bot.MessageType
import           Bot.NetworkType
import           Bot.StateType

import           Turtle hiding (fold)

--- DATA --------------------------------------------------------------------------------------

-- Lists the type of webpages that are logged
cmdWbPg :: [T.Text]
cmdWbPg = ["http", "ftp"]

cmdPic :: [T.Text]
cmdPic = ["jpg", "png", "jpeg", "gif", "jpg:large", "png:large",
          "jpeg:large", "jpg#nsfw", "png#nsfw", "jpeg#nsfw", "JPG"]

cmdVid :: [T.Text]
cmdVid = ["webm", "mp4", "flv", "ogv", "wmv", "gifv", "webm#nsfw", "x-m4v"]

cmdMus :: [T.Text]
cmdMus = ["flac", "mp3", "tta", "ogg", "wma", "wav", "aiff", "mpeg"]

cmdMisc :: [T.Text]
cmdMisc = ["pdf", "epub", "djvu", "txt", "hs", "ml", "lisp", "cpp", "c", "java", "rs"]

cmdAll :: [T.Text]
cmdAll = fold [cmdPic, cmdVid, cmdMus, cmdMisc]

cmdAllS :: S.Set Text
cmdAllS = S.fromList cmdAll

--- FUNCTIONS ---------------------------------------------------------------------------------

-- takes an IRC message and generates the correct response
respond
  :: BS.ByteString
  -> AllServers
  -> Either String Command
  -> Server
  -> VomState
  -> IRCNetwork
  -> Client.Manager
  -> IO Func
respond s _    (Left err)   _erver _tate _ _manager =
  appendError err s >> print err >> return NoResponse
respond _ allS (Right priv) server state net manager = f priv
  where
    f (PRIVMSG priv)     = runReaderT (allLogsM manager (information priv manager) >> runCmd) (information priv manager)
    f (NOTICE priv)      = processNotice priv (runReaderT (allLogsM manager (information priv manager)>> runCmd) (information priv manager))
    f (TOPICCHANGE priv) = NoResponse <$ runReaderT (allLogsM manager (information priv manager)) (information priv manager)
    f (PING (Ping s))    = return $ Response ("PONG", [Modifier.effNonModifiable s])
    f _                  = return NoResponse

    information :: PrivMsg -> Client.Manager -> InfoPriv
    information priv mng = Info priv server state mng net allS

--- LOGGING -----------------------------------------------------------------------------------

allLogsM :: CmdImp m => Client.Manager -> InfoPriv -> m ()
allLogsM mnger info@(Info priv _ _ _ net _)
  | usrNick (user priv) `elem` (netIgnore net) = return ()
  | otherwise                                  = traverse_ (toReaderImp . (. message)) [cmdFldr, cmdLog, cmdLogFile mnger info]

-- Logs any links posted and appends them to the users .log file
cmdLog :: PrivMsg -> IO ()
cmdLog = traverse_ . appendLog <*> linLn
  where
    linLn = fmap (<> "\n") . allLinks


-- Downloads any file and saves it to the user folder
cmdLogFile :: Client.Manager -> InfoPriv -> PrivMsg -> IO ()
cmdLogFile manager info = traverse_ . dwnfile (Just manager) info <*> allImg
  where
    allImg = allLinks

dwnfile :: MonadIO m => Maybe Client.Manager -> InfoPriv -> PrivMsg -> Text -> m ()
dwnfile manager info msg link = do
  extension <- getFileType link manager
  case extension of
    Nothing -> pure ()
    Just ex -> () <$ dwnUsrFileExtension info msg link ex

cmdFldr :: PrivMsg -> IO ()
cmdFldr = createUsrFldr

--- HELPER ------------------------------------------------------------------------------------

-- creates a list of all links
allLinks :: PrivMsg -> [T.Text]
allLinks = (cmdWbPg >>=) . specWord

getFileType :: MonadIO m => T.Text -> Maybe Client.Manager -> m (Maybe T.Text)
getFileType link manager = do
  mime <- getMimeType link manager
  pure $ case mime of
    Nothing -> Nothing
    Just extension
      | y <- getSubtypeFromMime (TE.decodeUtf8 extension)
      , y `S.member` cmdAllS ->
        --
        Just y
      | y <- last (T.splitOn "." link)
      , y `S.member` S.fromList cmdMisc
      && getSubtypeFromMime (TE.decodeUtf8 extension) /= "html"  ->
        --
        Just y
      | otherwise ->
        Nothing

-- image/jpeg ⟶ jpeg, text/html ; text utf8 ⟶ html
getSubtypeFromMime :: Text -> Text
getSubtypeFromMime =
  T.takeWhile (/= ';') . T.drop 1 . T.dropWhile (/= '/')

processNotice :: PrivMsg -> IO Func -> IO Func
processNotice priv process
  | nickname priv == "saybot" = process
  | otherwise                 = return NoResponse
  where nickname = usrNick . user

-- todo ∷ pass the connection context from main to this
-- this eats another 16 MB of ram, due to using Req's one
getMimeType :: MonadIO m => Text -> Maybe Client.Manager -> m (Maybe BS.ByteString)
getMimeType link altMngr =
  liftIO $
    Exception.catch
      (Req.runReq Req.defaultHttpConfig { Req.httpConfigAltManager = altMngr} $ do
          uri <- URI.mkURI link
          let Just t = Req.useURI uri
          case t of
            Right x ->
              response <$> uncurry reqHead x
            Left x ->
              response <$> uncurry reqHead x)
      (\ (e :: Exception.SomeException) -> do
          print e
          pure Nothing)
  where
    response t = Req.responseHeader t "content-type"

reqHead ::
  Req.MonadHttp m => Req.Url scheme -> Req.Option scheme -> m Req.BsResponse
reqHead x = Req.req Req.HEAD x Req.NoReqBody Req.bsResponse
