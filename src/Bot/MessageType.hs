{-# LANGUAGE TemplateHaskell #-}

--- MODULE DEFINITION -------------------------------------------------------------------------
module Bot.MessageType where
--- IMPORTS -----------------------------------------------------------------------------------
import qualified Data.Text       as T
import qualified Data.Map.Strict as M

import qualified Network.HTTP.Client as Client

import           Control.Concurrent.MVar
import           Control.Concurrent.STM.TVar
import           Control.Lens

import Bot.StateType
import Bot.NetworkType
--- TYPES -------------------------------------------------------------------------------------

--- DATA STRUCTURES ---------------------------------------------------------------------------

data Command = PRIVMSG     PrivMsg
             | TOPICCHANGE PrivMsg
             | NOTICE      PrivMsg
             | JOIN        Join
             | CQUIT       CQuit
             | NUMBERS     Numbers
             | PART        Part
             | PING        Ping
             | OTHER       !T.Text Other -- the T.Text is the unidentified command
             | ERROR
             deriving Show

data InfoPriv = Info
  { message  :: !PrivMsg
  , server   :: !T.Text
  , vomState :: VomState
  , manager  :: Client.Manager
  , network  :: IRCNetwork
  , _servers :: AllServers
  }

data AllServers = S
  { _servToNumConn    :: TVar (M.Map Server Int)
  , _servToNumDisconn :: TVar (M.Map Server Int)
  , _numToConnect     :: TVar (M.Map Int ConnectionInfo)
  , _numToDisconnect  :: TVar (M.Map Int IRCNetwork)
  }


data ConnectionInfo = C
  { _connection  :: MVar Quit -- the quit var for the thread each listen tries to take
  , _networkInfo :: IRCNetwork
  }

-- taking only user prefixes
data PrivMsg = PrivMsg { user       :: !UserI
                       , msgChan    :: !Target
                       , msgContent :: !Content
                       } deriving Show


data Part  = Part  !UserI !Target !Content deriving Show
data Join  = Join  !UserI !Target         deriving Show
data CQuit = CQuit !UserI !Content        deriving Show

-- taking no prefixes
newtype Ping = Ping Content deriving Show

data UserI = UserI { usrNick :: !Nick
                   , usrUser :: !(Maybe User)
                   , usrHost :: !(Maybe Host)
                   } deriving Show

data Numbers = N354 !Server !Content
             | N904 !Server !Content -- Authentication Failed
             | N903 !Server !Content -- Authentication Successful
             | N376 !Server !Content -- MOTD
             | N422 !Server !Content -- Missing MOTD
             | NOther !Int Other
             deriving Show


data Other = OtherUser   !UserI !Content
           | OtherServer !Server !Content
           | OtherNoInfo !Content
           deriving Show


msgNick :: PrivMsg -> Nick
msgNick = usrNick . user
msgUser = usrUser . user
msgHost = usrHost . user

infoNick    = msgNick . message
infoUser    = msgUser . message
infoHost    = msgHost . message
infoChan    = msgChan . message
infoContent = msgContent . message

class GetUser f where
  userI :: f -> UserI

instance GetUser (PrivMsg) where
  userI (PrivMsg u _ _) = u

makeLenses ''InfoPriv
makeLenses ''AllServers
makeLenses ''ConnectionInfo
