{-# LANGUAGE OverloadedStrings #-}

module HttpClient
( HttpError(..)
, Header
, get
, get_
) where

import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString as BS
import Network.HTTP.Simple hiding (httpLbs, Header)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Client
    ( newManager
    , httpLbs
    )
import Network.HTTP.Client.Conduit
    ( defaultManagerSettings
    , ManagerSettings (..)
    , responseTimeoutMicro
    )
import Network.HTTP.Types.Header (HeaderName)
import Control.Exception.Safe (tryAny, SomeException, fromException)
import Network.HTTP.Client (Manager)
import Control.Concurrent.Timeout (timeout)

import Socks (SocksConnectError (..))

httpTimeout :: Integer
httpTimeout = 60 * 1000000 -- 60 seconds

data HttpError
    = HttpException String SomeException
    | StatusCodeError String Int LBS.ByteString
    | Timeout String
    | SocksConnectTimeout String
    deriving (Show)

type Header = (HeaderName, [ BS.ByteString ])

get_ :: IO Manager -> String -> [ Header ] -> IO (Either HttpError LBS.ByteString)
get_ mkManager url headers = do
    result <- timeout (httpTimeout * 2) $ do
        initReq <- parseRequest url
        let req = foldl (\r (k,v) -> setRequestHeader k v r) initReq headers
        putStrLn $ "calling " ++ url
        manager <- mkManager
        handleHttp url (httpLbs req manager)

    return
        (
            case result of
                Nothing -> Left $ Timeout $ "get_ has timed out on " <> url
                Just x -> x
        )


get :: String -> [ Header ] -> IO (Either HttpError LBS.ByteString)
get = get_ $ newManager $
    defaultManagerSettings
    { managerResponseTimeout = responseTimeoutMicro (fromIntegral httpTimeout) }


handleHttp :: String -> IO (Response LBS.ByteString) -> IO (Either HttpError LBS.ByteString)
handleHttp url action = do
    result <- tryAny action
    case result of
        Right response ->
            let sc = statusCode $ getResponseStatus response
            in if sc >= 200 && sc < 300
               then return $ Right $ getResponseBody response
               else return $ Left $ StatusCodeError url sc (getResponseBody response)

        -- Catch the typed SOCKS failure specifically
        Left e
            | Just (SocksConnectError msg) <- fromException e ->
                return $ Left $ SocksConnectTimeout msg

            | otherwise ->
                return $ Left $ HttpException url e
