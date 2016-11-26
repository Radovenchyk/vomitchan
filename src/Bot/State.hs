{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE Haskell2010       #-}
{-# LANGUAGE OverloadedStrings #-}


--- MODULE DEFINITION -------------------------------------------------------------------------
module Bot.State (
  GlobalState
) where
--- IMPORTS -----------------------------------------------------------------------------------
import qualified Data.Text       as T
import           Text.Regex.TDFA
import qualified Data.Aeson           as JSON
import           GHC.Generics
--- TYPES -------------------------------------------------------------------------------------
--- DATA STRUCTURES ---------------------------------------------------------------------------


-- IRC State information
data GlobalState = GlobalState
                 { dreamMode   :: [(String, Bool)]
                 , muteMode    :: [(String, Bool)]
                 } deriving (Show, Generic)


instance JSON.FromJSON GlobalState
instance JSON.ToJSON   GlobalState
