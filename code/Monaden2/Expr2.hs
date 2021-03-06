module Expr2 where

import           Control.Monad (liftM2)

data Expr  = Const  Int
           | Binary BinOp Expr Expr
             deriving (Show)

data BinOp = Add | Sub | Mul | Div | Mod
             deriving (Eq, Show)

data Result a
           = Val { val :: a }
           | Exc { exc :: String }
             deriving (Show)

instance Monad Result where
    return        = Val
    (Exc e) >>= _ = (Exc e)
    (Val v) >>= g = g v

throwError :: String -> Result a
throwError = Exc

eval :: Expr -> Result Int
eval (Const i)
    = return i

eval (Binary op l r)
    = do f <- lookupFtab op
         f (eval l) (eval r)

type BinFct = Result Int -> Result Int -> Result Int

lookupFtab :: BinOp -> Result BinFct
lookupFtab op
    = case lookup op ftab of
        Nothing -> throwError
                   "operation not implemented"
        Just f  -> return f

ftab :: [(BinOp, BinFct)]
ftab = [ (Add, liftM2 (+))
       , (Sub, liftM2 (-))
       , (Mul, liftM2 (*))
       , (Div, div'')
       ]

div''   :: Result Int -> Result Int -> Result Int
div'' x y
    = do x1 <- x
         y1 <- y
         if y1 == 0
           then throwError
                "division by zero"
           else return (x1 `div` y1)

-- ----------------------------------------

{- some tests

e1 = Binary Mul (Binary Add (Const 2)
                            (Const 4)
                )
                (Const 7)
e2 = Binary Div (Const 1) (Const 0)
e3 = Binary Mod (Const 1) (Const 0)

-- -}

-- ----------------------------------------
