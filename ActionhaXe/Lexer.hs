-- Turn the as3 source into Tokens for parsing

module ActionhaXe.Lexer (runLexer, Token, tokenSource, tokenLine, tokenCol, tokenItem, TokenType(..), TokenNum(..), keywords, operators) where

import Text.Parsec
import Text.Parsec.String (Parser)
import Text.Parsec.Char
import Text.Parsec.Perm
import Data.Char
import Data.List 

type Token = (SourcePos, TokenType)

tokenSource (s, i) = sourceName s
tokenLine (s, i) = sourceLine s
tokenCol (s, i) = sourceColumn s
tokenItem (s, i) = i

data TokenNum    = TokenInteger String
                 | TokenDouble String
                 | TokenOctal String
                 | TokenHex String
    deriving (Show, Eq)


data TokenType = 
             TokenWhite String
           | TokenComment String
           | TokenNum TokenNum
           | TokenIdent String
           | TokenString String
           | TokenNl String
           | TokenRegex (String, String)
           | TokenKw String
           | TokenOp String
           | TokenXml String
           | TokenUnknown String
    deriving (Show, Eq)

keywords = [ "...", "as", "break", "case", "catch", "class", "const", "continue", "default",
             "delete", "do", "else", "extends", "false", "finally", "for", "function", "if",
             "implements", "internal", "is", "native", "new", "null", "package", "private",
             "protected", "public", "return", "super", "switch", "this", "throw", "to",
             "true", "try", "typeof", "use", "var", "void", "while", "with",
-- syntactic keywords
             "each", "get", "set", "namespace", "include", "dynamic", "final", "native",
             "override", "static"
           ]

operators = [ ".", "[", "]", "(", ")", "@", "::", "..", "{", "}", 
              "++", "--", "-", "~", "!", "*", "/", "%",
              "+", "-", "<<", ">>", ">>>", "<", "<=", ">", ">=",
              "==", "!=", "===", "!==", "&", "^", "|", "&&", "||",
              "?", "=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=",
              ">>>=", "&=", "^=", "|=", ",", ":", ";"
            ]

keyword = do { x <- many1 identChar; if (elem x $ keywords) then return (TokenKw x) else unexpected "keyword" }

identifier = do{ x<- (satisfy (\c -> isAlpha c || c == '_' || c == '$')); x' <- many identChar; return $ TokenIdent $ [x]++x' }

identChar = satisfy (\c -> isAlphaNum c || c == '_' || c == '$')

sortByLength = sortBy (\x y -> compare (length y) (length x))

operator' (o:os) = try (do{ s <- string o; return $ TokenOp s })
               <|> operator' os
operator' []     = fail " failed "

operator = operator' $ sortByLength operators

simpleSpace = many1 (satisfy (\c -> c == ' ' || c == '\t'))
whiteSpace = do{ x <- many1 ( try( simpleSpace ) <|>  nl' ); return $ TokenWhite $ concat x}

anyCharButNl = do{ c <- (satisfy(\c-> isPrint c && c /= '\r' && c /= '\n')); return c }

escapedAnyChar = try(do{ char '\\'; c <- anyCharButNl; return $ "\\"++[c]})
             <|> do{ c <- anyCharButNl; return [c]}

nl' = do{ try (string "\r\n"); return "\r\n" }
 <|> do{ try (char '\n'); return "\n" }
 <|> do{ try (char '\r'); return "\r" }

nl = do{ x <- nl'; return $ TokenNl x}

quotedDString = do{ char '"'; s <- manyTill escapedAnyChar (char '"'); return $ TokenString $ "\"" ++ (concat s) ++ "\""}
quotedSString = do{ char '\''; s <- manyTill escapedAnyChar (char '\''); return $ TokenString $ "'" ++ (concat s) ++ "'"}

commentSLine = do{ string "//"; s <- manyTill anyChar (lookAhead nl); return $ TokenComment $ "//"++s}
commentMLine = do{ string "/*"; s <- manyTill anyChar (try(string "*/")); return $ TokenComment $ "/*"++s++"*/" }

xml = do{ char '<'; t <- many1 (satisfy (\c -> isPrint c && c /= '>')); char '>'; x <- manyTill anyChar (try (string $ "</"++t++">")); return $ TokenXml $ "<"++t++">"++x++"</"++t++">"}

xmlSTag = do{ char '<'; t <- manyTill (satisfy (\c -> isPrint c && c /= '/' && c /= '>')) (string "/>"); return $ TokenXml $ "<"++t++"/>"}

regexOptions = permute (catter <$?> ('_', char 'g') <|?> ('_', char 'i') <|?> ('_', char 'm') <|?> ('_', char 's') <|?> ('_', char 'x'))
    where catter g i m s x =  filter (\c -> c /= '_') [g, i, m, s, x]
regex = do { char '/'; notFollowedBy (char ' '); s <- manyTill escapedAnyChar (char '/'); o <- optionMaybe regexOptions; return $ maybe (TokenRegex ("/"++(concat s)++"/", "")) (\m -> TokenRegex ("/"++(concat s)++"/", m)) o}

number = try (do{ char '0'; char 'x'; x <- many1 hexDigit; return $ TokenNum $ TokenHex $ "0x"++x})
     <|> try (do{ char '0'; x <- many1 octDigit; return $ TokenNum $ TokenOctal $ "0"++x})
     <|> try (do{ x <- many digit; char '.'; y <- many1 digit; return $ TokenNum $ TokenDouble $  x++"."++y  })
     <|> try (do{ x <- many1 digit; return $ TokenNum $ TokenInteger $ x })

atoken = 
         try (do{ x <- keyword; return x})
     <|> try (do{ x <- commentSLine; return x})
     <|> try (do{ x <- commentMLine; return x})
     <|> try (do{ x <- xmlSTag; return x})
     <|> try (do{ x <- xml; return x})
     <|> try (do{ x <- regex; return x})
     <|> try (do{ x <- number; return x})
     <|> try (do{ x <- operator; return x})
     <|> try (do{ x <- identifier; return x})
     <|> try (do{ x <- quotedDString; return x})
     <|> try (do{ x <- quotedSString; return x})
     <|> try (do{ x <- whiteSpace; return x}) 
     <|> try (do{ x <- anyToken; return $ TokenUnknown $ x:[]})


lexer = many1 (do { p <- getPosition; t <- atoken; return (p, t) })

runLexer :: String -> String -> [Token]
runLexer filename s = case parse lexer filename s of
                  Right l -> l
                  Left _ -> []
