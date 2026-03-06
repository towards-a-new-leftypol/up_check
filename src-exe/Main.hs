{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Main where

import qualified Data.ByteString.Lazy as B
import System.Console.CmdArgs (cmdArgs, Data)
import System.Exit (exitFailure)
import Data.Aeson (eitherDecode, encode, FromJSON, ToJSON)
import GHC.Generics
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Bifunctor (first, second)
import Data.Maybe (fromMaybe)
import Data.List (isPrefixOf)

import HttpClient (get, pxyGet, HttpError (..))
import TCP (TCPError (..), checkTCPService)
import Email (SMTPEmailSettings, emailTheError)

newtype CliArgs = CliArgs
  { settingsFile :: String
  } deriving (Show, Data)


data ProxiedUrls = ProxiedUrls
    { urls :: [ String ]
    , socks5_host :: String
    , socks5_port :: Int
    } deriving (Generic, FromJSON, ToJSON)


data JSONSettings = JSONSettings
    { get_urls :: [ String ]
    , proxied_get_urls :: Maybe [ ProxiedUrls ]
    , smtp_settings :: SMTPEmailSettings
    } deriving (Generic, FromJSON, ToJSON)


data ProgramException
    = PHttpException HttpError
    | ConnectionException TCPError
    deriving Show


type IOe a = ExceptT ProgramException IO a


liftHttpIO :: IO (Either HttpError a) -> IOe a
liftHttpIO = ExceptT . fmap (first PHttpException)


liftTCPIO :: IO (Either TCPError a) -> IOe a
liftTCPIO = ExceptT . fmap (first ConnectionException)


getSettings :: IO JSONSettings
getSettings = do
    cliArgs <- cmdArgs $ CliArgs "settings.json"

    let filePath = settingsFile cliArgs
    if null filePath
    then do
        putStrLn "Error: No JSON settings file provided."
        exitFailure
    else do
        putStrLn $ "Loading settings from: " ++ filePath
        content <- B.readFile filePath
        case eitherDecode content :: Either String JSONSettings of
            Left e -> do
                putStrLn $ "Error: Invalid JSON format: " <> e
                exitFailure
            Right settings -> return settings


tcpPrefix :: String
tcpPrefix = "tcp://"


subjectFromException :: ProgramException -> String
subjectFromException (PHttpException httpErr) = "Http error for " ++ getUrl httpErr
    where
        getUrl (HttpException url _) = url
        getUrl (StatusCodeError url _ _) = url
subjectFromException (ConnectionException tcpErr) = "TCP error for " ++
  tcpPrefix ++ tcpErrorHost tcpErr ++ ":" ++ show (tcpErrorPort tcpErr)


main :: IO ()
main = do
    settings <- getSettings

    B.putStr $ encode settings
    putStrLn ""

    endResult <- runExceptT $ do
        mapM_ handleGetUrl $ get_urls settings
        let proxied_get_urls_ = fromMaybe [] $ proxied_get_urls settings
        mapM handleProxiedGets proxied_get_urls_

    case endResult of
        Left e -> do
            print e
            emailResult <- emailTheError
                (smtp_settings settings)
                (subjectFromException e)
                (show e)

            case emailResult of
                Nothing -> putStrLn "Timeout occurred when sending outbound error email!"
                Just _ -> return ()

            exitFailure
        Right _ -> putStrLn "Success"

    where
        handleGetUrl :: String -> IOe ()
        handleGetUrl u
            | isPrefixOf tcpPrefix u = do
                let hostPortStr = drop (length tcpPrefix) u
                    (host, port) = break (== ':') hostPortStr
                liftTCPIO $ do
                    putStrLn $ "calling " <> u
                    checkTCPService host (read $ drop 1 port)
            | otherwise =  liftHttpIO $ second (const ()) <$> get u []

        handleProxiedGets :: ProxiedUrls -> IOe [ B.ByteString ]
        handleProxiedGets proxied =
            mapM (\u -> liftHttpIO $ pxyGet h p u []) (urls proxied)

            where
                h = socks5_host proxied
                p = socks5_port proxied
