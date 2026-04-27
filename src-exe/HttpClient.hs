{-# LANGUAGE OverloadedStrings #-}

module HttpClient
( HttpError(..)
, Header
, get
, pxyGet
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
import Control.Exception.Safe (tryAny, SomeException)
import Network.HTTP.Client (Manager)
import Control.Concurrent.Timeout (timeout)

import Socks (mkSocksManager)

httpTimeout :: Integer
httpTimeout = 60 * 1000000 -- 60 seconds

data HttpError
    = HttpException String SomeException
    | StatusCodeError String Int LBS.ByteString
    | Timeout String
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


pxyGet :: String -> Int -> String -> [Header] -> IO (Either HttpError LBS.ByteString)
pxyGet proxyHost_ proxyPort_ url headers =
    get_ (mkSocksManager proxyHost_ proxyPort_) url headers


handleHttp :: String -> IO (Response LBS.ByteString) -> IO (Either HttpError LBS.ByteString)
handleHttp url action = do
    result <- tryAny action
    case result of
        Right response ->
            let responseBody = getResponseBody response
            in if 200 <= (statusCode $ getResponseStatus response) && (statusCode $ getResponseStatus response) < 300
               then return $ Right responseBody
               else return $ Left (StatusCodeError url (statusCode $ getResponseStatus response) responseBody)
        Left e -> do
            putStrLn "Some nasty http exception must have occurred"
            return $ Left $ HttpException url e
