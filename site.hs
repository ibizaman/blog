--------------------------------------------------------------------------------
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
import           Data.Maybe                     ( catMaybes
                                                , fromMaybe
                                                )
import           Data.Monoid                    ( mappend )
import           Hakyll
import           Control.Monad                  ( forM_
                                                , foldM
                                                , mplus
                                                , forM
                                                )
import qualified Data.Set                      as S
import qualified Data.Map                      as M
import qualified Text.Blaze.Html5              as H
import           Data.List                      ( sortBy
                                                , intercalate
                                                , intersperse
                                                )
import qualified Text.Blaze.Html5.Attributes   as A
import           Text.Blaze.Html5               ( (!) )
import           Text.Blaze.Html                ( ToValue(toValue) )
import           Text.Blaze.Html                ( toHtml )
import           Text.Blaze.Html.Renderer.String
                                                ( renderHtml )
import           Control.Arrow                  ( Arrow((&&&)) )
import           Data.Ord                       ( comparing )
import           Data.Char                      ( toLower )


--------------------------------------------------------------------------------
conf :: Configuration
conf = defaultConfiguration
  { deployCommand =
    "rm -rf ibizaman.github.io/* && cp -r _site/* ibizaman.github.io"
  }


main :: IO ()
main = hakyllWith conf $ do
  match "images/*" $ do
    route idRoute
    compile copyFileCompiler

  match "css/*" $ do
    route idRoute
    compile compressCssCompiler

  match (fromList ["about.markdown", "contact.markdown"]) $ do
    route $ setExtension "html"
    compile
      $   pandocCompiler
      >>= loadAndApplyTemplate "templates/default.html" defaultContext
      >>= relativizeUrls

  tags  <- buildTags "posts/*" (fromCapture "tags/*.html")
  serie <- buildSeries "posts/*" (fromCapture "serie/*.html")
  let postCtxWithTags = postCtx tags serie

  tagsRules tags $ \tag pattern -> do
    let title = "Posts tagged \"" ++ tag ++ "\""
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll pattern
      let ctx =
            constField "title" title
              `mappend` listField "posts" postCtxWithTags (return posts)
              `mappend` defaultContext

      makeItem ""
        >>= loadAndApplyTemplate "templates/tag.html"     ctx
        >>= loadAndApplyTemplate "templates/default.html" ctx
        >>= relativizeUrls

  seriesRules serie $ \s pattern -> do
    let title = "Posts from serie \"" ++ s ++ "\""
    route idRoute
    compile $ do
      posts <- chronological =<< loadAll pattern
      let ctx =
            constField "title" title
              `mappend` listField "posts" postCtxWithTags (return posts)
              `mappend` defaultContext

      makeItem ""
        >>= loadAndApplyTemplate "templates/serie.html"   ctx
        >>= loadAndApplyTemplate "templates/default.html" ctx
        >>= relativizeUrls

  match "posts/*" $ do
    route $ setExtension "html"
    compile
      $   pandocCompiler
      >>= loadAndApplyTemplate "templates/post.html"    postCtxWithTags
      >>= loadAndApplyTemplate "templates/default.html" postCtxWithTags
      >>= relativizeUrls

  create ["archive.html"] $ do
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll "posts/*"
      let archiveCtx =
            listField "posts" postCtxWithTags (return posts)
              `mappend` constField "title" "Archive"
              `mappend` defaultContext

      makeItem ""
        >>= loadAndApplyTemplate "templates/archive.html" archiveCtx
        >>= loadAndApplyTemplate "templates/default.html" archiveCtx
        >>= relativizeUrls

  create ["tags.html"] $ do
    route idRoute
    compile $ do
      tags' <- tagsMetadata tags
      let tagsCtx =
            listField
                "tags"
                (  field "name"  (return . tagName . itemBody)
                <> field "url"   (return . tagUrl . itemBody)
                <> field "count" (return . show . tagCount . itemBody)
                )
                (sequence $ map makeItem $ tags')
              `mappend` defaultContext

      getResourceBody
        >>= applyAsTemplate tagsCtx
        >>= loadAndApplyTemplate "templates/default.html" tagsCtx
        >>= relativizeUrls

  match "index.html" $ do
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll "posts/*"
      let indexCtx =
            listField "posts" postCtxWithTags (return posts)
              `mappend` defaultContext

      getResourceBody
        >>= applyAsTemplate indexCtx
        >>= loadAndApplyTemplate "templates/default.html" indexCtx
        >>= relativizeUrls

  match "templates/*" $ compile templateBodyCompiler


--------------------------------------------------------------------------------
postCtx :: Tags -> Series -> Context String
postCtx tags series =
  tagsField "tags" tags
    `mappend` seriesField "series" series
    `mappend` dateField "date" "%B %e, %Y"
    `mappend` defaultContext

data TagMetadata = TagMetadata
         { tagName :: String
         , tagUrl :: String
         , tagCount :: Int
         }

tagsMetadata :: Tags -> Compiler [TagMetadata]
tagsMetadata tags = do
  let tagsList = map fst $ tagsMap tags
  forM (tagsMap tags) $ \(tag, ids) -> do
    route' <- getRoute $ tagsMakeId tags tag
    return $ TagMetadata tag (fromMaybe "/" route') (length ids)


--------------------------------------------------------------------------------
-- | Data about series
data Series = Series
    { seriesMap        :: [(String, [Identifier])]
    , seriesMakeId     :: String -> Identifier
    , seriesDependency :: Dependency
    }


--------------------------------------------------------------------------------
-- | Obtain series from a page in the default way: parse them from the @series@
-- metadata field. This can either be a list or a comma-separated string.
getSeries :: MonadMetadata m => Identifier -> m [String]
getSeries identifier = do
  metadata <- getMetadata identifier
  return
    $       fromMaybe []
    $       (lookupStringList "series" metadata)
    `mplus` (map trim . splitAll "," <$> lookupString "series" metadata)


--------------------------------------------------------------------------------
-- | Higher-order function to read series
buildSeriesWith
  :: MonadMetadata m
  => (Identifier -> m [String])
  -> Pattern
  -> (String -> Identifier)
  -> m Series
buildSeriesWith f pattern makeId = do
  ids      <- getMatches pattern
  serieMap <- foldM addSeries M.empty ids
  let set' = S.fromList ids
  return $ Series (M.toList serieMap) makeId (PatternDependency pattern set')
 where
    -- Create a serie map for one page
  addSeries serieMap id' = do
    series <- f id'
    let serieMap' = M.fromList $ zip series $ repeat [id']
    return $ M.unionWith (++) serieMap serieMap'


--------------------------------------------------------------------------------
buildSeries :: MonadMetadata m => Pattern -> (String -> Identifier) -> m Series
buildSeries = buildSeriesWith getSeries


--------------------------------------------------------------------------------
buildCategories
  :: MonadMetadata m => Pattern -> (String -> Identifier) -> m Series
buildCategories = buildSeriesWith getCategory


--------------------------------------------------------------------------------
seriesRules :: Series -> (String -> Pattern -> Rules ()) -> Rules ()
seriesRules series rules = forM_ (seriesMap series) $ \(serie, identifiers) ->
  rulesExtraDependencies [seriesDependency series]
    $ create [seriesMakeId series serie]
    $ rules serie
    $ fromList identifiers


--------------------------------------------------------------------------------
-- | Render series in HTML (the flexible higher-order function)
renderSeries
  :: (String -> String -> Int -> Int -> Int -> String)
           -- ^ Produce a serie item: serie, url, count, min count, max count
  -> ([String] -> String)
           -- ^ Join items
  -> Series
           -- ^ Serie cloud renderer
  -> Compiler String
renderSeries makeHtml concatHtml series = do
    -- In series' we create a list: [((serie, route), count)]
  series' <- forM (seriesMap series) $ \(serie, ids) -> do
    route' <- getRoute $ seriesMakeId series serie
    return ((serie, route'), length ids)

  -- TODO: We actually need to tell a dependency here!

  let -- Absolute frequencies of the pages
      freqs = map snd series'

      -- The minimum and maximum count found
      (min', max') | null freqs = (0, 1)
                   | otherwise  = (minimum &&& maximum) freqs

      -- Create a link for one item
      makeHtml' ((serie, url), count) =
        makeHtml serie (toUrl $ fromMaybe "/" url) count min' max'

  -- Render and return the HTML
  return $ concatHtml $ map makeHtml' series'


--------------------------------------------------------------------------------
-- | Render a serie cloud in HTML
renderSerieCloud
  :: Double
               -- ^ Smallest font size, in percent
  -> Double
               -- ^ Biggest font size, in percent
  -> Series
               -- ^ Input series
  -> Compiler String
               -- ^ Rendered cloud
renderSerieCloud = renderSerieCloudWith makeLink (intercalate " ")
 where
  makeLink minSize maxSize serie url count min' max' =
      -- Show the relative size of one 'count' in percent
    let diff     = 1 + fromIntegral max' - fromIntegral min'
        relative = (fromIntegral count - fromIntegral min') / diff
        size     = floor $ minSize + relative * (maxSize - minSize) :: Int
    in  renderHtml
          $ H.a
          ! A.style (toValue $ "font-size: " ++ show size ++ "%")
          ! A.href (toValue url)
          $ toHtml serie


--------------------------------------------------------------------------------
-- | Render a serie cloud in HTML
renderSerieCloudWith
  :: (Double -> Double -> String -> String -> Int -> Int -> Int -> String)
                   -- ^ Render a single serie link
  -> ([String] -> String)
                   -- ^ Concatenate links
  -> Double
                   -- ^ Smallest font size, in percent
  -> Double
                   -- ^ Biggest font size, in percent
  -> Series
                   -- ^ Input series
  -> Compiler String
                   -- ^ Rendered cloud
renderSerieCloudWith makeLink cat minSize maxSize =
  renderSeries (makeLink minSize maxSize) cat


--------------------------------------------------------------------------------
-- | Render a serie cloud in HTML as a context
serieCloudField
  :: String
               -- ^ Destination key
  -> Double
               -- ^ Smallest font size, in percent
  -> Double
               -- ^ Biggest font size, in percent
  -> Series
               -- ^ Input series
  -> Context a
               -- ^ Context
serieCloudField key minSize maxSize series =
  field key $ \_ -> renderSerieCloud minSize maxSize series


--------------------------------------------------------------------------------
-- | Render a serie cloud in HTML as a context
serieCloudFieldWith
  :: String
                  -- ^ Destination key
  -> (Double -> Double -> String -> String -> Int -> Int -> Int -> String)
                  -- ^ Render a single serie link
  -> ([String] -> String)
                  -- ^ Concatenate links
  -> Double
                  -- ^ Smallest font size, in percent
  -> Double
                  -- ^ Biggest font size, in percent
  -> Series
                  -- ^ Input series
  -> Context a
                  -- ^ Context
serieCloudFieldWith key makeLink cat minSize maxSize series =
  field key $ \_ -> renderSerieCloudWith makeLink cat minSize maxSize series


--------------------------------------------------------------------------------
-- | Render a simple serie list in HTML, with the serie count next to the item
-- TODO: Maybe produce a Context here
renderSerieList :: Series -> Compiler (String)
renderSerieList = renderSeries makeLink (intercalate ", ")
 where
  makeLink serie url count _ _ =
    renderHtml $ H.a ! A.href (toValue url) $ toHtml
      (serie ++ " (" ++ show count ++ ")")


--------------------------------------------------------------------------------
-- | Render series with links with custom functions to get series and to
-- render links
seriesFieldWith
  :: (Identifier -> Compiler [String])
              -- ^ Get the series
  -> (String -> (Maybe FilePath) -> Maybe H.Html)
              -- ^ Render link for one serie
  -> ([H.Html] -> H.Html)
              -- ^ Concatenate serie links
  -> String
              -- ^ Destination field
  -> Series
              -- ^ Series structure
  -> Context a
              -- ^ Resulting context
seriesFieldWith getSeries' renderLink cat key series = field key $ \item -> do
  series' <- getSeries' $ itemIdentifier item
  links   <- forM series' $ \serie -> do
    route' <- getRoute $ seriesMakeId series serie
    return $ renderLink serie route'

  return $ renderHtml $ cat $ catMaybes $ links


--------------------------------------------------------------------------------
-- | Render series with links
seriesField
  :: String     -- ^ Destination key
  -> Series       -- ^ Series
  -> Context a  -- ^ Context
seriesField =
  seriesFieldWith getSeries simpleRenderLink (mconcat . intersperse ", ")


--------------------------------------------------------------------------------
-- | Render the category in a link
categoryField
  :: String     -- ^ Destination key
  -> Series       -- ^ Series
  -> Context a  -- ^ Context
categoryField =
  seriesFieldWith getCategory simpleRenderLink (mconcat . intersperse ", ")


--------------------------------------------------------------------------------
-- | Render one serie link
simpleRenderLink :: String -> (Maybe FilePath) -> Maybe H.Html
simpleRenderLink _ Nothing = Nothing
simpleRenderLink serie (Just filePath) =
  Just
    $ H.a
    ! A.title (H.stringValue ("All pages serieged '" ++ serie ++ "'."))
    ! A.href (toValue $ toUrl filePath)
    $ toHtml serie


--------------------------------------------------------------------------------
-- | Sort series using supplied function. First element of the tuple passed to
-- the comparing function is the actual serie name.
sortSeriesBy
  :: ((String, [Identifier]) -> (String, [Identifier]) -> Ordering)
  -> Series
  -> Series
sortSeriesBy f t = t { seriesMap = sortBy f (seriesMap t) }


--------------------------------------------------------------------------------
-- | Sample sorting function that compares series case insensitively.
caseInsensitiveSeries
  :: (String, [Identifier]) -> (String, [Identifier]) -> Ordering
caseInsensitiveSeries = comparing $ map toLower . fst
