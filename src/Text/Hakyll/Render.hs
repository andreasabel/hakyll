-- | Module containing rendering functions. All these functions are used to
--   render files to the @_site@ directory.
module Text.Hakyll.Render 
    ( render
    , renderAndConcat
    , renderChain
    , static
    , css
    ) where

import Control.Arrow ((>>>))
import Control.Monad.Reader (liftIO)
import System.Directory (copyFile)
import Data.Maybe (fromMaybe)
import qualified Data.Map as M

import Text.Hakyll.Hakyll (Hakyll, Context)
import Text.Hakyll.File
import Text.Hakyll.HakyllAction
import Text.Hakyll.Internal.CompressCss
import Text.Hakyll.Internal.Render
import Text.Hakyll.Internal.Template (readTemplate)

-- | Render to a Page.
render :: FilePath                     -- ^ Template to use for rendering.
       -> HakyllAction Context Context -- ^ The render computation.
render templatePath = HakyllAction
    { actionDependencies = [templatePath]
    , actionUrl          = Nothing
    , actionFunction     = actionFunction'
    }
  where
    actionFunction' context = do
        template <- readTemplate templatePath
        return $ pureRender template context

-- | Render each renderable with the given templates, then concatenate the
--   result. So, basically this function:
--
--   * Takes every renderable.
--
--   * Renders every renderable with all given templates. This is comparable
--     with a renderChain action.
--
--   * Concatenates the result.
--
renderAndConcat :: [FilePath]
                -> [HakyllAction () Context]
                -> HakyllAction () String
renderAndConcat templatePaths renderables = HakyllAction
    { actionDependencies = renders >>= actionDependencies
    , actionUrl          = Nothing
    , actionFunction     = actionFunction'
    }
  where
    render' = chain (map render templatePaths)
    renders = map (>>> render') renderables

    actionFunction' _ = do
        contexts <- mapM runHakyllAction renders
        return $ concatMap (fromMaybe "" . M.lookup "body") contexts

-- | Chain a render action for a page with a number of templates. This will
--   also write the result to the site destination. This is the preferred way
--   to do general rendering.
--
--   > renderChain [ "templates/notice.html"
--   >             , "templates/default.html"
--   >             ] $ createPagePath "warning.html"
--
--   This code will first render @warning.html@ using @templates/notice.html@,
--   and will then render the result with @templates/default.html@.
renderChain :: [FilePath]
            -> HakyllAction () Context
            -> Hakyll ()
renderChain templatePaths initial =
    runHakyllActionIfNeeded renderChainWith'
  where
    renderChainWith' :: HakyllAction () ()
    renderChainWith' = initial >>> chain' >>> writePage

    chain' = chain (map render templatePaths)


-- | Mark a certain file as static, so it will just be copied when the site is
--   generated.
static :: FilePath -> Hakyll ()
static source = runHakyllActionIfNeeded static'
  where
    static' = createFileHakyllAction source $ do
        destination <- toDestination source
        makeDirectories destination
        liftIO $ copyFile source destination

-- | Render a css file, compressing it.
css :: FilePath -> Hakyll ()
css source = runHakyllActionIfNeeded css'
  where
    css' = createFileHakyllAction source $ do
        contents <- liftIO $ readFile source
        destination <- toDestination source
        makeDirectories destination
        liftIO $ writeFile destination (compressCss contents)
