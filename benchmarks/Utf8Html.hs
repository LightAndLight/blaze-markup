-- | This is a possible library implementation experiment and benchmark.
{-# LANGUAGE OverloadedStrings #-}
module Main where

import Data.Monoid (Monoid, mempty, mconcat, mappend)
import Prelude hiding (div)

import Criterion.Main
import Data.Binary.Builder (Builder, toLazyByteString)
import Data.ByteString.Char8 (ByteString)
import Data.Text (Text)
import GHC.Exts (IsString, fromString)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T

import Text.Blaze.Internal.Utf8Builder

main = defaultMain
    [ bench "bigTable" $ nf (BL.length . bigTable) myTable
    , bench "basic" $ nf (BL.length . basic) myData
    , bench "bigTableM" $ nf (BL.length . bigTableM) myTable
    , bench "basicM" $ nf (BL.length . basicM) myData
    ]
  where
    rows :: Int
    rows = 1000

    myTable :: [[Int]]
    myTable = replicate rows [1..10]
    {-# NOINLINE myTable #-}

    myData :: (Text, Text, [Text])
    myData = ("Just a test", "joe", items)
    {-# NOINLINE myData #-}

    items :: [Text]
    items = map (("Number " `mappend`) . T.pack . show) [1 .. 14]
    {-# NOINLINE items #-}

newtype Html = Html { runHtml :: Builder -> Builder }

text :: Text -> Html
text = Html . const . fromHtmlText
{-# INLINE text #-}

rawByteString :: ByteString -> Html
rawByteString = Html . const . fromRawByteString
{-# INLINE rawByteString #-}

showHtml :: Show a => a -> Html
showHtml = Html . const . fromHtmlString . show
{-# INLINE showHtml #-}


tag :: ByteString -> Html -> Html
tag name inner = Html $ \attrs ->
    fromRawAscii7Char '<' `mappend` (fromRawByteString name
                          `mappend` (attrs
                          `mappend` (fromRawAscii7Char '>'
                          `mappend` (runHtml inner mempty
                          `mappend` (fromRawByteString "</" 
                          `mappend` (fromRawByteString name
                          `mappend` (fromRawAscii7Char '>')))))))
{-# INLINE tag #-}

addAttr :: ByteString -> Text -> Html -> Html
addAttr key value h = Html $ \attrs ->
    runHtml h $ attrs `mappend` (fromRawAscii7Char ' '
                      `mappend` (fromRawByteString key
                      `mappend` (fromRawByteString "=\""
                      `mappend` (fromHtmlText value
                      `mappend` (fromRawAscii7Char '"')))))
{-# INLINE addAttr #-}

tag' :: ByteString -> ByteString -> Html -> Html
tag' begin end = \inner -> Html $ \attrs ->
    fromRawByteString begin
      `mappend` attrs
      `mappend` fromRawAscii7Char '>'
      `mappend` runHtml inner mempty
      `mappend` fromRawByteString end
{-# INLINE tag' #-}


table :: Html -> Html
table = let tableB, tableE :: ByteString
            tableB = "<table"
            tableE = "</table>"
            {-# NOINLINE tableB #-}
            {-# NOINLINE tableE #-}
        in tag' tableB tableE
{-# INLINE table #-}

-- SM: The effect of this inlining has to be investigated carefully w.r.t. code
-- size. Not inlining it doesn't cost a lot and may well save quite some code.
-- Moreoever, for bigger templates it may even be beneficial due to the less
-- trashing 


tr :: Html -> Html
tr = let trB, trE :: ByteString
         trB = "<tr"
         trE = "</tr>"
         {-# NOINLINE trB #-}
         {-# NOINLINE trE #-}
     in tag' trB trE
{-# INLINE tr #-}


td :: Html -> Html
td = let tdB, tdE :: ByteString
         tdB = "<td"
         tdE = "</td>"
         {-# NOINLINE tdB #-}
         {-# NOINLINE tdE #-}
     in tag' tdB tdE
{-# INLINE td #-}

renderHtml :: Html -> BL.ByteString
renderHtml h = toLazyByteString $ runHtml h mempty

instance Monoid Html where
    mempty = Html $ \_ -> mempty
    {-# INLINE mempty #-}
    (Html h1) `mappend` (Html h2) = Html $ \attrs -> h1 attrs `mappend` h2 attrs
    {-# INLINE mappend #-}
    mconcat hs = Html $ \attrs ->
        foldr (\h k -> runHtml h attrs `mappend` k) mempty hs
    {-# INLINE mconcat #-}

bigTable :: [[Int]] -> BL.ByteString
bigTable t = renderHtml $ table $ mconcat $ map row t
  where
    row r = tr $ mconcat $ map (td . showHtml) r

html :: Html -> Html
html inner = 
  -- a too long string for the fairness of comparison
  rawByteString "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2 FINAL//EN\">\n<!--Rendered using the Haskell Html Library v0.2-->\n"
  `mappend` tag "html" inner
  
header = tag' "<header" "</header>"
title  = tag' "<title"  "</title>"
body   = tag' "<body"   "</body>"
div    = tag' "<div"    "</div>"
h1     = tag' "<h1"     "</h1>"
h2     = tag' "<h2"     "</h2>"
li     = tag' "<li"     "</li>"

-- THE following seems to be the desired recipe: sharing of data, inlining of
-- control.
pB = "<p"
pE = "</p>"
p  = tag' pB pE
{-# NOINLINE pB #-}
{-# NOINLINE pE #-}
{-# INLINE p #-}

idA = addAttr "id"

hello1, hello2, hello3, loop :: ByteString
hello1 = "Hello, "
hello2 = "Hello, me!"
hello3 = "Hello, world!"
loop   = "Loop"

static = Html . const . fromRawByteString
{-# INLINE static #-}

basic :: (Text, Text, [Text]) -- ^ (Title, User, Items)
      -> BL.ByteString
basic (title', user, items) = renderHtml $ html $ mconcat
    [ header $ title $ text title'
    , body $ mconcat
        [ div $ idA "header" (h1 $ text title')
        , p $ static hello1 `mappend` text user `mappend` text "!"
        , p $ static hello2
        , p $ static hello3
        , h2 $ static loop
        , mconcat $ map (li . text) items
        , idA "footer" (div $ mempty)
        ]
    ]

-------------------------------------------------------------------------------
-- Below is a monadic implementation. The questions is if we can get this as
-- fast as the non-monadic one.
-------------------------------------------------------------------------------

newtype HtmlM a = HtmlM { runHtmlM :: Builder -> Builder }

textM :: Text -> HtmlM a
textM = HtmlM . const . fromHtmlText
{-# INLINE textM #-}

rawByteStringM :: ByteString -> HtmlM a
rawByteStringM = HtmlM . const . fromRawByteString
{-# INLINE rawByteStringM #-}

showAscii7HtmlM :: Show a => a -> HtmlM a
showAscii7HtmlM = HtmlM . const . fromHtmlShow
{-# INLINE showAscii7HtmlM #-}

tagM :: ByteString -> HtmlM a -> HtmlM a
tagM name inner = HtmlM $ \attrs ->
    fromRawAscii7Char '<' `mappend` (fromRawByteString name
                          `mappend` (attrs
                          `mappend` (fromRawAscii7Char '>'
                          `mappend` (runHtmlM inner mempty
                          `mappend` (fromRawByteString "</" 
                          `mappend` (fromRawByteString name
                          `mappend` (fromRawAscii7Char '>')))))))
-- By inlining this function, functions calling this (e.g. `tableHtml`) will close
-- around the `tag` variable, which ensures `tag'` is only calculated once.
{-# INLINE tagM #-}

addAttrM :: ByteString -> Text -> HtmlM a -> HtmlM a
addAttrM key value h = HtmlM $ \attrs ->
    runHtmlM h $ attrs `mappend` (fromRawAscii7Char ' '
                       `mappend` (fromRawByteString key
                       `mappend` (fromRawByteString "=\""
                       `mappend` (fromHtmlText value
                       `mappend` (fromRawAscii7Char '"')))))
{-# INLINE addAttrM #-}

tableM = tagM "table"
trM    = tagM "tr"
tdM    = tagM "td"

renderHtmlM :: HtmlM a -> BL.ByteString
renderHtmlM = toLazyByteString . flip runHtmlM mempty

instance Monoid (HtmlM a) where
    mempty = HtmlM $ \_ -> mempty
    {-# INLINE mempty #-}
    (HtmlM h1) `mappend` (HtmlM h2) = HtmlM $
        \attrs -> h1 attrs `mappend` h2 attrs
    {-# INLINE mappend #-}
    mconcat hs = HtmlM $ \attrs ->
        foldr (\h k -> runHtmlM h attrs `mappend` k) mempty hs
    {-# INLINE mconcat #-}

instance Monad HtmlM where
    return a = mempty
    {-# INLINE return #-}
    (HtmlM h1) >> (HtmlM h2) = HtmlM $
        \attrs -> h1 attrs `mappend` h2 attrs
    {-# INLINE (>>) #-}
    h1 >>= f = h1 >> f (error "_|_")
    {-# INLINE (>>=) #-}

instance IsString (HtmlM h) where
    fromString = HtmlM . const . fromHtmlText . fromString
    {-# INLINE fromString #-}

bigTableM :: [[Int]] -> BL.ByteString
bigTableM t = renderHtmlM $ tableM $ mapM_ row t
  where
    row r = trM $ mapM_ (tdM . showAscii7HtmlM) r

htmlM :: HtmlM a -> HtmlM a
htmlM inner = 
  -- a too long string for the fairness of comparison
  rawByteStringM "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2 FINAL//EN\">\n<!--Rendered using the Haskell Html Library v0.2-->\n"
  `mappend` tagM "html" inner
  
headerM = tagM "header"
titleM = tagM "title"
bodyM = tagM "body"
divM = tagM "div"
h1M = tagM "h1"
h2M = tagM "h2"
pM = tagM "p"
liM = tagM "li"

idAM = addAttrM "id"

basicM :: (Text, Text, [Text]) -- ^ (Title, User, Items)
       -> BL.ByteString
basicM (title', user, items) = renderHtmlM $ htmlM $ do
    headerM $ titleM $ textM title'
    bodyM $ do
        divM $ idAM "header" (h1M $ textM title')
        pM $ "Hello, " `mappend` (textM user) `mappend` "!"
        pM $ "Hello, me!"
        pM $ "Hello, world!"
        h2M $ "Loop"
        mconcat $ map (liM . textM) items
        idAM "footer" (divM $ mempty)
        
