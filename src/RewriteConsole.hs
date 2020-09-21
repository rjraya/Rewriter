import Control.Monad
import Control.Exception
import System.IO
import System.IO.Error
import Data.List
import Data.Char
import System.Environment  
import Rewriting
import Text.Parsec.Error
import qualified Data.HashMap as M
import qualified TRS
import qualified Terms

extractTerm trs s = parseTermEither trs $ tail $ dropWhile (/=' ') s

extractTerms trs s sep =
    if isInfixOf sep' s' then 
        Just (parseTermEither trs s1, parseTermEither trs s2)
    else
        Nothing
    where sep' = ' ' : sep ++ " "
          s' = tail (dropWhile (/=' ') s)
          (s1,s2) = split s' []
          split (c:s) acc
              | isPrefixOf sep' (c:s) = (acc, drop (length sep') (c:s))
              | otherwise = split s (acc ++ [c])
              
helpMessage = "Available commands:" ++ concatMap ("\n  "++) commands ++ "\n"
    
commands = ["help", "rules", "term", "unify", "match", "rewrite", "trace", "normalise", 
            "normalise_trace", "critical_pairs", "locally_confluent", "quit"]
commandHelpMessages = [
    "help <command>\n"++
    "    Without an argument: displays a list of all available commands.\n" ++
    "    With a command as an argument: displays a description of the given \n" ++
    "    command.",
    "rules\n"++
    "    Prints a list of all the rules in the term rewriting system.\n",
    "term <term>\n"++
    "    Parses the given term and displays its internal (non-pretty-printed) \n" ++
    "    representation.\n",
    "unify <term1> and <term2>\n" ++
    "    Prints the most general unifier σ for the given two terms t1 and t2, \n" ++
    "    if a unifier exists. The term σ(t1) = σ(t2) is also printed.",
    "match <term1> to <term2>\n" ++
    "    Prints the matcher σ for the first given term t1 to the second one t2, \n" ++
    "    if it exists. A matcher is a substitution such that σ(t1) = t2.",
    "rewrite [<term>]\n"++
    "    Applies a single rewrite step to the given term and displays a list of\n"++
    "    all possible results. (There may be several, as several rules may be\n"++
    "    applicable, and the same rule may be applicable in different positions\n"++
    "    of the term.)\n"++
    "    If no term is given, the first term in the last result list is used.\n",
    "trace [<term>]\n"++
    "    Iteratively applies the rewrite rules until a normal form is reached and\n"++
    "    then displays a rewriting trace for every distinct normal form.\n"++
    "    If no term is given, the first term in the last result list is used.\n",
    "normalise [<term>]\n"++
    "    Eagerly applies all rewrite rules iteratively until a normal form is used\n"++
    "    and then returns this normal form.\n"++
    "    If no term is given, the first term in the last result list is used.\n",
    "normalise_trace [<term>]\n"++
    "    Eagerly applies all rewrite rules iteratively until a normal form is used\n"++
    "    and then returns a trace from the original term to this normal form.\n"++
    "    If no term is given, the first term in the last result list is used.\n",
    "critical_pairs\n"++
    "    Prints a list of all critical pairs of the term rewriting system.\n",
    "locally_confluent [verbose]\n"++
    "    Tries to determine whether the term rewriting system is locally \n"++
    "    confluent, i.e. whether any split of the form t1 ← s → t2 can be\n" ++
    "    rejoined with t1 →* t ←* t2.\n" ++
    "    If the option \"verbose\" is given, a list of all critical pairs and \n" ++
    "    whether they are joinable or not is also printed.\n",
    "quit\n"++
    "    Ends the programme.\n"]
    
doHelp s = case elemIndex s commands of
               Nothing -> putStrLn "No such command."
               Just i -> putStrLn ('\n' : commandHelpMessages !! i)

doShowRules :: TRS.TRS -> IO ()
doShowRules trs = case trs of
    TRS.TRS _ rules -> putStrLn $ intercalate "\n" $ map (prettyPrintRule trs) rules

