--------------------------------------------------------------------------------
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
import           Data.Maybe                     ( fromMaybe )
import           Hakyll
import           Control.Monad                  ( forM )
import Hakyll.Favicon (faviconsRules, faviconsField)


--------------------------------------------------------------------------------
conf :: Configuration
conf = defaultConfiguration
  { deployCommand =
    "rm -rf ibizaman.github.io/* && cp -r _site/* ibizaman.github.io"
  }


main :: IO ()
main = hakyllWith conf $ do
  match "images/**" $ do
    route idRoute
    compile copyFileCompiler

  match "css/*" $ do
    route idRoute
    compile compressCssCompiler

  match (fromList ["about.md", "contact.md"]) $ do
    route $ setExtension "html"
    let ctx = faviconsField
              `mappend` defaultContext
    compile
      $   pandocCompiler
      >>= loadAndApplyTemplate "templates/default.html" ctx
      >>= relativizeUrls

  tags <- buildTagsWith excludeWipPosts "posts/*" (fromCapture "tags/*.html")
  let postCtxWithTags = postCtx tags

  tagsRules tags $ \tag pattern -> do
    let title = "Posts tagged \"" ++ tag ++ "\""
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll pattern
      let ctx =
            constField "title" title
              `mappend` listField "posts" postCtxWithTags (return posts)
              `mappend` faviconsField
              `mappend` defaultContext

      makeItem ""
        >>= loadAndApplyTemplate "templates/tag.html"     ctx
        >>= loadAndApplyTemplate "templates/default.html" ctx
        >>= relativizeUrls

  matchMetadata "posts/*" (\metadata -> maybe True (\_ -> False) $ lookupString "wip" metadata) $ do
    route $ setExtension "html"
    compile
      $   pandocCompiler
      >>= loadAndApplyTemplate "templates/post.html"    postCtxWithTags
      >>= saveSnapshot "content"
      >>= loadAndApplyTemplate "templates/default.html" postCtxWithTags
      >>= relativizeUrls

  -- create ["archive.html"] $ do
  --   route idRoute
  --   compile $ do
  --     posts <- recentFirst =<< loadAll "posts/*"
  --     let archiveCtx =
  --           listField "posts" postCtxWithTags (return posts)
  --             `mappend` constField "title" "Archive"
  --             `mappend` defaultContext

  --     makeItem ""
  --       >>= loadAndApplyTemplate "templates/archive.html" archiveCtx
  --       >>= loadAndApplyTemplate "templates/default.html" archiveCtx
  --       >>= relativizeUrls

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
              `mappend` faviconsField
              `mappend` defaultContext

      getResourceBody
        >>= applyAsTemplate tagsCtx
        >>= loadAndApplyTemplate "templates/default.html" tagsCtx
        >>= relativizeUrls

  create ["atom.xml"] $ do
    route idRoute
    compile $ do
        let feedCtx = postCtxWithTags `mappend` bodyField "description"
        posts <- fmap (take 100) . recentFirst =<<
            loadAllSnapshots "posts/*" "content"
        renderAtom myFeedConfiguration feedCtx posts

  match "index.html" $ do
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll "posts/*"
      let indexCtx =
            listField "posts" postCtxWithTags (return posts)
              `mappend` faviconsField
              `mappend` defaultContext

      getResourceBody
        >>= applyAsTemplate indexCtx
        >>= loadAndApplyTemplate "templates/default.html" indexCtx
        >>= relativizeUrls

  match "templates/*" $ compile templateBodyCompiler

  faviconsRules "images/favicon.svg"


--------------------------------------------------------------------------------
postCtx :: Tags -> Context String
postCtx tags =
  tagsField "tags" tags
    `mappend` dateField "date" "%B %e, %Y"
    `mappend` faviconsField
    `mappend` defaultContext

data TagMetadata = TagMetadata
         { tagName :: String
         , tagUrl :: String
         , tagCount :: Int
         }

tagsMetadata :: Tags -> Compiler [TagMetadata]
tagsMetadata tags = do
  forM (tagsMap tags) $ \(tag, ids) -> do
    route' <- getRoute $ tagsMakeId tags tag
    return $ TagMetadata tag (fromMaybe "/" route') (length ids)

excludeWipPosts :: MonadMetadata m => Identifier -> m [String]
excludeWipPosts identifier =
    getTagsByField "wip" identifier >>= \case
        [] -> getTags identifier
        _ -> return []

myFeedConfiguration :: FeedConfiguration
myFeedConfiguration = FeedConfiguration
    { feedTitle       = "ibizaman's Blog"
    , feedDescription = "I write about programming, electronics and some other DIY projects."
    , feedAuthorName  = "ibizaman"
    , feedAuthorEmail = "blog@pierre.tiserbox.com"
    , feedRoot        = "https://blog.tiserbox.com/"
    }
