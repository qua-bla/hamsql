-- This file is part of HamSql
--
-- Copyright 2014-2016 by it's authors.
-- Some rights reserved. See COPYING, AUTHORS.
{-# LANGUAGE OverloadedStrings #-}

module Database.HamSql.Internal.Utils
  ( module Database.HamSql.Internal.Utils
  , Text
  , (<>)
  ) where

import Control.Monad
import Data.Char
import Data.List (group, intercalate, sort)
import Data.Monoid ((<>))
import Data.Text (Text, pack)
import qualified Data.Text as T
import Data.Text.IO
import Debug.Trace
import System.Exit
import System.IO (stderr)
import System.IO.Unsafe

import Database.HamSql.Internal.Option

join :: [a] -> [[a]] -> [a]
join = intercalate

err :: Text -> a
err xs =
  unsafePerformIO $
  do hPutStrLn stderr ("error: " <> xs)
     exitWith $ ExitFailure 1

inf :: Text -> a -> a
inf = msg "info"

warn :: Text -> a -> a
warn = msg "warning"

warn' :: Text -> IO ()
warn' = msg' "warning"

msg :: Text -> Text -> a -> a
msg typ xs ys =
  unsafePerformIO $
  do msg' typ xs
     return ys

msg' :: Text -> Text -> IO ()
msg' typ xs = hPutStrLn stderr (typ <> ": " <> xs)

debug :: OptCommon -> Text -> a -> a
debug opt
  | optVerbose opt = msg "debug"
  | otherwise = id'
  where
    id' _ = id

info :: OptCommon -> Text -> IO ()
info opts xs = when (optVerbose opts) $ msg' "debug" xs

removeDuplicates
  :: (Ord a)
  => [a] -> [a]
removeDuplicates = map head . group . sort

--- Maybe Utils
-- Makes list out of Maybe
maybeList :: Maybe [a] -> [a]
maybeList Nothing = []
maybeList (Just xs) = xs

-- Joins two Maybe lists
maybeJoin :: Maybe [a] -> Maybe [a] -> Maybe [a]
maybeJoin Nothing Nothing = Nothing
maybeJoin xs ys = Just (maybeList xs ++ maybeList ys)

-- Joins two Maybe lists
maybeLeftJoin :: Maybe [a] -> [a] -> Maybe [a]
maybeLeftJoin Nothing ys = Just ys
maybeLeftJoin xs ys = Just (maybeList xs ++ ys)

maybeText :: Maybe Text -> Text
maybeText Nothing = ""
maybeText (Just text) = text

-- Takes the right value, if Just there
maybeRight :: Maybe a -> Maybe a -> Maybe a
maybeRight _ (Just r) = Just r
maybeRight l _ = l

appendToMaybe :: Maybe [a] -> a -> Maybe [a]
appendToMaybe Nothing x = Just [x]
appendToMaybe (Just xs) x = Just (xs ++ [x])

maybeMap :: (a -> b) -> Maybe [a] -> [b]
maybeMap _ Nothing = []
maybeMap f (Just xs) = map f xs

fromJustReason :: Text -> Maybe a -> a
fromJustReason _ (Just x) = x
fromJustReason reason Nothing = err $ "fromJust failed: " <> reason

selectUniqueReason :: Text -> [a] -> a
selectUniqueReason _ [x] = x
selectUniqueReason msgt [] =
  err $ "No element found while trying to find exactly one: " <> msgt
selectUniqueReason msgt xs =
  err $
  "More then one element (" <> tshow (length xs) <>
  ") found while trying to extrac one: " <>
  msgt

tshow
  :: (Show a)
  => a -> Text
tshow = pack . show

showCode :: Text -> Text
showCode = T.replace "\n" "\n  " . T.cons '\n'

tr
  :: Show a
  => a -> a
tr x = trace (show x <> "\n") x

isIn :: Char -> Text -> Bool
isIn c t = T.singleton c `T.isInfixOf` t

(<->) :: Text -> Text -> Text
(<->) a b = a <> " " <> b

(<\>) :: Text -> Text -> Text
(<\>) a b = a <> "\n" <> b
