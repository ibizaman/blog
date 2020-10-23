--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Maybe                     ( fromMaybe )
import           Data.Monoid                    ( mappend )
import           Hakyll
import           Control.Monad                  ( forM )


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

  tags <- buildTags "posts/*" (fromCapture "tags/*.html")
  let postCtxWithTags = postCtx tags

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
postCtx :: Tags -> Context String
postCtx tags =
  tagsField "tags" tags
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
