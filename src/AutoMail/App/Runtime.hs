{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module AutoMail.App.Runtime (
    CriticalityApp(..)
    , RestartApp(..)
    , ComponentApp(..)
    , delayRestartApp
    , waitRestartApp
  ) where

import Control.Concurrent (threadDelay)
import Data.Text (Text)
import Data.Time.Clock (NominalDiffTime)
import GHC.Generics (Generic)

import AutoMail.App.Context (ShutdownApp)


data CriticalityApp =
    CriticalCA
  | RestartableCA
  deriving stock (Eq, Show, Generic)


data RestartApp =
    NeverRA
  | FixedRA NominalDiffTime
  | ExponentialRA NominalDiffTime NominalDiffTime
  deriving stock (Eq, Show, Generic)


data ComponentApp = ComponentApp {
    nameCA :: Text
    , criticalityCA :: CriticalityApp
    , restartCA :: RestartApp
    , runCA :: ShutdownApp -> IO ()
  }


delayRestartApp :: RestartApp -> Int -> Maybe NominalDiffTime
delayRestartApp restart attemptIndex =
  case restart of
    NeverRA -> Nothing
    FixedRA delay -> Just $ nonNegativeDelayApp delay
    ExponentialRA initial maximum ->
      let
        exponent = max 0 attemptIndex
        initialDelay = nonNegativeDelayApp initial
        maximumDelay = nonNegativeDelayApp maximum
        scaledDelay = scaleExponentialApp initialDelay exponent
      in
      Just $ min maximumDelay scaledDelay


waitRestartApp :: RestartApp -> Int -> IO Bool
waitRestartApp restart attemptIndex =
  case delayRestartApp restart attemptIndex of
    Nothing -> pure False
    Just delay -> do
      threadDelay $ microsecondsDelayApp delay
      pure True


nonNegativeDelayApp :: NominalDiffTime -> NominalDiffTime
nonNegativeDelayApp delay =
  max 0 delay


scaleExponentialApp :: NominalDiffTime -> Int -> NominalDiffTime
scaleExponentialApp initial exponent =
  initial * fromInteger multiplier
  where
  multiplier = 2 ^ min 30 exponent


microsecondsDelayApp :: NominalDiffTime -> Int
microsecondsDelayApp delay =
  let
    seconds = max 0 (realToFrac delay :: Double)
    micros = ceiling (seconds * 1000000) :: Integer
    bounded = min (fromIntegral (maxBound :: Int)) micros
  in
  fromInteger bounded