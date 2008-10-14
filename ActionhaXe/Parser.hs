-- Parse the tokens generated by Lexer
-- TODO:
--       updating Array parameter type,
--       for 
--       while/do
--       if
--       case

module ActionhaXe.Parser(parseTokens) where

import ActionhaXe.Lexer
import ActionhaXe.Prim
import ActionhaXe.Data
import Text.Parsec
import Text.Parsec.Combinator
import Text.Parsec.Perm
import Text.Parsec.Expr

emptyctok = ([],[])

parseTokens :: String -> [Token] -> Either ParseError Ast
parseTokens filename ts = runParser program initState filename ts

program :: AsParser Ast
program = do{ x <- package; a <- getState; return $ Program x a}

package = do{ w <- startWs; p <- kw "package"; i <- optionMaybe(ident); storePackage i;  b <- packageBlock; return $ Package w p i b }

packageBlock = do{ l <- op "{"; enterScope; x <- inPackageBlock; r <- op "}"; exitScope; return $ Block l x r }

inPackageBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- importDecl; i <- inPackageBlock; return $ [x] ++ i})
      <|> try(do{ x <- classDecl; i <- inBlock; return $ [x] ++ i})
      <|> try(do{ x <- anytok; i <- inPackageBlock; return $ [(Tok x)] ++ i})

classBlock = do{ l <- op "{"; enterScope; x <- inClassBlock; r <- op "}"; exitScope; return $ Block l x r }

inClassBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- methodDecl; i <- inClassBlock; return $ [x] ++ i})
      <|> try(do{ x <- varDecl; i <- inClassBlock; return $ [x] ++ i})
      <|> try(do{ x <- anytok; i <- inClassBlock; return $ [(Tok x)] ++ i})

funcBlock = do{ l <- op "{"; enterScope; x <- inMethodBlock; r <- op "}"; exitScope; return $ Block l x r }

inMethodBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- expr; i <- inMethodBlock; return $ [x] ++ i})
      <|> try(do{ b <- block; i <- inMethodBlock; return $ [b] ++ i })
      <|> try(do{ x <- varDecl; i <- inMethodBlock; return $ [x] ++ i})
      <|> try(do{ x <- anytok; i <- inMethodBlock; return $ [(Tok x)] ++ i})

block = do{ l <- op "{"; enterScope; x <- inBlock; r <- op "}"; exitScope; return $ Block l x r }

inBlock = try(do{ lookAhead( op "}"); return [] })
      <|> try(do{ x <- expr; i <- inBlock; return $ [x] ++ i})
      <|> try(do{ b <- block; i <- inBlock; return $ [b] ++ i })
      <|> try(do{ x <- varDecl; i <- inBlock; return $ [x] ++ i})
      <|> try(do{ x <- anytok; i <- inBlock; return $ [(Tok x)] ++ i})

importDecl = do{ k <- kw "import"; s <- sident; o <- maybeSemi; return $ ImportDecl k s o}

-- need to fix classImplements to return a tuple
classDecl = do{ a <- classAttributes; k <- kw "class"; i <- ident; e <- optionMaybe(classExtends); im <- optionMaybe(classImplements); storeClass i; b <- classBlock; return $ ClassDecl a k i e im b}

classAttributes = permute $ list <$?> (emptyctok, (try (kw "public") <|> (kw "internal"))) <|?> (emptyctok, kw "static") <|?> (emptyctok, kw "dynamic")
    where list v s d = filter (\a -> fst a /= []) [v,s,d]

classExtends = do{ k <- kw "extends"; s <- nident; return $ k:[s]}

-- need to fix this so it returns a tuple to classDecl
classImplements = do{ k <- kw "implements"; s <- sepByCI1 nident (op ","); return $ k:s} 

methodDecl = do{ attr <- methodAttributes; k <- kw "function"; acc <- optionMaybe( try(kw "get") <|> (kw "set")); n <- nident; enterScope; sig <- signature; b <- optionMaybe funcBlock; exitScope; storeMethod n; return $ MethodDecl attr k acc n sig b}

