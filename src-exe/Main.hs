{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE NumericUnderscores #-}

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
import Control.Monad.IO.Class (liftIO)
import Control.Concurrent (threadDelay)

import HttpClient (get, get_, HttpError (..))
import TCP (TCPError (..), checkTCPService)
import Email (SMTPEmailSettings, emailTheError)
import Socks (mkSocksManager)

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
        getUrl (Timeout e) = e
        getUrl (SocksConnectTimeout e) = e
subjectFromException (ConnectionException tcpErr) = "TCP error for " ++
  tcpPrefix ++ tcpErrorHost tcpErr ++ ":" ++ show (tcpErrorPort tcpErr)


-- | Retry wrapper: tries up to n times with exponential backoff.
withRetries :: Int -> Int -> IO (Either HttpError a) -> IO (Either HttpError a)
withRetries maxAttempts baseDelayMicros action = go 1
  where
    go attempt = do
        result <- action
        case result of
            Right _  -> return result
            Left err
                | attempt >= maxAttempts -> return result
                | isRetryable err -> do
                    let delay = baseDelayMicros * (2 ^ (attempt - 1))
                    putStrLn $ "Attempt " <> show attempt <> " failed ("
                        <> show err <> "), retrying in "
                        <> show (delay `div` 1_000_000) <> "s..."
                    threadDelay delay
                    go (attempt + 1)
                | otherwise -> return result  -- non-retryable (e.g. 404)

    isRetryable (HttpException _ _)    = True
    isRetryable (Timeout _)            = True
    isRetryable (SocksConnectTimeout _) = True
    isRetryable (StatusCodeError _ c _) = c >= 500  -- retry server errors only


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
        handleProxiedGets proxied = do
            mgr <- liftIO $ mkSocksManager h p

            liftHttpIO $ withRetries 3 (10 * 1_000_000) $ do
                results <- mapM (\u -> get_ (pure mgr) u []) (urls proxied)
                return $ sequence results

            where
                h = socks5_host proxied
                p = socks5_port proxied
