{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}

module Email where

import Network.Mail.SMTP
import Network.Mail.Mime (plainPart)
import Data.Text (pack)
import qualified Data.Text.Lazy as T
import GHC.Generics
import Data.Aeson (FromJSON, ToJSON)
import System.Timeout (timeout)

data SMTPEmailSettings = SMTPEmailSettings
  { host :: String
  , port :: Int
  , username :: String
  , password :: String
  , from_address :: String
  , to_addresses :: [ String ]
  } deriving (Generic, FromJSON, ToJSON)

emailTimeout :: Int
-- emailTimeout = 2 * 60 * 1000000  -- 2 minutes in microseconds
emailTimeout = 15 * 1000000 -- 15 seconds

emailTheError :: SMTPEmailSettings -> String -> String -> IO (Maybe ())
emailTheError SMTPEmailSettings {..} subject body = timeout emailTimeout $
  sendMailWithLoginTLS' host (toEnum port) username password mail

  where
    body_ = plainPart $ T.pack body
    cc = []
    bcc = []

    mail = simpleMail
      (mkAddress from_address)
      addys
      cc
      bcc
      (pack subject)
      [ body_ ]

    addys = map mkAddress to_addresses
    mkAddress = (Address Nothing) . pack
