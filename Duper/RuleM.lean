import Lean
import Duper.Unif
import Duper.MClause

namespace Duper

namespace RuleM
open Lean
open Lean.Core

structure Context where
  order : Expr → Expr → MetaM Comparison := Order.kbo
deriving Inhabited

structure ProofParent where
  clause : Clause 
  instantiations : Array Expr
  vanishingVarTypes : Array Expr
-- some variables disappear in inferences, 
-- but need to be instantiated when reconstructing the proof
-- e.g., EqRes on x != y
deriving Inhabited

/-- Takes: Proofs of the parent clauses, ProofParent information, the target clause -/
abbrev ProofReconstructor := Array Expr → Array ProofParent → Clause → MetaM Expr

structure Proof where
  parents : Array ProofParent := #[]
  ruleName : String := "unknown"
  introducedSkolems : Array (FVarId × (Array Expr → MetaM Expr)) := #[]
  mkProof : ProofReconstructor
deriving Inhabited

structure State where
  mctx : MetavarContext := {}
  lctx : LocalContext := {}
  loadedClauses : Array (Clause × Array MVarId) := #[]
  resultClauses : Array (Clause × Proof) := #[]
  introducedSkolems : Array (FVarId × (Array Expr → MetaM Expr)) := #[]
deriving Inhabited

abbrev RuleM := ReaderT Context $ StateRefT State CoreM

initialize
  registerTraceClass `Rule
  registerTraceClass `Rule.debug

instance : Monad RuleM := let i := inferInstanceAs (Monad RuleM); { pure := i.pure, bind := i.bind }

instance : MonadLCtx RuleM where
  getLCtx := return (← get).lctx

instance : MonadMCtx RuleM where
  getMCtx    := return (← get).mctx
  modifyMCtx f := modify fun s => { s with mctx := f s.mctx }

instance : Inhabited (RuleM α) where
  default := fun _ _ => arbitrary

@[inline] def RuleM.run (x : RuleM α) (ctx : Context := {}) (s : State := {}) : CoreM (α × State) :=
  x ctx |>.run s

@[inline] def RuleM.run' (x : RuleM α) (ctx : Context := {}) (s : State := {}) : CoreM α :=
  Prod.fst <$> x.run ctx s

@[inline] def RuleM.toIO (x : RuleM α) (ctxCore : Core.Context) (sCore : Core.State) (ctx : Context := {}) (s : State := {}) : IO (α × Core.State × State) := do
  let ((a, s), sCore) ← (x.run ctx s).toIO ctxCore sCore
  pure (a, sCore, s)

instance [MetaEval α] : MetaEval (RuleM α) :=
  ⟨fun env opts x _ => MetaEval.eval env opts x.run' true⟩

def getOrder : RuleM (Expr → Expr → MetaM Comparison) :=
  return (← read).order

def getMCtx : RuleM MetavarContext :=
  return (← get).mctx

def getLoadedClauses : RuleM (Array (Clause × Array MVarId)) :=
  return (← get).loadedClauses

def getResultClauses : RuleM (Array (Clause × Proof)) :=
  return (← get).resultClauses

def getIntroducedSkolems : RuleM (Array (FVarId × (Array Expr → MetaM Expr))) :=
  return (← get).introducedSkolems

def setMCtx (mctx : MetavarContext) : RuleM Unit :=
  modify fun s => { s with mctx := mctx }

def setLCtx (lctx : LocalContext) : RuleM Unit :=
  modify fun s => { s with lctx := lctx }

def setLoadedClauses (loadedClauses : Array (Clause × Array MVarId)) : RuleM Unit :=
  modify fun s => { s with loadedClauses := loadedClauses }

def setResultClauses (resultClauses : Array (Clause × Proof)) : RuleM Unit :=
  modify fun s => { s with resultClauses := resultClauses }

def setIntroducedSkolems (introducedSkolems : Array (FVarId × (Array Expr → MetaM Expr))) : RuleM Unit :=
  modify fun s => { s with introducedSkolems := introducedSkolems }

def withoutModifyingMCtx (x : RuleM α) : RuleM α := do
  let s ← getMCtx
  try
    x
  finally
    setMCtx s

-- TODO: Reset `introducedSkolems`?
def withoutModifyingLoadedClauses (x : RuleM α) : RuleM α := do
  let s ← getLoadedClauses
  try
    withoutModifyingMCtx x
  finally
    setLoadedClauses s

instance : AddMessageContext RuleM where
  addMessageContext := addMessageContextFull


-- TODO: MonadLift
def runMetaAsRuleM (x : MetaM α) : RuleM α := do
  let lctx ← getLCtx
  let mctx ← getMCtx
  let (res, state) ← Meta.MetaM.run (ctx := {lctx := lctx}) (s := {mctx := mctx}) do
    x
  setMCtx state.mctx
  return res

def mkFreshExprMVar (type? : Option Expr) (kind := MetavarKind.natural) (userName := Name.anonymous) : RuleM Expr := do
  runMetaAsRuleM $ Meta.mkFreshExprMVar type? kind userName

