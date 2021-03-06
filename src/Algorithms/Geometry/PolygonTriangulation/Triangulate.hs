module Algorithms.Geometry.PolygonTriangulation.Triangulate where


import qualified Algorithms.Geometry.PolygonTriangulation.MakeMonotone as MM
import qualified Algorithms.Geometry.PolygonTriangulation.TriangulateMonotone as TM
import           Algorithms.Geometry.PolygonTriangulation.Types
import           Control.Lens
import           Data.Either (lefts)
import           Data.Ext
import qualified Data.Foldable as F
import           Data.Geometry.PlanarSubdivision.Core
import           Data.Geometry.Polygon
import           Data.Semigroup

-- | Triangulates a polygon of \(n\) vertices
--
-- running time: \(O(n \log n)\)
triangulate       :: (Ord r, Fractional r)
                  => proxy s -> Polygon t p r
                  -> PlanarSubdivision s p PolygonEdgeType PolygonFaceData r
triangulate px pg = constructSubdivision px e es diags
  where
    (e:es)        = listEdges pg
    monotoneP     = MM.makeMonotone (wrap px) pg
    outerFaceId'  = outerFaceId monotoneP

    monotoneDiags = map (^._2.core) . filter (\e' -> e'^._2.extra == Diagonal)
                  . F.toList . edgeSegments $ monotoneP
    extraDiags    = concatMap (TM.computeDiagonals . toCounterClockWiseOrder')
                  . lefts . map (^._2.core)
                  . filter (\f -> f^._1 /= outerFaceId')
                  . F.toList . rawFacePolygons $ monotoneP
    diags         = monotoneDiags <> extraDiags

    -- we alredy know we get the polgyons in *clockwise* order, so skip the
    -- check if it is counter clockwise
    toCounterClockWiseOrder' = reverseOuterBoundary

    -- just to make sure that the proxies have different types
wrap :: a -> Identity a
wrap = Identity
