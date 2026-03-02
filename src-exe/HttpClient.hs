{-# LANGUAGE OverloadedStrings #-}

module HttpClient
( HttpError(..)
, Header
, get
) where

import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString as BS
import Network.HTTP.Simple hiding (httpLbs, Header)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Client
    ( newManager
    , managerSetMaxHeaderLength
    , httpLbs
    )
import Network.HTTP.Client.Conduit (defaultManagerSettings)
import Network.HTTP.Types.Header (HeaderName)
import Control.Exception.Safe (tryAny, SomeException)

data HttpError
    = HttpException SomeException
    | StatusCodeError Int LBS.ByteString
    deriving (Show)

type Header = (HeaderName, [ BS.ByteString ])

get :: String -> [ Header ] -> IO (Either HttpError LBS.ByteString)
get url headers = do
    initReq <- parseRequest url
    let req = foldl (\r (k,v) -> setRequestHeader k v r) initReq headers
    putStrLn $ "calling " ++ url

    let man_settings = managerSetMaxHeaderLength (16384 * 4) defaultManagerSettings
    manager <- newManager man_settings
    handleHttp (httpLbs req manager)

handleHttp :: IO (Response LBS.ByteString) -> IO (Either HttpError LBS.ByteString)
handleHttp action = do
    result <- tryAny action
    case result of
        Right response ->
            let responseBody = getResponseBody response
            in if 200 <= (statusCode $ getResponseStatus response) && (statusCode $ getResponseStatus response) < 300
               then return $ Right responseBody
               else return $ Left (StatusCodeError (statusCode $ getResponseStatus response) responseBody)
        Left e -> do
            putStrLn "Some nasty http exception must have occurred"
            return $ Left $ HttpException e
