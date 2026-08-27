{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.Model.Time (
    Clock(..)
    , RangeTime(..)
    , LeaseTime(..)
    , systemClock
    , insideRange
    , expiredAt
  ) where

import Data.Time.Clock (UTCTime, getCurrentTime)
import GHC.Generics (Generic)


data Clock m = Clock {
    nowC :: m UTCTime
  }


data RangeTime = RangeTime {
    fromRT :: Maybe UTCTime
    , untilRT :: Maybe UTCTime
  }
  deriving stock (Eq, Show, Generic)


data LeaseTime = LeaseTime {
    acquiredAtLT :: UTCTime
    , expiresAtLT :: UTCTime
  }
  deriving stock (Eq, Show, Generic)


systemClock :: Clock IO
systemClock = Clock {
    nowC = getCurrentTime
  }


-- | Determine whether a time falls within a half-open range: [from, until).
-- A missing lower or upper bound leaves that side of the range unbounded.
insideRange :: UTCTime -> RangeTime -> Bool
insideRange instant range =
  maybe True (<= instant) range.fromRT && maybe True (instant <) range.untilRT


-- | Determine whether an expiry time has been reached at the supplied time.
-- The first argument is the observation time and the second is the expiry time.
expiredAt :: UTCTime -> UTCTime -> Bool
expiredAt instant expiresAt = instant >= expiresAt