methodAttributes = permute $ list <$?> (emptyctok, (try (kw "public") <|> try (kw "private") <|> (kw "protected"))) <|?> (emptyctok, ident) <|?> (emptyctok, kw "override") <|?> (emptyctok, kw "static") <|?> (emptyctok, kw "final") <|?> (emptyctok, kw "native")
    where list v o s f n ns = filter (\a -> fst a /= []) [v,ns,o,s,f,n]

signature = do{ lp <- op "("; a <- sigargs; rp <- op ")"; ret <- optionMaybe ( do{ o <- op ":"; r <- datatype; return (o, r)}); return $ Signature lp a rp ret} -- missing return type means constructor

sigargs = do{ s <- many sigarg; return s}
sigarg = try(do{ a <- ident; o <- op ":"; t <- datatype; d <- optionMaybe( do{ o' <- op "="; a <- defval; return $ [o']++a}); c <- optionMaybe(op ","); storeVar a t; return $ Arg a o t d c})
     <|> do{ d <- count 3 (op "."); i <- ident; storeVar i AsTypeRest; return $ RestArg d i }

defval = do{ x <- manyTill defval' (try (lookAhead (op ",")) <|> lookAhead(op ")")); return x }

defval' = try( do{ x <- kw "null"; return x})
      <|> try( do{ x <- kw "true"; return x})
      <|> try( do{ x <- kw "false"; return x})
      <|> try( do{ x <- ident; return x})
      <|> try( do{ x <- str; return x})
      <|> do{ x <- num; return x}

varDecl = do{ ns <- optionMaybe(varAttributes); k <- choice[kw "var", kw "const"]; b <- many1 varBinding; s <- maybeSemi; return $ VarDecl ns k b s}

varAttributes = permute $ list <$?> (emptyctok, (choice[kw "public", kw "private", kw "protected"])) <|?> (emptyctok, ident) <|?> (emptyctok, kw "static") <|?> (emptyctok, kw "native")
    where list v ns s n = filter (\a -> fst a /= []) [v,ns,s,n]

varBinding = do{ n <- idn; c <- op ":"; dt <- datatype; i <- optionMaybe (do{ o <- op "="; e <- assignE; return $ (o, e)}); s <- optionMaybe (op ","); storeVar n dt; return $ VarBinding n c dt i s }

datatype = try(do{ t <- kw "void";      return $ AsType t})
       <|> try(do{ t <- mid "int";      return $ AsType t})
       <|> try(do{ t <- mid "uint";     return $ AsType t})
       <|> try(do{ t <- mid "Number";   return $ AsType t})
       <|> try(do{ t <- mid "Boolean";  return $ AsType t})
       <|> try(do{ t <- mid "String";   return $ AsType t})
       <|> try(do{ t <- mid "Object";   return $ AsType t})
       <|> try(do{ t <- op "*";         return $ AsType t})
       <|> try(do{ t <- mid "Array";    return $ AsType t})
       <|> try(do{ t <- mid "Function"; return $ AsType t})
       <|> try(do{ t <- mid "RegExp";   return $ AsType t})
       <|> try(do{ t <- mid "XML";      return $ AsType t})
-- Vector.<*> new in flash 10
       <|> do{ i <- ident; return $ AsTypeUser i}

primaryE = try(do{ x <- kw "this"; return $ PEThis x})
       <|> try(do{ x <- idn; return $ PEIdent x})
       <|> try(do{ x <- choice[(kw "null"), (kw "true"), (kw "false"), (kw "public"), (kw "private"), (kw "protected"), (kw "internal")]; return $ PELit x})
       <|> try(do{ x <- str; return $ PELit x})
       <|> try(do{ x <- num; return $ PELit x})
       <|> try(do{ x <- arrayLit; return $ PEArray x})
       <|> try(do{ x <- objectLit; return $ PEObject x})
       <|> try(do{ x <- reg; return $ PERegex x})
       <|> try(do{ x <- xml; return $ PEXml x})
       <|> try(do{ x <- funcE; return $ PEFunc x})
       <|> do{ x <- parenE; return $ x} 

arrayLit = try(do{ l <- op "["; e <- elementList; r <- op "]"; return $ ArrayLit l e r})
       <|> do{ l <- op "["; e <- optionMaybe elision; r <- op "]"; return $ ArrayLitC l e r}

elementList = do 
    l <- optionMaybe elision
    e <- assignE
    el <- many (try(do{ c <- elision; p <- assignE; return $ EAE c p}))
    r <- optionMaybe elision
    return $ El l e el r

elision = do{ x <- many1 (op ","); return $ Elision x}

objectLit = do{ l <- op "{"; x <- optionMaybe propertyNameAndValueList; r <- op "}"; return $ ObjectLit l x r}

propertyNameAndValueList = do{ x <- many1 (do{ p <- propertyName; c <- op ":"; e <- assignE; s <- optionMaybe (op ","); return (p, c, e, s)}); return $ PropertyList x}

propertyName = do{ x <- choice [ident, str, num]; return x}

funcE = do{ f <- kw "function"; i <- optionMaybe ident; enterScope; s <- signature; b <- funcBlock; exitScope; return $ FuncE f i s b}

parenE = do{ l <- op "("; e <- listE; r <- op ")"; return $ PEParens l e r}

listE = do{ e <- many1 (do{x <- assignE; c <- optionMaybe (op ","); return (x, c)}); return $ ListE e}

postFixE = try(do{ x <- fullPostFixE; o <- postFixUp; return $ PFFull x o})
        <|> do{ x <- shortNewE; o <- postFixUp; return $ PFShortNew x o}
    where postFixUp = optionMaybe (do{ o <- choice [op "++", op "--"]; return o})

fullPostFixE = try(do{ x <- primaryE; s <- many fullPostFixSubE; return $ FPFPrimary x s})
           <|> try(do{ x <- fullNewE; s <- many fullPostFixSubE; return $ FPFFullNew x s})
           <|> (do{ x <- superE; p <- propertyOp; s <- many fullPostFixSubE; return $ FPFSuper x p s})

fullPostFixSubE = try(do{ p <- propertyOp; return $ FPSProperty p})
              <|> try(do{ a <- args; return $ FPSArgs a})  -- call expression
              <|> do{ q <- queryOp; return $ FPSQuery q}

fullNewE = do{ k <- kw "new"; e <- fullNewSubE; a <- args; return $ FN k e a}

fullNewSubE = try(do{ e <- fullNewE; return e})
          <|> try(do{ e <- primaryE; p <- many propertyOp; return $ FNPrimary e p})
          <|> do{ e <- superE; p <- many1 propertyOp; return $ FNSuper e p}

shortNewE = do{ k <- kw "new"; s <- shortNewSubE; return $ SN k s}

shortNewSubE = try(do{ e <- fullNewSubE; return $ SNSFull e})
           <|> do{ e <- shortNewE; return $ SNSShort e}

superE = do{ k <- kw "super"; p <- optionMaybe args; return $ SuperE k p}

args = do{ l <- op "("; e <- optionMaybe listE; r <- op ")"; return $ Arguments l e r}

propertyOp = try(do{ o <- op "."; n <- idn; return $ PropertyOp o n})
         <|> do{ l <- op "["; e <- listE; r <- op "]"; return $ PropertyB l e r}

queryOp = try(do{ o <- op ".."; n <- nident; return $ QueryOpDD o n})
      <|> do{ o <- op "."; l <- op "("; e <- listE; r <- op ")"; return $ QueryOpD o l e r}

unaryE = try(do{ k <- kw "delete"; p <- postFixE; return $ UEDelete k p})
     <|> try(do{ k <- kw "void"; p <- postFixE; return $ UEVoid k p})
     <|> try(do{ k <- kw "typeof"; p <- postFixE; return $ UETypeof k p})
     <|> try(do{ o <- op "++"; p <- postFixE; return $ UEInc o p})
     <|> try(do{ o <- op "--"; p <- postFixE; return $ UEDec o p})
     <|> try(do{ o <- op "+"; p <- unaryE; return $ UEPlus o p})
     <|> try(do{ o <- op "-"; p <- unaryE; return $ UEMinus o p})
     <|> try(do{ o <- op "~"; p <- unaryE; return $ UEBitNot o p})
     <|> try(do{ o <- op "!"; p <- unaryE; return $ UENot o p})
     <|> do{ p <- postFixE; return $ UEPrimary p }

aeUnary = do{ x <- unaryE; return $ AEUnary x}

aritE = buildExpressionParser (aritOpTable True) aeUnary

aritENoIn = buildExpressionParser (aritOpTable False) aeUnary

aritOpTable allowIn =
    [
     [o "*", o "/", o "%"],                     -- multiplicative
     [o "+", o "-"],                             -- additive
     [o "<<", o ">>", o ">>>"],                 -- shift
     [o "<", o ">", o "<=", o ">="] 
         ++ (if allowIn == True then [ok "in"] else []) 
         ++ [ ok "instanceof", ok "is", ok "as"],   -- relational
     [o "==", o "!=", o "===", o "!=="],       -- equality
     [o "&"], [o "^"], [o "|"],                 -- bitwise
     [o "&&"], [o "||"]                          -- logical
    ]
    where o opr = Infix (do{ o' <- op opr; return (\x y -> AEBinary o' x y)}) AssocLeft
          ok kop = Infix (do{ k <- kw kop; return (\x y -> AEBinary k x y)}) AssocLeft

