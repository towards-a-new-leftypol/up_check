-- vibe coded, works
{-# LANGUAGE OverloadedStrings #-}

module Socks
  ( mkSocksManager
  ) where

import Network.HTTP.Client
    ( Manager
    , newManager
    , managerRawConnection
    , managerTlsConnection
    , socketConnection
    , managerSetMaxHeaderLength
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

mkSocksManager :: String -> Int -> IO Manager
mkSocksManager proxyHost proxyPort = withSocketsDo $ do
    proxyAddr <- resolveSockAddr proxyHost proxyPort
    
    let socksConf = (defaultSocksConf proxyAddr)
            { socksVersion = SocksVer5
            }
    
    let makeSocksConnection :: Maybe HostAddress -> String -> Int -> IO Connection
        makeSocksConnection _maybeLocalIP destHost destPort = do
            let destAddr = SocksAddress 
                    (SocksAddrDomainName (BS8.pack destHost)) 
                    (fromIntegral destPort)
            
            (sock, _resolved) <- socksConnect socksConf destAddr
            socketConnection sock 4096
    
    newManager $ managerSetMaxHeaderLength (16384 * 4)
        (tlsManagerSettings 
            { managerRawConnection = return makeSocksConnection
            , managerTlsConnection = return makeSocksConnection
            })


resolveSockAddr :: String -> Int -> IO SockAddr
resolveSockAddr host port = do
    let hints = defaultHints { addrSocketType = Stream }
    addrs <- getAddrInfo (Just hints) (Just host) (Just (show port))
    case NE.nonEmpty addrs of
        Nothing -> fail $ "Could not resolve SOCKS proxy address: " ++ host
        Just nonEmpty -> return $ addrAddress $ NE.head nonEmpty
