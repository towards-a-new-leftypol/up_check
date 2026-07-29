-- vibe coded, works
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NumericUnderscores #-}

module Socks
  ( mkSocksManager
  , SocksConnectError (..)
  ) where

import Network.HTTP.Client
    ( Manager
    , newManager
    , managerRawConnection
    , managerTlsConnection
    , socketConnection
    , managerSetMaxHeaderLength
    , ManagerSettings (..)
    , responseTimeoutMicro
    )
import Network.HTTP.Client.Internal (Connection)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.Socks5
    ( SocksConf(..)
    , SocksAddress(..)
    , SocksHostAddress(..)
    , defaultSocksConf
    , socksConnect
    )
import Network.Socks5.Types
  ( SocksVersion(..)
  )
import Network.Socket
    ( SockAddr(..)
    , getAddrInfo
    , defaultHints
    , addrAddress
    , addrSocketType
    , SocketType(..)
    , withSocketsDo
    , HostAddress
    )
import qualified Data.List.NonEmpty as NE
import qualified Data.ByteString.Char8 as BS8
import Control.Exception (Exception, throwIO)
import Data.Typeable (Typeable)
import Control.Concurrent.Timeout (timeout)

data SocksConnectError = SocksConnectError String
    deriving (Show, Typeable)

instance Exception SocksConnectError

responseTimeout :: Int
responseTimeout = 90 * 1_000_000 -- one and a half minutes in microseconds

makeSocksConnection :: SocksConf -> Maybe HostAddress -> String -> Int -> IO Connection
makeSocksConnection socksConf _maybeLocalIP destHost destPort = do
    let destAddr = SocksAddress
            (SocksAddrDomainName (BS8.pack destHost))
            (fromIntegral destPort)

    result <- timeout (45 * 1_000_000) $ socksConnect socksConf destAddr  -- 45 s for circuit

    case result of
        Nothing -> throwIO $
            SocksConnectError $
                "SOCKS circuit timeout connecting to "
                <> destHost <> ":" <> show destPort

        Just (sock, _) -> socketConnection sock 4096

mkSocksManager :: String -> Int -> IO Manager
mkSocksManager proxyHost proxyPort = withSocketsDo $ do
    proxyAddr <- resolveSockAddr proxyHost proxyPort
    
    let socksConf = (defaultSocksConf proxyAddr)
            { socksVersion = SocksVer5
            }
    
    newManager $ managerSetMaxHeaderLength (16384 * 4)
        (tlsManagerSettings 
            { managerRawConnection = return $ makeSocksConnection socksConf
            , managerTlsConnection = return $ makeSocksConnection socksConf
            , managerResponseTimeout = responseTimeoutMicro responseTimeout
            })


resolveSockAddr :: String -> Int -> IO SockAddr
resolveSockAddr host port = do
    let hints = defaultHints { addrSocketType = Stream }
    addrs <- getAddrInfo (Just hints) (Just host) (Just (show port))
    case NE.nonEmpty addrs of
        Nothing -> fail $ "Could not resolve SOCKS proxy address: " ++ host
        Just nonEmpty -> return $ addrAddress $ NE.head nonEmpty
