{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedLabels #-}

module Cardano.Wallet.Primitive.MigrationSpec
    where

import Prelude

import Cardano.Wallet.Primitive.Migration
    ( RewardWithdrawal (..), createPlan )
import Cardano.Wallet.Primitive.Migration.Planning
    ( categorizeUTxO, uncategorizeUTxO )
import Cardano.Wallet.Primitive.Migration.SelectionSpec
    ( MockTxConstraints
    , Pretty (..)
    , genCoinRange
    , genTokenBundleMixed
    , unMockTxConstraints
    )
import Cardano.Wallet.Primitive.Types.Address.Gen
    ( genAddressSmallRange )
import Cardano.Wallet.Primitive.Types.Coin
    ( Coin (..) )
import Cardano.Wallet.Primitive.Types.Tx
    ( TxIn, TxOut (..) )
import Cardano.Wallet.Primitive.Types.Tx.Gen
    ( genTxInLargeRange )
import Cardano.Wallet.Primitive.Types.UTxO
    ( UTxO (..) )
import Control.Monad
    ( replicateM )
import Data.Function
    ( (&) )
import Data.Generics.Internal.VL.Lens
    ( view )
import Data.Generics.Labels
    ()
import Test.Hspec
    ( Spec, describe, it )
import Test.Hspec.Extra
    ( parallel )
import Test.QuickCheck
    ( Gen, Property, choose, conjoin, forAll, oneof, property, (===) )

import qualified Cardano.Wallet.Primitive.Migration.Planning as Planning
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as Map

spec :: Spec
spec = describe "Cardano.Wallet.Primitive.MigrationSpec" $

    parallel $
        describe "Creating migration plans (with concrete wallet types)" $ do

            it "prop_createPlan_equivalent" $
                property prop_createPlan_equivalent

--------------------------------------------------------------------------------
-- Creating migration plans (with concrete wallet types)
--------------------------------------------------------------------------------

-- This property test is really just a simple sanity check to ensure that it's
-- possible to create migration plans through the public interface, using
-- concrete wallet types such as 'UTxO', 'TxIn', and 'TxOut'.
--
-- As such, this test does not do anything beyond establishing that the results
-- of calling the following functions are equivalent:
--
--  - Migration         .createPlan (uses concrete wallet types)
--  - Migration.Planning.createPlan (uses abstract types)
--
-- For a more detailed test of 'createPlan' (with abstract types) see
-- 'PlanningSpec.prop_createPlan'.
--
prop_createPlan_equivalent :: Pretty MockTxConstraints -> Property
prop_createPlan_equivalent (Pretty mockConstraints) =
    forAll genUTxO $ \utxo ->
    forAll genRewardWithdrawal $ \reward ->
    prop_createPlan_equivalent_inner mockConstraints utxo reward
  where
    genUTxO :: Gen UTxO
    genUTxO = do
        entryCount <- choose (0, 64)
        UTxO . Map.fromList <$> replicateM entryCount genUTxOEntry
      where
        genUTxOEntry :: Gen (TxIn, TxOut)
        genUTxOEntry = (,) <$> genTxIn <*> genTxOut
          where
            genTxIn :: Gen TxIn
            genTxIn = genTxInLargeRange

            genTxOut :: Gen TxOut
            genTxOut = TxOut
                <$> genAddressSmallRange
                <*> genTokenBundleMixed mockConstraints

    genRewardWithdrawal :: Gen RewardWithdrawal
    genRewardWithdrawal = RewardWithdrawal <$> oneof
        [ pure (Coin 0)
        , genCoinRange (Coin 1) (Coin 1_000_000)
        ]

prop_createPlan_equivalent_inner
    :: MockTxConstraints
    -> UTxO
    -> RewardWithdrawal
    -> Property
prop_createPlan_equivalent_inner mockConstraints utxo reward =
    conjoin
        [ (===)
            (view #totalFee planWithConcreteTypes)
            (view #totalFee planWithAbstractTypes)
        , (===)
            (view #selections planWithConcreteTypes)
            (view #selections planWithAbstractTypes)
        , (===)
            (view #unselected planWithConcreteTypes)
            (view #unselected planWithAbstractTypes & uncategorizeUTxO)
        , (===)
            (utxoEmpty)
            (utxoIntersect utxoSelected utxoNotSelected)
        , (===)
            (utxo)
            (utxoUnion utxoSelected utxoNotSelected)
        ]
  where
    planWithConcreteTypes = createPlan constraints utxo reward
    planWithAbstractTypes = Planning.createPlan
        constraints (categorizeUTxO constraints utxo) reward

    constraints = unMockTxConstraints mockConstraints

    utxoEmpty :: UTxO
    utxoEmpty = UTxO Map.empty

    utxoIntersect :: UTxO -> UTxO -> UTxO
    utxoIntersect (UTxO u1) (UTxO u2) = UTxO $ Map.intersection u1 u2

    utxoUnion :: UTxO -> UTxO -> UTxO
    utxoUnion (UTxO u1) (UTxO u2) = UTxO $ Map.union u1 u2

    utxoSelected :: UTxO
    utxoSelected = planWithConcreteTypes
        & view #selections
        & fmap (NE.toList . view #inputIds)
        & mconcat
        & Map.fromList
        & UTxO

    utxoNotSelected :: UTxO
    utxoNotSelected = planWithConcreteTypes
        & view #unselected
