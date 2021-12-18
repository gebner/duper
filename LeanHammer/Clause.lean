import Lean
import LeanHammer.Util

open Lean
open Lean.Meta

structure Lit :=
(sign : Bool)
(lvl : Level)
(ty : Expr)
(lhs : Expr)
(rhs : Expr)

deriving Inhabited, BEq, Hashable

namespace Lit

def toExpr (lit : Lit) : Expr :=
  if lit.sign
  then mkApp3 (mkConst ``Eq [lit.lvl]) lit.ty lit.lhs lit.rhs
  else mkApp3 (mkConst ``Ne [lit.lvl]) lit.ty lit.lhs lit.rhs

def fromExpr (e : Expr) (sign := true) : Lit :=
  Lit.mk
    (sign := true)
    (lvl := levelOne)
    (ty := mkSort levelZero)
    (lhs := e)
    (rhs := if sign then mkConst ``True else mkConst ``False)
  

def map (f : Expr → Expr) (l : Lit) :=
  {l with ty := f l.ty, lhs := f l.lhs, rhs := f l.rhs}

def mapM {m : Type → Type w} [Monad m] (f : Expr → m Expr) (l : Lit) : m Lit := do
  return {l with ty := ← f l.ty, lhs := ← f l.lhs, rhs := ← f l.rhs}

def fold {α : Type v} (f : α → Expr → α) (init : α) (l : Lit) : α :=
  f (f (f init l.ty) l.lhs) l.rhs

def foldM {β : Type v} {m : Type v → Type w} [Monad m] 
    (f : β → Expr → m β) (init : β) (l : Lit) (type := false) : m β := do
  let b := if type then ← f init l.ty else init
  f (← f b l.lhs) l.rhs

def symm (l : Lit) : Lit :=
{l with 
  lhs := l.rhs
  rhs := l.lhs}

instance : ToFormat Lit :=
⟨ fun lit => format lit.toExpr ⟩

instance : ToMessageData Lit :=
⟨ fun lit => lit.toExpr ⟩

end Lit

structure Clause :=
(bVarTypes : Array Expr)
(lits : Array Lit)
deriving Inhabited, BEq, Hashable

namespace Clause

def empty : Clause := ⟨#[], #[]⟩

def fromExpr (e : Expr) : Clause :=
  Clause.mk #[] #[Lit.fromExpr e]

def toExpr (c : Clause) : Expr :=
  litsToExpr c.lits.data
where litsToExpr : List Lit → Expr
| [] => mkConst ``False
| [l] => l.toExpr
| l :: ls => mkApp2 (mkConst ``Or) l.toExpr (litsToExpr ls)

def toForallExpr (c : Clause) : Expr :=
  c.bVarTypes.foldr (fun ty b => mkForall Name.anonymous BinderInfo.default ty b) c.toExpr

instance : ToFormat Clause :=
⟨ fun c => format c.toExpr ⟩

instance : ToMessageData Clause :=
⟨ fun c => c.toExpr ⟩

end Clause