import LeanHammer.ProverM
import LeanHammer.Iterate
import LeanHammer.RuleM
import LeanHammer.MClause
import LeanHammer.Boolean
import Std.Data.BinomialHeap

namespace ProverM
open Lean
open Meta
open Lean.Core
open Result
open Std
open ProverM
open RuleM

set_option trace.Prover.debug true

set_option maxHeartbeats 10000


#check MetaM.run

def forwardSimplify (givenClause : Clause) : ProverM (Option Clause) := do
  let lctx ← getLCtx
  let res : Option Clause ← RuleM.run' (s := {lctx := lctx}) do
    let mclause ← MClause.fromClause givenClause
    match ← clausificationStep mclause with
    | some [] => return none
    | some (c :: cs) => some $ ← c.toClause  --TODO: Fix this
    | none => return some givenClause
  return res 

def backwardSimplify (givenClause : Clause) : ProverM Unit := do
  ()

def performInferences (givenClause : Clause) : ProverM Unit := do
  ()

-- throwEmptyClauseException

partial def saturate : ProverM Unit := do
  Core.withCurrHeartbeats $ iterate $
    try do
      let some givenClause ← chooseGivenClause
        | do
          setResult saturated
          return LoopCtrl.abort
      let some givenClause ← forwardSimplify givenClause
        | return LoopCtrl.next
      backwardSimplify givenClause
      addToActive givenClause
      performInferences givenClause
      Core.checkMaxHeartbeats "saturate"
      return LoopCtrl.next
    catch
    | Exception.internal emptyClauseExceptionId _  =>
      setResult contadiction
      return LoopCtrl.abort
    | e => throw e
  trace[Prover.debug] "Done."
  trace[Prover.debug] "Result: {← getResult}"
  trace[Prover.debug] "Active: {(← getActiveSet).toArray}"
  trace[Prover.debug] "Passive: {(← getPassiveSet).toArray}"
  
#check BinomialHeap
#eval saturate

end ProverM