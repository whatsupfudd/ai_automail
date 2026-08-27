{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.Provider.Driver where

import Data.Aeson (Value)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import qualified Data.Vector as V
import GHC.Generics (Generic)

import AutoMail.App.Error (ErrorPrv)
import AutoMail.Mail.Types (OutgoingMail)
import AutoMail.Model.Common (TokenPage)
import AutoMail.Model.Id (
    AttachmentIdPrv
    , CollectionIdPrv
    , CursorPrv
    , DraftIdPrv
    , MessageIdPrv
    , ThreadIdPrv
  )
import AutoMail.Provider.Types (
    AccountPrv
    , AttachmentPrv
    , CapabilityPrv(..)
    , CollectionPrv
    , KindPrv
    , MessagePrv
    , PageChangePrv
    , PageSyncPrv
    , ProfilePrv
    , RequestSyncPrv
    , RequestWatchPrv
    , WatchPrv
  )


data ReaderPrv m = ReaderPrv {
    profileRP :: AccountPrv -> m (Either ErrorPrv ProfilePrv)
    , collectionsRP :: AccountPrv -> m (Either ErrorPrv (V.Vector CollectionPrv))
    , syncFullRP :: AccountPrv -> RequestSyncPrv -> m (Either ErrorPrv PageSyncPrv)
    , fetchMessageRP :: AccountPrv -> MessageIdPrv -> m (Either ErrorPrv MessagePrv)
    , fetchAttachmentRP :: AccountPrv -> MessageIdPrv -> AttachmentIdPrv -> m (Either ErrorPrv AttachmentPrv)
  }


data ChangerPrv m = ChangerPrv {
    syncChangesCP :: AccountPrv -> CursorPrv -> Maybe TokenPage -> m (Either ErrorPrv PageChangePrv)
  }


data WatcherPrv m = WatcherPrv {
    startWP :: AccountPrv -> RequestWatchPrv -> m (Either ErrorPrv WatchPrv)
    , renewWP :: AccountPrv -> RequestWatchPrv -> m (Either ErrorPrv WatchPrv)
    , stopWP :: AccountPrv -> m (Either ErrorPrv ())
  }


data DraftPrv = DraftPrv {
    draftIdDP :: DraftIdPrv
    , messageIdDP :: Maybe MessageIdPrv
    , metadataDP :: Value
  }
  deriving stock (Eq, Show, Generic)


data SentPrv = SentPrv {
    messageIdSP :: MessageIdPrv
    , threadIdSP :: Maybe ThreadIdPrv
    , metadataSP :: Value
  }
  deriving stock (Eq, Show, Generic)


data DrafterPrv m = DrafterPrv {
    createDP :: AccountPrv -> OutgoingMail -> m (Either ErrorPrv DraftPrv)
    , updateDP :: AccountPrv -> DraftIdPrv -> OutgoingMail -> m (Either ErrorPrv DraftPrv)
    , discardDP :: AccountPrv -> DraftIdPrv -> m (Either ErrorPrv ())
  }


data SenderPrv m = SenderPrv {
    sendDraftSP :: AccountPrv -> DraftIdPrv -> m (Either ErrorPrv SentPrv)
    , sendMessageSP :: AccountPrv -> OutgoingMail -> m (Either ErrorPrv SentPrv)
  }


data CollectionChangePrv =
    AddCollectionCCP MessageIdPrv CollectionIdPrv
  | RemoveCollectionCCP MessageIdPrv CollectionIdPrv
  deriving stock (Eq, Show, Generic)


data WriterPrv m = WriterPrv {
    changeCollectionsWP :: AccountPrv -> V.Vector CollectionChangePrv -> m (Either ErrorPrv ())
  }


data DriverPrv m = DriverPrv {
    kindDP :: KindPrv
    , readerDP :: ReaderPrv m
    , changerDP :: Maybe (ChangerPrv m)
    , watcherDP :: Maybe (WatcherPrv m)
    , writerDP :: Maybe (WriterPrv m)
    , drafterDP :: Maybe (DrafterPrv m)
    , senderDP :: Maybe (SenderPrv m)
  }


newtype RegistryPrv m = RegistryPrv (Map KindPrv (DriverPrv m))


emptyRegistryPrv :: RegistryPrv m
emptyRegistryPrv = RegistryPrv M.empty


registerPrv :: DriverPrv m -> RegistryPrv m -> RegistryPrv m
registerPrv driver (RegistryPrv drivers) =
  RegistryPrv $ M.insert driver.kindDP driver drivers


lookupPrv :: KindPrv -> RegistryPrv m -> Maybe (DriverPrv m)
lookupPrv kind (RegistryPrv drivers) = M.lookup kind drivers


supportsPrv :: CapabilityPrv -> DriverPrv m -> Bool
supportsPrv capability driver =
  case capability of
    ReadCP -> True
    ChangeCP -> presentPrv driver.changerDP
    WatchCP -> presentPrv driver.watcherDP
    DraftCP -> presentPrv driver.drafterDP
    SendCP -> presentPrv driver.senderDP
    CollectionCP -> presentPrv driver.writerDP


presentPrv :: Maybe a -> Bool
presentPrv value =
  case value of
    Nothing -> False
    Just _ -> True