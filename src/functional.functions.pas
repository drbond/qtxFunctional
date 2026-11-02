unit functional.functions;

// ---------------------------------------------------------------------------
//  qtxFunctional - higher-order functions and composition
//
//  Quartex Pascal has no generics, so this layer is specialised to Integer.
//  Every factory returns a *new* function value (a closure); nothing here
//  holds mutable state, so all of it is safe to share and reuse.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils;

type
  TIntArray     = array of Integer;

  TIntFunc      = function (Value: Integer): Integer;
  TIntPredicate = function (Value: Integer): Boolean;
  TIntFoldFunc  = function (Accumulator, Value: Integer): Integer;
  TIntGenerator = function (Index: Integer): Integer;
  TIntSink      = function (Value: Integer): Boolean;   // False = stop

  EFunctional = class(Exception);
  // Variant-based types - Quartex's substitute for generics
  TVarArray     = array of Variant;

  TVarFunc      = function (Value: Variant): Variant;
  TVarPredicate = function (Value: Variant): Boolean;
  TVarFoldFunc  = function (Accumulator, Value: Variant): Variant;
  TVarThunk     = function: Variant;
  TVarSink      = function (Value: Variant): Boolean;   // False = stop
  TVarSource    = procedure (const Sink: TVarSink);      // pushes until Sink says stop


  TFunction = class
  public
    // Basic functions
    class function Identity: TIntFunc;
    class function Constant(Value: Integer): TIntFunc;

    // Composition
    class function Compose(const F, G: TIntFunc): TIntFunc;   // x -> F(G(x))
    class function AndThen(const F, G: TIntFunc): TIntFunc;   // x -> G(F(x))

    // Curried arithmetic (partial application)
    class function Add(Amount: Integer): TIntFunc;
    class function Multiply(Factor: Integer): TIntFunc;
    class function Square: TIntFunc;

    // Predicates and predicate combinators
    class function IsEven: TIntPredicate;
    class function IsOdd: TIntPredicate;
    class function GreaterThan(Limit: Integer): TIntPredicate;
    class function Negate(const P: TIntPredicate): TIntPredicate;
    class function Both(const P, Q: TIntPredicate): TIntPredicate;

    // Fold (reducer) functions
    class function Sum: TIntFoldFunc;
    class function Product: TIntFoldFunc;
    class function Maximum: TIntFoldFunc;
  end;
  // Variant-typed counterpart used by TSequence / TLazy, plus "lifting"
  // helpers that turn the Integer functions above into Variant functions.
  TVarFunction = class
  public
    class function Identity: TVarFunc;
    class function Compose(const F, G: TVarFunc): TVarFunc;   // x -> F(G(x))
    class function AndThen(const F, G: TVarFunc): TVarFunc;   // x -> G(F(x))
    class function Both(const P, Q: TVarPredicate): TVarPredicate;
    class function Negate(const P: TVarPredicate): TVarPredicate;

    class function Lift(const F: TIntFunc): TVarFunc;
    class function LiftPredicate(const P: TIntPredicate): TVarPredicate;
    class function LiftFold(const F: TIntFoldFunc): TVarFoldFunc;

    class function ToText: TVarFunc;                          // Value -> String
    class function Concat(const Separator: String): TVarFoldFunc;
  end;


implementation

class function TFunction.Identity: TIntFunc;
begin
  Result := function (Value: Integer): Integer
    begin
      Result := Value;
    end;
end;

class function TFunction.Constant(Value: Integer): TIntFunc;
var
  Fixed: Integer;
begin
  Fixed := Value;
  Result := function (Value: Integer): Integer
    begin
      Result := Fixed;
    end;
end;

class function TFunction.Compose(const F, G: TIntFunc): TIntFunc;
var
  Outer, Inner: TIntFunc;
begin
  Outer := F;
  Inner := G;
  Result := function (Value: Integer): Integer
    begin
      Result := Outer(Inner(Value));
    end;
end;

class function TFunction.AndThen(const F, G: TIntFunc): TIntFunc;
begin
  Result := Compose(G, F);
end;

class function TFunction.Add(Amount: Integer): TIntFunc;
var
  Delta: Integer;
begin
  Delta := Amount;
  Result := function (Value: Integer): Integer
    begin
      Result := Value + Delta;
    end;
end;

class function TFunction.Multiply(Factor: Integer): TIntFunc;
var
  Scale: Integer;
begin
  Scale := Factor;
  Result := function (Value: Integer): Integer
    begin
      Result := Value * Scale;
    end;
end;

