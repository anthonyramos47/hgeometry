{-# Language DeriveFunctor#-}
{-# Language FunctionalDependencies #-}
module Data.BinaryTree where

import           Control.DeepSeq
import           Data.List.NonEmpty (NonEmpty(..),(<|))
import qualified Data.List.NonEmpty as NonEmpty
import           Data.Maybe (mapMaybe)
import           Data.Semigroup
import           Data.Semigroup.Foldable
import qualified Data.Tree as Tree
import qualified Data.Vector as V
import           GHC.Generics (Generic)

--------------------------------------------------------------------------------

data BinLeafTree v a = Leaf !a
                     | Node (BinLeafTree v a) !v (BinLeafTree v a)
                     deriving (Show,Read,Eq,Ord,Functor,Generic)

instance (NFData v, NFData a) => NFData (BinLeafTree v a)

class Semigroup v => Measured v a | a -> v where
  measure :: a -> v

-- | smart constructor
node     :: Measured v a => BinLeafTree v a -> BinLeafTree v a -> BinLeafTree v a
node l r = Node l (measure l <> measure r) r


instance Measured v a => Measured v (BinLeafTree v a) where
  measure (Leaf x)     = measure x
  measure (Node _ v _) = v


instance Foldable (BinLeafTree v) where
  foldMap f (Leaf a)     = f a
  foldMap f (Node l _ r) = foldMap f l `mappend` foldMap f r

instance Foldable1 (BinLeafTree v)

instance Traversable (BinLeafTree v) where
  traverse f (Leaf a)     = Leaf <$> f a
  traverse f (Node l v r) = Node <$> traverse f l <*> pure v <*> traverse f r

instance Measured v a => Semigroup (BinLeafTree v a) where
  l <> r = node l r

-- | Create a balanced tree, i.e. a tree of height \(O(\log n)\) with the
-- elements in the leaves.
--
-- \(O(n)\) time.
asBalancedBinLeafTree :: NonEmpty a -> BinLeafTree Size (Elem a)
asBalancedBinLeafTree = repeatedly merge . fmap (Leaf . Elem)
  where
    repeatedly _ (t :| []) = t
    repeatedly f ts        = repeatedly f $ f ts

    merge ts@(_ :| [])  = ts
    merge (l :| r : []) = node l r :| []
    merge (l :| r : ts) = node l r <| (merge $ NonEmpty.fromList ts)
-- -- the implementation below produces slightly less high trees, but runs in
-- -- \(O(n \log n)\) time, as on every level it traverses the list passed down.
-- asBalancedBinLeafTree ys = asBLT (length ys') ys' where ys' = toList ys

--     asBLT _ [x] = Leaf (Elem x)
--     asBLT n xs  = let h       = n `div` 2
--                       (ls,rs) = splitAt h xs
--                   in node (asBLT h ls) (asBLT (n-h) rs)

-- | Given a function to combine internal nodes into b's and leafs into b's,
-- traverse the tree bottom up, and combine everything into one b.
foldUp                  :: (b -> v -> b -> b) -> (a -> b) -> BinLeafTree v a -> b
foldUp _ g (Leaf x)     = g x
foldUp f g (Node l x r) = f (foldUp f g l) x (foldUp f g r)


-- | Traverses the tree bottom up, recomputing the assocated values.
foldUpData     :: (w -> v -> w -> w) -> (a -> w) -> BinLeafTree v a -> BinLeafTree w a
foldUpData f g = foldUp f' Leaf
  where
    f' l v r = Node l (f (access' l) v (access' r)) r

    access' (Leaf x)     = g x
    access' (Node _ v _) = v

-- | Takes two trees, that have the same structure, and uses the provided
-- functions to "zip" them together
zipExactWith                                  :: (u -> v -> w)
                                              -> (a -> b -> c)
                                              -> BinLeafTree u a
                                              -> BinLeafTree v b
                                              -> BinLeafTree w c
zipExactWith _ g (Leaf x)     (Leaf y)        = Leaf (x `g` y)
zipExactWith f g (Node l m r) (Node l' m' r') = Node (zipExactWith f g l l')
                                                     (m `f` m')
                                                     (zipExactWith f g r r')
zipExactWith _ _ _            _               =
    error "zipExactWith: tree structures not the same "

newtype Size = Size Int deriving (Show,Read,Eq,Num,Integral,Enum,Real,Ord,Generic,NFData)

instance Semigroup Size where
  x <> y = x + y

instance Monoid Size where
  mempty = Size 0
  mappend = (<>)

newtype Elem a = Elem { _unElem :: a }
               deriving (Show,Read,Eq,Ord,Functor,Foldable,Traversable)

instance Measured Size (Elem a) where
  measure _ = 1


data Sized a = Sized !Size a
             deriving (Show,Eq,Ord,Functor,Foldable,Traversable,Generic)
instance NFData a => NFData (Sized a)

instance Semigroup a => Semigroup (Sized a) where
  (Sized i a) <> (Sized j b) = Sized (i <> j) (a <> b)

instance Monoid a => Monoid (Sized a) where
  mempty = Sized mempty mempty
  (Sized i a) `mappend` (Sized j b) = Sized (i <> j) (a `mappend` b)

-- instance Semigroup a => Measured Size (Sized a) where
--   measure (Sized i _) = i


--------------------------------------------------------------------------------
-- * Converting into a Data.Tree

data RoseElem v a = InternalNode v | LeafNode a deriving (Show,Eq,Functor)

toRoseTree              :: BinLeafTree v a -> Tree.Tree (RoseElem v a)
toRoseTree (Leaf x)     = Tree.Node (LeafNode x) []
toRoseTree (Node l v r) = Tree.Node (InternalNode v) (map toRoseTree [l,r])


drawTree :: (Show v, Show a) => BinLeafTree v a -> String
drawTree = Tree.drawTree . fmap show . toRoseTree


--------------------------------------------------------------------------------
-- * Internal Node Tree


data BinaryTree a = Nil
                  | Internal (BinaryTree a) !a (BinaryTree a)
                  deriving (Show,Read,Eq,Ord,Functor,Foldable,Traversable,Generic)
instance NFData a => NFData (BinaryTree a)

-- | Get the element stored at the root, if it exists
access                  :: BinaryTree a -> Maybe a
access Nil              = Nothing
access (Internal _ x _) = Just x

-- | Create a balanced binary tree
--
-- \(O(n)\)
asBalancedBinTree :: [a] -> BinaryTree a
asBalancedBinTree = mkTree . V.fromList
  where
    mkTree v = let n = V.length v
                   h = n `div` 2
                   x = v V.! h
               in if n == 0 then Nil
                            else Internal (mkTree $ V.slice 0 h v) x
                                          (mkTree $ V.slice (h+1) (n - h -1) v)


foldBinaryUp                      :: b -> (a -> b -> b -> b)
                                  -> BinaryTree a -> BinaryTree (a,b)
foldBinaryUp _ _ Nil              = Nil
foldBinaryUp e f (Internal l x r) = let l' = foldBinaryUp e f l
                                        r' = foldBinaryUp e f r
                                        g  = maybe e snd . access
                                        b  = f x (g l') (g r')
                                    in Internal l' (x,b) r'

toRoseTree'                  :: BinaryTree a -> Maybe (Tree.Tree a)
toRoseTree' Nil              = Nothing
toRoseTree' (Internal l v r) = Just $ Tree.Node v $ mapMaybe toRoseTree' [l,r]

drawTree' :: Show a => BinaryTree a -> String
drawTree' = maybe "Nil" (Tree.drawTree . fmap show) . toRoseTree'