condE = do{ e <- aritE; o <- optionMaybe (do{ q <- op "?"; e1 <- assignE; c <- op ":"; e2 <- assignE; return $ (q, e1, c, e2)}); return $ CondE e o}

condENoIn = do{ e <- aritENoIn; o <- optionMaybe (do{ q <- op "?"; e1 <- assignENoIn; c <- op ":"; e2 <- assignENoIn; return $ (q, e1, c, e2)}); return $ CondE e o}

nonAssignE = do{ e <- aritE; o <- optionMaybe (do{ q <- op "?"; e1 <- nonAssignE; c <- op ":"; e2 <- nonAssignE; return $ (q, e1, c, e2)}); return $ NAssignE e o}

nonAssignENoIn = do{ e <- aritENoIn; o <- optionMaybe (do{ q <- op "?"; e1 <- nonAssignENoIn; c <- op ":"; e2 <- nonAssignENoIn; return $ (q, e1, c, e2)}); return $ NAssignE e o}

typeE = nonAssignE

typeENoIn = nonAssignENoIn

assignE = try(do{ p <- postFixE; 
                          try(do{o <- choice [op "&&=", op "^^=", op "||="]; a <- assignE; return $ ALogical p o a})
                      <|> try(do{o <- choice [op "*=", op "/=", op "%=", op "+=", op "-=", op "<<=", op ">>=", op ">>>=", op "&=", op "^=", op "|="]; a <- assignE; return $ ACompound p o a})
                      <|> do{ p <- postFixE; o <- op "="; a <- assignE; return $ AAssign p o a}
                }
             )
      <|> do{ e <- condE; return $ ACond e}

assignENoIn = try(do{ p <- postFixE; o <- choice [op "&&=", op "^^=", op "||="]; a <- assignENoIn; return $ ALogical p o a})
      <|> try(do{ p <- postFixE; o <- choice [op "*=", op "/=", op "%=", op "+=", op "-=", op "<<=", op ">>=", op ">>>=", op "&=", op "^=", op "|="]; a <- assignENoIn; return $ ACompound p o a})
      <|> try(do{ p <- postFixE; o <- op "="; a <- assignENoIn; return $ AAssign p o a})
      <|> do{ e <- condE; return $ ACond e}

expr = do{ x <- assignE; return $ Expr x}

exprNoIn = do{ x <- assignENoIn; return $ Expr x}
