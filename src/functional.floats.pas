unit functional.floats;

// ---------------------------------------------------------------------------
//  qtxFunctional - TFloatFunction
//
//  Higher-order functions over floating-point values (Stage 2), mirroring
//  TFunction for Integer, plus Lift* helpers that plug them straight into
//  TSequence / TLazy pipelines.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions;

type
  TFloatArray     = array of Float;
  TFloatFunc      = function (Value: Float): Float;
  TFloatPredicate = function (Value: Float): Boolean;
  TFloatFoldFunc  = function (Accumulator, Value: Float): Float;

  TFloatFunction = class
  public
    class function Identity: TFloatFunc;
    class function Compose(const F, G: TFloatFunc): TFloatFunc;   // x -> F(G(x))
    class function AndThen(const F, G: TFloatFunc): TFloatFunc;   // x -> G(F(x))

    class function Add(Amount: Float): TFloatFunc;
    class function Scale(Factor: Float): TFloatFunc;
    class function Square: TFloatFunc;
    class function Root: TFloatFunc;                               // square root
    class function Reciprocal: TFloatFunc;
    class function Polynomial(const Coefficients: TFloatArray): TFloatFunc; // c0 + c1*x + c2*x^2 ...

    class function Above(Limit: Float): TFloatPredicate;
    class function Below(Limit: Float): TFloatPredicate;

    class function Sum: TFloatFoldFunc;
    class function Maximum: TFloatFoldFunc;
    class function Minimum: TFloatFoldFunc;

    class function Lift(const F: TFloatFunc): TVarFunc;
    class function LiftPredicate(const P: TFloatPredicate): TVarPredicate;
    class function LiftFold(const F: TFloatFoldFunc): TVarFoldFunc;
  end;

implementation

class function TFloatFunction.Identity: TFloatFunc;
begin
  Result := function (Value: Float): Float
    begin
      Result := Value;
    end;
end;

class function TFloatFunction.Compose(const F, G: TFloatFunc): TFloatFunc;
var
  Outer, Inner: TFloatFunc;
begin
  Outer := F;
  Inner := G;
  Result := function (Value: Float): Float
    begin
      Result := Outer(Inner(Value));
    end;
end;

class function TFloatFunction.AndThen(const F, G: TFloatFunc): TFloatFunc;
begin
  Result := Compose(G, F);
end;

class function TFloatFunction.Add(Amount: Float): TFloatFunc;
var
  Delta: Float;
begin
  Delta := Amount;
  Result := function (Value: Float): Float
    begin
      Result := Value + Delta;
    end;
end;

class function TFloatFunction.Scale(Factor: Float): TFloatFunc;
var
  K: Float;
begin
  K := Factor;
  Result := function (Value: Float): Float
    begin
      Result := Value * K;
    end;
end;

class function TFloatFunction.Square: TFloatFunc;
begin
  Result := function (Value: Float): Float
    begin
      Result := Value * Value;
    end;
end;

class function TFloatFunction.Root: TFloatFunc;
begin
  Result := function (Value: Float): Float
    begin
      Result := Sqrt(Value);
    end;
end;

class function TFloatFunction.Reciprocal: TFloatFunc;
begin
  Result := function (Value: Float): Float
    begin
      Result := 1 / Value;
    end;
end;

class function TFloatFunction.Polynomial(const Coefficients: TFloatArray): TFloatFunc;
var
  C: TFloatArray;
  i: Integer;
begin
  for i := 0 to High(Coefficients) do
    C.Add(Coefficients[i]);
  Result := function (Value: Float): Float
    var
      k: Integer;
    begin
      // Horner's method: ((c_n*x + c_{n-1})*x + ...) + c0
      Result := 0;
      for k := High(C) downto 0 do
        Result := Result * Value + C[k];
    end;
end;

class function TFloatFunction.Above(Limit: Float): TFloatPredicate;
var
  Bound: Float;
begin
  Bound := Limit;
  Result := function (Value: Float): Boolean
    begin
      Result := Value > Bound;
    end;
end;

class function TFloatFunction.Below(Limit: Float): TFloatPredicate;
var
  Bound: Float;
begin
  Bound := Limit;
  Result := function (Value: Float): Boolean
    begin
      Result := Value < Bound;
    end;
end;

class function TFloatFunction.Sum: TFloatFoldFunc;
begin
  Result := function (Accumulator, Value: Float): Float
    begin
      Result := Accumulator + Value;
    end;
end;

class function TFloatFunction.Maximum: TFloatFoldFunc;
begin
  Result := function (Accumulator, Value: Float): Float
    begin
      if Value > Accumulator then
        Result := Value
      else
        Result := Accumulator;
    end;
end;

class function TFloatFunction.Minimum: TFloatFoldFunc;
begin
  Result := function (Accumulator, Value: Float): Float
    begin
      if Value < Accumulator then
        Result := Value
      else
        Result := Accumulator;
    end;
end;

class function TFloatFunction.Lift(const F: TFloatFunc): TVarFunc;
var
  Inner: TFloatFunc;
begin
  Inner := F;
  Result := function (Value: Variant): Variant
    begin
      Result := Inner(TVariant.AsFloat(Value));
    end;
end;

class function TFloatFunction.LiftPredicate(const P: TFloatPredicate): TVarPredicate;
var
  Inner: TFloatPredicate;
begin
  Inner := P;
  Result := function (Value: Variant): Boolean
    begin
      Result := Inner(TVariant.AsFloat(Value));
    end;
end;

class function TFloatFunction.LiftFold(const F: TFloatFoldFunc): TVarFoldFunc;
var
  Inner: TFloatFoldFunc;
begin
  Inner := F;
  Result := function (Accumulator, Value: Variant): Variant
    begin
      Result := Inner(TVariant.AsFloat(Accumulator), TVariant.AsFloat(Value));
    end;
end;

end.
