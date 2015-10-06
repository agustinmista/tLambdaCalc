module Simplytyped (
           conversion,    -- conversion a terminos localmente sin nombre
           eval,          -- evaluador
           infer,         -- inferidor de tipos
           quote          -- valores -> terminos
       ) where

import Common
import Data.List
import Data.Maybe
import Prelude hiding ((>>=))
import PrettyPrinter
import Text.PrettyPrint.HughesPJ (render)

-- conversion a términos localmente sin nombres
conversion :: LamTerm -> Term
conversion = conversion' []

conversion' :: [String] -> LamTerm -> Term
conversion' b (LVar n)    = maybe (Free (Global n)) Bound (n `elemIndex` b)
conversion' b (App t u)   = conversion' b t :@: conversion' b u
conversion' b (Abs n t u) = Lam t (conversion' (n:b) u)
conversion' b (Let x u v) = TLet (conversion' b u) (conversion' (x:b) v)
conversion' b (As t u)    = TAs t (conversion' b u)

-----------------------
--- eval
-----------------------

sub :: Int -> Term -> Term -> Term
sub i t (Bound j)  = if i == j then t else Bound j
sub _ _ (Free n)   = Free n
sub i t (u :@: v)  = sub i t u :@: sub i t v
sub i t (Lam t' u) = Lam t' (sub (i+1) t u)
sub i t (TLet u v) = TLet (sub i t u) (sub (i+1) t v)
sub i t (TAs t' u) = TAs t' (sub i t u)


-- evaluador de términos
eval :: NameEnv Value Type -> Term -> Value
eval _ (Bound _)             = error "variable ligada inesperada en eval"
eval e (Free n)              = fst $ fromJust $ lookup n e
eval _ (Lam t u)             = VLam t u
eval e (Lam _ u :@: Lam s v) = eval e (sub 0 (Lam s v) u)
eval e (Lam t u :@: v)       = case eval e v of
                                  VLam t' u' -> eval e (Lam t u :@: Lam t' u')
                                  _          -> error "Error de tipo en run-time, verificar type checker"
eval e (u :@: v)             = case eval e u of
                                  VLam t  u' -> eval e (Lam t u' :@: v)
                                  _          -> error "Error de tipo en run-time, verificar type checker"
eval e (TLet u@(Lam _ _) v)  = eval e (sub 0 u v)
eval e (TLet u           v)  = case eval e u of
                                  VLam t' u' -> eval e (sub 0 (Lam t' u') v)
                                  _          -> error "Error de tipo en run-time, verificar type checker"
eval e (TAs t u)             = eval e u

-----------------------
--- quoting
-----------------------

quote :: Value -> Term
quote (VLam t f) = Lam t f

----------------------
--- type checker
-----------------------

-- type checker
infer :: NameEnv Value Type -> Term -> Either String Type
infer = infer' []

infer' :: Context -> NameEnv Value Type -> Term -> Either String Type
infer' c _ (Bound i)   = ret (c !! i)
infer' _ e (Free n)    = case lookup n e of
                            Nothing    -> notfoundError n
                            Just (_,t) -> ret t
infer' c e (t :@: u)    = do tt <- infer' c e t
                             tu <- infer' c e u
                             case tt of
                                Fun t1 t2 -> if tu == t1
                                             then ret t2
                                             else matchError t1 tu
                                _         -> notfunError tt
infer' c e (Lam t u)    = do tu <- infer' (t:c) e u
                             ret $ Fun t tu
infer' c e (TLet u v)   = do tu <- infer' c e u
                             infer' (tu:c) e v
infer' c e (TAs t u)    = do tu <- infer' c e u
                             if t == tu then ret tu else matchError t tu

-- Sin notacion do
-- infer' c e (t :@: u)    = infer' c e t >>= \tt ->
--                          infer' c e u >>= \tu ->
--                              case tt of
--                                  Fun t1 t2 -> if tu == t1
--                                               then ret t2
--                                               else matchError t1 tu
--                                  _         -> notfunError tt
-- infer' c e (Lam t u)    = infer' (t:c) e u >>=
--                             \tu -> ret $ Fun t tu
-- infer' c e (TLet u v)   = infer' c e u >>=
--                             \tu -> infer' (tu:c) e v
-- infer' c e (TAs t u)    = infer' c e u >>=
--                             \tu -> if t = tu
--                                    then ret tu
--                                    else matchError t tu


-- definiciones auxiliares
ret :: Type -> Either String Type
ret = Right

err :: String -> Either String Type
err = Left

(>>=) :: Either String Type -> (Type -> Either String Type) -> Either String Type
(>>=) v f = either Left f v

-- fcs. de error
matchError :: Type -> Type -> Either String Type
matchError t1 t2 = err $ "se esperaba " ++ render (printType t1) ++
                         ", pero "      ++ render (printType t2) ++
                         " fue inferido."

notfunError :: Type -> Either String Type
notfunError t1 = err $ render (printType t1) ++ " no puede ser aplicado."

notfoundError :: Name -> Either String Type
notfoundError n = err $ show n ++ " no está definida."

----------------------------------