def getMVarType (mvarId : MVarId) : RuleM Expr := do
  runMetaAsRuleM $ Meta.getMVarType mvarId

def forallMetaTelescope (e : Expr) (kind := MetavarKind.natural) : RuleM (Array Expr × Array BinderInfo × Expr) :=
  runMetaAsRuleM $ Meta.forallMetaTelescope e kind

def mkFreshSkolem (name : Name) (type : Expr) (mkProof : Array Expr → MetaM Expr) : RuleM Expr := do
  let name := Name.mkNum name (← getLCtx).decls.size
  let (lctx, res) ← runMetaAsRuleM $ do
    Meta.withLocalDeclD name type fun x => do
      return (← getLCtx, x)
  setLCtx lctx
  setIntroducedSkolems $ (← getIntroducedSkolems).push (res.fvarId!, mkProof)
  return res

def mkForallFVars (xs : Array Expr) (e : Expr) (usedOnly : Bool := false) (usedLetOnly : Bool := true) : RuleM Expr :=
  runMetaAsRuleM $ Meta.mkForallFVars xs e usedOnly usedLetOnly

def inferType (e : Expr) : RuleM Expr :=
  runMetaAsRuleM $ Meta.inferType e

def instantiateMVars (e : Expr) : RuleM Expr :=
  runMetaAsRuleM $ Meta.instantiateMVars e

def unify (l : Array (Expr × Expr)) : RuleM Bool := do
  runMetaAsRuleM $ Meta.unify l

def isProof (e : Expr) : RuleM Bool := do
  runMetaAsRuleM $ Meta.isProof e

def isType (e : Expr) : RuleM Bool := do
  runMetaAsRuleM $ Meta.isType e

def getFunInfoNArgs (fn : Expr) (nargs : Nat) : RuleM Meta.FunInfo := do
  runMetaAsRuleM $ Meta.getFunInfoNArgs fn nargs

def replace (e : Expr) (target : Expr) (replacement : Expr) : RuleM Expr := do
  Core.transform e (pre := fun s => 
    if s == target then TransformStep.done replacement else TransformStep.visit s )

def loadClauseCore (c : Clause) : RuleM (Array Expr × MClause) := do
  let mVars ← c.bVarTypes.mapM fun ty => mkFreshExprMVar (some ty)
  let lits := c.lits.map fun l =>
    l.map fun e => e.instantiateRev mVars
  setLoadedClauses ((← getLoadedClauses).push (c, mVars.map Expr.mvarId!))
  return (mVars, MClause.mk lits)

def loadClause (c : Clause) : RuleM MClause := do
  let (mvars, mclause) ← loadClauseCore c
  return mclause

def neutralizeMClauseCore (c : MClause) : RuleM (Clause × CollectMVars.State) := do
  let c ← c |>.mapM instantiateMVars
  let mVarIds := (c.lits.foldl (fun acc (l : Lit) =>
    l.fold (fun acc e => e.collectMVars acc) acc) {})
  let lits := c.lits.map fun l =>
    l.map fun e => e.abstractMVars (mVarIds.result.map mkMVar)
  let c := Clause.mk (← mVarIds.result.mapM getMVarType) lits
  (c, mVarIds)

def neutralizeMClause (c : MClause) : RuleM Clause := do
  (← neutralizeMClauseCore c).1

def yieldClauseCore (c : MClause) (ruleName : String) (mkProof : Option ProofReconstructor) : RuleM Unit := do
  let (c, cVars) ← neutralizeMClauseCore c
  let mut proofParents := #[]
  for (loadedClause, instantiations) in ← getLoadedClauses do
    let instantiations ← instantiations.mapM fun m => do instantiateMVars $ mkMVar m
    let additionalVars := instantiations.foldl (fun acc e => e.collectMVars acc) 
      {visitedExpr := cVars.visitedExpr, result := #[]} -- ignore vars in `cVars`
    let instantiations := instantiations.map 
      (fun e => e.abstractMVars ((cVars.result ++ additionalVars.result).map mkMVar))
    proofParents ← proofParents.push {
      clause := loadedClause
      instantiations := instantiations
      vanishingVarTypes := ← additionalVars.result.mapM getMVarType
    }
  let mkProof := match mkProof with
  | some mkProof => mkProof
  | none => fun _ _ _ => 
    -- TODO: Remove sorry!?
    Lean.Meta.mkSorry c.toForallExpr (synthetic := true)
  let proof := {
    parents := proofParents,  
    ruleName := ruleName,
    introducedSkolems := ← getIntroducedSkolems --TODO: neutralize MVars?
    mkProof := mkProof
  }
  setResultClauses ((← getResultClauses).push (c, proof))



def yieldClause (c : MClause) (ruleName : String) (mkProof : Option ProofReconstructor := none) : RuleM Unit := do
  let _ ← yieldClauseCore c ruleName mkProof

def compare (s t : Expr) : RuleM Comparison := do
  let ord ← getOrder
  runMetaAsRuleM do ord s t

end RuleM

end Duper