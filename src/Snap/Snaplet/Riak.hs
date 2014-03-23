{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}


module Snap.Snaplet.Riak (
  dataDir,
  riakInit,
  riakInit',
  Riak(..),
  HasRiak(..),
  rget,
  rput,
  withRiak
) where

import           Data.Aeson
import           Network.Riak.Connection
import           Network.Riak.Connection.Pool
import qualified Network.Riak.JSON.Resolvable     as RR
import           Network.Riak.Types

import           Control.Monad.CatchIO            (MonadCatchIO)
import           Control.Monad.IO.Class
import           Control.Monad.State
import           Control.Monad.Trans.Reader
import           Snap

import           Data.ByteString                  (ByteString)
import qualified Data.ByteString.Lazy             as L
import qualified Data.Text                        as T
import qualified Data.Text.Encoding               as T
import qualified Data.Text.Lazy                   as TL
import qualified Data.Text.Lazy.Builder           as TB
import qualified Data.Text.Lazy.Builder.Int       as TB
import qualified Data.Text.Lazy.Builder.RealFloat as TB

import qualified Data.Configurator                as C
import qualified Data.Configurator.Types          as C

import           Paths_snapletriak2

data Riak = Riak
        { riakPool :: Pool }

class (MonadCatchIO m) => HasRiak m where
        getRiakState :: m Riak

instance HasRiak (Handler b Riak) where
        getRiakState = get

instance (MonadCatchIO m) => HasRiak (ReaderT Riak m) where
        getRiakState = ask

dataDir :: Maybe (IO FilePath)
dataDir = Just $ liftM (++"/resources") getDataDir


riakInit :: SnapletInit b Riak
riakInit = makeSnaplet "riak2" "Abstraction for Riak KV" dataDir $ do
        config <- getSnapletUserConfig
        initHelper config

-- | Init default client (localhost:8098)
riakInit' :: SnapletInit b Riak
riakInit' = makeSnaplet "riak2" "Abstraction for Riak KV" dataDir $ do
        initHelper'


initHelper :: MonadIO m => C.Config -> m Riak
initHelper config = do
        host <- liftIO $ C.lookupDefault "127.0.0.1" config "host"
        port <- liftIO $ C.lookupDefault "8087" config "port"
        clientID <- liftIO $ C.lookupDefault L.empty config "clientID"
        let client = Client host port clientID
        pool <- liftIO $ create client 1 1 300
        return $ Riak pool

initHelper' :: MonadIO m => m Riak
initHelper' = do
        pool <- liftIO $ create defaultClient 1 1 300
        return $ Riak pool

withRiak :: (HasRiak m)
        => (Connection -> IO b) -> m b
withRiak f = do
        s <- getRiakState
        let pool = riakPool s
        liftIO $ withConnection pool f

rget :: (HasRiak m, RR.Resolvable a, ToJSON a, FromJSON a) =>
        Bucket ->
        Key ->
        m (Maybe (a, VClock))
rget bucket key = withRiak (\c -> RR.get c bucket key Quorum)

rput :: (HasRiak m, FromJSON v, ToJSON v, RR.Resolvable v) =>
        Bucket ->
        Key ->
        v ->
        m (v, VClock)
rput bucket key value = withRiak (\c -> RR.put c bucket key Nothing value Quorum Quorum)