doShowTerm :: Either ParseError Terms.Term -> IO (Maybe Terms.Term)
doShowTerm (Left e) = putStrLn (show e) >> return Nothing
doShowTerm (Right t) = putStrLn (show t) >> return (Just t)

doUnify :: TRS.TRS -> Maybe (Either ParseError Terms.Term, Either ParseError Terms.Term) -> IO (Maybe Terms.Term)
doUnify _ Nothing = putStrLn ("Invalid parameters. Please type " ++
                        "\"unify <term1> and <term2>\".") >> return Nothing
doUnify _ (Just (Left e, _)) = putStrLn (show e) >> return Nothing
doUnify _ (Just (_, Left e)) = putStrLn (show e) >> return Nothing
doUnify trs (Just (Right t1, Right t2)) =
    case unify (t1,t2) of
        Left e -> putStrLn ("No unifiers: " ++ show e) >> return Nothing
        Right σ -> let t' = Terms.applySubst σ t1 
                   in putStrLn ("Most general unifier:\n" ++ 
                                 prettyPrintSubst trs σ ++ "\n\n" ++
                                 "Corresponding term: " ++ prettyPrint trs t') >>
                      return (Just t')

doMatch :: TRS.TRS -> Maybe (Either ParseError Terms.Term, Either ParseError Terms.Term) -> IO ()
doMatch _ Nothing = putStrLn ("Invalid parameters. Please type " ++
                       "\"match <term1> to <term2>\".")
doMatch _ (Just (Left e, _)) = putStrLn (show e)
doMatch _ (Just (_, Left e)) = putStrLn (show e)
doMatch trs (Just (Right t1,Right t2)) =
    case match (t1,t2) of
        Left e -> putStrLn ("No matchers: " ++ show e)
        Right σ -> putStrLn ("Matcher:\n" ++ prettyPrintSubst trs σ)

doRewrite :: TRS.TRS -> Either ParseError Terms.Term -> IO (Maybe Terms.Term)
doRewrite _ (Left e) = putStrLn (show e) >> return Nothing
doRewrite trs (Right t) = case ts of
    [] -> putStrLn "Term is already in normal form." >> return Nothing
    (t:_) -> do putStrLn $ intercalate "\n" $ 
                    zipWith (\a b -> show a ++ ": " ++ b) 
                    [1..genericLength ts] (map (prettyPrint trs) ts)
                return (Just t)
    where ts = rewrite trs t

doTrace :: TRS.TRS -> Either ParseError Terms.Term -> IO (Maybe Terms.Term)
doTrace _ (Left e) = putStrLn (show e) >> return Nothing
doTrace trs (Right t) = case traces of
    [] -> putStrLn "No result." >> return Nothing
    _ -> do putStrLn $ intercalate "\n\n" $ 
                zipWith (\a b -> "Trace " ++ show a ++ ":\n" ++ b) 
                [1..genericLength traces] (map (prettyPrintTrace trs) traces)
            return Nothing
    where traces = rewriteTrace trs t

doNormalise :: TRS.TRS -> Either ParseError Terms.Term -> IO (Maybe Terms.Term)
doNormalise _ (Left e) = putStrLn (show e) >> return Nothing
doNormalise trs (Right t) = putStrLn (prettyPrint trs (normalise trs t)) >> return Nothing

doNormaliseTrace :: TRS.TRS -> Either ParseError Terms.Term -> IO (Maybe Terms.Term)
doNormaliseTrace _ (Left e) = putStrLn (show e) >> return Nothing
doNormaliseTrace trs (Right t) = putStrLn (prettyPrintTrace trs (normaliseTrace trs t)) >> return Nothing

doCriticalPairs :: TRS.TRS -> IO ()
doCriticalPairs trs = 
    case cps of 
        [] -> putStrLn "No critical pairs."
        _ -> putStr $ concatMap formatPair $ zip [1..genericLength cps] cps
    where cps = criticalPairs trs
          formatPair (i,(s,t1,t2)) = "Critical pair " ++ show i ++ ":\n" ++
                                     pretty s ++ " → " ++ pretty t1 ++ "\n" ++
                                     pretty s ++ " → " ++ pretty t2 ++ "\n\n"
          pretty t = prettyPrint trs t

doLocallyConfluent :: TRS.TRS -> Bool -> IO ()
doLocallyConfluent trs verbose = putStr $ 
        (if verbose then concatMap formatPair $ zip [1..ncps] cps else []) ++
        ("System is " ++ (if isWeaklyConfluent trs then [] else "not ") ++
              "locally confluent.\n")
    where cps = concatMap (\(s,t1,t2) -> 
                               let n1 = normalise trs t1
                                   n2 = normalise trs t2
                                in if n1 == n2 then [] else [(s,t1,t2,n1,n2)])
                          (criticalPairs trs)
          ncps = genericLength cps
          formatPair (i,(s,t1,t2,n1,n2)) = 
              "Unjoinable critical pair " ++ show i ++ ":\n" ++
              pretty s ++ " → " ++ pretty t1 ++ " →* " ++ pretty n1 ++ " (irreducible)\n" ++
              pretty s ++ " → " ++ pretty t2 ++ " →* " ++ pretty n2 ++  " (irreducible)\n\n"
          pretty t = prettyPrint trs t

commandLoop :: TRS.TRS -> Maybe Terms.Term -> IO ()
commandLoop trs last = do
    putStr "TRS> "
    hFlush stdout
    str <- getLine
    case words (map toLower str) of
        [] -> commandLoop trs last
        "quit":_ -> return ()
        "help":[] -> putStrLn helpMessage >> commandLoop trs last
        "help":cmd:_ -> doHelp cmd >> commandLoop trs last
        "rules":_ -> doShowRules trs >> commandLoop trs last
        "term":[] -> case last of
            Nothing -> putStrLn "No current result. Type 'term <term>'" >> commandLoop trs Nothing
            Just t -> doShowTerm (Right t) >>= commandLoop trs
        "rewrite":[] -> case last of
            Nothing -> putStrLn "No current result. Type 'rewrite <term>'" >> commandLoop trs Nothing
            Just t -> doRewrite trs (Right t) >>= commandLoop trs
        "trace":[] -> case last of
            Nothing -> putStrLn "No current result. Type 'trace <term>'" >> commandLoop trs Nothing
            Just t -> doTrace trs (Right t) >>= commandLoop trs
        "normalise":[] -> case last of
            Nothing -> putStrLn "No current result. Type 'normalise <term>'" >> commandLoop trs Nothing
            Just t -> doNormalise trs (Right t)  >>= commandLoop trs
        "normalise_trace":[] -> case last of
            Nothing -> putStrLn "No current result. Type 'normalise_trace <term>'" >> commandLoop trs Nothing
            Just t -> doNormaliseTrace trs (Right t)  >>= commandLoop trs
        "term":_ -> doShowTerm (extractTerm trs str) >>= commandLoop trs
        "unify":_ -> doUnify trs (extractTerms trs str "and") >>= commandLoop trs
        "match":_ -> doMatch trs (extractTerms trs str "to") >> commandLoop trs last
        "rewrite":_ -> doRewrite trs (extractTerm trs str) >>= commandLoop trs
        "trace":_ -> doTrace trs (extractTerm trs str) >>= commandLoop trs
        "normalise":_ -> doNormalise trs (extractTerm trs str) >>= commandLoop trs
        "normalise_trace":_ -> doNormaliseTrace trs (extractTerm trs str) >>= commandLoop trs
        "critical_pairs":_ -> doCriticalPairs trs >> commandLoop trs Nothing
        "locally_confluent":"verbose":_-> doLocallyConfluent trs True >> commandLoop trs Nothing
        "locally_confluent":_ -> doLocallyConfluent trs False >> commandLoop trs Nothing
        xs:_ -> putStrLn ("Unknown command: " ++ xs) >> commandLoop trs last

main = do
    args <- getArgs
    if genericLength args < 1 then
        putStrLn "Usage: rewrite <TRS file>"
    else do
        trs <- parseTRSFile (head args)
        seq trs $ catch (commandLoop trs Nothing) (\e -> if isEOFError e then putStrLn "" else ioError e)



