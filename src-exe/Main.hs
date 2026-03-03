{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

module Main where

import qualified Data.ByteString.Lazy as B
import System.Console.CmdArgs (cmdArgs, Data)
import System.Exit (exitFailure)
import Data.Aeson (decode, encode, FromJSON, ToJSON)
import GHC.Generics
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Data.Bifunctor (first)

import HttpClient (get, HttpError)


newtype CliArgs = CliArgs
  { settingsFile :: String
  } deriving (Show, Data)


data JSONSettings = JSONSettings
    { get_urls :: [ String ]
    } deriving (Generic, FromJSON, ToJSON)


data ProgramException = HttpException HttpError
  deriving Show


type IOe a = ExceptT ProgramException IO a

liftHttpIO :: IO (Either HttpError a) -> IOe a
liftHttpIO = ExceptT . fmap (first HttpException)

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
        case decode content :: Maybe JSONSettings of
            Nothing -> do
                putStrLn "Error: Invalid JSON format."
                exitFailure
            Just settings -> return settings


main :: IO ()
main = do
    putStrLn "Hello, Haskell!"

    settings <- getSettings

    print $ encode settings

    endResult <- runExceptT $
        mapM (\u -> liftHttpIO $ get u []) (get_urls settings)

    case endResult of
        Left e -> do
            print e
            exitFailure
        Right _ -> putStrLn "Success"
