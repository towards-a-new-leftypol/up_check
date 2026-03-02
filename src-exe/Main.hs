module Main where

import HttpClient


main :: IO ()
main = do
    putStrLn "Hello, Haskell!"

    print =<< get "https://google.com" []

    putStrLn "Bye!"