class function TFunction.Square: TIntFunc;
begin
  Result := function (Value: Integer): Integer
    begin
      Result := Value * Value;
    end;
end;

class function TFunction.IsEven: TIntPredicate;
begin
  Result := function (Value: Integer): Boolean
    begin
      Result := (Value mod 2) = 0;
    end;
end;

class function TFunction.IsOdd: TIntPredicate;
begin
  Result := function (Value: Integer): Boolean
    begin
      Result := (Value mod 2) <> 0;
    end;
end;

class function TFunction.GreaterThan(Limit: Integer): TIntPredicate;
var
  Bound: Integer;
begin
  Bound := Limit;
  Result := function (Value: Integer): Boolean
    begin
      Result := Value > Bound;
    end;
end;

class function TFunction.Negate(const P: TIntPredicate): TIntPredicate;
var
  Inner: TIntPredicate;
begin
  Inner := P;
  Result := function (Value: Integer): Boolean
    begin
      Result := not Inner(Value);
    end;
end;

class function TFunction.Both(const P, Q: TIntPredicate): TIntPredicate;
var
  First, Second: TIntPredicate;
begin
  First := P;
  Second := Q;
  Result := function (Value: Integer): Boolean
    begin
      Result := First(Value) and Second(Value);
    end;
end;

class function TFunction.Sum: TIntFoldFunc;
begin
  Result := function (Accumulator, Value: Integer): Integer
    begin
      Result := Accumulator + Value;
    end;
end;

class function TFunction.Product: TIntFoldFunc;
begin
  Result := function (Accumulator, Value: Integer): Integer
    begin
      Result := Accumulator * Value;
    end;
end;

class function TFunction.Maximum: TIntFoldFunc;
begin
  Result := function (Accumulator, Value: Integer): Integer
    begin
      if Value > Accumulator then
        Result := Value
      else
        Result := Accumulator;
    end;
end;

{ TVarFunction }

class function TVarFunction.Identity: TVarFunc;
begin
  Result := function (Value: Variant): Variant
    begin
      Result := Value;
    end;
end;

class function TVarFunction.Compose(const F, G: TVarFunc): TVarFunc;
var
  Outer, Inner: TVarFunc;
begin
  Outer := F;
  Inner := G;
  Result := function (Value: Variant): Variant
    begin
      Result := Outer(Inner(Value));
    end;
end;

class function TVarFunction.AndThen(const F, G: TVarFunc): TVarFunc;
begin
  Result := Compose(G, F);
end;

class function TVarFunction.Both(const P, Q: TVarPredicate): TVarPredicate;
var
  First, Second: TVarPredicate;
begin
  First := P;
  Second := Q;
  Result := function (Value: Variant): Boolean
    begin
      Result := First(Value) and Second(Value);
    end;
end;

class function TVarFunction.Negate(const P: TVarPredicate): TVarPredicate;
var
  Inner: TVarPredicate;
begin
  Inner := P;
  Result := function (Value: Variant): Boolean
    begin
      Result := not Inner(Value);
    end;
end;

class function TVarFunction.Lift(const F: TIntFunc): TVarFunc;
var
  Inner: TIntFunc;
begin
  Inner := F;
  Result := function (Value: Variant): Variant
    var
      N: Integer;
    begin
      N := Value;
      Result := Inner(N);
    end;
end;

class function TVarFunction.LiftPredicate(const P: TIntPredicate): TVarPredicate;
var
  Inner: TIntPredicate;
begin
  Inner := P;
  Result := function (Value: Variant): Boolean
    var
      N: Integer;
    begin
      N := Value;
      Result := Inner(N);
    end;
end;

class function TVarFunction.LiftFold(const F: TIntFoldFunc): TVarFoldFunc;
var
  Inner: TIntFoldFunc;
begin
  Inner := F;
  Result := function (Accumulator, Value: Variant): Variant
    var
      A, N: Integer;
    begin
      A := Accumulator;
      N := Value;
      Result := Inner(A, N);
    end;
end;

class function TVarFunction.ToText: TVarFunc;
begin
  Result := function (Value: Variant): Variant
    var
      S: String;
    begin
      S := Value;
      Result := S;
    end;
end;

class function TVarFunction.Concat(const Separator: String): TVarFoldFunc;
var
  Sep: String;
begin
  Sep := Separator;
  Result := function (Accumulator, Value: Variant): Variant
    var
      A, B: String;
    begin
      A := Accumulator;
      B := Value;
      if A = '' then
        Result := B
      else
        Result := A + Sep + B;
    end;
end;
end.
