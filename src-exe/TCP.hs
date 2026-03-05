{-# LANGUAGE OverloadedStrings #-}

module TCP
  ( TCPError(..)
  , TCPErrorType(..)
  , checkTCPService
  ) where

import Control.Exception.Safe (try, Exception, SomeException, displayException, throwIO, bracket)
import System.Timeout (timeout)
import qualified Network.Socket as NS

-- | Categories of TCP connection errors
data TCPErrorType
  = Timeout
  | DNSResolutionFailed
  | ConnectionError
  deriving (Show, Eq)

-- | Detailed TCP error including host, port, and error type
data TCPError = TCPError
  { tcpErrorHost :: String
  , tcpErrorPort :: Int
  , tcpErrorType :: TCPErrorType
  , tcpErrorMessage :: String
  } deriving (Show, Eq)

instance Exception TCPError

defaultTimeout :: Int
defaultTimeout = 15 * 1000000  -- 15 seconds in microseconds

-- | Attempt to connect to a host:port.
-- Returns 'Right ()' on success, 'Left TCPError' on failure.
checkTCPService :: String -> Int -> IO (Either TCPError ())
checkTCPService host port = do
    result <- timeout defaultTimeout $ try
        (
            do
                addrInfos <- NS.getAddrInfo (Just hints) (Just host) (Just (show port))

                case addrInfos of
                    [] -> throwIO $ TCPError host port DNSResolutionFailed "No addresses resolved"
                    (addr:_) -> bracket
                        (NS.socket (NS.addrFamily addr) NS.Stream NS.defaultProtocol)
                        NS.close
                        (\sock -> do
                            NS.setSocketOption sock NS.ReuseAddr 1
                            NS.connect sock (NS.addrAddress addr)
                        )
        ) :: IO (Maybe (Either SomeException ()))

    case result of
        Just (Right ()) -> return (Right ())
        Just (Left e)   -> return (Left $ TCPError host port ConnectionError (displayException e))
        Nothing         -> return (Left $ TCPError host port Timeout "Connection timed out")

    where
        hints = NS.defaultHints
          { NS.addrFlags = [ NS.AI_ADDRCONFIG ]
          , NS.addrSocketType = NS.Stream
          , NS.addrFamily = NS.AF_INET
          }
